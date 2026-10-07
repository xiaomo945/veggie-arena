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
	"ranged_pct", "melee_pct", "elem_pct", "gold_pct", "crit_chance",
]

# 职业亲和（决定"这把萝卜适合哪种武器"）：mixed=均衡，其余对应武器分域
const AFFINITY := ["mixed", "ranged", "melee", "elem"]

# 角色自带"命中附加持续伤害"（data/characters.json 的 on_hit_dot 段）。
#
# 为什么必须存在（踩过的坑）：
#   焦辣萝卜 scorch 的人设是"毒 + 灼烧双 DoT"，但改造前 DoT 只挂在【技能】上，
#   于是玩家选了它、开枪打了 3 秒，屏幕上一点火都没有 —— 只看到自己普攻数值
#   比别人低一截。人设写在 tip 里、机制藏在技能冷却里，"上手门槛"直接劝退。
#   这一层把角色的身份钉在【第一次命中】上：选它，打中，火就烧起来，
#   不需要读任何说明。文案只能解释机制，不能替代机制。
#
#   数值刻意做小：apply_fx 取 max 不叠层，所以一只怪最多同时吃一份 burn，
#   它是"你碰过的怪都在慢慢掉血"，不是"每一发都追加伤害"。
static func on_hit_dot(entry: Dictionary) -> Dictionary:
	var d := entry.get("on_hit_dot", {}) as Dictionary
	if d.is_empty():
		return {}
	return {
		"burn": float(d.get("burn", 0.0)),           # 灼烧每秒伤害（绝对值）
		"poison_pct": float(d.get("poison_pct", 0.0)),  # 中毒每秒伤害（敌人最大血量占比）
		"dur": float(d.get("dur", 2.0)),             # 持续时间（秒）
	}

# 开局白送几个颠勺充能（爆炒萝卜 sizzle：进局就能按，按一下就懂）
static func start_wok_charges(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("start_wok_charges", 0)))

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
		"crit_chance": return "CRIT"
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
