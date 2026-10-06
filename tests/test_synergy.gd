extends RefCounted

# 角色 × 武器 × 技能 × 道具 四元素联动（Q3）：core/Synergy.gd + core/SkillDef.gd。
#
# 要保的事（这些一旦破了，游戏就退回"武器各管各的、买谁都一样"）：
#   1) 每个角色都必须有 bond / signature / skill，且引用都指向真实存在的
#      武器 / 武器类 / 技能 —— 写错一个 key，那个角色就静默少一整条成长线。
#   2) 阶梯必须【边际递增】：堆得越多，下一档给得越狠。递增反过来（越堆越不值）
#      玩家就会随手换武器，本命机制直接失效。
#   3) 同一把武器在不同角色手里加成必须不同（这是"角色决定玩法"的硬证据）。
#   4) 技能变体：角色 + 本命类武器凑够件数 → 技能真的变强（不是配了不生效）。
#   5) 道具的 skill_power 必须能放大技能 —— 四元素闭环的最后一环。

const Synergy := preload("res://core/Synergy.gd")
const SkillDef := preload("res://core/SkillDef.gd")
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

func run(data) -> Dictionary:
	var defs: Dictionary = data.weapons
	var sets: Dictionary = data.weapon_sets
	var chars: Dictionary = data.characters
	var skills: Array = data.skills_cfg()

	# ---- 1) 每个角色的三条成长线都指向真实存在的东西 ----
	var bad_sig: Array = []
	var bad_bond: Array = []
	var bad_skill: Array = []
	for ck in chars:
		var c := chars[ck] as Dictionary
		var sig := c.get("signature", {}) as Dictionary
		var bd := c.get("bond", {}) as Dictionary
		var sk := str(c.get("skill", ""))
		if sig.is_empty() or not defs.has(str(sig.get("key", ""))):
			bad_sig.append(ck)
		if bd.is_empty() or not sets.has(str(bd.get("tag", ""))):
			bad_bond.append(ck)
		if sk.is_empty() or SkillDef.base_of(sk, skills).is_empty():
			bad_skill.append(ck)
	chk(bad_sig.is_empty(), "每个角色的本命武器都是真实武器（异常：%s）" % str(bad_sig))
	chk(bad_bond.is_empty(), "每个角色的羁绊类是真实武器类（异常：%s）" % str(bad_bond))
	chk(bad_skill.is_empty(), "每个角色的专属技能都能在技能库找到（异常：%s）" % str(bad_skill))

	# ---- 2) 阶梯边际递增：每多一件，新增收益不能比上一档少 ----
	var flat: Array = []
	for ck in chars:
		var c := chars[ck] as Dictionary
		for branch in ["signature", "bond"]:
			var br := c.get(branch, {}) as Dictionary
			if br.is_empty():
				continue
			var tiers := br.get("tiers", []) as Array
			var prev := -1.0
			for i in tiers.size():
				var st := (tiers[i] as Dictionary).get("stats", {}) as Dictionary
				var tot := 0.0
				for k in st:
					tot += absf(float(st[k]))
				if tot <= prev:
					flat.append("%s.%s#%d" % [ck, branch, i + 1])
				prev = tot
	chk(flat.is_empty(), "所有角色的羁绊阶梯都边际递增（异常档位：%s）" % str(flat))

	# ---- 3) 加成是真属性（拼错的 key 会静默失效）----
	var unknown: Array = []
	for ck in chars:
		var c := chars[ck] as Dictionary
		for branch in ["signature", "bond"]:
			var tiers := (c.get(branch, {}) as Dictionary).get("tiers", []) as Array
			for i in tiers.size():
				var st := (tiers[i] as Dictionary).get("stats", {}) as Dictionary
				for k in st:
					if Stats.entry(str(k)).is_empty():
						unknown.append("%s.%s:%s" % [ck, branch, str(k)])
	chk(unknown.is_empty(), "羁绊加成的属性 key 都在属性目录里（未知：%s）" % str(unknown))

	# ---- 4) 堆满本命：确实拿到满档加成 ----
	var cmd := chars["commando"] as Dictionary
	var sig_key := str((cmd.get("signature", {}) as Dictionary).get("key", ""))
	var six: Array = []
	for i in 6:
		six.append({"key": sig_key, "lv": 1})
	var b6 := Synergy.bonuses(six, cmd, defs)
	var b1 := Synergy.bonuses([{"key": sig_key, "lv": 1}], cmd, defs)
	chk(float(b6.get("crit_chance", 0.0)) > float(b1.get("crit_chance", 0.0)),
		"堆 6 把本命比 1 把给得多（%.0f%% vs %.0f%%）"
		% [float(b6.get("crit_chance", 0.0)) * 100.0, float(b1.get("crit_chance", 0.0)) * 100.0])
	chk(float(b6.get("crit_chance", 0.0)) >= 0.35,
		"满档本命暴击加成到位（实测 %.0f%%）" % (float(b6.get("crit_chance", 0.0)) * 100.0))
	chk(Synergy.signature_count(six, sig_key) == 6, "本命按【持有把数】计数（6 把=6）")

	# ---- 5) 同一把武器，不同角色收益不同（角色决定玩法的硬证据）----
	var pistol6: Array = []
	for i in 6:
		pistol6.append({"key": "pistol", "lv": 1})
	var cmd_b := Synergy.bonuses(pistol6, cmd, defs)
	var turnip_b := Synergy.bonuses(pistol6, chars["turnip"] as Dictionary, defs)
	chk(float(cmd_b.get("crit_chance", 0.0)) > 0.0,
		"老手拿 6 把手枪吃满暴击（%.0f%%）" % (float(cmd_b.get("crit_chance", 0.0)) * 100.0))
	chk(float(turnip_b.get("crit_chance", 0.0)) == 0.0,
		"田园萝卜拿同样 6 把手枪【没有】暴击加成（角色差异生效）")
	chk(Synergy.is_signature(cmd, "pistol") and not Synergy.is_signature(chars["turnip"] as Dictionary, "pistol"),
		"手枪是老手的本命、不是萝卜的本命")

	# ---- 6) 羁绊类：本命类武器凑够件数才给加成 ----
	var gun4: Array = []
	for i in 4:
		gun4.append({"key": "smg", "lv": 1})
	var mag := chars["magnet"] as Dictionary
	var bg4 := Synergy.bonuses(gun4, mag, defs)
	chk(float(bg4.get("rate_pct", 0.0)) > 0.0,
		"磁铁萝卜凑 4 件枪械拿到羁绊攻速（%.0f%%）" % (float(bg4.get("rate_pct", 0.0)) * 100.0))
	chk(Synergy.bond_count(gun4, "gun", defs) == 4, "枪械件数按 tag 统计（4 件=4）")

	# ---- 7) 技能变体：角色 + 武器凑够 → 技能真的变强 ----
	var no_stat := func(_n: String) -> float: return 0.0
	var mark_base := SkillDef.base_of("mark", skills)
	var mark_plain := SkillDef.resolve(mark_base, "commando", [], defs, no_stat)
	var mark_boost := SkillDef.resolve(mark_base, "commando", gun4, defs, no_stat)
	chk(float(mark_boost.get("dmg", 0.0)) > float(mark_plain.get("dmg", 0.0)),
		"老手凑 4 件枪 → 标记射击伤害被变体放大（%.0f → %.0f）"
		% [float(mark_plain.get("dmg", 0.0)), float(mark_boost.get("dmg", 0.0))])
	var other := SkillDef.resolve(mark_base, "bruiser", gun4, defs, no_stat)
	chk(absf(float(other.get("dmg", 0.0)) - float(mark_plain.get("dmg", 0.0))) < 0.001,
		"别的角色凑同样 4 件枪【不会】触发老手的变体（角色限定生效）")

	# ---- 8) 道具的 skill_power 放大技能（第四环闭环）----
	var pow15 := func(_n: String) -> float: return 0.15 if _n == "skill_power" else 0.0
	var boosted := SkillDef.resolve(mark_base, "commando", [], defs, pow15)
	chk(float(boosted.get("dmg", 0.0)) > float(mark_plain.get("dmg", 0.0)),
		"买技能强度道具 → 技能伤害变高（%.0f → %.0f）"
		% [float(mark_plain.get("dmg", 0.0)), float(boosted.get("dmg", 0.0))])

	# ---- 9) 角色拿到的是自己的技能 ----
	var ids: Array = []
	for ck in chars:
		ids.append(SkillDef.skill_id_of(chars[ck] as Dictionary))
	chk(ids.has("mark") and ids.has("quake") and ids.has("combo"),
		"不同角色拿到不同专属技能（含 mark/quake/combo）")
	chk(SkillDef.active_skill(cmd, skills, [], defs, no_stat).get("id", "") == "mark",
		"老手的生效技能是 mark（角色专属）")

	return {"pass": _p, "fail": _f, "failures": _failures}
