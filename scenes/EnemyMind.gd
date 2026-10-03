extends RefCounted

# 敌人 AI + 移动 + 接触结算（从 EnemySystem 拆出的独立部件）。
# 为什么拆：EnemySystem 已贴 300 行红线，而"行为多样"要不断加新逻辑；
# 敌人 AI 是天然独立的子系统（读 world、写敌人移动、开火、接触伤害），拆出来不牵一发动全身。
#
# 只通过 Enemy 的公开 API 操作（speed/dmg/radius/global_position/move_speed/apply_fx/...），
# 不碰任何 Enemy 私有字段（架构守卫 R3）。伤害/击杀/掉金/锅气一律回调 EnemySystem.damage_enemy，
# 只有那里才知道击杀计数；死亡分裂回调 EnemySystem.spawn_child。

const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")
const Shake := preload("res://entities/effects/Shake.gd")

# 炮手：维持的交火距离（太近就后撤、太远就靠近、中间横移）
const KEEP_DIST := 210.0
const SHOOT_CD := 1.6
const SHOOT_RANGE := 430.0
# 猛冲兵相位机：待机 → 蓄力 → 猛冲 → 恢复
const CHARGE_CD := 3.0
const CHARGE_WIND := 0.4
const CHARGE_DASH := 0.5
const CHARGE_RECOVER := 0.6
const CHARGE_MULT := 3.0
# 自爆：接触爆炸的视觉半径（对玩家是单体但带范围感）
const BOMB_RADIUS := 70.0

var world = null
var damage_fn: Callable = Callable()   # (enemy, amount) -> bool，EnemySystem.damage_enemy
var bullet_sys = null                  # BulletSystem，供炮手开火（launch_enemy）
var spawn_child_fn: Callable = Callable()  # (pos, type) -> void，供分裂怪
# 行为状态按 eid 存（对象池复用：eid 每刷一只自增，天然跟"当前 occupant"绑定）
var _beh: Dictionary = {}              # eid -> 行为名（shooter/charger/splitter/bomber）
var _st: Dictionary = {}               # eid -> 行为状态机（相位/计时/开火冷却）

func setup(w, dmg, bullets, spawn_child) -> void:
	world = w
	damage_fn = dmg
	bullet_sys = bullets
	spawn_child_fn = spawn_child

# 刷怪时登记行为（EnemySystem.spawn_one/spawn_child 调用），并清掉上一任的状态
func register(e, stats: Dictionary) -> void:
	_beh[e.eid] = str(stats.get("behavior", ""))
	_st.erase(e.eid)

