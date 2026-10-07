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
#   3) 杂食 variety —— 按【身上有几种武器类】分档，与 bond 正好相反：
#      bond 奖励"同一类堆到底"，variety 奖励"每样来一件"。
#
#      为什么要有这条反向的线（用户点名的"每个角色都要有独特玩法"）：
#        12 个角色都在鼓励【堆同一把 / 堆同一类】，于是所有局的最优解形状一样 ——
#        "刷出什么买什么"和"照着一条路攒"之间其实没有区别，玩家感受不到角色差异。
#        田园萝卜 turnip 是全游戏唯一【没有专精】的角色：它的本命不是某一把武器，
#        而是"齐全"。拿 6 把一模一样的枪在它手里反而是最差解 —— 这一条把
#        "为了一个角色去重新学怎么买东西"变成真实存在的体验。
#      对轻度玩家它也是最友好的一条：不需要认识任何武器名字，只要记得
#        "武器栏里颜色越杂越强"，看一眼就懂。
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

# 武器"类"清单：与 data/weapon_sets.json 的类 key 一一对应。
# ⚠️ 这里写死了一份，靠 tests/test_synergy.gd 断言它和 weapon_sets.json 完全同步 ——
#    以后加第六类武器时，测试会直接失败提醒你来改，不会静默少算一类。
const CLASSES := ["blade", "heavy", "gun", "elemental", "kitchen"]

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

# 杂食：身上出现了【几种】武器类（0~5）。同一类拿几把都只算 1 种 ——
# 这正是它和 bond 相反的地方：堆同一类在这里一分钱不值。
static func variety_count(weapons: Array, defs: Dictionary) -> int:
	var counts := WeaponSets.tag_counts(weapons, defs)
	var n := 0
	for c in CLASSES:
		if int(counts.get(c, 0)) > 0:
			n += 1
	return n

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
	_merge(out, _branch_stats(weapons, char_entry, defs, "variety"))
	return out

# ---- UI 进度 ----
# 返回 {"signature": {...}, "bond": {...}, "variety": {...}}，每项：
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
	var vr: Dictionary = char_entry.get("variety", {}) as Dictionary
	if not vr.is_empty():
		var tiers3 = vr.get("tiers", [])
		var n3 := variety_count(weapons, defs)
		var tier3 := tier_of(n3, tiers3)
		out["variety"] = {
			"tag": "variety", "count": n3, "tier": tier3,
			"need_next": next_need(n3, tiers3),
			"max_need": _max_need(tiers3),
			"stats_now": tier_stats(tiers3, tier3),
		}
	return out

# 再买一件（本命 or 羁绊类）会带来什么变化 —— 商店卡片上那个"买了给多少"的数字。
#   {"cross": bool, "need": int, "stat": String, "delta": float}
#   cross=true  → 买下就跨档，delta 是立刻拿到的属性增量（stat 是属性 key）
#   cross=false → 买了也不跨档，need 是"买完之后还差几件"（0 = 已经满档）
# 放在 core 而不是 UI：这一段是纯规则，必须能单测（UI 层用 autoload，单测拉不起来）。
static func next_gain(weapons: Array, char_entry: Dictionary, defs: Dictionary,
		branch: String) -> Dictionary:
	var br := char_entry.get(branch, {}) as Dictionary
	var tiers = br.get("tiers", [])
	var n := _count_of(weapons, char_entry, defs, branch)
	var t_now := tier_of(n, tiers)
	var t_after := tier_of(n + 1, tiers)
	if t_after <= t_now:
		var need := next_need(n + 1, tiers)
		return {"cross": false, "need": maxi(0, need - (n + 1)), "stat": "", "delta": 0.0}
	# 跨档：取增量最大的那条属性（卡片只有一行，全写会太长）
	var a := tier_stats(tiers, t_now)
	var b := tier_stats(tiers, t_after)
	var best_k := ""
	var best_d := 0.0
	for k in b:
		var dv := float(b[k]) - float(a.get(k, 0.0))
		if dv > best_d:
			best_d = dv
			best_k = str(k)
	return {"cross": true, "need": 0, "stat": best_k, "delta": best_d}

# 某把武器对当前角色是"本命"吗（商店卡片高亮用）
static func is_signature(char_entry: Dictionary, weapon_key: String) -> bool:
	var sig: Dictionary = char_entry.get("signature", {}) as Dictionary
	return not weapon_key.is_empty() and str(sig.get("key", "")) == weapon_key

# 这张卡能带来一个【新的】武器类吗（杂食角色的"该不该买"判据）。
# 与 bond 相反：bond 问"它是不是我要堆的那一类"，这里问"我身上还没有这一类吗"。
# 只有能开出新类的卡才值得杂食角色优先拿 —— 同一类的第 N 把对它一文不值。
static func is_variety_gain(char_entry: Dictionary, weapon_key: String, defs: Dictionary,
		weapons: Array) -> bool:
	if (char_entry.get("variety", {}) as Dictionary).is_empty():
		return false
	var def = defs.get(weapon_key, null)
	if not (def is Dictionary):
		return false
	var held := WeaponSets.tag_counts(weapons, defs)
	for t in (def as Dictionary).get("tags", []):
		if CLASSES.has(str(t)) and int(held.get(str(t), 0)) <= 0:
			return true
	return false

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
	var n := _count_of(weapons, char_entry, defs, branch)
	return tier_stats(tiers, tier_of(n, tiers))

# 一条分支当前"攒到几件了"：signature 按同 key 把数、bond 按 tag 件数、variety 按类种数。
# 三种数法完全不同，但后面取档位/算增量的逻辑完全一样，所以只在这里分叉一次。
static func _count_of(weapons: Array, char_entry: Dictionary, defs: Dictionary,
		branch: String) -> int:
	var br: Dictionary = char_entry.get(branch, {}) as Dictionary
	match branch:
		"signature":
			return signature_count(weapons, str(br.get("key", "")))
		"variety":
			return variety_count(weapons, defs)
		_:
			return bond_count(weapons, str(br.get("tag", "")), defs)

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
