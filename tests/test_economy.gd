extends RefCounted

const Economy := preload("res://core/Economy.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")

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
	# 2b) 刷新与道具同口径吃波次通胀：刷新也是金币出口，
	#     否则后期道具价 ×6.7 而刷新还是原价 3 金，通胀就漏了一个出水口
	chk(Economy.reroll_cost(0, SHOP_CFG, 20, 0.3) == 20,
		"第20波首次刷新吃通胀 3→20（×6.7，与 price_of 同口径）")
	chk(Economy.reroll_cost(3, SHOP_CFG, 20, 0.3) == 60,
		"第20波第四次刷新 9→60（次数涨价与通胀相乘）")
	chk(Economy.reroll_cost(0, SHOP_CFG, 1, 0.3) == 3,
		"第1波不涨价（首店还没经历通胀，与 price_of 的 wave>1 判据一致）")

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

	# 5b) 保底搭档要给"买得起的最高档"（2026-10-05 经济改造）
	#     旧逻辑无脑保底最高档：max_lv 提到 10 之后，后期一张 8 级搭档标价几万，
	#     等于每间店白占一个卡位买不动 —— 金币因此花不出去（实测结余 43%）。
	#     现在改成"买得起的最高档"，谁都买不起时退给最便宜的那张。
	var ppool: Array = [
		{"kind": "weapon", "key": "hi", "lv": 8, "merge_partner": true, "cost": 25600},
		{"kind": "weapon", "key": "lo", "lv": 2, "merge_partner": true, "cost": 120},
		{"kind": "upgrade", "key": "u1", "cost": 40},
		{"kind": "upgrade", "key": "u2", "cost": 60},
	]
	var r3 := RandomNumberGenerator.new(); r3.seed = 4242
	var rich := Economy.roll_offers(ppool, 4, r3, 999999)
	chk(str(rich[0].get("key", "")) == "hi",
		"钱够时保底给最高档 hi（实际 %s）" % str(rich[0].get("key", "")))
	var poor := Economy.roll_offers(ppool, 4, r3, 200)
	chk(str(poor[0].get("key", "")) == "lo",
		"只有 200 金时保底降级到买得起的 lo（实际 %s）" % str(poor[0].get("key", "")))
	var broke := Economy.roll_offers(ppool, 4, r3, 30)
	chk(str(broke[0].get("key", "")) == "lo",
		"全都买不起时保底给最便宜的那张（实际 %s）" % str(broke[0].get("key", "")))
	chk(Economy.partner_score({"cost": 120, "lv": 2}, 200)
		> Economy.partner_score({"cost": 25600, "lv": 8}, 200),
		"partner_score：买得起的优先于买不起的")
	chk(Economy.partner_score({"cost": 25600, "lv": 8}, 999999)
		> Economy.partner_score({"cost": 120, "lv": 2}, 999999),
		"partner_score：钱够时高档优先")
	# 向后兼容：不传钱包（-1）时退回"最高档优先"，老调用方的行为不变
	var legacy := Economy.roll_offers(ppool, 4, r3)
	chk(str(legacy[0].get("key", "")) == "hi", "不传钱包时保持旧行为（最高档优先）")

	# 9) 属性线续抽（羁绊续抽）：投过资的线，未持有的卡权重 ×chain_pity_mult。
	#    证据：crit_mult 线 4 张卡合计 2.7%/抽，20 波单局中位 24 波才凑齐 ——
	#    构筑线在单局时长内完不成，玩家"选了暴击流却永远堆不起来"。
	var line_ups := {
		"dmg1": {"stat": "dmg_pct", "value": 0.1, "rarity": 1, "cost": 10},
		"dmg2": {"stat": "dmg_pct", "value": 0.2, "rarity": 2, "cost": 20},
		"hp1": {"stat": "max_hp", "value": 15, "rarity": 1, "cost": 10},
		"mix": {"stats": {"dmg_pct": 0.3}, "rarity": 2, "cost": 30},   # 多属性卡不进线
	}
	var w_of := func(pool: Array, key: String) -> float:
		for it in pool:
			if str(it.get("key")) == key:
				return float(it.get("weight", 0.0))
		return -1.0
	var plain := Economy.build_pool(empty_weapons, wk, line_ups, 6, 4)
	chk(absf(w_of.call(plain, "dmg2") - 3.0) < 0.001,
		"未投过资：dmg2 权重 = 稀有度权重 3.0（实际 %.1f）" % w_of.call(plain, "dmg2"))
	chk(absf(w_of.call(plain, "mix") - 3.0) < 0.001,
		"多属性卡 mix 不受任何线影响（权重 3.0，实际 %.1f）" % w_of.call(plain, "mix"))
	# 投了 dmg_pct 线（买了 dmg1）：dmg2 加速 ×chain_pity_mult（数据值），其余不动。
	# 倍率是调参旋钮（data/shop_tiers.json），测试钉机制不钉数值：
	# 超标由 power_band 把门，机制对不对由这里把门。
	var pm := ShopTiers.new().chain_pity_mult()
	var pity1 := Economy.build_pool(empty_weapons, wk, line_ups, 6, 4, [], 0.0, 5, 0.0, {"dmg1": 1})
	chk(absf(w_of.call(pity1, "dmg2") - 3.0 * pm) < 0.001,
		"投过 dmg 线：dmg2 权重 3.0→%.1f（×chain_pity_mult=%.1f，实际 %.1f）"
			% [3.0 * pm, pm, w_of.call(pity1, "dmg2")])
	chk(absf(w_of.call(pity1, "dmg1") - 6.0) < 0.001,
		"已持有的卡不加速（重买走原速率 6.0，实际 %.1f）" % w_of.call(pity1, "dmg1"))
	chk(absf(w_of.call(pity1, "hp1") - 6.0) < 0.001,
		"没投过的线不受影响（hp1 仍 6.0，实际 %.1f）" % w_of.call(pity1, "hp1"))
	chk(absf(w_of.call(pity1, "mix") - 3.0) < 0.001,
		"多属性卡不因同名属性被误加速（mix 仍 3.0，实际 %.1f）" % w_of.call(pity1, "mix"))
	# 买了多属性卡不算"投过资"（独立原型，不归属任何线）
	var pity2 := Economy.build_pool(empty_weapons, wk, line_ups, 6, 4, [], 0.0, 5, 0.0, {"mix": 1})
	chk(absf(w_of.call(pity2, "dmg2") - 3.0) < 0.001,
		"只买多属性卡不触发续抽（dmg2 仍 3.0，实际 %.1f）" % w_of.call(pity2, "dmg2"))
	# 向后兼容：不传 owned_upgrades = 旧口径（不续抽）
	chk(absf(w_of.call(Economy.build_pool(empty_weapons, wk, line_ups, 6, 4), "dmg2") - 3.0) < 0.001,
		"不传 owned_upgrades 时保持旧口径（无续抽）")
	# invested_lines 的判据边界
	chk(Economy.invested_lines(line_ups, {"dmg1": 1}).has("dmg_pct"),
		"invested_lines：持有 dmg1 → dmg_pct 线已投")
	chk(not Economy.invested_lines(line_ups, {"dmg1": 1}).has("max_hp"),
		"invested_lines：只标记持有过的线")
	chk(Economy.invested_lines(line_ups, {}).is_empty(),
		"invested_lines：空持有 = 无线已投")
	chk(Economy.invested_lines(line_ups, {"dmg1": 0}).is_empty(),
		"invested_lines：次数为 0 不算持有")
	chk(Economy.invested_lines(line_ups, {"mix": 2}).is_empty(),
		"invested_lines：多属性卡不标记任何线")

	# 6) 一波收入
	var inc := Economy.wave_income(1, 15, 1.0, WAVE_CFG)
	chk(inc == 29, "第1波：15 杀 ×1 金币 + 14 奖励 = 29（实际 %d）" % inc)

	# 7) 波次通胀：每过一关商店涨价，金币才有处可花（用户核心诉求：金币花不完）
	var infl := 0.5
	chk(Economy.price_of(100, 0.0, 1, infl) == 100, "首店(wave1)不通胀 = 100")
	chk(Economy.price_of(100, 0.0, 2, infl) == 150, "第2家店涨价50%% = 150")
	chk(Economy.price_of(100, 0.0, 5, infl) == 300, "第5家店涨价200%% = 300")
	# 打折与通胀叠加：先通胀再打折
	var both := int(round(100.0 * (1.0 + 2.0 * infl) * 0.5))
	chk(Economy.price_of(100, 0.5, 3, infl) == both, "通胀+打折叠加正确（=%d）" % both)

	return {"pass": _p, "fail": _f, "failures": _failures}
