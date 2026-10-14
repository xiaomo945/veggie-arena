extends RefCounted

# 四元素联动第二环：武器/道具【产出】技能（core/SkillSlots.gd + SkillDef 的 base_mul）。
#
# 要保的事（破了就退回"技能和道具武器完全脱节"）：
#   1) 本命技永远在槽 0、威力 100% —— 角色的招牌不能排到白送的后面。
#   2) 武器赠送按持有顺序入槽、道具赠送排最后，基础值打 GIFT_MUL 折。
#   3) 上限 3 槽：来源再多也按"先武器后道具"截断，不是把 HUD 扇面撑爆。
#   4) 同一技能只占一槽（本命 > 武器 > 道具，先到先得）—— 买了不重复计费。
#   5) 折扣只作用于强度/范围（GIFT_MUL_KEYS），冷却不打折。
#   6) 赠送技照样吃 variants：法师拿冰桶送冰镇，堆 4 件元素一样触发他的强化。
#   7) 数据守门：武器表/道具表的 skill 字段必须指向真实技能 id（写错 = 静默丢一个技能）。

const SkillSlots := preload("res://core/SkillSlots.gd")
const SkillDef := preload("res://core/SkillDef.gd")
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

func _w(key: String) -> Dictionary:
	return {"key": key, "lv": 1}

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

