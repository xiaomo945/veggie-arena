extends Node2D

# 敌人：造型一眼能分清（grunt 红圆 / fast 橙三角 / tank 紫六边 / fly 菱 / boss 星）。
# 有 res://art/sprite_enemy_<类型>.png 就画贴图，否则走凶萌手绘（EnemyShape）；
# 闪白 / 挤压回弹 / 出场升起 / 血条共用。

const SPRITE_SCALE := 2.2   # 贴图边长 = radius * 系数（贴图角色约占画布 90%，与手绘体量一致）
const FLASH_DUR := 0.16

var alive := false
var eid := 0
var etype := "grunt"
var hp := 10.0
var max_hp := 10.0
var speed := 50.0
var dmg := 5.0
var radius := 14.0
var gold := 1
var tint := Color(0.88, 0.38, 0.37)
var flight := false
var elite := false
var final_boss := false             # 终局 Boss（第 total 波专属）：更大更红、多一个阶段
var _flash := 0.0
var _phase := 0.0
var _kb := Vector2.ZERO          # 受击击退脉冲（由 EnemySystem 施加/衰减）
# 状态效果统一表：{效果名: {"v": 强度, "t": 剩余秒}}。slow 减速 / freeze 冻结 / poison 中毒(按最大生命%结算) / burn 灼烧 / shred 破甲，加新效果只多一个名字。
var _fx: Dictionary = {}
# Boss 多阶段 / 冲锋技能（仅 etype=="boss" 生效）
var _phase_steps: Array = []        # 阶段血量阈值（来自配置；空数组=不分阶段）
var _boss_phase := 1
var _base_speed := 0.0
var _base_dmg := 0.0
var _charge_cd := 0.0
var _charge_t := 0.0
# 出场升起（Boss/精英专属演出）：armed=还没等到进屏幕；>=0 = 升起进行中
var _rise_armed := false
var _rise := -1.0
# 受击挤压回弹（squash & stretch）：撞击方向 + 剩余时间
var _squash := 0.0
var _squash_dir := Vector2.ZERO
var _dirty := false                 # 屏幕外时攒下的重绘请求（进屏幕再补，见 EnemyCull）
const Shake := preload("res://entities/effects/Shake.gd")
const Cull := preload("res://entities/Enemy/EnemyCull.gd")
const EnemyShape := preload("res://entities/Enemy/EnemyShape.gd")

const RISE_T := 0.85      # Boss "从地里升起来"的时长

func spawn(pos: Vector2, stats: Dictionary, id: int) -> void:
	etype = str(stats.get("type", "grunt"))
	eid = id
	hp = float(stats.get("hp", 10))
	max_hp = hp
	speed = float(stats.get("speed", 50))
	dmg = float(stats.get("damage", 5))
	radius = float(stats.get("radius", 14))
	gold = int(stats.get("gold", 1))
	tint = Color(str(stats.get("color", "#e0605f")))
	flight = bool(stats.get("flight", false))
	elite = bool(stats.get("elite", false))
	final_boss = bool(stats.get("final", false))
	if etype == "boss":
		_boss_phase = 1
		_phase_steps = stats.get("phase_steps", [0.66, 0.33]) as Array
		_base_speed = speed
		_base_dmg = dmg
		_charge_cd = 3.5
		_charge_t = 0.0
	global_position = pos
	alive = true
	_flash = 0.0
	_phase = 0.0
	_squash = 0.0
	_squash_dir = Vector2.ZERO
	# Boss 出场要"从地里升起来"：等它走进屏幕那一刻才开始播（别白播）
	_rise_armed = etype == "boss"
	_rise = -1.0
	_dirty = false           # 屏幕外时攒着没画的重绘请求（进屏幕再补）
	_fx.clear()      # 对象池复用：上一只怪身上的毒/冰不能带到下一只身上
	visible = true
	_redraw()

func recycle() -> void:
	alive = false
	visible = false
	_fx.clear()

func hurt(amount: float) -> bool:
	hp -= amount
	_flash = FLASH_DUR
	_redraw()
	if hp <= 0.0:
		recycle()
		return true
	return false

# 受击挤压：挨打的瞬间沿打击方向压扁，随后回弹（打击感"肉感"来源）
func squash(dir: Vector2) -> void:
	_squash = 0.14
	_squash_dir = dir.normalized()
	_redraw()

