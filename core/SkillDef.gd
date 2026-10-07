extends RefCounted

# 技能解析（四元素联动的第三环）。
#
# 一个技能最终长什么样，由四样东西一起决定：
#   1) 技能自己（data/skills.json 的 base 参数）
#   2) 角色（只有角色能用它自己那一个 —— character.skill 指向 id）
#   3) 武器（variants：角色 + 某类武器凑够 N 件 → 技能被强化）
#   4) 属性/道具（skill_power 与 dmg_pct / elem_pct 继续往上叠）
#
# 于是"同一个技能在不同角色手里不一样、同角色拿不同武器也不一样"是规则的自然
# 结果，不是硬编码的特例。改技能只动 skills.json，改角色只动 characters.json，
# 改武器只动 weapons.json，三者互不相识 —— 这就是模块化的意义。
#
# 纯函数、不碰 autoload（架构守卫 R2）：stat_of 由调用方注入，便于单测。

const Synergy := preload("res://core/Synergy.gd")

# 这些字段是"强度"，吃 skill_power（通用技能强化道具）
const POWER_KEYS := ["dmg", "dur", "slow_dur", "freeze_dur", "gold", "burn_dps"]
# 这些字段不吃强度，只按 variants 缩放（半径无限膨胀会破坏手感与性能）
const PLAIN_KEYS := ["radius", "cooldown", "slow_v"]

# 形态字段：form 里允许覆盖的"展示字段"（改了不算数值膨胀，算换了招）
const FORM_META := ["key", "zh", "en", "tip", "tip_en", "color"]
const BASE_FORM := "base"

# 角色此刻该用哪个技能（角色表里写了 id；没有就退回 primary，绝不留空）
static func skill_id_of(char_entry: Dictionary, fallback: String = "frost") -> String:
	var id := str(char_entry.get("skill", ""))
	return id if not id.is_empty() else fallback

# 按 id 取技能原始配置（找不到返回空表）
static func base_of(id: String, skills: Array) -> Dictionary:
	for s in skills:
		if not (s is Dictionary):
			continue
		if str((s as Dictionary).get("id", "")) == id:
			return s as Dictionary
	return {}

# 当前生效的那个 variant（没有满足条件的返回空表）。
# 多条同时满足时取【要求最高】的那条 —— 玩家堆得越多，拿越强那档。
static func variant_of(base: Dictionary, char_key: String, weapons: Array,
		defs: Dictionary) -> Dictionary:
	return _best_variant(base, char_key, weapons, defs, false)

