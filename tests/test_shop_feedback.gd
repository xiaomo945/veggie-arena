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

	return {"pass": _p, "fail": _f, "failures": _failures}
