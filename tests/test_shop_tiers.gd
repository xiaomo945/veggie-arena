extends RefCounted

# 武器分级商店 + 手动合成/售出（用户最终规则：2 合 1 升下级；按持有等级刷高阶；
# 价格每级至少 ×2，1级≥20/2级≥40/3级≥80，高级绝不便宜；售出价 ≤ 买入价）

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
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

func run(arg = null) -> Dictionary:
	var st := ShopTiers.new()

	# 1) 价格倍率与底价保底
	chk(absf(st.tier_price_mult() - 2.0) < 0.001, "价格倍率 = 2（每升一级至少 ×2）")
	chk(st.price_for_tier(10, 1) == 20, "1 级底价 ≥20（实际 %d）" % st.price_for_tier(10, 1))
	chk(st.price_for_tier(10, 2) == 40, "2 级底价 ≥40（实际 %d）" % st.price_for_tier(10, 2))
	chk(st.price_for_tier(10, 3) == 80, "3 级底价 ≥80（实际 %d）" % st.price_for_tier(10, 3))
	chk(st.price_for_tier(10, 4) == 160, "4 级底价 ≥160（实际 %d）" % st.price_for_tier(10, 4))
	# 高级绝不便宜：每级严格递增
	chk(st.price_for_tier(10, 4) > st.price_for_tier(10, 3), "4 级严格贵于 3 级")
	# 自带高价武器：始终高于底价线
	chk(st.price_for_tier(30, 1) == 30, "高价武器 1 级=自身价 30（实际 %d）" % st.price_for_tier(30, 1))
	chk(st.price_for_tier(30, 2) == 60, "高价武器 2 级=60（实际 %d）" % st.price_for_tier(30, 2))
	# 售出价 ≤ 买入价（默认 80%）
	chk(st.sell_price(40) == 32, "40 买入 → 售出 32（实际 %d）" % st.sell_price(40))
	chk(st.sell_price(100) == 80, "100 买入 → 售出 80（实际 %d）" % st.sell_price(100))
	chk(st.sell_price(40) <= 40, "售出价永不超过买入价")

	# 2) 按"持有等级"刷出可买档位（核心：玩家拥有 L 级 → 刷 [L-1, L]）
	chk(_offer_eq(st, 0, 9, 6, [1]), "未持有 → 只刷 1 级")
	chk(_offer_eq(st, 1, 9, 6, [1]), "持有 1 级 → 刷 1 级")
	chk(_offer_eq(st, 3, 9, 6, [2, 3]), "持有 3 级 → 刷 [2,3]（买 3 级即可合成 4 级）")
	chk(_offer_eq(st, 4, 9, 6, [3, 4]), "持有 4 级 → 刷 [3,4]")
	chk(_offer_eq(st, 3, 1, 6, [2, 3]), "波次不影响持有门禁（仍按持有刷）")

	# 3) 波次门禁（高档的硬上限，早期波次不会冒出超过进度的货）
	chk(st.max_tier_for_wave(1, 6) == 1, "第1波上限 1 级")
	chk(st.max_tier_for_wave(2, 6) == 2, "第2波上限 2 级")
	chk(st.max_tier_for_wave(6, 6) == 3, "第6波上限 3 级")
	chk(st.max_tier_for_wave(10, 6) == 4, "第10波上限 4 级")
	chk(st.max_tier_for_wave(18, 6) == 6, "第18波上限 6 级(传说)")
	chk(st.max_rarity_for_wave(0) >= 2, "开局就有 1~2 级道具")
	chk(st.max_rarity_for_wave(8) == 3, "第8波起才出 3 级道具（难度控制）")

	# 4) 6 档武器配色各不相同
	var cols := {}
	for L in range(1, 7):
		cols[st.tier_color(L).to_html()] = true
	chk(cols.size() == 6, "6 档武器 6 种不同颜色")

	# 5) build_pool：未持有时第 N 波也只出 1 级；持有 3 级时才出 [2,3]
	var wd := {"pistol": {"key": "pistol", "dmg": 9, "cost": 10}, "bow": {"key": "bow", "dmg": 18, "cost": 20}}
	var ud := {"hp": {"stat": "max_hp", "value": 15, "rarity": 2}}
	var pool_empty := Economy.build_pool([], wd, ud, 6, 6, [], 0.0, 9, 0.0)
	chk(not _has_tier_above(pool_empty, 1), "空持有 + 第9波：仍只刷 1 级（持有门禁生效）")
	var owned3 := [{"key": "pistol", "lv": 3, "dmg": 9, "cd": 0.42}]
	var pool_own := Economy.build_pool(owned3, wd, ud, 6, 6, [], 0.0, 9, 0.0)
	var pt := _tiers_of(pool_own, "pistol")
	chk(pt.has(2) and pt.has(3) and pt.size() == 2, "持有 3 级 → 只出 2/3 级（实际 %s）" % str(pt))
	# 底价保底生效：pistol 1 级底价应是 floor 20 而非自身 10
	var pool1 := Economy.build_pool([], wd, ud, 6, 6, [], 0.0, 1, 0.0)
	chk(_base_of(pool1, "pistol", 1) == 20, "pistol 1 级底价=20（floor，实际 %d）" % _base_of(pool1, "pistol", 1))

	# 6) 购买落独立槽位 + 不自动合成 + 记录买入价
	var cfg := {"merge_dmg_multiplier": 1.30, "merge_cd_multiplier": 0.93}
	var inv: Array = []
	var ok := Inventory.buy_weapon(inv, wd["pistol"], 1, 20, 6, cfg)
	chk(ok and inv.size() == 1 and int(inv[0].get("lv", 1)) == 1, "买 1 级 → 落一把 1 级成品")
	chk(int(inv[0].get("buy_cost", -1)) == 20, "买入价 20 记进 buy_cost（实际 %d）" % int(inv[0].get("buy_cost", -1)))
	var ok2 := Inventory.buy_weapon(inv, wd["pistol"], 1, 20, 6, cfg)
	chk(ok2 and inv.size() == 2, "再买 1 级 → 落第二把（不自动合成，实际 %d 把）" % inv.size())
	chk(Inventory.has_mergeable(inv, 6) == true, "两把同 key 同等级 → 可手动合成")

	# 7) 手动合成：两把 1 级 → 一把 2 级，买入价累加
	var done := Inventory.merge_pairs(inv, 6, cfg)
	chk(inv.size() == 1 and int(inv[0].get("lv", 1)) == 2, "合成后剩 1 把 2 级（实际 %d 把 Lv%d）" % [inv.size(), int(inv[0].get("lv", 1))])
	chk(int(inv[0].get("buy_cost", -1)) == 40, "合成后买入价=两把之和 40（实际 %d）" % int(inv[0].get("buy_cost", -1)))
	chk(done.size() == 1 and int(done[0].get("lv", 1)) == 2, "merge_pairs 返回合成结果")

	# 8) 售出：回收 ≤ 买入价，且移除武器；但至少保留 1 把（避免无武器软锁）
	#    先用两把武器验证退款与移除
	var inv2 := [{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42, "buy_cost": 20},
		{"key": "pistol", "lv": 2, "dmg": 12, "cd": 0.39, "buy_cost": 40}]
	var gain := Inventory.sell_weapon(inv2, 1, st.sell_ratio())
	chk(gain == 32, "售出 2 级（买入40）→ 回收 32（实际 %d）" % gain)
	chk(gain <= 40, "售出回收不超过累计买入 40")
	chk(inv2.size() == 1, "售出后移除该把（剩 1 把）")
	# 只剩一把时不允许再卖（Inventory 的"至少留 1 把"保护）
	var alone := [{"key": "pistol", "lv": 1, "buy_cost": 20}]
	chk(Inventory.sell_weapon(alone, 0, st.sell_ratio()) == 0, "只剩一把时不允许卖出（返回 0）")
	chk(alone.size() == 1, "只剩一把时武器不被移除")

	# 9) 模拟器兼容：merge_or_add 仍可直接升级（headless 平衡模拟用）
	var sim := [{"key": "bow", "lv": 1, "dmg": 18, "cd": 0.8}]
	var ok3 := Inventory.merge_or_add(sim, {"key": "bow", "lv": 1, "dmg": 18, "cd": 0.8}, 6, 6, cfg)
	chk(ok3 and int(sim[0].get("lv", 1)) == 2, "merge_or_add(模拟器) 仍自动升 2 级")

	return {"pass": _p, "fail": _f, "failures": _failures}

func _offer_eq(st: ShopTiers, owned: int, wave: int, cap: int, expect: Array) -> bool:
	var got := st.offer_tiers(owned, st.max_tier_for_wave(wave, cap), cap)
	var s1 := _sort(got); var s2 := _sort(expect)
	if s1.size() != s2.size():
		return false
	for i in s1.size():
		if s1[i] != s2[i]:
			return false
	return true

func _sort(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b

func _tiers_of(pool: Array, key: String) -> Dictionary:
	var out := {}
	for it in pool:
		if str(it.get("key", "")) == key and str(it.get("kind", "")) == "weapon":
			out[int(it.get("lv", 1))] = true
	return out

func _has_tier_above(pool: Array, max_lv: int) -> bool:
	for it in pool:
		if str(it.get("kind", "")) == "weapon" and int(it.get("lv", 1)) > max_lv:
			return true
	return false

func _base_of(pool: Array, key: String, lv: int) -> int:
	for it in pool:
		if str(it.get("key", "")) == key and int(it.get("lv", 1)) == lv:
			return int(it.get("base_cost", 0))
	return -1
