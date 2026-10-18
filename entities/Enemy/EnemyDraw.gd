extends Node2D

# 敌人合批②：同屏敌人全部在这一个节点里画完，draw call 从"每只怪一次"降到 1 次。
# 由来：每只怪原来是独立 Node2D 各画一份 _draw（造型+脸+阴影+描边+血条），
# "满屏怪掉帧"的主因就是绘制开销随怪数线性涨（PerfGuard 只能被动降档，不降单只成本）。
#
# 逐怪差异化逐字保留：贴图/手绘造型、受击闪白、squash 挤压、出场升起、Boss 终局
# 装饰、精英/Boss 描边、血条 —— 绘制序列复刻原 Enemy._draw。
#
# 两个关键实现：
# 1) EnemyShape 的绘制函数内部会 draw_set_transform 做绝对复位（显式多边形阴影
#    拒绝跟随 squash 的刻意设计，见 EnemyShape.ground_shadow 注释），所以不能
#    "设一次每怪变换再复用它们"。做法：EnemyCanvas 跟随代理 —— 复刻 CanvasItem
#    的变换语义（绘制点 = frame × xform × 局部点），把每个 draw_* 转写到本节点。
# 2) 物理插值复刻：project.godot 开了 physics_interpolation，旧路径里每只怪节点的
#    渲染位置由引擎在物理 tick 间插值（60Hz 物理+120Hz 渲染时的平滑来源）。合批后
#    只有一个节点，必须自己插值：_physics_process 快照各池槽上一 tick 末位置，
#    _draw 里按 Engine.get_physics_interpolation_fraction() 在 prev→cur 间插值。
#    公式与引擎逐字一致（prev/cur = 相邻两 tick 末的全局位置）。
#
# 接线：Game._build_pools 建完敌人池后创建本节点挂 game —— 保持
# 子弹 < 敌人(合批) < 击杀爆点 的层级与原来完全一致。
# 每帧有活怪且未暂停就 queue_redraw；屏幕外逐怪跳过（复用 EnemyCull，同原引擎逐节点剔除）。

const Cull := preload("res://entities/Enemy/EnemyCull.gd")
const Shape := preload("res://entities/Enemy/EnemyShape.gd")
const Enemy := preload("res://entities/Enemy/Enemy.gd")
const EnemyCanvas := preload("res://entities/Enemy/EnemyCanvas.gd")

const SPRITE_SCALE := 2.2   # 贴图边长 = radius × 系数（原 Enemy.SPRITE_SCALE 随绘制挪来）
const RISE_T := 0.85        # Boss 破土演出时长（与 Enemy.RISE_T 一致，绘制侧复刻）

var world = null            # 注入：BattleWorld（只读 enemies 池）

func _init(w) -> void:
	world = w

# 物理插值复刻用的逐槽快照（池槽顺序终身不变，可用下标索引，稳态零分配）。
# 引擎插值 = lerp(上一 tick 末位置, 本 tick 末位置, fraction)。本节点的 _physics_process
# 跑在 Game（父节点，负责移怪）之后，拿到的是本 tick 末位置 —— 故用移位寄存器：
#   _cur_pos[i]  = 最近一次快照的全局位置（最新 tick 末）
#   _prev_pos[i] = 上一次快照的全局位置（上一 tick 末）→ 即引擎的 prev
# _prev_eid[i]  = _prev 快照时的 eid；槽位复用时 eid 变 → 两个寄存器都重置（防残影）
var _prev_pos := PackedVector2Array()
var _cur_pos := PackedVector2Array()
var _prev_eid := PackedInt32Array()

func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var n: int = world.enemies.size()
	if _prev_pos.size() != n:
		_prev_pos.resize(n)
		_cur_pos.resize(n)
		_prev_eid.resize(n)
	for i in n:
		var e = world.enemies[i]
		if not e.alive:
			continue
		if _prev_eid[i] != e.eid:      # 槽位复用：prev 作废，两寄存器对齐到当前位置
			_prev_pos[i] = e.global_position
			_prev_eid[i] = e.eid
		else:
			_prev_pos[i] = _cur_pos[i]   # 移位：旧 cur 降级为 prev
		_cur_pos[i] = e.global_position

var _cv: EnemyCanvas = null  # 跟随代理（见 EnemyCanvas.gd），惰性建

func _process(_delta: float) -> void:
	if world == null:
		return
	if GameState != null and GameState.paused:
		return                 # 暂停时敌人不 tick，状态冻结，重绘纯浪费
	for e in world.enemies:
		if e.alive:
			if _cv == null:
				_cv = EnemyCanvas.new()
			queue_redraw()
			return

