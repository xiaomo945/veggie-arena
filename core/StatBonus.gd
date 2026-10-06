extends RefCounted

# 玩家属性的两条"装备派生"加成线，汇总成一个数。
#
#   1) 武器套装 —— 看【武器自己】的 tag 凑了几件（core/WeaponSets.gd）
#   2) 角色羁绊 —— 看【角色身份】：本命武器几把、羁绊类几件（core/Synergy.gd）
#
# 两条线彼此独立：套装是"这把武器属于哪一套"，羁绊是"这把武器对我这把萝卜
# 有没有缘分"。同一个角色拿不同武器收益不同，靠的就是第 2 条。
#
# 拆成独立文件是为了让 GameState 不必同时认识这两个模块（它已经顶到 300 行
# 红线），也让"加成到底从哪来"有唯一一处可查。纯函数、不碰 autoload（R2）。

const WeaponSets := preload("res://core/WeaponSets.gd")
const Synergy := preload("res://core/Synergy.gd")

# 某条属性此刻从这两条线拿到的总加成（同名属性相加）
static func extra(weapons: Array, char_entry: Dictionary, defs: Dictionary,
		sets: Dictionary, stat: String) -> float:
	var total := float(WeaponSets.bonuses(weapons, defs, sets).get(stat, 0.0))
	total += float(Synergy.bonuses(weapons, char_entry, defs).get(stat, 0.0))
	return total
