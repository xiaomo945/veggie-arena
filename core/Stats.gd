extends RefCounted

# 玩家属性目录（纯数据，不依赖任何 autoload —— 取值在 ui 层做）。
# "玩家属性做全"的单一真相源：这一局里玩家能堆的所有属性都登记在这里，
# 属性页、商店摘要、成就都从这张表取，加新属性只改这一处。
#
# 每个条目：{key, cat, name, fmt}
#   key  —— GameState.stat_value(key) 的取值键（max_hp 特例，直接读 GameState.max_hp）
#   cat  —— 分组 id，须出现在 CATS 里
#   name —— I18n 译文键（stat_xxx）
#   fmt  —— 显示格式：
#           pct  百分比加成，value 是 0..1 小数，显示为 +N%（×100 取整）
#           flat 整数加成，显示为 +N
#           lvl  拥有层数（从 0 起的整数，如颠勺强化 / 全屏拾取），显示为 ×N
#           hp   生命上限特例，直接读 GameState.max_hp，显示为 N
#
# ⚠️ 只登记"真有供给源"的属性：升级表 / 角色自带 / 基准配置里能加到的才进目录，
#    否则属性页会显示一堆永远是 0 的假属性。下面这 7 个曾被代码消费却无供给的
#    "孤儿属性"（homing_pct / knock_pct / low_hp_dmg / wave_heal / ricochet /
#    shop_discount / hit_boost）已在 data/upgrades.json 补了供给源，现在都是真机制。

const CATS := [
	{"id": "core", "title": "stats_cat_core"},
	{"id": "econ", "title": "stats_cat_econ"},
	{"id": "wok",  "title": "stats_cat_wok"},
	{"id": "move", "title": "stats_cat_move"},
]

