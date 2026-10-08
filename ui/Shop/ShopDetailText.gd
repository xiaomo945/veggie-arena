extends RefCounted

# 商店详情页（ui/Shop/ShopOfferDetail.gd）的文案：自带中英双语、纯函数。
# 不放进已经满载的 I18n.gd（那条红线 300 行，加不动），照 ui/WeaponInfo.gd 的路子。

const ZH := {
	"intro": "介绍",
	"play": "玩法",
	"set": "套装进度",
	"bond": "羁绊收益",
	"buy": "购买 (%d)",
	"lock": "锁定",
	"unlock": "解锁",
}
const EN := {
	"intro": "ABOUT",
	"play": "HOW IT PLAYS",
	"set": "SET PROGRESS",
	"bond": "SYNERGY",
	"buy": "BUY (%d)",
	"lock": "LOCK",
	"unlock": "UNLOCK",
}

static func t(key: String, locale: String) -> String:
	var table: Dictionary = EN if locale == "en" else ZH
	return str(table.get(key, key))
