extends RefCounted

# 套装条（SetBar）要渲染的那几行：件数 / 还差几件到下一档 / 档位 / 颜色 / 名字。
#
# 单独成文件有两个原因：一是 Shop.gd 已经顶到 300 行红线，二是"套装进度怎么算"
# 与"商店怎么卖东西"本来就是两件事，拆开后改套装展示不会碰到任何交易逻辑。
# 翻译在这里做掉，SetBar 自己不碰 I18n（它只管画）。

const WeaponSets := preload("res://core/WeaponSets.gd")

static func rows(weapons: Array, defs: Dictionary, sets: Dictionary) -> Array:
	var out: Array = []
	for p in WeaponSets.progress(weapons, defs, sets):
		var it := p as Dictionary
		out.append({"label": I18n.t("set_" + str(it.get("tag", ""))),
			"count": int(it.get("count", 0)), "need": int(it.get("need_next", 0)),
			"tier": int(it.get("tier", 0)), "color": str(it.get("color", "#8a7a5a"))})
	return out
