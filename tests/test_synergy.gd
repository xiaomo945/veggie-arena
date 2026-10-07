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
const Character := preload("res://core/Character.gd")
const Stats := preload("res://core/Stats.gd")
const SP := preload("res://tests/SrcParse.gd")

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


	# ---- 10) 技能 UI 完整性（真踩过的漂移：改了技能表忘了改按钮）----
	# 技能表角色化之后，HUD 扇面还写死 id="poison"、I18n 只有 frost/poison 两个名字，
	# 于是按钮点了没反应、名字显示成 "skill_mark" 这种 key。肉眼看不出来，钉死在源码上。
	var i18n_src := SP.read("res://autoload/I18n.gd")
	var btn_src := SP.read("res://ui/HUD/SkillButton.gd")
	var layout_src := SP.read("res://ui/HUD/HudLayout.gd")
	chk(i18n_src.length() > 0 and btn_src.length() > 0 and layout_src.length() > 0,
		"能读到 I18n / SkillButton / HudLayout 源码（路径写错会导致假通过）")
	var skill_ids: Array = []
	for s in skills:
		skill_ids.append(str((s as Dictionary).get("id", "")))
	var no_name: Array = []
	var no_color: Array = []
	for sid in skill_ids:
		if str(sid).is_empty():
			continue
		if not ('"skill_%s"' % sid) in i18n_src:
			no_name.append(sid)
		if not ('"%s": Color' % sid) in btn_src:
			no_color.append(sid)
	chk(no_name.is_empty(), "每个技能都有按钮短名翻译 skill_<id>（缺：%s）" % str(no_name))
	chk(no_color.is_empty(), "每个技能在按钮配色表里都有颜色（缺：%s）" % str(no_color))
	# 反向：I18n 里不能留着指向"已经不存在的技能"的僵尸词条
	var re := RegEx.new()
	re.compile("\"skill_([a-z_]+)\"")
	var orphan: Array = []
	for m in re.search_all(i18n_src):
		if not skill_ids.has(m.get_string(1)):
			orphan.append(m.get_string(1))
	chk(orphan.is_empty(), "I18n 里没有指向不存在技能的残留词条（残留：%s）" % str(orphan))
	var fan_body := SP.func_body(layout_src, "func buttons_fan()")
	chk(fan_body.length() > 0 and not fan_body.contains("\"id\""),
		"HUD 扇面按钮不写死技能 id（按当前角色取，避免放出技能表里没有的招）")

	# ---- 10b) 数据表里的 effect 必须在 SkillSystem 里有分支 ----
	# 反过来的老坑：SkillSystem 曾经实现了 poison 却没有任何技能用它（点了没反应的死技能）。
	# 现在反过来也危险 —— data/skills.json 里写一个 cast() 不认识的 effect，
	# 按钮转圈、音效照放，但敌人一滴血不掉，测试也会全绿。
	var sys_src := SP.read("res://scenes/SkillSystem.gd")
	chk(sys_src.length() > 0, "能读到 SkillSystem 源码（路径写错会导致下面的断言假通过）")
	var no_branch: Array = []
	for s in skills:
		var eff := str((s as Dictionary).get("effect", ""))
		if eff.is_empty() or not ('"%s"' % eff) in sys_src:
			no_branch.append("%s=%s" % [str((s as Dictionary).get("id", "?")), eff])
	chk(no_branch.is_empty(), "每个技能的 effect 都在 SkillSystem 里有分支（没有的：%s）"
		% (", ".join(no_branch) if no_branch.size() > 0 else "无"))
	# 分支存在不等于真的干活：爆燃火候这种"不伤人只涨火"的技能，
	# 万一 _apply_heat 被人改成空函数，按钮照样转圈，玩家只会觉得这角色很废。
	var heat_body := SP.func_body(sys_src, "func _apply_heat(cfg: Dictionary)")
	chk(heat_body.contains("GameState.add_wok"),
		"火候技能真的会往锅里加火（否则爆炒萝卜就是个废角色）")


	# ---- 11) "再买一件给多少"（B2：商店卡片上的那个数字）----
	# 只描金边蓝边，玩家只知道"这张对我有用"；写上数字才知道"现在买值不值"。
	# 规则必须边际递增：第 2 把给的要比第 1 把多，否则"再买一把"没有理由。
	var cmde := chars["commando"] as Dictionary
	var g0 := Synergy.next_gain([], cmde, defs, "signature")
	chk(bool(g0.get("cross", false)) and absf(float(g0.get("delta", 0.0)) - 0.04) < 0.001,
		"老手买第 1 把手枪就跨档（暴击 +4%，实测 %.2f）" % float(g0.get("delta", 0.0)))
	var g1 := Synergy.next_gain([{"key": "pistol", "lv": 1}], cmde, defs, "signature")
	chk(bool(g1.get("cross", false)) and float(g1.get("delta", 0.0)) > float(g0.get("delta", 0.0)),
		"再买一把的收益更大（%.2f → %.2f，卡片上写得出边际递增）"
		% [float(g0.get("delta", 0.0)), float(g1.get("delta", 0.0))])
	var g6 := Synergy.next_gain(six, cmde, defs, "signature")
	chk(not bool(g6.get("cross", false)) and int(g6.get("need", -1)) == 0,
		"满档后再买一件不跨档且 need=0（卡片显示已满）")
	var gb := Synergy.next_gain([], cmde, defs, "bond")
	chk(not bool(gb.get("cross", false)) and int(gb.get("need", -1)) == 1,
		"枪械羁绊一件都没有时，买 1 件还差 1 件到档1（need=%d，文案是买完之后的状态）"
		% int(gb.get("need", -1)))
	var gb2 := Synergy.next_gain(gun4, cmde, defs, "bond")
	chk(not bool(gb2.get("cross", false)) and int(gb2.get("need", -1)) == 1,
		"已凑 4 件枪械时买 1 件变 5 件，仍差 1 件才跨档3（need=%d）" % int(gb2.get("need", -1)))
	var gun5: Array = []
	for _i in 5:
		gun5.append({"key": "smg", "lv": 1})
	var gb3 := Synergy.next_gain(gun5, cmde, defs, "bond")
	chk(bool(gb3.get("cross", false)) and float(gb3.get("delta", 0.0)) > 0.0,
		"已凑 5 件时再买 1 件就跨到档3（%.2f）" % float(gb3.get("delta", 0.0)))
	return {"pass": _p, "fail": _f, "failures": _failures}
