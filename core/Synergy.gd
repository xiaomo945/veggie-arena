extends RefCounted

# 角色 × 武器 羁绊（Q3 核心）：让玩家为了一个角色去钻研"该拿什么武器"。
#
# 为什么必须有这一层：
#   改造前，角色只有一堆静态属性（+25% 远程之类），武器是各管各的独立个体。
#   结果就是"商店刷出什么买什么"——因为拿哪把武器，角色给你的加成都一样，
#   买武器只是在比大小，没有"这把对我有用、那把对我没用"的判断，也就没有
#   "攒钱等它刷出来"的期待感。这一层把【角色身份】接进【武器选择】：
#
#   1) 本命武器 signature —— 每个角色有自己的一把本命（commando 的手枪、
#      bruiser 的擀面杖）。按【持有把数】分 6 档，边际递增：拿 1 把只是小甜头，
#      堆满 6 把才是质变。于是"再买一把同样的"永远比"换把别的"划算 ——
#      这就是 Brotato 里老手只买树枝的由来，也是"换武器成本巨大"的来源。
#   2) 武器类羁绊 bond —— 角色对某一类武器（gun/blade/heavy/elemental/kitchen）
#      有专属加成，按该类件数 2/4/6 分档。它决定角色"大体走哪一路"。
#
#   同一把武器可以是多个角色的本命（合理：pistol 对 commando 是暴击流，
#   对别人可能只是普通枪）—— 因为加成写在【角色】这一侧，不在武器上，
#   所以"同一把武器在不同角色手里效果不同"是天然结果，不需要额外配置。
#
# 模块化约定（改东西不会改崩别的）：
#   - 角色侧只认 data/characters.json 的 bond / signature 两个字段；
#   - 武器侧只认 data/weapons.json 的 tags；
#   - 阶梯形状与数值全在角色自己的块里，改 A 角色碰不到 B 角色；
#   - 本文件是纯函数，不碰 autoload（架构守卫 R2），可直接在 --script 下单测。

const WeaponSets := preload("res://core/WeaponSets.gd")

# ---- 计数 ----

# 本命武器当前持有几把（同 key 累加，不看等级：堆件数才有"再买一把"的动力）
static func signature_count(weapons: Array, key: String) -> int:
	if key.is_empty():
		return 0
	var n := 0
	for w in weapons:
		if not (w is Dictionary):
			continue
		if str((w as Dictionary).get("key", "")) == key:
			n += 1
	return n

# 羁绊类当前几件（一件带多个 tag 就各记一次，与套装口径一致）
static func bond_count(weapons: Array, tag: String, defs: Dictionary) -> int:
	if tag.is_empty():
		return 0
	return int(WeaponSets.tag_counts(weapons, defs).get(tag, 0))

# ---- 档位 ----

# 达成第几档（1 起；0=一件都没有）。tiers 里的 need 是"该档需要的件数"。
# 与套装同口径：只看最高达成的那一档，档位给的 stats 是【总】加成不是累加。
static func tier_of(count: int, tiers) -> int:
	if not (tiers is Array):
		return 0
	var best := 0
	for i in (tiers as Array).size():
		var t = (tiers as Array)[i]
		if not (t is Dictionary):
			continue
		if count >= int((t as Dictionary).get("need", 99)):
			best = i + 1
	return best

# 距离下一档还差几件（已满级返回 0）
static func next_need(count: int, tiers) -> int:
	if not (tiers is Array):
		return 0
	for i in (tiers as Array).size():
		var t = (tiers as Array)[i]
		if not (t is Dictionary):
			continue
		var need := int((t as Dictionary).get("need", 99))
		if count < need:
			return need
	return 0

# 第 tier 档给出的加成表（tier 从 1 起；越界/0 返回空表）
static func tier_stats(tiers, tier: int) -> Dictionary:
	if not (tiers is Array) or tier <= 0 or tier > (tiers as Array).size():
		return {}
	var t = (tiers as Array)[tier - 1]
	if not (t is Dictionary):
		return {}
	return (t as Dictionary).get("stats", {}) as Dictionary

