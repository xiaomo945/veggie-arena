extends RefCounted

# 角色详情独立页（D3-4）的内容齐全性测试。
# 详情页五节（本命/怎么玩/买什么/点什么技能/自带属性）全部取自 characters.json，
# 一旦新增角色忘了写 trait/tip/best，玩家点开详情就会看到空白 —— 这里直接堵死。
# 同时校验：本命武器在数据里真实存在、技能 id 能落到真技能（否则详情页写成 "skill_xxx" 裸键）。

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
	var keys: Array = data.characters.keys()
	chk(keys.size() >= 4, "角色数 = %d（至少 4 个可玩）" % keys.size())
	var skill_ids := {}
	for s in data.skills_cfg():
		skill_ids[str((s as Dictionary).get("id", ""))] = true
	for k in keys:
		var e: Dictionary = data.character(str(k))
		# 中英双语都不能空：出海后 locale=en 时详情页同样要完整
		chk(not str(e.get("trait", "")).is_empty(), "%s 有本命特性(trait)" % k)
		chk(not str(e.get("trait_en", "")).is_empty(), "%s 有英文 trait_en" % k)
		chk(not str(e.get("tip", "")).is_empty(), "%s 有怎么玩(tip)" % k)
		chk(not str(e.get("tip_en", "")).is_empty(), "%s 有英文 tip_en" % k)
		chk(not str(e.get("best", "")).is_empty(), "%s 有配装建议(best)" % k)
		chk(not str(e.get("best_en", "")).is_empty(), "%s 有英文 best_en" % k)
		# 本命武器必须是真武器（详情页会显示它的名字，写成无效 key 直接露馅）
		var sig: Dictionary = e.get("signature", {}) as Dictionary
		var wk := str(sig.get("key", ""))
		chk(wk != "" and data.weapons.has(wk), "%s 本命武器有效：%s" % [k, wk])
		# 技能能解析到真 id，详情页就不是 skill_ 开头的裸翻译键
		var sid := SkillDef.skill_id_of(e)
		chk(skill_ids.has(sid), "%s 技能可解析：%s" % [k, sid])
	return {"pass": _p, "fail": _f, "failures": _failures}
