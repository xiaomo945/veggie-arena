extends RefCounted

# 解锁条件的人话翻译（纯函数：locale 由外部传进来，不碰 autoload）。
#
# 为什么不塞进 autoload/I18n.gd：那条单例已经顶到架构守卫的 300 行上限（硬失败），
# 而这一族文案会随着职业线越加越长。这里自成一个小文件，加条件不用再去挤 I18n。
#
# 输入统一是 core/Unlocks.remaining() 返回的 {type, need, have, left, char}，
# 这样"判定"和"怎么说"分家：改门槛动 data/unlocks.json，改措辞只动本文件。

# 这段锁定说明的小标题
static func title_locked(locale: String) -> String:
	return "HOW TO UNLOCK" if _en(locale) else "如何解锁"

# 按钮上的锁定文案（详情页「选他」在锁住时显示的替代词）
static func btn_locked(locale: String) -> String:
	return "LOCKED" if _en(locale) else "未解锁"

# 条件本身。who：clear_with 里前置角色的显示名（由调用方查好传进来）
static func condition(info: Dictionary, who: String = "", locale: String = "zh") -> String:
	if info.is_empty():
		return ""
	var en := _en(locale)
	var t := str(info.get("type", ""))
	var need := int(info.get("need", 0))
	if t == "free":
		return "Available from the start" if en else "开局可选"
	if t == "clear_with":
		return ("Clear a run with %s" % who) if en else ("用「%s」通关一次" % who)
	match t:
		"total_kills":
			return ("Reach %d total kills" % need) if en else ("累计击杀 %d" % need)
		"total_gold":
			return ("Collect %d total gold" % need) if en else ("累计金币 %d" % need)
		"best_wave":
			return ("Reach wave %d" % need) if en else ("单局打到第 %d 波" % need)
		"wins":
			return ("Clear the game %d times" % need) if en else ("通关 %d 次" % need)
	return t

# 还差多少（left=0 时返回空，调用方可以直接拼接）
static func progress(info: Dictionary, locale: String = "zh") -> String:
	if info.is_empty():
		return ""
	var left := int(info.get("left", 0))
	if left <= 0:
		return ""
	return ("%d to go" % left) if _en(locale) else ("还差 %d" % left)

# 详情页里那段锁定说明的完整一句话
static func sentence(info: Dictionary, who: String = "", locale: String = "zh") -> String:
	var c := condition(info, who, locale)
	var p := progress(info, locale)
	if c.is_empty():
		return ""
	return c if p.is_empty() else c + "（" + p + "）"

# 标题页那行"下一个能解锁谁"
static func next_hint(info: Dictionary, who: String = "", locale: String = "zh") -> String:
	if info.is_empty():
		return ""
	var name := str(info.get("key", ""))
	var en := _en(locale)
	var tail := sentence(info, who, locale)
	if en:
		return "NEXT CHARACTER: %s — %s" % [name, tail]
	return "下一个角色：%s — %s" % [name, tail]

# 关系树节点里的极短条件：一个方块只有 ~118px 宽，长句塞不下
static func short(info: Dictionary, locale: String = "zh") -> String:
	if info.is_empty():
		return ""
	var en := _en(locale)
	var t := str(info.get("type", ""))
	var need := int(info.get("need", 0))
	match t:
		"free":
			return "FREE" if en else "免费"
		"total_kills":
			return ("%d KILLS" % need) if en else ("%d 击杀" % need)
		"total_gold":
			return ("%d GOLD" % need) if en else ("%d 金币" % need)
		"best_wave":
			return ("WAVE %d" % need) if en else ("第 %d 波" % need)
		"wins":
			return ("CLEAR x%d" % need) if en else ("通关 %d 次" % need)
	return ""

# ---- 关系树那张图自己的文案 ----
static func route_title(locale: String) -> String:
	return "UNLOCK ROUTE" if _en(locale) else "解锁路线"

static func route_hint(locale: String) -> String:
	return ("Clear the one above to unlock the one below."
		if _en(locale) else "通关上面的角色，就能玩下面那个")

static func route_lane_main(locale: String) -> String:
	return "MAIN LINE" if _en(locale) else "主线 · 通关解锁"

static func route_lane_side(locale: String) -> String:
	return "ANY TIME" if _en(locale) else "旁路 · 攒够就开"

static func route_owned(locale: String) -> String:
	return "OWNED" if _en(locale) else "已拥有"

static func route_close(locale: String) -> String:
	return "CLOSE" if _en(locale) else "关闭"

static func btn_route(locale: String) -> String:
	return "UNLOCK MAP" if _en(locale) else "解锁路线"

static func route_progress(owned: int, total: int, locale: String) -> String:
	return ("%d / %d OWNED" % [owned, total]) if _en(locale) else ("已拥有 %d / %d" % [owned, total])

static func _en(locale: String) -> bool:
	return locale != "zh"
