extends RefCounted

# 锅气大招（颠勺）的施放 —— 从 EnemySystem 拆出来的独立部件。
#
# 为什么拆：锅气是这游戏最核心的差异化玩法，光"附加什么效果"就有 9 种
# （减速/冻结/中毒/灼烧/破甲/连环爆/吸血/掉金/返火），全塞在 EnemySystem 里
# 会把它顶穿 300 行红线，而且以后每加一种效果都会再撞一次。
#
# 效果数值的组装在 core/WokEffects.gd（纯逻辑、可单测）；这里只负责把算好的
# 效果施加到敌人身上。
#
# ⚠️ 伤害必须回调用 EnemySystem.damage_enemy：只有那里才知道击杀计数、掉金币、
#    涨锅气。绕过它自己扣血会导致"毒死/炸死的怪不算击杀、不掉钱、不涨火候"。

const WokEffects := preload("res://core/WokEffects.gd")
const Movement := preload("res://core/Movement.gd")

var world = null                     # BattleWorld
var damage_fn: Callable = Callable() # (enemy, amount) -> bool 是否被这一击打死

# 执行一发大招。返回是否真的放出去了（没充能时返回 false）
func execute() -> bool:
	if not GameState.wok_ready():
		return false
	var pp: Vector2 = world.player.global_position
	var fx := WokEffects.build(_stat_snapshot(), Data.wok_cfg())
	# 双重施放（wok_double）：一次消耗，连炸两轮
	var shots := 1 + int(fx.get("double", 0))
	var hit_count := 0
	var dead_pos: Array = []
	for i in shots:
		var r: Dictionary = _burst(pp, fx)
		hit_count += int(r.get("hit", 0))
		dead_pos.append_array(r.get("dead", []) as Array)

	_chain_blast(fx, dead_pos)
	_payout(fx, hit_count, pp)
	_buff(fx, pp)

	# 冲击波视觉
	world.kick_shock(pp)
	GameState.toss_wok()
	# 返火：连发流的核心 —— 放完还留一截火候，能更快攒出下一发
	var refund := float(fx.get("refund", 0.0))
	if refund > 0.0:
		GameState.add_wok(refund * float(Data.wok_cfg().get("max", 100)))
	Events.wok_tossed.emit(pp)
	return true

# 一轮全屏冲击：重伤 + 位移 + 挂持续效果。
# 返回 {"hit": 波及几只, "dead": 被打死的位置列表}（连环爆炸要用死亡位置）
func _burst(pp: Vector2, fx: Dictionary) -> Dictionary:
	var knock := float(fx.get("knock", 130.0))
	var vortex := float(fx.get("vortex", 0.0))
	var exec := float(fx.get("execute", 0.0))
	var elite_pct := float(fx.get("elite_pct", 0.0))
	var hit := 0
	var dead: Array = []
	for e in world.enemies:
		if not e.alive:
			continue
		var epos: Vector2 = e.global_position
		var dir: Vector2 = epos - pp
		if dir.length() < 0.001:
			dir = Vector2(0, 1)
		hit += 1
		# 重伤：按敌人最大血量比例结算，Boss 也削一大块
		var amount: float = e.max_hp * float(fx.get("dmg_mult", 0.6)) \
			+ float(fx.get("flat", 25.0))
		# 精英特攻：对首领 / 精英怪再乘一档，让大招在 Boss 波也能当主力
		if elite_pct > 0.0 and (e.elite or e.etype == "boss"):
			amount *= 1.0 + elite_pct
		# 斩杀：血量已经低于阈值的直接处决（残血怪不用再磨）
		if exec > 0.0 and e.hp <= e.max_hp * exec:
			amount = maxf(amount, float(e.hp) + 1.0)
		var died := _hit(e, amount)
		if died:
			dead.append(epos)
			continue
		# 位移：默认甩飞（颠勺的爆开感）；买了聚怪就反过来吸向玩家
		var push: float = -vortex if vortex > 0.0 else knock
		var np: Vector2 = e.global_position + dir.normalized() * push
		e.global_position = Movement.clamp_to_arena(np, world.arena, e.radius)
		_apply_fx(e, fx)
	_chain_hop(fx, pp)
	return {"hit": hit, "dead": dead}

