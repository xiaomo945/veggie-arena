extends RefCounted

# 羁绊相关文案的共用零件：把"一条属性 → 人话"翻出来。
#
# 为什么要单独一个文件：选角页的阶梯（CharTiers）和结算页的复盘（RunSynergyRecap）
#   都要写"暴击 +12%"，两处各写一份必然漂移 —— 哪天改了百分比格式（比如保留一位小数），
#   只改一处就会变成"选角页 +12%、结算页 +12.0%"。这里是唯一的那一份。

const Stats := preload("res://core/Stats.gd")

# 一支的配色：本命金 / 杂食绿 / 羁绊蓝。
# 卡片描边和 HUD 进度条必须同一个色 —— 两处各写一份必然漂移，玩家会对不上号
# （"卡片上这把是金边的、进度条上那条是金色的，是一回事吗？"），所以这里是唯一一份。
static func color_of(branch: String) -> Color:
	if branch == "signature":
		return Color(1.0, 0.84, 0.32)
	if branch == "variety":
		return Color(0.48, 0.82, 0.42)
	return Color(0.45, 0.75, 1.0)

# 一支的名字：本命写武器名，羁绊写武器类名，杂食只写"杂食"（它不指向某一类）
static func head_of(branch: String, br: Dictionary) -> String:
	if branch == "signature":
		return I18n.t("syn_signature") + "·" + I18n.pick(Data.weapon(str(br.get("key", ""))))
	if branch == "variety":
		return I18n.t("syn_variety")
	return I18n.t("syn_bond") + "·" + I18n.t("set_" + str(br.get("tag", "")))

# 属性名（取第一条；一档可能给好几条属性，一行字只放得下一条）
static func name_of(st: Variant) -> String:
	if not (st is Dictionary):
		return ""
	for k in (st as Dictionary):
		return I18n.t(str(Stats.entry(str(k)).get("name", "")))
	return ""

# 属性值（取第一条，含正负号：fmt_value 给的是 "+12%" / "×2"）
static func value_of(st: Variant) -> String:
	if not (st is Dictionary):
		return ""
	for k in (st as Dictionary):
		return Stats.fmt_value(str(Stats.entry(str(k)).get("fmt", "")),
			float((st as Dictionary)[k]))
	return ""

# "属性名 属性值" 合起来写（复盘用：格子够，写全更好读）
static func pair_of(st: Variant) -> String:
	var n := name_of(st)
	if n.is_empty():
		return value_of(st)
	var v := value_of(st)
	return n if v.is_empty() else n + " " + v
