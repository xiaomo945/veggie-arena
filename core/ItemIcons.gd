extends RefCounted

# 道具图标映射：136 个道具按"玩家 3 秒内能看懂的语义"归成 18 类，每类一张
# icon_item_<cat>.png；颠勺锅那类直接复用场景里的 icon_wok.png（它画的本来就是
# 一口着火的锅）。细分 stat 合并进主属性图标 —— 商店里玩家只关心"这卡加什么"，
# 具体数值差异由 tip 文案承担；只有颠勺系元素（火/冰/毒/冲击）单独成图，
# 因为那是玩法差异最大、也最想让玩家在货架上一眼认出来的东西。
#
# 未列出的 stat 返回 ""（商店回落到宝石兜底画法）—— 新 stat 上线时在这里补一行，
# tests/test_art_icons.gd 会用 upgrades.json 全量比对，漏配直接红。

const POOLS := {
	"hp": ["max_hp", "heal_now", "wave_heal"],
	"regen": ["regen"],
	"speed": ["speed_pct"],
	"dmg": ["dmg_pct", "low_hp_dmg", "hit_boost", "elem_pct", "melee_pct", "ranged_pct",
		"multi:melee_pct/ranged_pct", "multi:dmg_pct/elem_pct"],
	"rate": ["rate_pct", "fullauto"],
	"armor": ["armor", "ifr_pct", "dodge"],
	"crit": ["crit_chance", "crit_mult"],
	"leech": ["lifesteal", "wok_lifesteal"],
	"gold": ["gold_pct", "wok_gold", "shop_discount"],
	"magnet": ["pickup_pct", "autopick"],
	"wok": ["wok_pct", "wok_dmg_pct", "wok_charges", "wok_refund", "wok_double",
		"wok_chain", "wok_explode", "wok_vortex", "wok_elite_pct"],
	"fire": ["wok_burn"],
	"ice": ["wok_slow", "wok_freeze"],
	"poison": ["wok_poison", "wok_shred"],
	"knock": ["wok_knock_pct", "knock_pct"],
	"dash": ["dash_cd_pct", "dash_dist_pct"],
	"pierce": ["pierce_add", "ricochet", "homing_pct"],
	"burst": ["aoe_add", "pellets_add"],
	"range": ["range_pct", "bullet_speed_pct"],
}

# 一条升级定义 → Art.icon() 的键。没有 stat 字段的多属性道具（如 melee_focus）
# 用 stats 字典的键排序后拼成 "multi:a/b" 再进表 —— 同一组合共用一张图。
static func key_for_def(def: Dictionary) -> String:
	var st := str(def.get("stat", ""))
	if st == "" and def.get("stats") is Dictionary:
		var keys: Array = (def["stats"] as Dictionary).keys()
		keys.sort()
		st = "multi:" + "/".join(keys)
	return art_key(st)

# stat → Art.icon() 的键。"wok" 返回原名（复用 icon_wok.png），其余返回
# "item_<cat>"（对应 icon_item_<cat>.png）；查不到映射返回 ""（调用方兜底）。
static func art_key(st: String) -> String:
	for cat in POOLS:
		if st in POOLS[cat]:
			return "wok" if cat == "wok" else "item_" + cat
	return ""
