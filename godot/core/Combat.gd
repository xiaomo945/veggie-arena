extends RefCounted

# 战斗结算 —— 纯函数，不引用任何 Node / 场景 / 输入 / 渲染
# 规则 R4：core/ 必须能在 --headless 下独立运行

# 护甲减伤，结果不低于 min_damage（默认 1）
static func damage_after_armor(raw: float, armor: float, min_damage: int = 1) -> int:
	return maxi(min_damage, int(round(raw - armor)))

# 无敌帧内不可再次受击
static func can_be_hit(ifr: float) -> bool:
	return ifr <= 0.0

# 命中后剩余穿透次数
static func pierce_after_hit(pierce: int) -> int:
	return maxi(0, pierce - 1)

# 命中后子弹是否继续飞（还有穿透次数就活着）
static func bullet_alive_after_hit(pierce: int) -> bool:
	return pierce > 0

# 范围伤害：返回落在半径内的目标（目标需含 "pos": Vector2）
static func aoe_targets(center: Vector2, radius: float, targets: Array) -> Array:
	var out: Array = []
	for t in targets:
		if not (t is Dictionary):
			continue
		var p = t.get("pos", null)
		if p == null:
			continue
		var pv: Vector2 = p
		if pv.distance_to(center) <= radius:
			out.append(t)
	return out

# 一次 aoe 造成的总伤害（用于模拟测试）
static func aoe_total_damage(center: Vector2, radius: float, targets: Array, dmg: float, armor: float = 0.0, min_damage: int = 1) -> int:
	var hits := aoe_targets(center, radius, targets)
	return hits.size() * damage_after_armor(dmg, armor, min_damage)

# 玩家每秒理论输出（用于配平模拟，不含命中率）
static func weapon_dps(weapon: Dictionary, dmg_pct: float = 0.0, rate_pct: float = 0.0) -> float:
	var dmg := float(weapon.get("dmg", 0))
	var cd := float(weapon.get("cd", 1.0))
	var pellets := float(weapon.get("pellets", 1))
	if cd <= 0.0:
		return 0.0
	return dmg * (1.0 + dmg_pct) * pellets * (1.0 + rate_pct) / cd

# 击杀一个敌人需要多少秒（单武器）
static func time_to_kill(hp: float, weapon: Dictionary, dmg_pct: float = 0.0, rate_pct: float = 0.0) -> float:
	var d := weapon_dps(weapon, dmg_pct, rate_pct)
	if d <= 0.0:
		return INF
	return hp / d
