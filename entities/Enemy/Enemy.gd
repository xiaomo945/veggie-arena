extends Node2D

# 敌人：状态与逻辑（移动/受击/效果/Boss 阶段）在这；绘制已合批到 EnemyDraw.gd
# （同屏敌人在一个节点画完，draw call 每只一次→1 次，治"满屏怪掉帧"）。
# 造型一眼能分清（grunt 红圆 / fast 橙三角 / tank 紫六边 / fly 菱 / boss 星）：
# 贴图在 spawn 时缓存到 _tex，逐怪差异化（闪白/挤压/升起/血条）由 EnemyDraw
# 读取本文件尾部的公开状态访问器复刻绘制。

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
# 持续伤害（毒/灼烧）节流累加器：见 tick_fx。一片怪同时中毒时若每帧都走 damage_enemy
# （飘字+挤压+结算）会瞬间上千次调用卡死手机——这里把 dot 累加、每 0.5s 才结算一次；
# 抽成独立 DotTicker（core/，纯逻辑）以便单测直接验证节流。
var _ticker := DotTicker.new()
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
var _tex: Texture2D = null          # spawn 时缓存一次贴图（EnemyDraw 经 tex2d() 读），省每帧 Art.sprite 归一化/拼串/查表
const Shake := preload("res://entities/effects/Shake.gd")
const Cull := preload("res://entities/Enemy/EnemyCull.gd")
const DotTicker := preload("res://core/DotTicker.gd")

const RISE_T := 0.85      # Boss "从地里升起来"的时长

func spawn(pos: Vector2, stats: Dictionary, id: int) -> void:
	etype = str(stats.get("type", "grunt"))
	_tex = Art.sprite("enemy_" + etype)   # 缓存一次，_draw_body 不再每帧查表
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
	_fx.clear()      # 对象池复用：上一只怪身上的毒/冰不能带到下一只身上
	_ticker.reset()  # 上一任残留的 dot 累加也清掉，否则会误结算到新怪身上
	visible = true

func recycle() -> void:
	alive = false
	visible = false
	_fx.clear()
	_ticker.reset()

func hurt(amount: float) -> bool:
	hp -= amount
	_flash = FLASH_DUR
	if hp <= 0.0:
		recycle()
		return true
	return false

# 受击挤压：挨打的瞬间沿打击方向压扁，随后回弹（打击感"肉感"来源）
func squash(dir: Vector2) -> void:
	_squash = 0.14
	_squash_dir = dir.normalized()

func apply_knockback(dir: Vector2, impulse: float) -> void:
	var v: Vector2 = _kb + dir * impulse
	_kb = v.limit_length(220.0)

# 逐帧推进（EnemyMind 驱动）。绘制侧重绘请求已挪去 EnemyDraw 每帧统一处理，
# 这里只推状态计时。
func tick(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta)
	if _rise_armed:
		_tick_rise(delta)
	if etype == "boss":
		_tick_boss(delta)

# 升起演出：等进入屏幕才开始；升起期间站桩（move_speed 挡移动）
func _tick_rise(delta: float) -> void:
	if _rise < 0.0:
		if Cull.in_view(self):
			_rise = 0.0
		return
	_rise += delta
	if _rise >= RISE_T:
		_rise_armed = false
		_rise = -1.0

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
# ⚠️ 节流：委托 DotTicker 每 DOT_TICK 秒才返回一次累积 dot，而非每帧结算。
# 总伤害完全不变（线性累加），但"一片怪同时中毒"时从每帧上千次伤害结算+飘字
# 节点暴增，降到 2 次/秒/怪 —— 这是毒雾/颠勺毒之前卡死手机的真正根因。
func tick_fx(delta: float) -> float:
	return _ticker.accumulate(_fx, delta)

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

# ---- 供合批绘制节点(EnemyDraw.gd)读取的公开状态 ----
# R3：EnemyDraw 不跨文件碰本类私有字段，绘制所需的内部状态一律经这里读出
# （EnemyDraw 侧复刻原 Enemy._draw 的绘制序列，保持逐怪差异化不变）。

# 受击闪白强度 0~1（原 _draw 里现算的 flash_k 挪到这，全项目只用这一个口径）
func flash_k() -> float:
	if _flash <= 0.0:
		return 0.0
	return clampf(_flash / FLASH_DUR, 0.0, 1.0)

func rising() -> bool:
	return _rise >= 0.0

func rise_t() -> float:
	return _rise

func squashing() -> bool:
	return _squash > 0.0

func squash_q() -> float:
	return _squash

func squash_dir() -> Vector2:
	return _squash_dir

func anim_phase() -> float:
	return _phase

func tex2d() -> Texture2D:
	return _tex