func apply_knockback(dir: Vector2, impulse: float) -> void:
	var v: Vector2 = _kb + dir * impulse
	_kb = v.limit_length(220.0)

func tick(delta: float) -> void:
	if _dirty and Cull.in_view(self):
		_dirty = false
		_redraw()
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_redraw()
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta)
		_redraw()
	if _rise_armed:
		_tick_rise(delta)
	if etype == "boss":
		_tick_boss(delta)

# 升起演出：等进入屏幕才开始；升起期间站桩（move_speed 挡移动）
func _tick_rise(delta: float) -> void:
	if _rise < 0.0:
		if Cull.in_view(self):
			_rise = 0.0
			_redraw()
		return
	_rise += delta
	_redraw()
	if _rise >= RISE_T:
		_rise_armed = false
		_rise = -1.0

# 屏幕外不重绘（性能）：可见就画，不可见只记 _dirty，进屏幕时由 tick 补画
func _redraw() -> void:
	_dirty = not Cull.redraw_if_visible(self)

# 施加一个状态效果。同种效果取"更强 + 更久"，不叠乘（叠乘会让数值失控）。
func apply_fx(name: String, value: float, dur: float) -> void:
	if dur <= 0.0 or value <= 0.0:
		return
	var cur: Dictionary = _fx.get(name, {})
	_fx[name] = {
		"v": maxf(float(cur.get("v", 0.0)), value),
		"t": maxf(float(cur.get("t", 0.0)), dur),
	}

func fx(name: String) -> float:
	var d: Dictionary = _fx.get(name, {})
	if float(d.get("t", 0.0)) <= 0.0:
		return 0.0
	return float(d.get("v", 0.0))

# 推进所有效果的计时，返回本帧应结算的持续伤害（毒/灼烧）。
# 伤害由 EnemySystem 走 damage_enemy 统一结算 —— 只有那边才知道击杀/掉金/锅气。
func tick_fx(delta: float) -> float:
	if _fx.is_empty():
		return 0.0
	var dot := 0.0
	for k in _fx.keys():
		var d: Dictionary = _fx[k]
		var t := float(d.get("t", 0.0)) - delta
		if t <= 0.0:
			_fx.erase(k)
			continue
		d["t"] = t
		if k == "poison" or k == "burn":
			dot += float(d.get("v", 0.0)) * delta
	return dot

# 本帧实际移动速度：升起演出期间站桩；冻结优先（完全定住），其次是减速
func move_speed() -> float:
	if _rise >= 0.0:
		return 0.0
	if fx("freeze") > 0.0:
		return 0.0
	return speed * (1.0 - clampf(fx("slow"), 0.0, 0.95))

# ---- 给 EnemySystem 的公开读写接口 ----
# 这些状态由 EnemySystem 每帧驱动，但**只有 Enemy 能改内部字段**：对外只给访问器，
# 避免"谁都能直接改 _kb"这种跨模块写私有字段。

# 飞行蛇形摆动：推进相位并返回当前相位（EnemySystem 用它算左右摆动的偏移）
func wobble(delta: float) -> float:
	_phase += delta * 7.0
	return _phase

func knockback() -> Vector2:
	return _kb

func set_knockback(v: Vector2) -> void:
	_kb = v

# Boss：按血量阈值切阶段（提速+加伤），并周期朝玩家冲锋。纯逻辑，靠 speed/dmg 字段驱动移动与接触伤害。
func _tick_boss(delta: float) -> void:
	if not alive:
		return
	_phase += delta * 1.2          # 终局 Boss 装饰的缓慢旋转/脉动用（飞行兵才走 wobble）
	var ratio := hp / max_hp
	var target := 1
	for i in _phase_steps.size():
		if ratio <= float(_phase_steps[i]):
			target = i + 2
	if target > _boss_phase:
		_boss_phase = target
		speed = _base_speed * (1.0 + 0.25 * (_boss_phase - 1))
		dmg = _base_dmg * (1.0 + 0.20 * (_boss_phase - 1))
		_flash = FLASH_DUR
		Shake.kick(7.0, 0.35)
	_charge_cd -= delta
	if _charge_t > 0.0:
		_charge_t -= delta
		if _charge_t <= 0.0:
			speed = _base_speed * (1.0 + 0.25 * (_boss_phase - 1))   # 冲锋结束，回到本阶段速度
	else:
		if _charge_cd <= 0.0:
			_charge_t = 0.5
			_charge_cd = 3.6 - 0.6 * _boss_phase      # 阶段越高，冲锋越频繁
			speed = _base_speed * 2.2                   # 冲锋：短暂极速猛冲
			Shake.kick(4.0, 0.18)