# 满足条件的 variant 里挑【要求最高】的那条 —— 玩家堆得越多，拿越强那档。
# want_form=true 时只在"带形态的那几条"里挑：形态与数值可以来自不同路线 ——
# 主堆的那条给数值，副凑的那条给形态，于是"元素 6 件 + 刀 4 件"能同时吃到两者。
static func _best_variant(base: Dictionary, char_key: String, weapons: Array,
		defs: Dictionary, want_form: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_need := -1
	for v in (base.get("variants", []) as Array):
		if not (v is Dictionary):
			continue
		var vd := v as Dictionary
		if str(vd.get("char", "")) != char_key:
			continue
		if want_form and (vd.get("form", {}) as Dictionary).is_empty():
			continue
		var need := int(vd.get("need", 0))
		var tag := str(vd.get("tag", ""))
		if not tag.is_empty() and Synergy.bond_count(weapons, tag, defs) < need:
			continue
		if need > best_need:
			best_need = need
			best = vd
	return best

# 当前生效的形态（没触发任何 form 就是空表 = 基础形态）。
#
# 为什么要"形态"而不是继续加 mul：只乘数字的话，凑够 6 件元素武器拿到的还是
# "原来的那个技能，范围 +20%" —— 玩家按下去干的是同一件事，没有"换了招"的惊喜。
# form 允许换 effect、换名字、引入新机制字段（burn_dps / knock），
# 于是同一个按键在不同 build 下是两招。这是 C3 的核心。
static func form_of(base: Dictionary, char_key: String, weapons: Array,
		defs: Dictionary) -> Dictionary:
	return _best_variant(base, char_key, weapons, defs, true).get("form", {}) as Dictionary

# 形态 key（UI 取名/配色用）：基础形态恒为 "base"
static func form_key_of(base: Dictionary, char_key: String, weapons: Array,
		defs: Dictionary) -> String:
	var f := form_of(base, char_key, weapons, defs)
	if f.is_empty():
		return BASE_FORM
	var k := str(f.get("key", ""))
	return k if not k.is_empty() else BASE_FORM

# 这个技能一共有几种形态（基础形态 + 每个 variant 带的 form）。
# 守门用：形态数 < 2 = 这个技能只有数值缩放，不算"会变招"。
static func form_count(base: Dictionary) -> int:
	var n := 1
	for v in base.get("variants", []) as Array:
		if not (v is Dictionary):
			continue
		if not ((v as Dictionary).get("form", {}) as Dictionary).is_empty():
			n += 1
	return n

# 所有形态的清单（选角页/结算页预览"你还能变成什么"）。
# 每项 {key, zh, en, tag, need, is_base}
static func forms_of(base: Dictionary) -> Array:
	var out: Array = [{
		"key": BASE_FORM, "zh": str(base.get("zh", "")), "en": str(base.get("en", "")),
		"tag": "", "need": 0, "is_base": true,
	}]
	for v in base.get("variants", []) as Array:
		if not (v is Dictionary):
			continue
		var vd := v as Dictionary
		var f: Dictionary = vd.get("form", {}) as Dictionary
		if f.is_empty():
			continue
		out.append({
			"key": str(f.get("key", "")),
			"zh": str(f.get("zh", base.get("zh", ""))),
			"en": str(f.get("en", base.get("en", ""))),
			"tag": str(vd.get("tag", "")),
			"need": int(vd.get("need", 0)),
			"is_base": false,
		})
	return out

# 解析最终参数：base → 套形态 form → 套 variant 的 mul → 套属性/道具缩放。
# stat_of: Callable(stat_name) -> float（GameState.stat_value）
static func resolve(base: Dictionary, char_key: String, weapons: Array, defs: Dictionary,
		stat_of: Callable) -> Dictionary:
	if base.is_empty():
		return {}
	var out: Dictionary = base.duplicate(true)
	out.erase("variants")            # 变体规则不参与运行时，免得被误当参数

	# --- 1) 形态：换一套参数（可能连 effect 都换掉，等于换了招）---
	var vr := variant_of(base, char_key, weapons, defs)
	var form: Dictionary = vr.get("form", {}) as Dictionary
	for k in form:
		out[str(k)] = form[k]
	out["form"] = str(form.get("key", BASE_FORM))

	# --- 2) 武器带来的变体：乘算覆盖（在形态之上继续放大）---
	var mul: Dictionary = vr.get("mul", {}) as Dictionary
	for k in mul:
		var key := str(k)
		if out.has(key):
			out[key] = float(out.get(key, 0.0)) * float(mul[k])

	# --- 3) 道具/属性带来的强度 ---
	var power := 1.0 + _st(stat_of, "skill_power")
	for k in POWER_KEYS:
		if out.has(k):
			out[k] = float(out.get(k, 0.0)) * power

	# --- 4) 伤害类技能再吃一层伤害属性（dmg_pct，元素技能额外吃 elem_pct）---
	if out.has("dmg"):
		var dm := 1.0 + _st(stat_of, "dmg_pct")
		if bool(out.get("elemental", false)):
			dm += _st(stat_of, "elem_pct")
		out["dmg"] = float(out.get("dmg", 0.0)) * maxf(0.05, dm)

	# --- 5) 冷却：受道具的 skill_cd_pct 影响（负值=放得更频繁）---
	if out.has("cooldown"):
		var cdm := 1.0 + _st(stat_of, "skill_cd_pct")
		out["cooldown"] = maxf(1.0, float(out.get("cooldown", 6.0)) * maxf(0.3, cdm))
	return out

# 一步到位：角色 + 当前武器 → 最终生效的技能（含 id）
static func active_skill(char_entry: Dictionary, skills: Array, weapons: Array,
		defs: Dictionary, stat_of: Callable) -> Dictionary:
	var id := skill_id_of(char_entry)
	var base := base_of(id, skills)
	if base.is_empty():
		# 角色指了个不存在的技能 → 退回通用技，绝不让技能按钮变哑巴
		id = skill_id_of({}, "frost")
		base = base_of(id, skills)
	if base.is_empty():
		return {}
	var out := resolve(base, str(char_entry.get("_key", "")), weapons, defs, stat_of)
	out["id"] = id
	return out

static func _st(stat_of: Callable, name: String) -> float:
	if stat_of == null or not stat_of.is_valid():
		return 0.0
	return float(stat_of.call(name))