# ---- 汇总 ----

# 该角色此刻从羁绊里拿到的全部加成 {stat: value}（本命 + 武器类，同名相加）。
# 这个结果必须并进 GameState.stat_value，否则羁绊只是 UI 上一行字。
static func bonuses(weapons: Array, char_entry: Dictionary, defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_merge(out, _branch_stats(weapons, char_entry, defs, "signature"))
	_merge(out, _branch_stats(weapons, char_entry, defs, "bond"))
	return out

# ---- UI 进度 ----
# 返回 {"signature": {...}, "bond": {...}}，每项：
#   {"key"/"tag", "count", "tier", "need_next", "max_need", "stats_now"}
# 商店/选角页拿它画"3/6 还差 3 件"和"本命 +24%"。
static func progress(weapons: Array, char_entry: Dictionary, defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var sig: Dictionary = char_entry.get("signature", {}) as Dictionary
	if not sig.is_empty():
		var key := str(sig.get("key", ""))
		var tiers = sig.get("tiers", [])
		var n := signature_count(weapons, key)
		var tier := tier_of(n, tiers)
		out["signature"] = {
			"key": key, "count": n, "tier": tier,
			"need_next": next_need(n, tiers),
			"max_need": _max_need(tiers),
			"stats_now": tier_stats(tiers, tier),
		}
	var bd: Dictionary = char_entry.get("bond", {}) as Dictionary
	if not bd.is_empty():
		var tag := str(bd.get("tag", ""))
		var tiers2 = bd.get("tiers", [])
		var n2 := bond_count(weapons, tag, defs)
		var tier2 := tier_of(n2, tiers2)
		out["bond"] = {
			"tag": tag, "count": n2, "tier": tier2,
			"need_next": next_need(n2, tiers2),
			"max_need": _max_need(tiers2),
			"stats_now": tier_stats(tiers2, tier2),
		}
	return out

# 某把武器对当前角色是"本命"吗（商店卡片高亮用）
static func is_signature(char_entry: Dictionary, weapon_key: String) -> bool:
	var sig: Dictionary = char_entry.get("signature", {}) as Dictionary
	return not weapon_key.is_empty() and str(sig.get("key", "")) == weapon_key

# 某把武器属于当前角色的羁绊类吗（商店卡片次一级高亮用）
static func in_bond(char_entry: Dictionary, weapon_key: String, defs: Dictionary) -> bool:
	var bd: Dictionary = char_entry.get("bond", {}) as Dictionary
	var tag := str(bd.get("tag", ""))
	if tag.is_empty() or weapon_key.is_empty():
		return false
	var def = defs.get(weapon_key, null)
	if not (def is Dictionary):
		return false
	return tag in ((def as Dictionary).get("tags", []) as Array)

# ---- 内部 ----

# 取一条分支（signature / bond）当前档位的加成表
static func _branch_stats(weapons: Array, char_entry: Dictionary, defs: Dictionary,
		branch: String) -> Dictionary:
	var br: Dictionary = char_entry.get(branch, {}) as Dictionary
	if br.is_empty():
		return {}
	var tiers = br.get("tiers", [])
	var n := 0
	if branch == "signature":
		n = signature_count(weapons, str(br.get("key", "")))
	else:
		n = bond_count(weapons, str(br.get("tag", "")), defs)
	return tier_stats(tiers, tier_of(n, tiers))

static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		var key := str(k)
		dst[key] = float(dst.get(key, 0.0)) + float(src[k])

static func _max_need(tiers) -> int:
	if not (tiers is Array):
		return 0
	var m := 0
	for i in (tiers as Array).size():
		var t = (tiers as Array)[i]
		if t is Dictionary:
			m = maxi(m, int((t as Dictionary).get("need", 0)))
	return m
