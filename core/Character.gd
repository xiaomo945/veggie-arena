extends RefCounted

# 角色（蔬菜）的数据层：读 characters.json，产出属性表并做配平校验。
#
# 设计原则：**有得必有失**。每个非默认角色必须同时有正加成和负加成，
# 否则"选它就纯赚"，角色选择就退化成"选最强的那个"，选择本身失去意义。
# 这条规则写在测试里（test_character.gd），加纯加强角色会被测试拦下。

# 允许出现在 stats 里的属性名（与 upgrades.json 的 stat 保持同一套词表）
const VALID_STATS := [
	"max_hp", "speed_pct", "dmg_pct", "rate_pct",
	"armor", "pickup_pct", "lifesteal", "wok_pct",
	"ranged_pct", "melee_pct", "elem_pct", "gold_pct",
]

# 职业亲和（决定"这把萝卜适合哪种武器"）：mixed=均衡，其余对应武器分域
const AFFINITY := ["mixed", "ranged", "melee", "elem"]

# 这些是绝对值（不是百分比），描述时不能用 % 显示
const ABSOLUTE_STATS := ["max_hp", "armor", "lifesteal"]

# 取某个角色的属性表（找不到角色或没有 stats → 空表）
static func stats_of(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = entry.get("stats", {}) as Dictionary
	for k in raw:
		out[str(k)] = float(raw[k])
	return out

# 配平校验：默认角色（空 stats）或"有正有负"才算合格
static func is_balanced(entry: Dictionary) -> bool:
	var st := stats_of(entry)
	if st.is_empty():
		return true          # 基准角色：没有加成就是平衡
	var pos := 0.0
	var neg := 0.0
	for k in st:
		var v := float(st[k])
		if v > 0.0:
			pos += v
		elif v < 0.0:
			neg += -v
	return pos > 0.0 and neg > 0.0

# 属性名是否合法（拼错的 stat 会静默失效，所以在测试里拦一道）
static func has_unknown_stat(entry: Dictionary) -> String:
	var st := stats_of(entry)
	for k in st:
		if not VALID_STATS.has(str(k)):
			return str(k)
	return ""

# 一句话属性摘要（UI 卡片用，英文，出海）
static func describe(entry: Dictionary) -> String:
	var st := stats_of(entry)
	if st.is_empty():
		return "No bonus / no penalty"
	var parts: Array = []
	for k in st:
		var ks := str(k)
		var v := float(st[k])
		var name := _label(ks)
		var num := _fmt(ks, v)
		# 负号由 _fmt 自己带，正号在这里补
		parts.append(("+%s %s" % [num, name]) if v > 0.0 else ("%s %s" % [num, name]))
	return "\n".join(parts)

# ⚠️ 绝对值类（HP/护甲/吸血）不能按百分比显示 —— 40 点血会变成 "+4000%"
static func _fmt(stat: String, v: float) -> String:
	if stat in ABSOLUTE_STATS:
		return "%d" % int(round(v))
	return "%d%%" % int(round(v * 100.0))

static func _label(stat: String) -> String:
	match stat:
		"max_hp": return "HP"
		"speed_pct": return "SPD"
		"dmg_pct": return "DMG"
		"rate_pct": return "RATE"
		"armor": return "ARM"
		"pickup_pct": return "PICK"
		"lifesteal": return "LIFE"
		"wok_pct": return "HEAT"
		"ranged_pct": return "RANGED"
		"melee_pct": return "MELEE"
		"elem_pct": return "ELEM"
		"gold_pct": return "GOLD"
	return stat

# 职业亲和的短标签（中文/英文），供选角卡片显示"这把萝卜适合哪种武器"
static func affinity_text(affinity: String, locale: String = "zh") -> String:
	match affinity:
		"ranged": return "远程" if locale != "en" else "RANGED"
		"melee": return "近战" if locale != "en" else "MELEE"
		"elem": return "法师" if locale != "en" else "MAGE"
		_: return "均衡" if locale != "en" else "BALANCED"

# 职业亲和的配色（选角卡片的亲和标签用，和武器分域色一致）
static func affinity_color(affinity: String) -> Color:
	match affinity:
		"ranged": return Color(0.37, 0.69, 0.88)
		"melee": return Color(0.85, 0.54, 0.35)
		"elem": return Color(0.69, 0.42, 1.0)
		_: return Color(0.48, 0.82, 0.42)
