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
const Stats := preload("res://core/Stats.gd")
const DetailText := preload("res://ui/Shop/ShopDetailText.gd")

# 给卡片数据打上羁绊标记（原地改 d）。weapons 是玩家当前已持有的武器。
static func decorate(d: Dictionary, char_entry: Dictionary, weapon_key: String,
		defs: Dictionary, weapons: Array) -> void:
	if weapon_key.is_empty():
		return
	var syn := ""
	if Synergy.is_signature(char_entry, weapon_key):
		syn = "signature"
	elif Synergy.is_variety_gain(char_entry, weapon_key, defs, weapons):
		# 杂食：这张能开出我还没有的一类 → 对田园萝卜来说这就是"最该拿的那张"
		syn = "variety"
	elif Synergy.in_bond(char_entry, weapon_key, defs):
		syn = "bond"
	if syn.is_empty():
		return
	d["syn"] = syn
	# 顺带把"还差几件到下一档"带给卡片，玩家知道自己攒到哪了
	var pr := Synergy.progress(weapons, char_entry, defs)
	var branch := "signature" if syn == "signature" else ("variety" if syn == "variety" else "bond")
	var sg := pr.get(branch, {}) as Dictionary
	d["syn_need"] = int(sg.get("need_next", 0))
	d["syn_count"] = int(sg.get("count", 0))
	d["tag"] = I18n.t("syn_" + branch) + "·" + str(d.get("tag", ""))
	# B2：把"买了这张到底给多少"直接写在卡片上。只有金边蓝边还不够 —— 玩家要能
	# 算出"这一把值不值得现在买"，才谈得上"攒钱等它刷出来"。
	d["syn_gain"] = gain_text(weapons, char_entry, defs, syn)

# 买了这张之后本命/羁绊会给多少（增量）。
#   跨档 → "暴击 +12%"（立刻拿到的收益，这是"现在就买"的理由）
#   没跨档 → "还差 2 件"（攒的方向，这是"再忍一波"的理由）
static func gain_text(weapons: Array, char_entry: Dictionary, defs: Dictionary,
		syn: String) -> String:
	# 规则在 core/Synergy.next_gain（纯函数、有单测），这里只负责翻译成人话
	var g := Synergy.next_gain(weapons, char_entry, defs, syn)
	if not bool(g.get("cross", false)):
		var need := int(g.get("need", 0))
		return I18n.t("syn_max") if need <= 0 else I18n.t("syn_next") % need
	var k := str(g.get("stat", ""))
	if k.is_empty():
		return I18n.t("syn_max")
	# fmt_value 自带正负号（"+12%" / "×2"），这里不要再加一个 "+"
	var e := Stats.entry(k)
	return I18n.t(str(e.get("name", ""))) + " " + Stats.fmt_value(
		str(e.get("fmt", "")), float(g.get("delta", 0.0)))

# 携带技能标签："赠·灼烧" / "GIFT: Sear"。
# 武器/道具白送一个主动技能（core/SkillSlots.gd）—— 货架上看不见这个机制，
# 玩家就只能买了才知道，"武器产出技能"等于没存在过。返回 "" = 这张不送技能。
# def 是武器或道具的原始定义（都有 skill 可选字段）。
static func gift_tag(def: Dictionary, locale: String) -> String:
	var sid := str(def.get("skill", ""))
	if sid.is_empty():
		return ""
	var en := locale == "en"
	var name := ""
	for s in Data.skills.get("skills", []):
		var d := s as Dictionary
		if str(d.get("id", "")) == sid:
			name = str(d.get("en", "")) if en else str(d.get("zh", ""))
			break
	if name.is_empty():
		return ""
	var word := DetailText.t("gift", locale)
	return (word + ": " + name) if en else (word + "·" + name)