# 大招专属增益：护盾 / 狂暴 / 吸金（每发大招结算一次，不按波次叠加）
func _buff(fx: Dictionary, pp: Vector2) -> void:
	var sh := int(fx.get("shield", 0))
	if sh > 0:
		GameState.add_shield(sh)
	var fr := float(fx.get("frenzy", 0.0))
	if fr > 0.0:
		GameState.start_frenzy(fr)
	if float(fx.get("magnet", 0.0)) > 0.0 and world.pickups != null:
		# 吸金：把地上散落的金币一次性收进兜里，配合"掉金"道具很爽
		var got: int = world.pickups.collect_all(pp)
		if got > 0:
			GameState.add_gold(got)

# 连环爆炸：被大招打死的怪炸到周围的同伴
func _chain_blast(fx: Dictionary, dead_pos: Array) -> void:
	var boom := float(fx.get("explode", 0.0))
	if boom <= 0.0:
		return
	var r := float(fx.get("explode_radius", 70.0))
	for p in dead_pos:
		for o in world.enemies:
			if not o.alive:
				continue
			if o.global_position.distance_to(p) <= r:
				_hit(o, boom)

# 连锁（wok_chain）：从玩家脚下起跳，在最近的存活怪之间依次传导 N 次。
# 与"连环爆炸"的区别：爆炸要有怪被炸死才触发，连锁是**一定**会跳，
# 所以它是"清残血"道具而不是"滚雪球"道具。
func _chain_hop(fx: Dictionary, from: Vector2) -> void:
	var hops := int(fx.get("chain", 0))
	if hops <= 0:
		return
	var per: float = float(fx.get("chain_dmg", 12.0))
	var at := from
	var used: Array = []
	for i in hops:
		var best = null
		var best_d := INF
		for e in world.enemies:
			if not e.alive or used.has(e.eid):
				continue
			var d: float = at.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			return
		used.append(best.eid)
		at = best.global_position
		_hit(best, per * (1.0 + float(fx.get("dmg_mult", 0.6))))

# 吸血 / 掉金：按"被大招波及的敌人数"结算
func _payout(fx: Dictionary, hit_count: int, pp: Vector2) -> void:
	var ls := float(fx.get("lifesteal", 0.0))
	if ls > 0.0 and hit_count > 0:
		GameState.heal(int(round(ls * float(hit_count))))
	var gd := float(fx.get("gold", 0.0))
	if gd > 0.0 and hit_count > 0 and world.pickups != null:
		world.pickups.drop(pp, int(round(gd * float(hit_count))))

# 把大招的持续效果挂到一只活着的怪身上
func _apply_fx(e, fx: Dictionary) -> void:
	if float(fx.get("slow_v", 0.0)) > 0.0:
		e.apply_fx("slow", float(fx.get("slow_v", 0.0)), float(fx.get("slow_dur", 0.0)))
	if float(fx.get("freeze_dur", 0.0)) > 0.0:
		e.apply_fx("freeze", 1.0, float(fx.get("freeze_dur", 0.0)))
	if float(fx.get("poison_dps_pct", 0.0)) > 0.0:
		e.apply_fx("poison", e.max_hp * float(fx.get("poison_dps_pct", 0.0)),
			float(fx.get("poison_dur", 0.0)))
	if float(fx.get("burn_dps", 0.0)) > 0.0:
		e.apply_fx("burn", float(fx.get("burn_dps", 0.0)), float(fx.get("burn_dur", 0.0)))
	if float(fx.get("shred_v", 0.0)) > 0.0:
		e.apply_fx("shred", float(fx.get("shred_v", 0.0)), float(fx.get("shred_dur", 0.0)))

func _hit(e, amount: float) -> bool:
	return bool(damage_fn.call(e, amount))

# 一次性读出所有锅气 stat（避免每只怪都遍历一遍升级表）
func _stat_snapshot() -> Dictionary:
	var out := {}
	for k in WokEffects.STAT_KEYS:
		out[k] = GameState.stat_value(k)
	return out
