extends RefCounted

# C3 技能形态变体：同一个按键在不同 build 下是【两招】，不是"同一招数值更大"。
#
# 要保的事（破了就退回"武器只是数字堆叠"）：
#   1) 至少 5 个技能有 2 种以上形态 —— C3 的验收标准，掉了等于没做完。
#   2) 形态必须真的改机制（换 effect，或引入 burn_dps / knock 这类新字段）。
#      只把 dmg 乘大的"假形态"必须拦下：那和 mul 没区别，玩家看不出自己换了招。
#   3) 没凑够件数不能提前变形态（提前变 = 白送，阶梯就失去意义）。
#   4) 形态与数值可以来自【不同路线】：主堆的那条给数值、副凑的那条给形态。
#      这条一旦被改回"只取 need 最高那一条"，玩家凑的副路线就白费了。
#   5) 展示字段齐全 + I18n 有词条 —— 否则按钮上会显示出空名字。

const SkillDef := preload("res://core/SkillDef.gd")
const SP := preload("res://tests/SrcParse.gd")

# 这几个字段代表"机制"而不是"数值"：基础形态没有、形态里出现了 = 换了打法
const MECH_KEYS := ["burn_dps", "knock", "freeze_dur", "dur"]

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
	var skills: Array = data.skills_cfg()
	var chars: Dictionary = data.characters
	var no_stat := func(_n: String) -> float: return 0.0
	var i18n_src := SP.read("res://autoload/I18n.gd")
	chk(i18n_src.length() > 0, "I18n.gd 源码可读（读不到会让下面的词条断言假通过）")

	# 真实武器类与角色表：形态的 tag / char 必须落在这里面
	var all_tags := {}
	for wk in defs:
		for t in ((defs[wk]) as Dictionary).get("tags", []):
			all_tags[str(t)] = true

	# ---- 1) 形态数量：C3 的验收线 ----
	var multi := 0
	var variants := 0
	for s in skills:
		var sd := s as Dictionary
		if SkillDef.form_count(sd) >= 2:
			multi += 1
			variants += SkillDef.form_count(sd) - 1
	chk(multi >= 5, "至少 5 个技能有 2 种以上形态（实际 %d 个技能 / %d 个形态变体）" % [multi, variants])

	# ---- 2) 每个形态：字段齐全 + 真改机制 + 引用有效 + I18n 有名字 ----
	var bad_field: Array = []
	var fake_form: Array = []
	var no_i18n: Array = []
	var bad_ref: Array = []
	for s in skills:
		var sd := s as Dictionary
		var base_eff := str(sd.get("effect", ""))
		for v in sd.get("variants", []) as Array:
			var vd := v as Dictionary
			var f: Dictionary = vd.get("form", {}) as Dictionary
			if f.is_empty():
				continue
			var key := str(f.get("key", ""))
			for k in ["key", "zh", "en", "color"]:
				if str(f.get(k, "")).is_empty():
					bad_field.append(key + "." + k)
			if not chars.has(str(vd.get("char", ""))):
				bad_ref.append(key + ".char=" + str(vd.get("char", "")))
			if not all_tags.has(str(vd.get("tag", ""))):
				bad_ref.append(key + ".tag=" + str(vd.get("tag", "")))
			var changed := false
			var fe := str(f.get("effect", ""))
			if fe != "" and fe != base_eff:
				changed = true
			for k in MECH_KEYS:
				if f.has(k) and not sd.has(k):
					changed = true
			if not changed:
				fake_form.append(key)
			if i18n_src.find("\"skill_" + key + "\"") < 0:
				no_i18n.append(key)
	chk(bad_field.is_empty(), "每个形态都填齐 key/zh/en/color（缺：%s）" % str(bad_field))
	chk(fake_form.is_empty(), "形态真的改了机制，不是只把数字乘大（假形态：%s）" % str(fake_form))
	chk(no_i18n.is_empty(), "I18n 有每个形态的名字词条（缺：%s）" % str(no_i18n))
	chk(bad_ref.is_empty(), "形态的 char / tag 都指向真实角色与武器类（错：%s）" % str(bad_ref))

	# ---- 3) 触发条件：差一件就是差一件 ----
	var nova := SkillDef.base_of("frost_nova", skills)
	var blade2 := _stack("blade", 2, defs)
	var blade3 := _stack("blade", 3, defs)
	chk(SkillDef.form_key_of(nova, "mage", [], defs) == SkillDef.BASE_FORM,
		"一把刀都没有 → 基础形态（冰霜新星）")
	chk(SkillDef.form_key_of(nova, "mage", blade2, defs) == SkillDef.BASE_FORM,
		"只凑 2 件刀 → 不变形态（need=3）")
	chk(SkillDef.form_key_of(nova, "mage", blade3, defs) == "glacial_burst",
		"凑够 3 件刀 → 变冰锥爆裂")
	var nova_base := SkillDef.resolve(nova, "mage", [], defs, no_stat)
	var nova_form := SkillDef.resolve(nova, "mage", blade3, defs, no_stat)
	chk(str(nova_base.get("effect", "")) == "slow" and str(nova_form.get("effect", "")) == "damage",
		"形态生效后技能真的从【减速冻结】变成【范围伤害】")
	chk(float(nova_base.get("radius", 0.0)) > float(nova_form.get("radius", 0.0)),
		"冰锥爆裂范围更小（用爆发换覆盖：%.0f → %.0f）"
		% [float(nova_base.get("radius", 0.0)), float(nova_form.get("radius", 0.0))])

	# ---- 4) 主路线给数值、副路线给形态（两条可以同时吃到）----
	var elem6 := _stack("elemental", 6, defs)
	var mixed: Array = elem6.duplicate()
	for w in blade3:
		mixed.append(w)
	chk(SkillDef.form_key_of(nova, "mage", mixed, defs) == "glacial_burst",
		"主堆 6 件元素不会吃掉副凑 3 件刀的形态")
	var both := SkillDef.resolve(nova, "mage", mixed, defs, no_stat)
	chk(float(both.get("radius", 0.0)) > float(nova_base.get("radius", 0.0)),
		"同一发技能同时吃到元素档的半径加成（%.0f → %.0f）"
		% [float(nova_base.get("radius", 0.0)), float(both.get("radius", 0.0))])

	# ---- 5) 形态清单能预览（选角页那行字靠它）----
	var forms := SkillDef.forms_of(nova)
	chk(forms.size() == 2, "frost_nova 的形态清单有 2 项（基础 + 冰锥）")
	var has_base := false
	for f in forms:
		if bool((f as Dictionary).get("is_base", false)):
			has_base = true
	chk(has_base, "形态清单含基础形态（选角页要先说清原本是什么招）")

	return {"pass": _p, "fail": _f, "failures": _failures}

# 造 n 件同一类的武器（取该类第一把真实武器，重复 n 次）
func _stack(tag: String, n: int, defs: Dictionary) -> Array:
	var key := ""
	for wk in defs:
		if ((defs[wk]) as Dictionary).get("tags", []).has(tag):
			key = str(wk)
			break
	var out: Array = []
	for _i in n:
		out.append({"key": key, "lv": 1})
	return out
