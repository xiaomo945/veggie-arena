extends RefCounted

# 模拟 AI 的购物策略（core/ShopAI.gd）：口径必须和 scripts/SimCore.gd 一致，
# 否则 playtest 测出的"死在第几波"是假的，拿它当基线调难度会调过头。

const ShopAI := preload("res://core/ShopAI.gd")
const Inventory := preload("res://core/Inventory.gd")
const Economy := preload("res://core/Economy.gd")

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

# 一把"每 0.5 秒打 10 点"的武器；dmg/cd 与真实 weapons.json 同量级
func _w(key: String, lv: int, dmg: int = 10, cd: float = 0.5) -> Dictionary:
	return {"key": key, "kind": "weapon", "lv": lv, "dmg": dmg, "cd": cd, "cost": 10}

func _u(key: String, stat: String, value: float, cost: int = 10) -> Dictionary:
	return {"key": key, "kind": "upgrade", "stat": stat, "value": value, "cost": cost}

var _data = null

func run(data = null) -> Dictionary:
	_data = data
	var ccfg := {}
	if data != null and data.balance.has("combat"):
		ccfg = data.balance["combat"]

	# 1) 不改动原始武器数组（只在副本上推演，落袋由调用方做）
	var ws := [{"key": "pistol", "lv": 1, "dmg": 10, "cd": 0.5}]
	var offers := [_w("bow", 1), _w("smg", 1)]
	var plan := ShopAI.plan(offers, ws, {}, 100, 6, 20, ccfg)
	chk(ws.size() == 1, "plan() 不改动传入的武器数组（仍 %d 把）" % ws.size())

	# 2) 贪心：贵的低效武器不该被优先买 —— 同 DPS 下便宜的那张先买
	var cheap := _w("bow", 1, 10, 0.5); cheap["cost"] = 10
	var pricey := _w("smg", 1, 10, 0.5); pricey["cost"] = 60
	var p2 := ShopAI.plan([pricey, cheap], [], {}, 20, 6, 20, ccfg)
	chk(p2 == [1], "只买得起便宜的那张时，买它（顺序 %s）" % str(p2))
	var p2b := ShopAI.plan([pricey, cheap], [], {}, 100, 6, 20, ccfg)
	chk(p2b[0] == 1, "两张都买得起时先买性价比高的（便宜同 DPS 优先，顺序 %s）" % str(p2b))
	chk(p2b.size() == 2, "钱够就两张都买（实际 %d 张）" % p2b.size())

	# 3) 买不起的卡不进计划（不会出现"买了之后钱变负数"）
	var rich := _w("rocket", 1, 100, 0.4); rich["cost"] = 9999
	var p3 := ShopAI.plan([rich, cheap], [], {}, 15, 6, 20, ccfg)
	chk(p3 == [1], "买不起的贵卡被跳过（顺序 %s）" % str(p3))
	var spent := 0
	for i in p3:
		spent += int([rich, cheap][i].get("cost", 0))
	chk(spent <= 15, "计划总花费 %d 不超过钱包 15" % spent)

	# 4) 跳级合成不再发生：旧 AI 用 merge_or_add 能把 lv1 直接顶到 lv5。
	#    真实规则只认"同 key 同档"的搭档，且一次只升一级。
	var lv1 := [{"key": "pistol", "lv": 1, "dmg": 10, "cd": 0.5}]
	var twin := _w("pistol", 1, 10, 0.5); twin["cost"] = 10
	chk(ShopAI.gain(lv1, {}, twin, 1, 20, ccfg) > 0.0, "满槽且有同 key 同档搭档时能买（合成升一级）")
	var lv5 := _w("pistol", 5, 10, 0.5); lv5["cost"] = 10
	chk(ShopAI.gain(lv1, {}, lv5, 1, 20, ccfg) == -1.0,
		"手里 lv1 却买 lv5 → 买不了（旧版会跳级合成，是失真根源）")
	var alone := [{"key": "bow", "lv": 1, "dmg": 10, "cd": 0.5}]
	chk(ShopAI.gain(alone, {}, twin, 1, 20, ccfg) == -1.0, "满槽且没同档搭档时买不了新武器")

	# 5) 生存类道具（DPS 增益为 0）也会被买 —— 真人不只堆输出，
	#    不建模就会得出"后期钱花不完"的假象
	var hp_up := _u("hp", "max_hp", 20.0, 10)
	var dmg_up := _u("dmg", "dmg_pct", 0.2, 10)
	var p5 := ShopAI.plan([hp_up, dmg_up], [{"key": "pistol", "lv": 2, "dmg": 10, "cd": 0.5}], {}, 100, 6, 20, ccfg)
	chk(p5.has(0) and p5.has(1), "生存类与输出类都会买（顺序 %s）" % str(p5))

	# 6) 槽位满了就停止买新武器（不无限扩张）
	var full := []
	for i in 6:
		full.append({"key": "w%d" % i, "lv": 1, "dmg": 10, "cd": 0.5})
	var p6 := ShopAI.plan([_w("newgun", 1)], full, {}, 9999, 6, 20, ccfg)
	chk(p6.is_empty(), "槽位满时不再买新武器（实际 %d 张）" % p6.size())

	# 7) stats_of 把 {"key": 份数} 折成属性（多买几份要累加）
	var st := ShopAI.stats_of({"hp": 3}, {"hp": {"stat": "max_hp", "value": 10}})
	chk(float(st.get("max_hp", 0)) == 30.0, "同一道具买 3 份 → max_hp +30（实际 %s）" % str(st.get("max_hp", 0)))

	# 8) 真实数据下的健全性：任何一波、任何钱包，计划都自洽（不超支、不越界）
	if data != null:
		var bad := []
		var over := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var scfg: Dictionary = data.balance.get("shop", {})
		var max_slot := int(scfg.get("max_slot", 6))
		var max_lv := int(scfg.get("max_lv", 20))
		for w in range(1, 21):
			for gold in [0, 30, 120, 900, 9000]:
				var held := [{"key": "pistol", "lv": mini(1 + w / 3, max_lv), "dmg": 10, "cd": 0.5}]
				var pool := Economy.build_pool(held, data.weapons, data.upgrades,
					max_slot, max_lv, [], 0.0, w, float(scfg.get("price_inflation", 0.0)))
				var offs := Economy.roll_offers(pool, 6, rng, gold)
				var pl := ShopAI.plan(offs, held, {}, gold, max_slot, max_lv, ccfg)
				var sum := 0
				for i in pl:
					if i < 0 or i >= offs.size():
						bad.append("w%d g%d idx%d" % [w, gold, i])
						continue
					sum += int((offs[i] as Dictionary).get("cost", 0))
				if sum > gold:
					over.append("w%d g%d 花了%d" % [w, gold, sum])
		chk(bad.is_empty(), "计划下标全部合法（越界：%s）" % str(bad))
		chk(over.is_empty(), "计划从不超支（超支：%s）" % str(over))

	return {"pass": _p, "fail": _f, "failures": _failures}
