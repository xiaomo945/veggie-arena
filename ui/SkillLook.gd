extends RefCounted

# 技能外观（配色 + 特效样式）：唯一一份表，HUD 按钮与施放特效共用。
#
# 为什么抽出来：换形态时按钮和特效必须【同时】变，各存一份表迟早会出现
# "按钮已经变红了、特效还是冰蓝"这种半变不变的状态。而且 SkillButton 已经贴着
# 300 行红线，这张表留在那里再加形态逻辑必爆。
#
# 颜色两个来源：形态自带的 color（skills.json 的 form.color）优先，没有就退回
# "基础技能按 id 上色"。于是换形态 = 按钮换色 + 特效换色，一次生效。

const FALLBACK := Color(0.90, 0.70, 0.40)

# 基础技能配色：每个专属技能各给一色 —— 一眼认出"这一局的招是什么"，
# 换角色颜色跟着变，也是"换个角色像换个游戏"的一环。
const SKILL_COLORS := {
	"frost": Color(0.50, 0.85, 1.00),      # 冰镇 —— 冰蓝
	"frost_nova": Color(0.62, 0.72, 1.00), # 冰霜新星 —— 淡紫蓝
	"pierce_shot": Color(0.55, 0.92, 0.78),# 穿透射击 —— 青
	"quake": Color(0.88, 0.66, 0.34),      # 震地 —— 土黄
	"gust": Color(0.60, 0.95, 0.62),       # 疾风 —— 浅绿
	"coin_rain": Color(1.00, 0.82, 0.30),  # 金币雨 —— 金
	"spike_burst": Color(0.82, 0.74, 0.52),# 尖刺爆发 —— 灰褐
	"mark": Color(0.96, 0.45, 0.38),       # 标记射击 —— 红
	"combo": Color(1.00, 0.55, 0.28),      # 连击狂潮 —— 橙红
	"magnet_pull": Color(0.45, 0.72, 0.95),# 磁吸 —— 蓝
	"sear": Color(0.94, 0.36, 0.20),       # 灼烧 —— 焦红（毒+火）
	"grind": Color(0.80, 0.66, 0.40),      # 碾压 —— 薯泥黄褐
	"flashfire": Color(1.00, 0.68, 0.20),  # 爆燃火候 —— 旺火橙（全是锅气，不伤人）
}

# 形态 → 滞留场样式（冰晶 / 气泡 / 火星 / 电弧）
const FORM_STYLES := {
	"glacial_burst": "shards",   # 冰锥爆裂：还是冰，碎得更狠
	"magma_fissure": "sparks",   # 沸腾油爆：滚油火星
	"wind_blade": "blades",      # 风刃：一圈切出去的刃
	"shock_field": "arcs",       # 电场：电弧
	"gold_crash": "sparks",      # 金砖砸落：砸出来的火星
	"burst_arrow": "sparks",     # 爆裂箭：着火
	"char_burst": "sparks",      # 炭爆：炭火
}

# 兜底：形态没登记样式时，按 effect 大类决定画什么
const STYLE_OF_EFFECT := {
	"slow": "shards", "poison": "bubbles",
	"damage": "sparks", "frenzy": "sparks", "heat": "sparks",
}

static func color_of(id: String, form: String) -> Color:
	var hex := form_hex(id, form)
	if hex != "":
		return Color(hex)
	return SKILL_COLORS.get(id, FALLBACK) as Color

static func style_of(id: String, form: String) -> String:
	var s := str(FORM_STYLES.get(form, ""))
	if s != "":
		return s
	return str(STYLE_OF_EFFECT.get(effect_of(id, form), "sparks"))

# 形态自带的颜色（skills.json 的 form.color）；没有返回空串
static func form_hex(id: String, form: String) -> String:
	if form.is_empty() or form == "base":
		return ""
	for s in Data.skills_cfg():
		var sd := s as Dictionary
		if str(sd.get("id", "")) != id:
			continue
		for v in sd.get("variants", []) as Array:
			if not (v is Dictionary):
				continue
			var f: Dictionary = (v as Dictionary).get("form", {}) as Dictionary
			if str(f.get("key", "")) == form:
				return str(f.get("color", ""))
	return ""

# 某形态最终是什么效果（决定特效大类：控制类画冰晶、持续类画气泡…）
static func effect_of(id: String, form: String) -> String:
	for s in Data.skills_cfg():
		var sd := s as Dictionary
		if str(sd.get("id", "")) != id:
			continue
		if form.is_empty() or form == "base":
			return str(sd.get("effect", ""))
		for v in sd.get("variants", []) as Array:
			if not (v is Dictionary):
				continue
			var f: Dictionary = (v as Dictionary).get("form", {}) as Dictionary
			if str(f.get("key", "")) == form:
				var e := str(f.get("effect", ""))
				return e if e != "" else str(sd.get("effect", ""))
	return ""
