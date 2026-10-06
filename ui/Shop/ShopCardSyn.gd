extends RefCounted

# 商店卡片的"角色羁绊"标记 —— 四元素联动在货架上的那一眼。
#
# 玩家攒钱等某把武器刷出来，前提是他在货架上能立刻分辨：
#   这张是【我的本命】（金边 + "本命·"前缀）→ 攒钱也要拿下
#   这张是【我的羁绊类】（蓝边 + "羁绊·"前缀）→ 顺手就拿
#   其余 → 除非特别好，否则让位给上面两类
# 没有这个区分，"刷到谁买谁"就还是最优解，本命机制形同虚设。
#
# 单独成文件：Shop.gd 已顶到 300 行红线，且这套标记逻辑与购买/刷新无关，
# 拆出来后改标记样式不会碰到任何交易逻辑。

const Synergy := preload("res://core/Synergy.gd")

# 给卡片数据打上羁绊标记（原地改 d）。weapons 是玩家当前已持有的武器。
static func decorate(d: Dictionary, char_entry: Dictionary, weapon_key: String,
		defs: Dictionary, weapons: Array) -> void:
	if weapon_key.is_empty():
		return
	var syn := ""
	if Synergy.is_signature(char_entry, weapon_key):
		syn = "signature"
	elif Synergy.in_bond(char_entry, weapon_key, defs):
		syn = "bond"
	if syn.is_empty():
		return
	d["syn"] = syn
	if syn == "signature":
		# 顺带把"还差几件到下一档"带给卡片，玩家知道自己攒到哪了
		var pr := Synergy.progress(weapons, char_entry, defs)
		var sg := pr.get("signature", {}) as Dictionary
		d["syn_need"] = int(sg.get("need_next", 0))
		d["syn_count"] = int(sg.get("count", 0))
	d["tag"] = I18n.t("syn_signature" if syn == "signature" else "syn_bond") \
		+ "·" + str(d.get("tag", ""))