# 每帧推进所有存活敌人：移动 / 分离 / 接触伤害 / 行为。原样保留了 chase 手感，
# 只在行为分支里叠加"炮手保持距离 + 开火 / 猛冲兵相位猛冲 / 自爆接触爆炸"。
func update(delta: float) -> void:
	var pp: Vector2 = world.player.global_position
	var pr: float = float(Data.player_cfg().get("radius", 16))
	var contact_dmg: float = GameState.stat_value("contact_dmg")
	for i in world.enemies.size():
		var e = world.enemies[i]
		if not e.alive:
			continue
		var beh: String = _beh.get(e.eid, "")
		var pos: Vector2 = e.global_position
		var to_p: Vector2 = pp - pos
		var dist_p: float = to_p.length()
		var dir: Vector2 = to_p.normalized() if dist_p > 0.001 else Vector2.ZERO

		# ---- 行为：炮手维持交火距离 ----
		if beh == "shooter":
			if dist_p < KEEP_DIST:
				dir = -dir                       # 太近 → 后撤
			elif dist_p < KEEP_DIST + 70.0:
				dir = Vector2(-dir.y, dir.x) * 0.6   # 交火圈内 → 横移走位

		# ---- 行为：猛冲兵相位机（蓄力→猛冲→恢复）----
		var spd_mult := 1.0
		if beh == "charger":
			if not _st.has(e.eid):
				_st[e.eid] = {"phase": 0, "t": CHARGE_CD, "dx": 0.0, "dy": 0.0}
			var s: Dictionary = _st[e.eid]
			s["t"] -= delta
			match int(s["phase"]):
				0:  # 待机
					if s["t"] <= 0.0:
						s["phase"] = 1; s["t"] = CHARGE_WIND
						Shake.kick(3.0, 0.12)
				1:  # 蓄力（仍正常靠近，给玩家反应窗口）
					if s["t"] <= 0.0:
						s["phase"] = 2; s["t"] = CHARGE_DASH
						s["dx"] = dir.x; s["dy"] = dir.y
				2:  # 猛冲：锁定方向、极速
					dir = Vector2(s["dx"], s["dy"])
					spd_mult = CHARGE_MULT
					if s["t"] <= 0.0:
						s["phase"] = 3; s["t"] = CHARGE_RECOVER
				3:  # 恢复
					if s["t"] <= 0.0:
						s["phase"] = 0; s["t"] = CHARGE_CD

		# 飞行兵：蛇形摆动（和原逻辑一致）
		if e.flight:
			var perp := Vector2(-dir.y, dir.x)
			dir = (dir + perp * sin(e.wobble(delta)) * 0.7).normalized()
		# 实际位移（move_speed 已含减速/冻结；猛冲再乘相位倍率）
		var spd: float = e.move_speed() * spd_mult
		pos += dir * spd * delta
		# 分离：只算附近，避免 O(n^2) 在满怪时拖慢手机
		world.neighbors.clear()
		for j in world.enemies.size():
			if j == i:
				continue
			var o = world.enemies[j]
			if not o.alive:
				continue
			if pos.distance_squared_to(o.global_position) < 3600.0:  # 60px 内才算
				world.neighbors.append({"pos": o.global_position, "radius": o.radius})
		pos += Hit.separation(pos, world.neighbors, e.radius) * 90.0 * delta
		# 别叠在玩家身上
		pos += Hit.keep_distance(pos, pp, e.radius + pr)
		# 受击击退脉冲：随帧快速衰减
		var kb: Vector2 = e.knockback()
		if kb.length_squared() > 0.01:
			pos += kb * delta
			e.set_knockback(kb.move_toward(Vector2.ZERO, 520.0 * delta))
		e.global_position = Movement.clamp_to_arena(pos, world.arena, e.radius)
		e.tick(delta)
		# 持续伤害（中毒/灼烧）：走 damage_enemy 统一结算（击杀/掉金/锅气都生效）
		var dot: float = e.tick_fx(delta)
		if dot > 0.0:
			damage_fn.call(e, dot)

		# ---- 接触玩家 ----
		var cd: float = e.radius + pr + 2.0
		if beh == "bomber" and pos.distance_to(pp) <= cd:
			_explode(e, pos)        # 自爆：单次大伤 + 视觉环，然后消失（不再走普通接触）
			continue
		if pos.distance_to(pp) <= cd:
			if world.player.has_method("take_hit"):
				world.player.take_hit(e.dmg)
				# 挨打掉火候（被摸一下 = 锅被泼了冷水）；封顶 8 点
				GameState.cool_wok(minf(e.dmg, 8.0))
				# 荆棘（contact_dmg）：贴上来就得挨烫
				if contact_dmg > 0.0:
					damage_fn.call(e, contact_dmg)

		# ---- 行为：炮手开火（朝玩家射一发敌弹）----
		if beh == "shooter":
			if not _st.has(e.eid):
				_st[e.eid] = {"fire": SHOOT_CD}
			var st: Dictionary = _st[e.eid]
			st["fire"] -= delta
			if st["fire"] <= 0.0 and dist_p < SHOOT_RANGE and bullet_sys != null:
				st["fire"] = SHOOT_CD
				var d: Vector2 = (pp - e.global_position).normalized()
				bullet_sys.launch_enemy(e.global_position, d, e.dmg * 1.3, Color(0.69, 0.42, 1.0))

# 自爆：对玩家造成一次范围感的大伤（无敌帧已防连击），视觉环 + 震屏，然后消失
func _explode(e, pos: Vector2) -> void:
	if world.player.has_method("take_hit"):
		world.player.take_hit(e.dmg * 3.0)
	Shake.kick(8.0, 0.3)
	Events.enemy_exploded.emit(pos, BOMB_RADIUS)
	e.recycle()

# 死亡分裂：仅"分裂"行为触发；子代是 splitling（无行为，不会无限分裂）
func on_kill(e, pos: Vector2) -> void:
	if _beh.get(e.eid, "") != "splitter":
		return
	if spawn_child_fn.is_valid():
		spawn_child_fn.call(pos + Vector2(-10.0, 0.0), "splitling")
		spawn_child_fn.call(pos + Vector2(10.0, 0.0), "splitling")
