extends RefCounted

# 每个角色【独占一条 build 路线】的守门测试。
#
# 为什么单独一个文件：这条规则是"角色可玩性"的底线，不是联动细节；
# 塞进 test_synergy.gd 会把它顶过 300 行红线（架构守卫硬失败），
# 而规则本身也值得有自己一块地方讲清楚。
#
# 钉死三件事：
#   1) 技能不许撞车 —— 两个角色共用同一个 skill id，等于其中一个是下位替代。
#   2) 本命武器不许撞车 —— 本命是"这个角色为什么值得研究"的入口，
#      两人共用同一把，选角页看着十几个角色，玩起来是同一局。
#   3) 每个角色都要真的拿到自己写的那个技能 —— SkillDef 在技能 id 写错时
#      会【静默退回通用技 frost】：按钮照样能按、CD 照样转，
#      只是这个角色从头到尾都不是他自己的玩法，而且没有任何报错。

const SkillDef := preload("res://core/SkillDef.gd")

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
	var chars: Dictionary = data.characters
	var skills: Array = data.skills_cfg()
	var no_stat := func(_n: String) -> float: return 0.0
	for ck in chars:
		(chars[ck] as Dictionary)["_key"] = str(ck)

	# 0) 角色条目必须带 _key —— 缺了它，SkillDef 认不出"这是哪个角色"，
	#    技能变体整条链路静默失效（data 层由 Data._tag_characters 注入）。
	var no_key: Array = []
	for ck in chars:
		if str((chars[ck] as Dictionary).get("_key", "")) != str(ck):
			no_key.append(str(ck))
	chk(no_key.is_empty(), "每个角色条目都带 _key（缺：%s）"
		% (", ".join(no_key) if no_key.size() > 0 else "无"))

	# ---- 9b) 每个角色【独占】一条 build 路线：技能与本命武器都不许撞车 ----
	# 两个角色共用一把本命武器，等于其中一个是另一个的下位替代 ——
	# 选角页看着有十几个，实际玩起来是同一局。C2 加了三个机制型角色后这条更重要。
	var dup_skill: Array = []
	var seen_skill := {}
	for ck in chars:
		var sid := SkillDef.skill_id_of(chars[ck] as Dictionary)
		if seen_skill.has(sid):
			dup_skill.append("%s/%s=%s" % [seen_skill[sid], ck, sid])
		seen_skill[sid] = ck
	chk(dup_skill.is_empty(), "每个角色有专属技能，没有两人共用（撞车：%s）"
		% (", ".join(dup_skill) if dup_skill.size() > 0 else "无"))
	var dup_sig: Array = []
	var seen_sig := {}
	for ck in chars:
		var sig := chars[ck] as Dictionary
		var wkey := str((sig.get("signature", {}) as Dictionary).get("key", ""))
		if wkey.is_empty():
			continue
		if seen_sig.has(wkey):
			dup_sig.append("%s/%s=%s" % [seen_sig[wkey], ck, wkey])
		seen_sig[wkey] = ck
	chk(dup_sig.is_empty(), "每个角色独占一把本命武器（撞车：%s）"
		% (", ".join(dup_sig) if dup_sig.size() > 0 else "无"))

	# ---- 9c) 全角色逐个验：拿到自己的技能，且凑够羁绊后技能被武器放大 ----
	# 只测某一个角色会漏 view：新加的角色可能把技能指到一个不存在 id 上，
	# 而 SkillDef 会【静默退回通用技 frost】 —— 按钮照样能按，只是不是他要的那个招。
	var wrong: Array = []
	var no_boost: Array = []
	for ck in chars:
		var ce := chars[ck] as Dictionary
		var want := SkillDef.skill_id_of(ce)
		var got := SkillDef.active_skill(ce, skills, [], defs, no_stat)
		if str(got.get("id", "")) != want:
			wrong.append("%s想要%s拿到%s" % [ck, want, str(got.get("id", ""))])
			continue
		# 凑够变体所需件数：优先用同 tag 的武器（本命武器天然带该 tag）
		var pack: Array = []
		var var_tag := ""
		var need_n := 4
		for s in skills:
			if str((s as Dictionary).get("id", "")) != want:
				continue
			for v in ((s as Dictionary).get("variants", []) as Array):
				var vd := v as Dictionary
				if str(vd.get("char", "")) == str(ck):
					var_tag = str(vd.get("tag", ""))
					need_n = int(vd.get("need", 4))
		if var_tag == "":
			continue
		# 用属于该 tag 的武器堆到 need 件（不足则退而求其次塞本命）
		for wk in defs:
			if pack.size() >= need_n:
				break
			var wd := defs[wk] as Dictionary
			if (wd.get("tags", []) as Array).has(var_tag):
				pack.append({"key": wk, "lv": 1})
		while pack.size() < need_n:
			pack.append({"key": str((ce.get("signature", {}) as Dictionary).get("key", "pistol")), "lv": 1})
		var boosted := SkillDef.active_skill(ce, skills, pack, defs, no_stat)
		var plain := SkillDef.active_skill(ce, skills, [], defs, no_stat)
		var grew := false
		for f in ["dmg", "amount", "poison_dps_pct", "radius", "dur", "slow_dur"]:
			if float(boosted.get(f, 0.0)) > float(plain.get(f, 0.0)):
				grew = true
		if not grew:
			no_boost.append("%s(%s)" % [ck, var_tag])
	chk(wrong.is_empty(), "每个角色都拿到自己指定的那种技能（错配：%s）"
		% (", ".join(wrong) if wrong.size() > 0 else "无"))
	chk(no_boost.is_empty(), "每个角色凑够羁绊件数后技能真的变强（没变化的：%s）"
		% (", ".join(no_boost) if no_boost.size() > 0 else "无"))

	return {"pass": _p, "fail": _f, "failures": _failures}
