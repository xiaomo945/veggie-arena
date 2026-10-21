extends RefCounted

# 商店三项修复的纯逻辑/几何自测：
#   1) Inventory.sell_weapon 在"最后一把"时返回 0 且不移除（避免无武器软锁）
#   2) ShopCard 高卡布局不重叠：描述区域底部 y 必须 < 价格条顶部 y
#      （复刻 ShopCard.gd 的布局常量：描述 y0=66、行距 16、最多 2 行；价格药丸 py=size.y-30）

const Inventory := preload("res://core/Inventory.gd")
const ShopCardCtl := preload("res://ui/Shop/ShopCardCtl.gd")

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)

func run() -> Dictionary:
	# 1) 最后一把武器不能卖
	var one: Array = [{"key": "pistol", "lv": 1, "buy_cost": 20}]
	var g1 := Inventory.sell_weapon(one, 0, 0.8)
	chk(g1 == 0, "只剩一把时 sell_weapon 返回 0（不退款）")
	chk(one.size() == 1, "只剩一把时武器数组不被移除（仍 1 把）")

	# 2) 两把以上正常卖、退款 = 买入价 × 比例
	var two: Array = [{"key": "a", "lv": 1, "buy_cost": 20},
		{"key": "b", "lv": 1, "buy_cost": 20}]
	var g2 := Inventory.sell_weapon(two, 0, 0.8)
	chk(g2 == 16, "两把时正常回收 20×0.8 = 16")
	chk(two.size() == 1, "两把时移除一把（剩 1 把）")

	# 3) 越界下标安全返回 0
	chk(Inventory.sell_weapon(two, 9, 0.8) == 0, "越界下标返回 0 不崩溃")

	# 4) 布局不重叠（高卡）：描述底部 < 价格条顶部
	var desc_y0 := 66.0
	var line_step := 16.0
	var desc_bottom := desc_y0 + 1.0 * line_step   # 2 行时第二行基线 y=82（再加字号也仍远低于价格条）
	for h in [124, 132, 300]:
		var price_top := float(h) - 30.0            # ShopCard._draw_price 非紧凑 py = size.y - 30
		chk(desc_bottom < price_top,
			"卡高 %d：描述底部(%.0f) < 价格条顶部(%.0f)，不重叠" % [h, desc_bottom, price_top])

	# 5) 小卡价格药丸右侧内边距：数字末位不被 2px 内边框压住。
	#    布局（ShopCardCtl.draw_tile 重做版）：药丸 = 8 内边距 + 币(16) + 间隙(4) + 数字 + 8，
	#    整组【币+数字】水平居中；数字右缘 = 8+16+4+cw，药丸 2px 内边框在 pw-2。
	#    旧版右距只有 1px，"286"的"6"被金框啃掉一角（真机反馈"金币数字被框遮挡"）。
	#    要求净空 ≥ 4px。
	for cw in [8.0, 16.0, 24.0, 32.0, 40.0]:
		var pw: float = ShopCardCtl.price_pill_w(cw)
		var num_right: float = 8.0 + 16.0 + 4.0 + cw
		var border_inner: float = pw - 2.0
		chk(num_right <= border_inner - 4.0,
			"数字宽 %.0f：右缘 %.0f 距内边框 %.0f ≥ 4px（药丸宽 %.0f）" % [cw, num_right, border_inner, pw])

	# 6) 一键购买（2026-10-21 玩家反馈"买东西太不方便、别点那么多下"）：
	#    价格药丸 = 购买按钮，点它 1 次直接买入；卡面其余区域仍开详情页。
	#    源码契约 + 命中区几何（+6px 外扩后横向不得出卡片）。
	var ctl_src := FileAccess.get_file_as_string("res://ui/Shop/ShopCardCtl.gd")
	var card_src := FileAccess.get_file_as_string("res://ui/Shop/ShopCard.gd")
	var shop_src := FileAccess.get_file_as_string("res://ui/Shop/Shop.gd")
	var panel_src := FileAccess.get_file_as_string("res://ui/Shop/ShopPanel.gd")
	chk(ctl_src.contains("d[\"_pill\"] = pill"), "小卡把价格药丸命中区存进 _pill（点价格=购买）")
	chk(card_src.contains("on_buy") and card_src.contains("_d.get(\"_pill\""),
		"卡片点击优先判价格药丸 → 一键购买")
	chk(shop_src.contains("c.on_buy = _buy.bind(i)"), "Shop 给每张卡接上一键购买")
	for h in [132.0, 176.0]:
		var pw2: float = ShopCardCtl.price_pill_w(24.0)
		var pill := Rect2(151.0 - 10.0 - pw2, h - 26.0, pw2, 22.0).grow(6.0)
		chk(pill.position.x >= 0.0 and pill.end.x <= 151.0,
			"卡高 %.0f：购买命中区横向不出卡片（%.1f..%.1f）" % [h, pill.position.x, pill.end.x])

	# 7) 按钮重排：合成/刷新搬到"我的武器"右侧，下一波改底部整宽主按钮
	chk(panel_src.contains("set_position(Vector2(394, 112))"), "合成按钮在库存右侧（不再挤底部）")
	chk(panel_src.contains("set_position(Vector2(394, 172))"), "刷新按钮在库存右侧")
	chk(panel_src.contains("Vector2(PANEL_W - 28, 58)"), "下一波是底部整宽主按钮")
	# 详情页关闭键与购买同排（旧版在右上角，买完要跨整页去关）
	var detail_src := FileAccess.get_file_as_string("res://ui/Shop/ShopOfferDetail.gd")
	chk(detail_src.contains("set_position(Vector2(398, 622))"), "详情页关闭键与购买同排")

	return {"pass": _p, "fail": _f, "failures": _failures}
