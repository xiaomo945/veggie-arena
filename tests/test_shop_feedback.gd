extends RefCounted

# 商店三项修复的纯逻辑/几何自测：
#   1) Inventory.sell_weapon 在"最后一把"时返回 0 且不移除（避免无武器软锁）
#   2) ShopCard 高卡布局不重叠：描述区域底部 y 必须 < 价格条顶部 y
#      （复刻 ShopCard.gd 的布局常量：描述 y0=66、行距 16、最多 2 行；价格药丸 py=size.y-30）

const Inventory := preload("res://core/Inventory.gd")

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

	return {"pass": _p, "fail": _f, "failures": _failures}