func _draw() -> void:
	if not alive:
		return
	var c := tint
	var flash_k := 0.0
	if _flash > 0.0:
		flash_k = clampf(_flash / FLASH_DUR, 0.0, 1.0)
		# 受击瞬间整体闪白，随受击时间衰减回原色
		c = tint.lerp(Color(1, 1, 1, 1), flash_k * 0.85)
	# 出场升起：先把"土坑 + 尘土"画在脚下，再让本体缩放淡入
	if _rise >= 0.0:
		_draw_rise_hole()
	_draw_body(c, flash_k)
	# 受击红色染色：随受击时间衰减，强化"被打到了"
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.25, 0.25, 0.35 * flash_k))
	if final_boss and _rise < 0.0:
		EnemyShape.final_decor(self, radius, _phase, c)
	_draw_hp_bar()

# 本体（贴图或手绘）+ 出场升起缩放 + 受击白色描边 + 挤压回弹
func _draw_body(c: Color, flash_k: float) -> void:
	var tex := Art.sprite("enemy_" + etype)
	var growing := _rise >= 0.0
	# 升起中：本体从坑里长出来（overshoot 一下更有"破土"的劲）
	if growing:
		var k := clampf(_rise / RISE_T, 0.0, 1.0)
		var sc := 0.25 + 0.85 * (1.0 - pow(1.0 - k, 2.6))
		if k > 0.8:
			sc = 1.0 + 0.12 * sin((k - 0.8) / 0.2 * PI)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
	elif _squash > 0.0:
		# squash：沿打击方向压到 0.72、垂直方向 1.22，随时间弹回
		var q := _squash / 0.14
		draw_set_transform(Vector2.ZERO, _squash_dir.angle(),
			Vector2(1.0 - 0.28 * q, 1.0 + 0.22 * q))
	if tex != null:
		_draw_sprite(tex, radius * SPRITE_SCALE, c)
	else:
		_draw_shape(c)
		# 精英/Boss 描边：远远就认得出是"硬货"
		if elite:
			draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.5, true)
		elif etype == "boss":
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 18, Color(1, 0.3, 0.4, 0.8), 3.5, true)
	# 冲刺/受击挤压共用一次变换复位；受击白描边随闪白淡出（贴图/手绘都吃得到）
	if growing or _squash > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flash_k > 0.25:
		_draw_flash_outline(radius * SPRITE_SCALE * 0.62 if tex != null else radius + 3.0, flash_k)

func _draw_flash_outline(r: float, k: float) -> void:
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(1, 1, 1, k * 0.9), 2.6, true)
# Boss 出场的土坑：脚下越裂越大的黑坑 + 几块崩出的土块
func _draw_rise_hole() -> void:
	EnemyShape.rise_hole(self, radius, clampf(_rise / RISE_T, 0.0, 1.0))

func _draw_poly(pts: PackedVector2Array, c: Color) -> void:
	EnemyShape.poly(self, pts, c)
# 缺图时的手绘造型：委托给 EnemyShape（升起变换已在 _draw_body 里设好）
func _draw_shape(c: Color) -> void:
	EnemyShape.body(self, etype, radius, c)

func _draw_sprite(tex: Texture2D, size: float, c: Color) -> void:
	var half := size * 0.5
	if _rise < 0.0:
		EnemyShape.ground_shadow(self, half)   # 脚下投影（贴图怪也有"站地"感）
	draw_texture_rect_region(tex, Rect2(-half, -half, size, size),
		Rect2(Vector2.ZERO, tex.get_size()), c)

# 血条：精英/Boss 常显；普通怪满血时不挡视线
func _draw_hp_bar() -> void:
	if hp >= max_hp and not elite and etype != "boss":
		return
	var w := radius * 2.0
	var y := -radius - 8.0
	draw_rect(Rect2(-w * 0.5, y, w, 3.5), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 3.5), Color(0.85, 0.95, 0.5))
