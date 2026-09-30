extends RefCounted

# 武器槽与合成升级 —— 纯逻辑
# 规则：同类武器再买一把 = 合成升级（不占新槽位），最高 max_lv

const Combat := preload("res://core/Combat.gd")

# 这个 key 还能不能进商店池？
# 条件：槽位没满，或者场上有一把同 key 且等级未满的
static func can_accept(weapons: Array, key: String, max_slot: int, max_lv: int) -> bool:
	if weapons.size() < max_slot:
		return true
	return find_merge_target(weapons, key, max_lv) >= 0

# 找可合成目标，返回索引；没有返回 -1
static func find_merge_target(weapons: Array, key: String, max_lv: int) -> int:
	for i in weapons.size():
		var w = weapons[i]
		if not (w is Dictionary):
			continue
		if str(w.get("key", "")) == key and int(w.get("lv", 1)) < max_lv:
			return i
	return -1

# 买一把武器：能合成就升级，否则占新槽。
# def 需含 key/dmg/cd。返回是否成功（槽满且不可合成时为 false）
static func merge_or_add(weapons: Array, def: Dictionary, max_slot: int, max_lv: int,
		combat_cfg: Dictionary = {}) -> bool:
	var key := str(def.get("key", ""))
	var idx := find_merge_target(weapons, key, max_lv)
	if idx >= 0:
		var w: Dictionary = weapons[idx]
		var dmg_mul := float(combat_cfg.get("merge_dmg_multiplier", 1.30))
		var cd_mul := float(combat_cfg.get("merge_cd_multiplier", 0.93))
		w["lv"] = int(w.get("lv", 1)) + 1
		w["dmg"] = int(round(float(w.get("dmg", 1)) * dmg_mul))
		w["cd"] = float(w.get("cd", 1.0)) * cd_mul
		weapons[idx] = w
		return true
	if weapons.size() >= max_slot:
		return false
	var nw: Dictionary = def.duplicate()
	nw["lv"] = 1
	weapons.append(nw)
	return true

# 把强化应用到属性表（stat 字段决定加到哪）
static func apply_upgrade(stats: Dictionary, up: Dictionary) -> Dictionary:
	var stat := str(up.get("stat", ""))
	var value = up.get("value", 0)
	match stat:
		"max_hp":
			stats["max_hp"] = float(stats.get("max_hp", 0)) + float(value)
			stats["hp"] = minf(float(stats.get("hp", 0)) + float(value), float(stats.get("max_hp", 0)))
		"heal_now":
			stats["hp"] = minf(float(stats.get("hp", 0)) + float(value), float(stats.get("max_hp", 100)))
		"speed_pct":
			stats["speed_pct"] = float(stats.get("speed_pct", 0)) + float(value)
		"dmg_pct":
			stats["dmg_pct"] = float(stats.get("dmg_pct", 0)) + float(value)
		"rate_pct":
			stats["rate_pct"] = float(stats.get("rate_pct", 0)) + float(value)
		"armor":
			stats["armor"] = float(stats.get("armor", 0)) + float(value)
		"pickup_pct":
			stats["pickup_pct"] = float(stats.get("pickup_pct", 0)) + float(value)
		_:
			push_warning("Inventory: 未知强化类型 " + stat)
	return stats

# 当前武器总 DPS（用于配平模拟）
static func total_dps(weapons: Array, dmg_pct: float = 0.0, rate_pct: float = 0.0) -> float:
	var total := 0.0
	for w in weapons:
		if w is Dictionary:
			total += Combat.weapon_dps(w, dmg_pct, rate_pct)
	return total
