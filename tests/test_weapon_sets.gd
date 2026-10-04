extends RefCounted

# 武器套装（Q1）+ 属性缩放（Q2）：core/WeaponSets.gd，纯函数 + 真实数据表。
#
# 要保的事：
#   1) 32 把武器【每把】都有 tag —— 漏一把，那把就永远吃不到套装，等于少一件装备。
#   2) 凑 2/4/6 件给的加成是该档位的【总值】而不是累加（6 件只能拿 6 件那一档）。
#   3) 加成必须落进玩家能感知的属性（会不会生效由 GameState.stat_value 接线保证，
#      这里至少保证 bonuses 的键是真实存在的属性 key）。
#   4) 伤害缩放：近战吃 melee_pct、远程吃 ranged_pct、元素武器额外吃 elem_pct ——
#      这是"同一把武器在不同 build 下手感不同"的根，搞反了等于白做。

const WeaponSets := preload("res://core/WeaponSets.gd")
const Stats := preload("res://core/Stats.gd")

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)

func _w(key: String) -> Dictionary:
	return {"key": key, "lv": 1}

func run(data) -> Dictionary:
	var defs: Dictionary = data.weapons
	var sets: Dictionary = data.weapon_sets

	# --- 数据完整性 ---
	var no_tag: Array = []
	for k in defs:
		var d := defs[k] as Dictionary
		if (d.get("tags", []) as Array).is_empty():
			no_tag.append(k)
	chk(no_tag.is_empty(), "32 把武器都有套装 tag（漏：%s）" % str(no_tag))
	var known: Array = []
	for t in sets:
		if str(t) != "_doc":
			known.append(str(t))
	var orphan: Array = []
	for k in defs:
		for t in ((defs[k] as Dictionary).get("tags", []) as Array):
			if not known.has(str(t)):
				orphan.append("%s:%s" % [k, t])
	chk(orphan.is_empty(), "没有指向不存在套装的 tag（孤儿：%s）" % str(orphan))
	var cnt := WeaponSets.tag_counts([], defs)
	chk(cnt.is_empty(), "空背包不激活任何套装")

	# --- 计数：一件带两个 tag 的武器两边各算一件 ---
	var c2 := WeaponSets.tag_counts([_w("fork"), _w("ladle")], defs)
	chk(int(c2.get("blade", 0)) == 1 and int(c2.get("kitchen", 0)) == 2,
		"双 tag 武器（叉子=刀工+厨具、汤勺=元素+厨具）两边各计一件")

	# --- 档位 ---
	var sb := sets.get("blade", {}) as Dictionary
	chk(WeaponSets.tier_of(1, sb) == 0, "1 件不激活")
	chk(WeaponSets.tier_of(2, sb) == 1 and WeaponSets.tier_of(3, sb) == 1, "2~3 件是第 1 档")
	chk(WeaponSets.tier_of(4, sb) == 2 and WeaponSets.tier_of(6, sb) == 3, "4 件第 2 档 / 6 件第 3 档")

	# --- 加成是该档位的总值，不是累加 ---
	var six: Array = []
	for k in defs:
		if ((defs[k] as Dictionary).get("tags", []) as Array).has("blade"):
			six.append(_w(str(k)))
	var b := WeaponSets.bonuses(six, defs, sets)
	chk(absf(float(b.get("melee_pct", 0.0)) - 0.30) < 0.0001,
		"6 件刀工 = 近战伤害 +30%%（实测 %s）" % b.get("melee_pct", 0.0))
	chk(absf(float(b.get("crit_chance", 0.0)) - 0.12) < 0.0001, "6 件刀工同时给 +12%% 暴击")
	var b2 := WeaponSets.bonuses([six[0], six[1]], defs, sets)
	chk(absf(float(b2.get("melee_pct", 0.0)) - 0.08) < 0.0001, "2 件刀工 = 近战伤害 +8%")

	# 加成键必须是真属性（写错 key 就永远不生效）
	var cat_keys: Dictionary = {}
	for e in Stats.catalog():
		cat_keys[str((e as Dictionary)["key"])] = true
	var bad: Array = []
	for t in sets:
		if str(t) == "_doc":
			continue
		for tier in ((sets[t] as Dictionary).get("tiers", []) as Array):
			for k in ((tier as Dictionary).get("stats", {}) as Dictionary):
				if not cat_keys.has(str(k)):
					bad.append(str(k))
	chk(bad.is_empty(), "套装加成的属性 key 都在属性目录里（错键：%s）" % str(bad))

	# --- Q2 属性缩放 ---
	var cleaver: Dictionary = defs.get("cleaver", {})
	var pistol: Dictionary = defs.get("pistol", {})
	var chili: Dictionary = defs.get("chili", {})
	chk(absf(float(WeaponSets.scaling_of(cleaver).get("melee_pct", 0.0)) - 1.0) < 0.0001,
		"近战武器（菜刀）完整吃 melee_pct")
	chk(float(WeaponSets.scaling_of(cleaver).get("ranged_pct", 0.0)) == 0.0, "菜刀不吃 ranged_pct")
	chk(absf(float(WeaponSets.scaling_of(pistol).get("ranged_pct", 0.0)) - 1.0) < 0.0001,
		"远程武器（手枪）完整吃 ranged_pct")
	chk(absf(float(WeaponSets.scaling_of(chili).get("elem_pct", 0.0)) - 1.0) < 0.0001,
		"元素武器（辣椒炮）额外完整吃 elem_pct")
	chk(absf(float(WeaponSets.scaling_of(chili).get("ranged_pct", 0.0)) - 1.0) < 0.0001,
		"辣椒炮同时还是远程武器")
	# 脉冲（铁板烧）算近战，光束（微波炉）算远程
	chk(WeaponSets.scaling_of(defs.get("griddle", {})).has("melee_pct"), "脉冲（铁板烧）算近战伤害")
	chk(WeaponSets.scaling_of(defs.get("microwave", {})).has("ranged_pct"), "光束（微波炉）算远程伤害")

	# 同一套属性下，不同武器拿到的倍率必须不同 —— 这就是"build 分化"
	var st := {"dmg_pct": 0.0, "melee_pct": 0.50, "ranged_pct": 0.0, "elem_pct": 0.0}
	var m_melee := WeaponSets.damage_mult(cleaver, st)
	var m_gun := WeaponSets.damage_mult(pistol, st)
	chk(absf(m_melee - 1.5) < 0.0001, "+50%% 近战时，菜刀 ×1.5（实测 %.2f）" % m_melee)
	chk(absf(m_gun - 1.0) < 0.0001, "同一套属性下，手枪一点没涨（实测 %.2f）" % m_gun)
	st = {"dmg_pct": 0.10, "melee_pct": 0.0, "ranged_pct": 0.20, "elem_pct": 0.0}
	chk(absf(WeaponSets.damage_mult(pistol, st) - 1.30) < 0.0001, "手枪叠满：+10%% 全局 +20%% 远程 = ×1.3")
	chk(absf(WeaponSets.damage_mult(cleaver, st) - 1.10) < 0.0001, "菜刀只吃到 +10%% 全局")
	chk(WeaponSets.damage_mult(pistol, {"dmg_pct": -5.0}) > 0.0, "负属性堆到离谱也不会打出负伤害")

	return {"pass": _p, "fail": _f, "failures": _failures}
