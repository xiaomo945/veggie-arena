extends Node2D

# 敌人：三种造型必须一眼能分清（之前版本被吐槽"看不到敌人是谁"）。
#   小兵 grunt = 红色圆（最常见）
#   冲刺兵 fast = 橙色尖三角（细长、快）
#   重甲兵 tank = 紫色六边形（大、慢、硬）
#
# 外观优先级：res://art/sprite_enemy_<类型>.png 存在 → 画贴图；
# 不存在 → 退回下面的手绘几何体。两条路径共用同一套闪白/血条逻辑。

# 贴图绘制边长 = radius * 该系数（贴图里角色占画布约 90%，画出来跟手绘版体量一致）
const SPRITE_SCALE := 2.2
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
var _flash := 0.0
var _phase := 0.0
var _kb := Vector2.ZERO          # 受击击退脉冲（由 EnemySystem 施加/衰减）
var _slow_t := 0.0               # 减速剩余秒数（颠勺减速道具施加）
var _slow_factor := 0.0          # 当前减速强度（0=不减速，0.5=移速减半）
# Boss 多阶段 / 冲锋技能（仅 etype=="boss" 生效）
var _boss_phase := 1
var _base_speed := 0.0
var _base_dmg := 0.0
var _charge_cd := 0.0
var _charge_t := 0.0
const Shake := preload("res://entities/effects/Shake.gd")

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
	if etype == "boss":
		_boss_phase = 1
		_base_speed = speed
		_base_dmg = dmg
		_charge_cd = 3.5
		_charge_t = 0.0
	global_position = pos
	alive = true
	_flash = 0.0
	_phase = 0.0
	visible = true
	queue_redraw()

func recycle() -> void:
	alive = false
	visible = false

# 返回 true 表示这一击打死了它
func hurt(amount: float) -> bool:
	hp -= amount
	_flash = FLASH_DUR
	queue_redraw()
	if hp <= 0.0:
		recycle()
		return true
	return false

# 受击击退：沿 dir 叠加一个快速衰减的速度脉冲（幅度由调用方克制）
func apply_knockback(dir: Vector2, impulse: float) -> void:
	var v: Vector2 = _kb + dir * impulse
	_kb = v.limit_length(220.0)

func tick(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			queue_redraw()
	# 减速计时：到点清零，移速恢复
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow_t = 0.0
			_slow_factor = 0.0
	if etype == "boss":
		_tick_boss(delta)

# 颠勺减速：factor=移速折扣(0.5→减半)，dur=持续秒数。取更强/更久者，不叠加。
func apply_slow(factor: float, dur: float) -> void:
	_slow_factor = maxf(_slow_factor, clampf(factor, 0.0, 0.95))
	_slow_t = maxf(_slow_t, dur)

# ---- 给 EnemySystem 的公开读写接口 ----
# 这些状态由 EnemySystem 每帧驱动（移动摆动 / 击退衰减 / 减速读数），但**只有 Enemy
# 能改内部字段**：对外只给访问器，避免"谁都能直接改 _kb"这种跨模块写私有字段。

# 飞行蛇形摆动：推进相位并返回当前相位（EnemySystem 用它算左右摆动的偏移）
func wobble(delta: float) -> float:
	_phase += delta * 7.0
	return _phase

# 当前击退脉冲速度（EnemySystem 每帧读一次、衰减一次）
func knockback() -> Vector2:
	return _kb

func set_knockback(v: Vector2) -> void:
	_kb = v

# 当前减速强度（0=不减速，0.5=移速减半）
func slow_factor() -> float:
	return _slow_factor

# Boss：按血量阈值切阶段（提速+加伤），并周期朝玩家冲锋。纯逻辑，靠 speed/dmg 字段驱动移动与接触伤害。
func _tick_boss(delta: float) -> void:
	if not alive:
		return
	var ratio := hp / max_hp
	var target := 1
	if ratio <= 0.33:
		target = 3
	elif ratio <= 0.66:
		target = 2
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
	if _flash > 0.0:
		var f: float = clampf(_flash / FLASH_DUR, 0.0, 1.0)
		# 受击瞬间整体闪白，随受击时间衰减回原色
		c = tint.lerp(Color(1, 1, 1, 1), f * 0.85)
	var tex := Art.sprite("enemy_" + etype)
	if tex != null:
		_draw_sprite(tex, radius * SPRITE_SCALE, c)
	else:
		_draw_shape(c)
		# 精英/Boss 加一道描边，远远就能认出是"硬货"
		if elite:
			draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.5, true)
		elif etype == "boss":
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 18, Color(1, 0.3, 0.4, 0.8), 3.5, true)
	# 受击红色染色：覆盖一层随受击时间衰减的红色，强化"被打到了"
	if _flash > 0.0:
		var f: float = clampf(_flash / FLASH_DUR, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.25, 0.25, 0.35 * f))
	_draw_hp_bar()

# 缺图时的手绘造型（保留原顺序：先"看清敌人"，再谈美术）
func _draw_shape(c: Color) -> void:
	match etype:
		"fast":
			# 尖三角，尖端朝上表示"冲得快"
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -radius * 1.25),
				Vector2(radius * 0.95, radius * 0.75),
				Vector2(-radius * 0.95, radius * 0.75)]), c)
		"tank":
			# 六边形，厚重
			var pts := PackedVector2Array()
			for i in range(6):
				var a := TAU * float(i) / 6.0 - PI * 0.5
				pts.append(Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(pts, c)
			draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 12,
				Color(1, 1, 1, 0.35), 3.0, true)
		"fly":
			# 菱形（四角星），小、亮，和其余三种一眼不同
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -radius * 1.3),
				Vector2(radius * 0.55, 0),
				Vector2(0, radius * 1.3),
				Vector2(-radius * 0.55, 0)]), c)
			draw_circle(Vector2.ZERO, radius * 0.32, Color(1, 1, 1, 0.5))
		"boss":
			# 十二角星，大、狰狞，是场地里的视觉焦点
			var sp := PackedVector2Array()
			for i in range(24):
				var a := TAU * float(i) / 24.0
				var rr := radius * (0.62 if i % 2 == 0 else 1.0)
				sp.append(Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(sp, c)
			draw_arc(Vector2.ZERO, radius * 0.5, 0.0, TAU, 14,
				Color(1, 1, 1, 0.4), 4.0, true)
		_:
			# 小兵：圆 + 一条"腰带"，比纯圆更好认
			draw_circle(Vector2.ZERO, radius, c)
			draw_arc(Vector2.ZERO, radius * 0.6, 0.0, TAU, 14,
				Color(0, 0, 0, 0.28), 3.0, true)

# 贴图版本：modulate 直接吃闪白，血条照旧画在上面
func _draw_sprite(tex: Texture2D, size: float, c: Color) -> void:
	var half := size * 0.5
	draw_texture_rect_region(tex, Rect2(-half, -half, size, size),
		Rect2(Vector2.ZERO, tex.get_size()), c)

# 血条：精英/Boss 常显（让玩家盯紧大目标）；普通怪满血时不挡视线
func _draw_hp_bar() -> void:
	if hp >= max_hp and not elite and etype != "boss":
		return
	var w := radius * 2.0
	var y := -radius - 8.0
	draw_rect(Rect2(-w * 0.5, y, w, 3.5), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 3.5),
		Color(0.85, 0.95, 0.5))