static func catalog() -> Array:
	return [
		# ---- 核心战斗 ----
		{"key": "max_hp",            "cat": "core", "name": "stat_max_hp",     "fmt": "hp"},
		{"key": "armor",             "cat": "core", "name": "stat_armor",      "fmt": "flat"},
		{"key": "speed_pct",         "cat": "core", "name": "stat_speed",      "fmt": "pct"},
		{"key": "dmg_pct",           "cat": "core", "name": "stat_dmg",        "fmt": "pct"},
		{"key": "rate_pct",          "cat": "core", "name": "stat_rate",       "fmt": "pct"},
		{"key": "melee_pct",         "cat": "core", "name": "stat_melee",      "fmt": "pct"},
		{"key": "ranged_pct",        "cat": "core", "name": "stat_ranged",     "fmt": "pct"},
		{"key": "elem_pct",          "cat": "core", "name": "stat_elem",       "fmt": "pct"},
		{"key": "range_pct",         "cat": "core", "name": "stat_range",      "fmt": "pct"},
		{"key": "bullet_speed_pct",  "cat": "core", "name": "stat_bspd",       "fmt": "pct"},
		{"key": "crit_chance",       "cat": "core", "name": "stat_crit",       "fmt": "pct"},
		{"key": "crit_mult",         "cat": "core", "name": "stat_critmul",    "fmt": "pct"},
		{"key": "pierce_add",        "cat": "core", "name": "stat_pierce",     "fmt": "flat"},
		{"key": "aoe_add",           "cat": "core", "name": "stat_aoe",        "fmt": "flat"},
		{"key": "pellets_add",       "cat": "core", "name": "stat_pellets",    "fmt": "flat"},
		{"key": "lifesteal",         "cat": "core", "name": "stat_lifesteal",  "fmt": "flat"},
		{"key": "regen",             "cat": "core", "name": "stat_regen",      "fmt": "flat"},
		{"key": "dodge",             "cat": "core", "name": "stat_dodge",      "fmt": "pct"},
		{"key": "homing_pct",        "cat": "core", "name": "stat_homing_pct",  "fmt": "pct"},
		{"key": "knock_pct",         "cat": "core", "name": "stat_knock_pct",   "fmt": "pct"},
		{"key": "low_hp_dmg",        "cat": "core", "name": "stat_low_hp_dmg",  "fmt": "pct"},
		{"key": "wave_heal",         "cat": "core", "name": "stat_wave_heal",   "fmt": "flat"},
		{"key": "ricochet",          "cat": "core", "name": "stat_ricochet",    "fmt": "flat"},
		{"key": "hit_boost",         "cat": "core", "name": "stat_hit_boost",   "fmt": "pct"},

		# ---- 经济 / 拾取 ----
		{"key": "gold_pct",          "cat": "econ", "name": "stat_goldgain",   "fmt": "pct"},
		{"key": "shop_discount",     "cat": "econ", "name": "stat_shop_discount","fmt": "pct"},
		{"key": "pickup_pct",        "cat": "econ", "name": "stat_pickup",     "fmt": "pct"},
		{"key": "autopick",          "cat": "econ", "name": "stat_autopick",   "fmt": "lvl"},
		{"key": "fullauto",          "cat": "econ", "name": "stat_fullauto",   "fmt": "lvl"},

		# ---- 锅气（颠勺）强化 ----
		{"key": "wok_pct",           "cat": "wok",  "name": "stat_wok_pct",    "fmt": "pct"},
		{"key": "wok_dmg_pct",       "cat": "wok",  "name": "stat_wok_dmg",    "fmt": "pct"},
		{"key": "wok_knock_pct",     "cat": "wok",  "name": "stat_wok_knock",  "fmt": "pct"},
		{"key": "wok_slow",          "cat": "wok",  "name": "stat_wok_slow",   "fmt": "lvl"},
		{"key": "wok_charges",       "cat": "wok",  "name": "stat_wok_charges","fmt": "flat"},
		{"key": "wok_freeze",        "cat": "wok",  "name": "stat_wok_freeze", "fmt": "lvl"},
		{"key": "wok_poison",        "cat": "wok",  "name": "stat_wok_poison", "fmt": "lvl"},
		{"key": "wok_burn",          "cat": "wok",  "name": "stat_wok_burn",   "fmt": "lvl"},
		{"key": "wok_shred",         "cat": "wok",  "name": "stat_wok_shred",  "fmt": "lvl"},
		{"key": "wok_explode",       "cat": "wok",  "name": "stat_wok_explode","fmt": "lvl"},
		{"key": "wok_lifesteal",     "cat": "wok",  "name": "stat_wok_lifesteal","fmt": "lvl"},
		{"key": "wok_gold",          "cat": "wok",  "name": "stat_wok_gold",   "fmt": "lvl"},
		{"key": "wok_refund",        "cat": "wok",  "name": "stat_wok_refund", "fmt": "lvl"},
		{"key": "wok_double",        "cat": "wok",  "name": "stat_wok_double", "fmt": "lvl"},
		{"key": "wok_vortex",        "cat": "wok",  "name": "stat_wok_vortex", "fmt": "lvl"},
		{"key": "wok_chain",         "cat": "wok",  "name": "stat_wok_chain",  "fmt": "lvl"},
		{"key": "wok_elite_pct",     "cat": "wok",  "name": "stat_wok_elite",  "fmt": "pct"},

		# ---- 机动 ----
		{"key": "dash_cd_pct",       "cat": "move", "name": "stat_dash_cd",    "fmt": "pct"},
		{"key": "dash_dist_pct",     "cat": "move", "name": "stat_dash_dist",  "fmt": "pct"},
		{"key": "ifr_pct",           "cat": "move", "name": "stat_ifr",        "fmt": "pct"},
	]

# 按分组聚好、按目录顺序排列，方便 UI 直接遍历渲染。
static func grouped() -> Array:
	var out: Array = []
	for c in CATS:
		var items: Array = []
		for s in catalog():
			if s["cat"] == c["id"]:
				items.append(s)
		out.append({"id": c["id"], "title": c["title"], "items": items})
	return out
