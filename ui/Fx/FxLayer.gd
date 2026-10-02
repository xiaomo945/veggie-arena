extends CanvasLayer

# 打击感特效层（Juice）
#
# 设计原则：只订阅 Events 信号做表现，不认识 Player / Game / Enemy，
# 也不写回任何玩法状态。删掉这个文件，游戏照样能玩 —— 这就是验收标准。
#
# 三件事：
#   1) 飘伤害数字（暴击更大更黄）
#   2) 击杀爆环（Boss 的环更大）
#   3) 挨打红闪 / 颠勺金闪（全屏 ColorRect，不挡触摸）

const MAX_FLOATS := 28
const MAX_RINGS := 18
const MAX_CRACKS := 24

# 飘字：时长、上飘速度、横向抖动范围
const FLOAT_LIFE := 0.62
const FLOAT_RISE := 46.0

var _rings: Array = []
var _arcs: Array = []
var _cracks: Array = []
var _floats: Array = []
var _pool: Array = []
var _ring_view: Node2D
var _arc_view: Node2D
var _crack_view: Node2D
var _hurt: ColorRect
var _gold: ColorRect
var _hurt_t := 0.0
var _gold_t := 0.0
var _last_hp := -1

const MELEE_LIFE := 0.16

func _ready() -> void:
	layer = 15          # 在世界之上、HUD(20) 之下
	# 镜头会跟随玩家平移：特效层必须跟着镜头走，否则飘字/爆环会钉在屏幕固定位置
	follow_viewport_enabled = true
	name = "FxLayer"

	# 爆环用一个独立 Node2D 画（CanvasLayer 自己不能 _draw）
	_ring_view = Node2D.new()
	_ring_view.set_script(preload("res://ui/Fx/FxRings.gd"))
	# Array 是引用类型：把数组直接给它，双方看到的是同一份，无需再同步
	_ring_view.set("rings", _rings)
	_ring_view.name = "Rings"
	add_child(_ring_view)

	# 近战挥砍扇形：同样的套路，独立的数组 + 独立 Node2D
	_arc_view = Node2D.new()
	_arc_view.set_script(preload("res://ui/Fx/MeleeArc.gd"))
	_arc_view.set("arcs", _arcs)
	_arc_view.name = "MeleeArcs"
	add_child(_arc_view)

	# 地面裂痕（菜刀等近战砍地）：独立数组 + 独立 Node2D
	_crack_view = Node2D.new()
	_crack_view.set_script(preload("res://ui/Fx/FxCracks.gd"))
	_crack_view.set("cracks", _cracks)
	_crack_view.name = "Cracks"
	add_child(_crack_view)

	_hurt = _mk_flash(Color(1.0, 0.12, 0.18))
	_gold = _mk_flash(Color(1.0, 0.78, 0.32))

	Events.damage_dealt.connect(_on_damage)
	Events.enemy_killed.connect(_on_killed)
	Events.player_hp_changed.connect(_on_hp)
	Events.wok_tossed.connect(_on_toss)
	Events.melee_visual.connect(_on_melee)

func _mk_flash(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ⚠️ 必须忽略触摸：全屏 ColorRect 默认会吃掉所有点击，摇杆会失灵
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

# ---- 信号：飘伤害数字 ----
func _on_damage(amount: int, pos: Vector2, critical: bool) -> void:
	if _floats.size() >= MAX_FLOATS:
		return          # 高射速时宁可少飘几个，也不能拖帧
	var lab := _take_label()
	if lab == null:
		return
	lab.text = str(amount)
	lab.position = pos + Vector2(randf_range(-8.0, 8.0), -10.0)
	lab.scale = Vector2(1.25, 1.25) if critical else Vector2(1.0, 1.0)
	lab.modulate = Color(1.0, 0.86, 0.35) if critical else Color(1.0, 1.0, 1.0)
	lab.visible = true
	_floats.append({"label": lab, "t": 0.0})

# ---- 信号：击杀爆环 ----
func _on_killed(_type: String, pos: Vector2) -> void:
	if _rings.size() >= MAX_RINGS:
		return
	_rings.append({"pos": pos, "t": 0.0, "life": 0.34, "big": (_type == "boss")})

# ---- 信号：挨打红闪 ----
func _on_hp(hp: int, _max_hp: int) -> void:
	if _last_hp >= 0 and hp < _last_hp:
		_hurt_t = 0.26
	_last_hp = hp

# ---- 信号：颠勺金闪 ----
func _on_toss() -> void:
	_gold_t = 0.42

# ---- 信号：近战扇形 + 地面裂痕 ----
func _on_melee(origin: Vector2, dir: Vector2, reach: float, half_arc: float, color: Color, key: String, level: int) -> void:
	if _arcs.size() >= 12:
		return          # 多武器高频挥砍时宁可少画几刀，也不拖帧
	_arcs.append({"origin": origin, "dir": dir, "reach": reach,
		"half": half_arc, "color": color, "t": 0.0, "life": MELEE_LIFE})
	# 近战砍地裂痕：落点在挥砍中点，长度/分叉随武器等级变大
	if _cracks.size() < MAX_CRACKS:
		_cracks.append({"pos": origin + dir * reach * 0.5, "dir": dir,
			"level": level, "color": color, "t": 0.0})

func _process(delta: float) -> void:
	# 飘字：上飘 + 后段淡出
	var i := 0
	while i < _floats.size():
		var f: Dictionary = _floats[i]
		var t: float = float(f.get("t", 0.0)) + delta
		f["t"] = t
		var lab: Label = f.get("label") as Label
		lab.position.y -= FLOAT_RISE * delta
		var k: float = clampf(t / FLOAT_LIFE, 0.0, 1.0)
		lab.modulate.a = 1.0 - k * k
		if t >= FLOAT_LIFE:
			_give_label(lab)
			_floats.remove_at(i)
		else:
			i += 1

	# 爆环推进
	var j := 0
	while j < _rings.size():
		var r: Dictionary = _rings[j]
		var rt: float = float(r.get("t", 0.0)) + delta
		r["t"] = rt
		if rt >= float(r.get("life", 0.34)):
			_rings.remove_at(j)
		else:
			j += 1
	_ring_view.queue_redraw()

	# 近战扇形推进
	var m := 0
	while m < _arcs.size():
		var ar: Dictionary = _arcs[m]
		var at: float = float(ar.get("t", 0.0)) + delta
		ar["t"] = at
		if at >= float(ar.get("life", MELEE_LIFE)):
			_arcs.remove_at(m)
		else:
			m += 1
	_arc_view.queue_redraw()

	# 地面裂痕推进
	var cc := 0
	while cc < _cracks.size():
		var cr: Dictionary = _cracks[cc]
		var ct: float = float(cr.get("t", 0.0)) + delta
		cr["t"] = ct
		if ct >= 0.85:
			_cracks.remove_at(cc)
		else:
			cc += 1
	_crack_view.queue_redraw()

	# 全屏闪光
	if _hurt_t > 0.0:
		_hurt_t -= delta
		_hurt.color.a = maxf(0.0, _hurt_t / 0.26) * 0.30
	if _gold_t > 0.0:
		_gold_t -= delta
		_gold.color.a = maxf(0.0, _gold_t / 0.42) * 0.34

# ---- Label 对象池：飘字是最高频的特效，绝不能每次 instantiate ----
func _take_label() -> Label:
	if not _pool.is_empty():
		return _pool.pop_back() as Label
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 20)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.visible = false
	add_child(lab)
	return lab

func _give_label(lab: Label) -> void:
	lab.visible = false
	if _pool.size() < MAX_FLOATS:
		_pool.append(lab)
