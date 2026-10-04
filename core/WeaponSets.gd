extends RefCounted

# 武器套装（Q1）：32 把武器各带了 1~2 个 tag（data/weapons.json），
# 身上凑够 2 / 4 / 6 件同 tag 的武器就触发该档位的加成（data/weapon_sets.json）。
#
# 为什么值得做：没有套装时，"买什么武器"只是比大小（DPS 高的赢）；有了套装，
# 玩家要决定"这局走刀工还是走元素"，同一个武器在不同 build 里价值完全不同 ——
# 这是 Brotato 能让人反复开局的底层原因之一。
#
# 纯函数、不碰 autoload：便于单测，也便于 --script 模式跑配平模拟。

const Weapon := preload("res://core/Weapon.gd")

# 统计身上每个 tag 各有几件（一件带两个 tag 就两边各 +1）。
# weapons: [{key, lv, ...}]；defs: 武器定义表（Data.weapons 的形状）
static func tag_counts(weapons: Array, defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for w in weapons:
		if not (w is Dictionary):
			continue
		var key := str((w as Dictionary).get("key", ""))
		var def = defs.get(key, null)
		if not (def is Dictionary):
			continue
		for t in (def as Dictionary).get("tags", []):
			var tag := str(t)
			out[tag] = int(out.get(tag, 0)) + 1
	return out

# 某个 tag 在当前件数下达到第几档（0=没激活，1/2/3 对应 tiers 下标）
static func tier_of(count: int, set_def: Dictionary) -> int:
	var tiers = set_def.get("tiers", [])
	var best := 0
	for i in tiers.size():
		var t = tiers[i]
		if not (t is Dictionary):
			continue
		if count >= int((t as Dictionary).get("need", 99)):
			best = i + 1
	return best

# 当前激活的套装：{tag: {"count": n, "tier": t, "need_next": n|0}}
static func active_sets(weapons: Array, defs: Dictionary, sets: Dictionary) -> Dictionary:
	var counts := tag_counts(weapons, defs)
	var out: Dictionary = {}
	for tag in counts:
		var sd = sets.get(tag, null)
		if not (sd is Dictionary):
			continue
		var s := sd as Dictionary
		var n := int(counts[tag])
		var tier := tier_of(n, s)
		if tier <= 0:
			continue
		var tiers = s.get("tiers", [])
		var need_next := 0
		if tier < tiers.size():
			need_next = int((tiers[tier] as Dictionary).get("need", 0))
		out[tag] = {"count": n, "tier": tier, "need_next": need_next}
	return out

# 把所有激活档位的加成汇总成一个 {stat: value}（同名属性相加）。
# 这个结果要并进 GameState.stat_value，套装才算真的生效。
static func bonuses(weapons: Array, defs: Dictionary, sets: Dictionary) -> Dictionary:
	var act := active_sets(weapons, defs, sets)
	var out: Dictionary = {}
	for tag in act:
		var sd = sets.get(tag, null)
		if not (sd is Dictionary):
			continue
		var tiers = (sd as Dictionary).get("tiers", [])
		var tier := int((act[tag] as Dictionary).get("tier", 0))
		if tier <= 0 or tier > tiers.size():
			continue
		var stats = (tiers[tier - 1] as Dictionary).get("stats", {})
		for k in stats:
			var key := str(k)
			out[key] = float(out.get(key, 0.0)) + float(stats[k])
	return out

# ---- Q2 属性缩放：每把武器吃不同的伤害属性 ----
# Brotato 里一把武器写着 "Melee Damage +100% / Ranged +50%"，于是同一把武器
# 在不同 build 下手感完全不同。这里同理：
#   基础系数由"近战 / 远程"自动推导（type=melee 或 behavior in melee/pulse → melee）；
#   data 里的 "scl" 字段写额外吃的属性（如元素武器写 {"elem": 1.0}）。
static func scaling_of(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var base := "melee_pct" if _is_melee_dmg(def) else "ranged_pct"
	out[base] = 1.0
	var scl = def.get("scl", {})
	if scl is Dictionary:
		for k in (scl as Dictionary):
			out[str(k) + "_pct"] = float((scl as Dictionary)[k])
	return out

# 最终伤害倍率：1 + dmg_pct（全局） + Σ(系数 × 该属性值)
# stat 取值函数由调用方注入（GameState.stat_value），core 层保持无 autoload 依赖。
static func damage_mult(def: Dictionary, stats: Dictionary) -> float:
	var m := 1.0 + float(stats.get("dmg_pct", 0.0))
	for k in scaling_of(def):
		m += float(scaling_of(def)[k]) * float(stats.get(k, 0.0))
	return maxf(0.05, m)

# 近战/脉冲算近战伤害；光束虽然也是扇形结算，但它是"远距离射击"，算远程
static func _is_melee_dmg(def: Dictionary) -> bool:
	if Weapon.is_melee(def):
		return true
	match Weapon.behavior_of(def):
		"melee", "pulse":
			return true
		_:
			return false
