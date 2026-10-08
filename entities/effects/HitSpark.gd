extends Node2D

# 击杀爆点（卡通"噗叽"）—— 【池化版：零 new / 零 Tween / 零 queue_free】
#
# 旧实现（"怪一多就卡"的尖峰真凶）：每次击杀 new 一个 HitSpark，内部再造
#   ~10 个 Polygon2D/Line2D 和 ~11 个 Tween，0.5s 后整棵子树 queue_free。
#   实测（tests/perf/FxBench.gd）30 连杀 = +300 节点 / +1650 对象 / 2.2ms，
#   占 120Hz 帧预算（8.33ms）的 26%，且【随击杀数线性增长】—— 怪越多死得越
#   多、尖峰越密，正是用户描述的那一种卡。
#
# 新实现：由 SparkPool 预建固定数量实例反复 reset 复用；动画在 _process 里
#   手动推进，一个 Tween 都不建；播完 visible=false 归还池。
#   稳态之外那根"尖刺"被彻底削平（见 FxBench 的前后对比）。
#
# ⚠️ 架构守卫 R3：不读写其他对象的私有字段。归还走父节点（池）的公开 recycle()。

const _OCT := 9
const MAX_BLOBS := 13      # Boss 用满；普通怪只用前 7 个
const LIFE := 0.36         # 动画时长（与旧版 0.34~0.36 一致）

var _puff: Polygon2D = null
var _ring: Line2D = null
var _blobs: Array = []
var _dirs: Array = []
var _spds: Array = []
var _active := false
var _t := 0.0
var _n := 7                # 本次用几个碎屑
var _ring_to := 2.6        # 环最终放大倍数

# 预生成多边形：reset 时只赋引用，不重新分配数组（旧版每次击杀都重建 14 个数组）
var _poly_blob_s := PackedVector2Array()
var _poly_blob_b := PackedVector2Array()
var _poly_puff_s := PackedVector2Array()
var _poly_puff_b := PackedVector2Array()

func _oct_poly(r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in _OCT:
		var a := TAU * float(i) / float(_OCT)
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

# 预建：池初始化时调用一次，之后只 reset
func build() -> void:
	_poly_blob_s = _oct_poly(5.0)
	_poly_blob_b = _oct_poly(8.0)
	_poly_puff_s = _oct_poly(8.0)     # 5.0 * 1.6
	_poly_puff_b = _oct_poly(12.8)    # 8.0 * 1.6
	_puff = Polygon2D.new()
	add_child(_puff)
	for _i in MAX_BLOBS:
		var b := Polygon2D.new()
		b.visible = false
		add_child(b)
		_blobs.append(b)
		_dirs.append(Vector2.ZERO)
		_spds.append(0.0)
	_ring = Line2D.new()
	var pts := PackedVector2Array()
	for k in 20:
		var ra := TAU * float(k) / 20.0
		pts.append(Vector2(cos(ra), sin(ra)) * 8.0)
	_ring.points = pts
	_ring.closed = true
	_ring.default_color = Color(1.0, 0.78, 0.42, 0.95)
	add_child(_ring)
	set_process(false)
	visible = false
	# 本节点的碎屑动画在【渲染帧】推进（纯表现，要的就是 120Hz 下最丝滑），
	# 与"物理步 + 插值"的世界更新不是一套时钟。不关掉插值的话两者会打架，
	# 表现为碎屑每物理步跳一下。关掉 = 完全按渲染帧走，与旧版观感一致。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func is_playing() -> bool:
	return _active

# 复用一次：只做属性赋值，不建任何节点/补间
func reset(pos: Vector2, big: bool) -> void:
	global_position = pos
	visible = true
	_active = true
	_t = 0.0
	set_process(true)
	_n = 13 if big else 7
	_ring_to = 3.6 if big else 2.6
	var blob_c := Color(1.0, 0.6, 0.42) if big else Color(1.0, 0.92, 0.66)
	_ring.width = 5.0 if big else 4.0
	_puff.polygon = _poly_puff_b if big else _poly_puff_s
	_puff.color = blob_c
	_puff.position = Vector2.ZERO
	_puff.scale = Vector2.ONE
	_puff.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_ring.position = Vector2.ZERO
	_ring.scale = Vector2.ONE
	_ring.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var pb := _poly_blob_b if big else _poly_blob_s
	var base := 132.0 if big else 72.0
	for i in MAX_BLOBS:
		var b := _blobs[i] as Polygon2D
		if i >= _n:
			b.visible = false
			continue
		b.visible = true
		b.polygon = pb
		b.color = blob_c
		b.position = Vector2.ZERO
		b.scale = Vector2.ONE
		b.modulate = Color(1.0, 1.0, 1.0, 1.0)
		var a := TAU * float(i) / float(_n) + randf_range(-0.3, 0.3)
		_dirs[i] = Vector2(cos(a), sin(a))
		_spds[i] = base * randf_range(0.6, 1.2)
	_apply(0.0)

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _t >= LIFE:
		_finish()
		return
	_apply(_t)

# 手动推进动画（替代旧版的 ~11 个 Tween）：缓动用 cubic-out 近似 EASE_OUT
func _apply(t: float) -> void:
	var p := clampf(t / LIFE, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - p, 3.0)
	var pe := 1.0 - pow(1.0 - clampf(t / 0.22, 0.0, 1.0), 3.0)
	_puff.scale = Vector2.ONE * lerpf(1.0, 2.2, pe)
	_puff.modulate.a = 1.0 - clampf(t / 0.34, 0.0, 1.0)
	var re := 1.0 - pow(1.0 - clampf(t / 0.32, 0.0, 1.0), 3.0)
	_ring.scale = Vector2.ONE * lerpf(1.0, _ring_to, re)
	_ring.modulate.a = 1.0 - clampf(t / 0.32, 0.0, 1.0)
	var bs := lerpf(1.0, 0.3, p)
	var ba := 1.0 - p
	for i in _n:
		var b := _blobs[i] as Polygon2D
		var d: Vector2 = _dirs[i]
		var sp: float = _spds[i]
		b.position = d * sp * e
		b.scale = Vector2.ONE * bs
		b.modulate.a = ba

func _finish() -> void:
	_active = false
	visible = false
	set_process(false)
	var p := get_parent()
	if p != null and p.has_method("recycle"):
		p.recycle(self)
