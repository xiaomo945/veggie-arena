extends RefCounted

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

var WAVE_CFG := {"bonus_base": 10, "bonus_per_wave": 4}
var SHOP_CFG := {"reroll_base": 3, "reroll_step": 2, "offer_count": 4}

func run() -> Dictionary:
	# 1) 波次奖励
	chk(Economy.wave_bonus(1, WAVE_CFG) == 14, "第 1 波奖励 14 金币")
	chk(Economy.wave_bonus(5, WAVE_CFG) == 30, "第 5 波奖励 30 金币")
	chk(Economy.wave_bonus(5, WAVE_CFG) > Economy.wave_bonus(1, WAVE_CFG), "奖励随波次递增")

	# 2) 刷新价格
	chk(Economy.reroll_cost(0, SHOP_CFG) == 3, "首次刷新 3 金币")
	chk(Economy.reroll_cost(1, SHOP_CFG) == 5, "第二次刷新 5 金币")
	chk(Economy.reroll_cost(3, SHOP_CFG) == 9, "第四次刷新 9 金币（越刷越贵）")

	# 3) 购买力
	chk(Economy.can_buy(20, 12) == true, "钱够能买")
	chk(Economy.can_buy(11, 12) == false, "钱不够不能买")
	chk(Economy.can_buy(12, 12) == true, "刚好够能买")

	# 4) 抽卡不重复
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var pool := ["a", "b", "c", "d", "e", "f", "g"]
	var offers := Economy.roll_offers(pool, 4, rng)
	chk(offers.size() == 4, "抽出 4 个商品（实际 %d）" % offers.size())
	var seen := {}
	var dup := false
	for o in offers:
		if seen.has(o):
			dup = true
		seen[o] = true
	chk(not dup, "4 个商品互不重复")
	# 池子不够时不会崩
	var small := Economy.roll_offers(["x"], 4, rng)
	chk(small.size() == 1, "池子只有 1 个时只出 1 个（不崩溃）")

	# 5) 商品池构造
	var weapon_defs := {
		"pistol": {"dmg": 9, "cd": 0.42},
		"bow": {"dmg": 18, "cd": 0.8},
	}
	var upgrade_defs := {"hp": {"stat": "max_hp", "value": 15}}
	var empty_weapons: Array = []
	var p1 := Economy.build_pool(empty_weapons, weapon_defs, upgrade_defs, 6, 4)
	chk(p1.size() == 3, "空背包：2 武器 + 1 强化 = 3 个候选（实际 %d）" % p1.size())

	# 槽位未满：按"持有等级"刷对应档位（未持有只刷1级；持有L级刷[L-1,L]）
	var part: Array = [
		{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42},
		{"key": "bow", "lv": 2, "dmg": 18, "cd": 0.8},
	]
	var wd2 := {
		"pistol": {"dmg": 9}, "bow": {"dmg": 18}, "smg": {"dmg": 5},
		"staff": {"dmg": 14}, "rocket": {"dmg": 40}, "shotgun": {"dmg": 8},
	}
	var p2 := Economy.build_pool(part, wd2, upgrade_defs, 6, 4)
	var kinds := {}
	for it in p2:
		kinds[it.get("key")] = it.get("kind")
	# pistol 持有1级→[1]；bow 持有2级→[1,2]；未持有的 smg/staff/rocket/shotgun→[1]
	# 武器共 1+2+1+1+1+1 = 7，加 1 强化 = 8
	chk(p2.size() == 8, "未满槽：按持有等级刷对应档位（实际 %d）" % p2.size())
	chk(kinds.has("bow"), "持有2级的 bow 仍可购买（刷出 1/2 级）")
	chk(kinds.has("pistol"), "持有1级的 pistol 仍刷1级")

	# 槽位满时：只刷"场上有同 key 同等级、能直接合成掉"的档位；
	# 全新武器 / 场上没有同等级的档位 / 已满级的档位一律不刷（买了没地方放）
	var full: Array = [
		{"key": "pistol", "lv": 4, "dmg": 20, "cd": 0.3},
		{"key": "bow", "lv": 1, "dmg": 18, "cd": 0.8},
		{"key": "smg", "lv": 2, "dmg": 6, "cd": 0.12},
		{"key": "staff", "lv": 3, "dmg": 20, "cd": 0.9},
		{"key": "rocket", "lv": 1, "dmg": 40, "cd": 1.8},
		{"key": "shotgun", "lv": 4, "dmg": 15, "cd": 0.9},
	]
	var p3 := Economy.build_pool(full, wd2, upgrade_defs, 6, 4)
	var wcount := 0
	var wkeys := {}
	for it in p3:
		if str(it.get("kind", "")) == "weapon":
			wcount += 1
			wkeys["%s|%d" % [it.get("key"), int(it.get("lv", 1))]] = true
	# 满槽可合成的：bow1 / smg2 / staff3 / rocket1（场上各有一把同等级的）
	chk(wcount == 4, "满槽时只刷能直接合成的 4 个档位（实际 %d 把）" % wcount)
	chk(wkeys.has("bow|1") and wkeys.has("smg|2") and wkeys.has("staff|3") and wkeys.has("rocket|1"),
		"满槽时场上有的等级照刷（买下去直接合成）")
	chk(not wkeys.has("pistol|4") and not wkeys.has("shotgun|4"), "满级档位在满槽时不刷（合不动）")
	chk(not wkeys.has("pistol|3") and not wkeys.has("smg|1"), "场上没有同等级的档位不刷（合不动）")

	# 8) 合成搭档保底：持有 L 级，商店必须 reliably 给得出 L 级去合 L+1
	#    （bug：高级武器权重极低，随机抽几乎永远抽不到那把关键搭档 → 5→6 合不出来）
	var wk := {
		"knife": {"cost": 20, "dmg": 10}, "pistol": {"cost": 20, "dmg": 10},
		"smg": {"cost": 20, "dmg": 10}, "bow": {"cost": 20, "dmg": 10},
		"sword": {"cost": 20, "dmg": 10}, "rocket": {"cost": 20, "dmg": 10},
	}
	var uk := {"hp": {"stat": "max_hp", "value": 15}, "dmg": {"stat": "dmg_pct", "value": 0.1}}
	var full5: Array = [
		{"key": "knife", "lv": 5, "dmg": 200, "cd": 0.1},
		{"key": "pistol", "lv": 3, "dmg": 20, "cd": 0.5},
		{"key": "smg", "lv": 2, "dmg": 15, "cd": 0.3},
		{"key": "bow", "lv": 4, "dmg": 40, "cd": 0.7},
		{"key": "sword", "lv": 2, "dmg": 30, "cd": 0.6},
		{"key": "rocket", "lv": 1, "dmg": 50, "cd": 1.1},
	]
	var pool5 := Economy.build_pool(full5, wk, uk, 6, 6)
	var has_partner := false
	for it in pool5:
		if str(it.get("key")) == "knife" and int(it.get("lv", 0)) == 5 and it.get("merge_partner", false):
			has_partner = true
	chk(has_partner, "满槽持有 knife Lv5 时，池子里把 knife Lv5 标成合成搭档")
	# 抽 100 次大商店（6 张），统计 knife Lv5 出现次数 —— 它是最高档搭档，应几乎每次都被保底
	var seen_partner := 0
	for t in 100:
		var r2 := RandomNumberGenerator.new(); r2.seed = 1000 + t
		var of5 := Economy.roll_offers(pool5, 6, r2)
		for it in of5:
			if str(it.get("key")) == "knife" and int(it.get("lv", 0)) == 5:
				seen_partner += 1
				break
	chk(seen_partner >= 95, "100 次大商店里 knife Lv5 至少出现 95 次（保底生效，实际 %d）" % seen_partner)

	# 6) 一波收入
	var inc := Economy.wave_income(1, 15, 1.0, WAVE_CFG)
	chk(inc == 29, "第1波：15 杀 ×1 金币 + 14 奖励 = 29（实际 %d）" % inc)

	# 7) 波次通胀：每过一关商店涨价，金币才有处可花（用户核心诉求：金币花不完）
	var infl := 0.22
	chk(Economy.price_of(100, 0.0, 1, infl) == 100, "首店(wave1)不通胀 = 100")
	chk(Economy.price_of(100, 0.0, 2, infl) == 122, "第2家店涨价22%% = 122")
	chk(Economy.price_of(100, 0.0, 5, infl) == 188, "第5家店涨价88%% = 188")
	# 打折与通胀叠加：先通胀再打折
	var both := int(round(100.0 * (1.0 + 2.0 * infl) * 0.5))
	chk(Economy.price_of(100, 0.5, 3, infl) == both, "通胀+打折叠加正确（=%d）" % both)

	return {"pass": _p, "fail": _f, "failures": _failures}