func run(data) -> Dictionary:
	var defs: Dictionary = data.weapons
	var items: Dictionary = data.upgrades
	var cfg: Dictionary = data.skills
	var chars: Dictionary = data.characters
	var skills: Array = data.skills_cfg()
	var no_stat := func(_n: String) -> float: return 0.0

	# ---- 1) 本命技：永远槽 0，威力 100% ----
	var s0 := SkillSlots.slots_of(chars.get("mage", {}), [], defs, [], items, cfg)
	chk(s0.size() == 1, "只有本命技时 1 个槽（实测 %d）" % s0.size())
	chk(str((s0[0] as Dictionary).get("id", "")) == "frost_nova", "槽 0 = 法师本命冰爆")
	chk(str((s0[0] as Dictionary).get("source", "")) == "char"
		and absf(float((s0[0] as Dictionary).get("mul", 0.0)) - 1.0) < 0.001,
		"本命技 source=char、威力 100% 不打折")

	# ---- 2) 武器赠送按持有顺序入槽 ----
	var w1 := _w("ice_bucket")   # 元素脉冲 → 送冰镇
	var w2 := _w("smg")          # 枪械 → 送连击
	var s1 := SkillSlots.slots_of(chars.get("mage", {}), [w1, w2], defs, [], items, cfg)
	chk(SkillSlots.ids_of(s1) == ["frost_nova", "frost", "combo"],
		"武器赠送按持有顺序追加在本命后面（实测 %s）" % str(SkillSlots.ids_of(s1)))
	chk(str((s1[1] as Dictionary).get("source", "")) == "weapon"
		and absf(float((s1[1] as Dictionary).get("mul", 0.0)) - SkillSlots.GIFT_MUL) < 0.001,
		"赠送技 source=weapon、基础值 %.1f 折" % SkillSlots.GIFT_MUL)

	# ---- 3) 上限 3：来源超了按"先武器后道具"截断 ----
	var many: Array = []
	for k in ["ice_bucket", "smg", "cleaver", "rolling_pin", "mortar"]:
		many.append(_w(k))
	var s3 := SkillSlots.slots_of(chars.get("mage", {}), many, defs,
		["hand_fan", "snow_globe"], items, cfg)
	chk(s3.size() == SkillSlots.MAX_SLOTS, "来源 8 个也只用 %d 槽（实测 %d）" % [SkillSlots.MAX_SLOTS, s3.size()])
	chk(SkillSlots.ids_of(s3) == ["frost_nova", "frost", "combo"],
		"截断保前面的：本命 > 先拿的武器，后买的不进槽（实测 %s）" % str(SkillSlots.ids_of(s3)))

	# ---- 4) 去重：同一技能只占一槽 ----
	var s4 := SkillSlots.slots_of(chars.get("scorch", {}), [_w("blowtorch")], defs, [], items, cfg)
	chk(SkillSlots.ids_of(s4) == ["sear"], "灼烧刺客拿喷火枪（送灼烧）不重复占槽")
	var s4b := SkillSlots.slots_of(chars.get("martial", {}), [_w("smg")], defs, [], items, cfg)
	chk(SkillSlots.ids_of(s4b) == ["combo"], "武者本命连击，冲锋枪再送一份也只占一槽")
	var s4c := SkillSlots.slots_of(chars.get("frost", {}), [], defs, ["snow_globe"], items, cfg)
	chk(SkillSlots.ids_of(s4c) == ["blizzard"], "暴雪法师本命暴雪，雪景球再送一份也不进第二槽")
	var s4d := SkillSlots.slots_of(chars.get("mage", {}), [], defs, ["hand_fan"], items, cfg)
	chk(SkillSlots.ids_of(s4d) == ["frost_nova", "gust"], "道具赠送同样入槽（折扇送疾风）")

	# ---- 5) 槽位变化可感知：卖武器技能消失，没变不重建 ----
	var after_sell := SkillSlots.slots_of(chars.get("mage", {}), [w2], defs, [], items, cfg)
	chk(SkillSlots.ids_of(after_sell) == ["frost_nova", "combo"],
		"卖掉冰桶后冰镇立刻消失（%s → %s）" % [str(SkillSlots.ids_of(s1)), str(SkillSlots.ids_of(after_sell))])
	chk(not SkillSlots.same_slots(s1, after_sell), "槽位序列真变了时 same_slots=false（HUD 才重建按钮）")
	chk(SkillSlots.same_slots(s1, SkillSlots.slots_of(chars.get("mage", {}),
		[w1, w2], defs, [], items, cfg)), "同一背包重算结果相同（HUD 不会每帧重建）")

	# ---- 6) 折扣：强度/范围打折，冷却不打 ----
	var frost_base := SkillDef.base_of("frost", skills)
	var g1 := SkillDef.resolve(frost_base, "mage", [], defs, no_stat, 1.0)
	var g08 := SkillDef.resolve(frost_base, "mage", [], defs, no_stat, SkillSlots.GIFT_MUL)
	chk(absf(float(g08.get("radius", 0.0)) - float(g1.get("radius", 0.0)) * SkillSlots.GIFT_MUL) < 0.01,
		"赠送技半径打 %.1f 折（%.0f → %.0f）" % [SkillSlots.GIFT_MUL,
			float(g1.get("radius", 0.0)), float(g08.get("radius", 0.0))])
	chk(absf(float(g08.get("freeze_dur", 0.0)) - float(g1.get("freeze_dur", 0.0)) * SkillSlots.GIFT_MUL) < 0.001,
		"赠送技冻结时长同样打折（%.2f → %.2f）" % [float(g1.get("freeze_dur", 0.0)), float(g08.get("freeze_dur", 0.0))])
	chk(absf(float(g08.get("cooldown", 0.0)) - float(g1.get("cooldown", 0.0))) < 0.001,
		"冷却不打折（白送一个技能已够好，再送快冷就过头）")

	# ---- 7) 赠送技照样吃 variants（联动的意义）----
	var elem4 := _stack("elemental", 4, defs)
	var v1 := SkillDef.resolve(frost_base, "mage", [], defs, no_stat, SkillSlots.GIFT_MUL)
	var v2 := SkillDef.resolve(frost_base, "mage", elem4, defs, no_stat, SkillSlots.GIFT_MUL)
	chk(float(v2.get("radius", 0.0)) > float(v1.get("radius", 0.0)),
		"法师拿赠送的冰镇，堆 4 件元素照样触发他的半径强化（%.0f → %.0f）"
		% [float(v1.get("radius", 0.0)), float(v2.get("radius", 0.0))])
	chk(float(v2.get("freeze_dur", 0.0)) > float(v1.get("freeze_dur", 0.0)),
		"冻结时长也跟着变招（%.2f → %.2f）" % [float(v1.get("freeze_dur", 0.0)), float(v2.get("freeze_dur", 0.0))])
	chk(absf(float(v2.get("radius", 0.0))
		- float(g1.get("radius", 0.0)) * SkillSlots.GIFT_MUL * 1.25) < 0.01,
		"折扣在变体之前套：半径 = 基础 × 0.8 × 1.25，不反过来超标")

	# ---- 8) 常量与兜底 ----
	chk(SkillSlots.MAX_SLOTS == 3, "技能上限恒为 3（HUD 扇面只排得下 3 个）")
	chk(absf(SkillSlots.GIFT_MUL - 0.8) < 0.001, "赠送技折扣恒为 0.8")
	var lost_power: Array = []
	for k in SkillDef.POWER_KEYS:
		if not SkillDef.GIFT_MUL_KEYS.has(k):
			lost_power.append(str(k))
	chk(lost_power.is_empty(),
		"赠送折扣覆盖所有强度字段（POWER_KEYS 新增字段别忘同步进 GIFT_MUL_KEYS；缺：%s）" % str(lost_power))
	var bogus: Dictionary = {"_key": "mage", "skill": "no_such_skill"}
	var s5 := SkillSlots.slots_of(bogus, [], defs, [], items, cfg)
	chk(SkillSlots.ids_of(s5) == ["frost"], "角色指了不存在的技能 → 退回 primary（实测 %s）" % str(SkillSlots.ids_of(s5)))
	var s6 := SkillSlots.slots_of(chars.get("mage", {}), [_w("staff")], defs, [], items, cfg)
	chk(SkillSlots.ids_of(s6) == ["frost_nova"], "不送技能的武器（法杖）不占槽")

	# ---- 9) 数据守门：skill 字段指向真实技能 + 数量不归零 + I18n 有名字 ----
	var skill_ids := {}
	for s in skills:
		skill_ids[str((s as Dictionary).get("id", ""))] = true
	var bad_w: Array = []
	for k in defs:
		var sid := str((defs[k] as Dictionary).get("skill", ""))
		if sid != "" and not skill_ids.has(sid):
			bad_w.append(str(k) + "→" + sid)
	chk(bad_w.is_empty(), "武器表的 skill 字段都指向真实技能（错：%s）" % str(bad_w))
	var bad_u: Array = []
	for k in items:
		var sid2 := str((items[k] as Dictionary).get("skill", ""))
		if sid2 != "" and not skill_ids.has(sid2):
			bad_u.append(str(k) + "→" + sid2)
	chk(bad_u.is_empty(), "道具表的 skill 字段都指向真实技能（错：%s）" % str(bad_u))
	var gift_w := 0
	for k in defs:
		if str((defs[k] as Dictionary).get("skill", "")) != "":
			gift_w += 1
	var gift_u := 0
	for k in items:
		if str((items[k] as Dictionary).get("skill", "")) != "":
			gift_u += 1
	chk(gift_w >= 9, "至少 9 把武器白送技能（第二环不能悄悄归零；实测 %d）" % gift_w)
	chk(gift_u >= 3, "至少 3 个道具白送技能（实测 %d）" % gift_u)
	var i18n_src := SP.read("res://autoload/I18n.gd")
	var miss_i18n: Array = []
	for sid in skill_ids:
		if i18n_src.find("\"skill_" + str(sid) + "\"") < 0:
			miss_i18n.append(str(sid))
	chk(miss_i18n.is_empty(), "每个技能 id 都有 I18n 短名词条（HUD 按钮/货架标签要用；缺：%s）" % str(miss_i18n))

	return {"pass": _p, "fail": _f, "failures": _failures}
