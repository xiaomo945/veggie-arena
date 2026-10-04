extends RefCounted

# 商店节奏（Q5）+ 单卡可控（Q6）的纯逻辑测试：core/ShopPlan.gd 与 ui/Shop/ShopCardCtl.gd。
# 两者都不依赖场景树/autoload，可以直接在 --script 模式下跑。
#
# 要保的事：
#   1) 大商店每 3 波一次（含第 1 波），卡更多 + 有折扣；小商店只有 2 张且无折扣。
#   2) 整店刷新保留锁定项，且不会刷出与保留项重复的卡。
#   3) 单张刷新只换那一张，且不会与店里其它卡重复（否则同店两张一模一样很出戏）。
#   4) 卡片右上角的"锁/单刷"按钮在【最矮的卡】（大商店 6 张，约 68px）里也不溢出、
#      不压住价格药丸、不与 Lv 角标重叠 —— 这是自适应布局最容易翻车的地方。

const ShopPlan := preload("res://core/ShopPlan.gd")
const Ctl := preload("res://ui/Shop/ShopCardCtl.gd")

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

const CFG := {"big_every": 3, "big_offer_count": 6, "small_offer_count": 2,
	"big_discount_pct": 0.15, "single_reroll_ratio": 0.5,
	"reroll_base": 3, "reroll_step": 2}

func _w(key: String, lv: int) -> Dictionary:
	return {"kind": "weapon", "key": key, "lv": lv, "cost": lv * 10, "weight": 4.0}

func _pool(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(_w("w%d" % i, 1))
	return out

func run(_data) -> Dictionary:
	# --- Q5：大 / 小商店的节奏 ---
	chk(ShopPlan.is_big(1, CFG) and ShopPlan.is_big(3, CFG) and ShopPlan.is_big(6, CFG),
		"第 1/3/6 波是大商店")
	chk(not ShopPlan.is_big(2, CFG) and not ShopPlan.is_big(4, CFG) and not ShopPlan.is_big(5, CFG),
		"第 2/4/5 波是小商店")
	chk(ShopPlan.offer_count(1, CFG) == 6 and ShopPlan.offer_count(2, CFG) == 2,
		"大商店 6 张 / 小商店 2 张")
	chk(absf(ShopPlan.discount(3, CFG) - 0.15) < 0.0001 and ShopPlan.discount(2, CFG) == 0.0,
		"只有大商店打折 15%")
	chk(ShopPlan.offer_count(1, {}) == 6 and ShopPlan.offer_count(2, {}) == 2,
		"缺配置时回落默认值（大 6 / 小 2）")

	# --- Q6：单张刷新的价格约为整店刷新的一半 ---
	chk(ShopPlan.single_reroll_cost(0, CFG) == 2, "首次单张刷新 2 金（整店 3 的一半向上取整）")
	chk(ShopPlan.single_reroll_cost(1, CFG) == 3, "第二次单张刷新 3 金（整店 5 的一半向上取整）")
	chk(ShopPlan.single_reroll_cost(0, CFG) < 3, "单张刷新必须比整店刷新便宜")

	# --- 整店刷新保留锁定项 ---
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var offers: Array = [_w("a", 1), _w("b", 2), _w("c", 3)]
	var kept := ShopPlan.reroll_keep(offers, [1], _pool(40), 3, rng)
	chk(kept.size() == 3, "保留锁定后仍是 3 张")
	chk(kept.has(offers[1]), "被锁定的那张还在")
	var keys: Array = []
	for o in kept: keys.append(ShopPlan.key_of(o))
	var dup := false
	for k in keys:
		if keys.count(k) > 1: dup = true
	chk(not dup, "保留刷新后没有重复卡")

	# --- 单张刷新：只换一张，且不撞店里其它卡 ---
	rng.seed = 11
	var before: Array = [_w("a", 1), _w("b", 2), _w("c", 3)]
	var after := ShopPlan.reroll_one(before, 0, _pool(40), rng)
	chk(after.size() == 3 and after[1] == before[1] and after[2] == before[2],
		"单张刷新只动第 0 张")
	chk(after[0] != before[0], "第 0 张确实换了一张新的")
	chk(ShopPlan.key_of(after[0]) != ShopPlan.key_of(before[1]) \
		and ShopPlan.key_of(after[0]) != ShopPlan.key_of(before[2]),
		"换出来的新卡不与店里其它卡重复")
	chk(ShopPlan.reroll_one(before, 9, _pool(40), rng) == before, "越界下标不改数据")
	chk(ShopPlan.reroll_one(before, 0, [], rng) == before, "池子空时不换（避免刷成空卡）")

	# --- 卡片按钮布局：大商店最矮的卡（6 张，约 68px）必须仍然放得下 ---
	var short := Vector2(468.0, 68.0)
	chk(Ctl.is_compact(short.y) and not Ctl.is_compact(132.0), "68px 卡走紧凑布局 / 132px 走常规布局")
	var rs := Ctl.rects(short)
	var r0 := rs[0] as Rect2
	var r1 := rs[1] as Rect2
	chk(r0.position.y >= 27.0, "紧凑时按钮让开了 Lv 角标（角标底部约 27）")
	chk(r1.position.y + r1.size.y <= short.y - 2.0, "紧凑时按钮不溢出卡片底部")
	chk(Ctl.hit(short, r0.get_center()) == 1 and Ctl.hit(short, r1.get_center()) == 2,
		"紧凑时两个按钮各自命中")
	chk(Ctl.hit(short, Vector2(20.0, 40.0)) == 0, "点卡片空白处不误触按钮")
	# 矮卡价格药丸挪到左下（y = h-34 = 34），按钮底 52 —— 横向不重叠才是关键
	chk(r0.position.x > 84.0 + 60.0, "紧凑时按钮在右侧，不与左下价格药丸抢位置")

	# --- 卡片区布局：6 张卡不能互相压住，2 张卡不能撑成巨无霸 ---
	var L := Ctl.layout(6, 224.0, 674.0, 8.0, 132.0)
	chk(absf(float(L[0]) - 68.3333) < 0.01, "大商店 6 张卡，每张约 68px 高")
	chk(absf(float(L[1]) - 224.0) < 0.01, "6 张时刚好铺满卡片区（不溢出）")
	var used6 := float(L[0]) * 6.0 + 8.0 * 5.0
	chk(used6 <= 450.0 + 0.01, "6 张卡总高 %.1f 不超过卡片区 450" % used6)
	var L2 := Ctl.layout(2, 224.0, 674.0, 8.0, 132.0)
	chk(absf(float(L2[0]) - 132.0) < 0.01, "小商店 2 张卡封顶 132px")
	chk(float(L2[1]) > 224.0, "2 张卡在卡片区内垂直居中")
	chk(Ctl.layout(0, 224.0, 674.0, 8.0, 132.0)[0] >= 132.0, "0 张时不产生除零/负数高度")

	# 高卡：右上角竖排，避开 Lv 角标（12~34）且不溢出
	var tall := Vector2(468.0, 132.0)
	var ts := Ctl.rects(tall)
	chk((ts[0] as Rect2).position.y >= 34.0, "常规布局按钮让开 Lv 角标")
	chk((ts[1] as Rect2).position.y + (ts[1] as Rect2).size.y <= tall.y - 2.0,
		"常规布局按钮不溢出卡片底部")

	return {"pass": _p, "fail": _f, "failures": _failures}