func _draw() -> void:
	if world == null:
		return
	if _cv == null:
		_cv = EnemyCanvas.new()
	var deco: bool = Perf.bool_cap("deco", true)
	var cv := _cv
	var frac: float = Engine.get_physics_interpolation_fraction()
	for i in world.enemies.size():
		var e = world.enemies[i]
		if not e.alive:
			continue
		if not Cull.in_view(e):
			continue         # 屏幕外跳过：同原"引擎逐节点剔除"，省不可见绘制
		var cur: Vector2 = e.global_position
		# 插值到引擎会显示的位置（两 tick 末位置之间）；槽位刚复用则 prev 已对齐
		var shown: Vector2 = _prev_pos[i].lerp(cur, frac) if i < _prev_pos.size() else cur
		cv.begin(self, shown - global_position)
		var c: Color = e.tint
		var flash_k: float = e.flash_k()
		if flash_k > 0.0:
			# 受击瞬间整体闪白，随受击时间衰减回原色
			c = e.tint.lerp(Color(1, 1, 1, 1), flash_k * 0.85)
		# 出场升起：先把"土坑 + 尘土"画在脚下，再让本体缩放淡入
		if e.rising():
			Shape.rise_hole(cv, e.radius, clampf(e.rise_t() / RISE_T, 0.0, 1.0))
		_draw_body(cv, e, c, flash_k, deco)
		# 受击红色染色：随受击时间衰减，强化"被打到了"
		if flash_k > 0.0:
			cv.draw_circle(Vector2.ZERO, e.radius, Color(1.0, 0.25, 0.25, 0.35 * flash_k))
		if e.final_boss and not e.rising():
			Shape.final_decor(cv, e.radius, e.anim_phase(), c)
		_draw_hp_bar(cv, e)

# 本体（贴图或手绘）+ 出场升起缩放 + 受击白色描边 + 挤压回弹（复刻 Enemy._draw_body）
func _draw_body(cv: EnemyCanvas, e: Enemy, c: Color, flash_k: float, deco: bool) -> void:
	var tex := e.tex2d()
	var growing := e.rising()
	# 升起中：本体从坑里长出来（overshoot 一下更有"破土"的劲）
	if growing:
		var k := clampf(e.rise_t() / RISE_T, 0.0, 1.0)
		var sc := 0.25 + 0.85 * (1.0 - pow(1.0 - k, 2.6))
		if k > 0.8:
			sc = 1.0 + 0.12 * sin((k - 0.8) / 0.2 * PI)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
	elif e.squashing():
		# squash：沿打击方向压到 0.72、垂直方向 1.22，随时间弹回
		var q := e.squash_q() / 0.14
		cv.draw_set_transform(Vector2.ZERO, e.squash_dir().angle(),
			Vector2(1.0 - 0.28 * q, 1.0 + 0.22 * q))
	if tex != null:
		_draw_sprite(cv, e, tex, c)
	else:
		Shape.body(cv, e.etype, e.radius, c, deco)
		# 精英/Boss 描边：远远就认得出是"硬货"
		if e.elite:
			cv.draw_arc(Vector2.ZERO, e.radius + 4.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.5, true)
		elif e.etype == "boss":
			cv.draw_arc(Vector2.ZERO, e.radius + 5.0, 0.0, TAU, 18, Color(1, 0.3, 0.4, 0.8), 3.5, true)
	# 冲刺/受击挤压共用一次变换复位；受击白描边随闪白淡出（贴图/手绘都吃得到）
	if growing or e.squashing():
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flash_k > 0.25:
		cv.draw_arc(Vector2.ZERO, _flash_radius(e, tex), 0.0, TAU, 20,
			Color(1, 1, 1, flash_k * 0.9), 2.6, true)

func _draw_sprite(cv: EnemyCanvas, e: Enemy, tex: Texture2D, c: Color) -> void:
	var half := e.radius * SPRITE_SCALE * 0.5
	if not e.rising():
		Shape.ground_shadow(cv, half)   # 脚下投影（贴图怪也有"站地"感）
	cv.draw_texture_rect_region(tex, Rect2(-half, -half, half * 2.0, half * 2.0),
		Rect2(Vector2.ZERO, tex.get_size()), c)

func _flash_radius(e: Enemy, tex: Texture2D) -> float:
	return e.radius * SPRITE_SCALE * 0.62 if tex != null else e.radius + 3.0

# 血条：精英/Boss 常显；普通怪满血时不挡视线（复刻 Enemy._draw_hp_bar）
func _draw_hp_bar(cv: EnemyCanvas, e: Enemy) -> void:
	if e.hp >= e.max_hp and not e.elite and e.etype != "boss":
		return
	var w := e.radius * 2.0
	var y := -e.radius - 8.0
	cv.draw_rect(Rect2(-w * 0.5, y, w, 3.5), Color(0, 0, 0, 0.55))
	cv.draw_rect(Rect2(-w * 0.5, y, w * clampf(e.hp / e.max_hp, 0.0, 1.0), 3.5), Color(0.85, 0.95, 0.5))
