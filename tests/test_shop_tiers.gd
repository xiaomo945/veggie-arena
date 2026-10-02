extends RefCounted

# 武器分级商店：分级门禁 / 价格复利 / 多档刷出 / 高级武器购买与合成

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

	# 1) 分级门禁：前几波只出低档，逐波解锁高档
	chk(st.max_tier_for_wave(1, 6) == 1, "第1波只有 1 级武器")
	chk(st.max_tier_for_wave(2, 6) == 2, "第2波起出 2 级")
	chk(st.max_tier_for_wave(5, 6) == 3, "第5波起出 3 级")
	chk(st.max_tier_for_wave(9, 6) == 4, "第9波起出 4 级")
	chk(st.max_tier_for_wave(17, 6) == 6, "第17波起出 6 级(传说)")
	chk(absf(st.tier_price_mult() - 3.0) < 0.001, "价格倍率 = 3（每升一级 ×3）")
	chk(st.max_rarity_for_wave(0) >= 2, "开局就有 1~2 级道具")
	chk(st.max_rarity_for_wave(8) == 3, "第8波起才出 3 级道具（难度控制）")

	# 2) 6 档武器配色各不相同（白/绿/蓝/紫/红/传说）
	var cols := {}
	for L in range(1, 7):
		cols[st.tier_color(L).to_html()] = true
	chk(cols.size() == 6, "6 档武器 6 种不同颜色")

	# 3) build_pool 多档刷出 + 价格复利（第9波、无通胀/打折）
	var wd := {"pistol": {"dmg": 9, "cost": 10}, "bow": {"dmg": 18, "cost": 20}}
	var ud := {"hp": {"stat": "max_hp", "value": 15, "rarity": 2}}
	var pool := Economy.build_pool([], wd, ud, 6, 6, [], 0.0, 9, 0.0)
	var bc := {}
	for it in pool:
		if str(it.get("kind", "")) == "weapon":
			var k := str(it.get("key", ""))
			if not bc.has(k):
				bc[k] = {}
			bc[k][int(it.get("lv", 1))] = int(it.get("base_cost", 0))
	chk(bc.has("pistol") and bc["pistol"].size() >= 4, "pistol 在第9波给出多档（≥4）")
	chk(int(bc["pistol"][1]) == 10, "pistol 1 级底价 = 10")
	chk(int(bc["pistol"][2]) == 30, "pistol 2 级底价 = 1 级 ×3 = 30")
	chk(int(bc["pistol"][3]) == 90, "pistol 3 级底价 = 2 级 ×3 = 90")
	chk(int(bc["pistol"][4]) == 270, "pistol 4 级底价 = 3 级 ×3 = 270")
	# 第1波只应出 1 级（门禁生效）
	var pool1 := Economy.build_pool([], wd, ud, 6, 6, [], 0.0, 1, 0.0)
	var tiers1 := {}
	for it in pool1:
		if str(it.get("kind", "")) == "weapon":
			tiers1[int(it.get("lv", 1))] = true
	chk(tiers1.has(1) and tiers1.size() == 1, "第1波只有 1 级武器（门禁生效）")

	# 4) can_accept_tier：高级武器购买资格
	var owned := [{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42}]
	chk(Inventory.can_accept_tier(owned, "pistol", 1, 6, 6) == true, "已有1级→可买1级(合成)")
	chk(Inventory.can_accept_tier(owned, "pistol", 2, 6, 6) == true, "已有1级→可买2级(升级)")
	chk(Inventory.can_accept_tier(owned, "bow", 3, 6, 6) == true, "有空槽→可直接买3级成品")
	var full: Array = []
	for i in 6:
		full.append({"key": "other%d" % i, "lv": 1, "dmg": 5, "cd": 0.5})
	chk(Inventory.can_accept_tier(full, "w0", 2, 6, 6) == false, "满槽且无上级→2级不可买")
	chk(Inventory.can_accept_tier(full, "w0", 1, 6, 6) == false, "满槽且无同key→1级也不可买")

	# 5) merge_or_add：直接买高级成品 / 合成升级
	var cfg := {"merge_dmg_multiplier": 1.30, "merge_cd_multiplier": 0.93}
	var inv := []
	var ok := Inventory.merge_or_add(inv, {"key": "pistol", "lv": 2, "dmg": 9, "cd": 0.42}, 6, 6, cfg)
	chk(ok and inv.size() == 1 and int(inv[0].get("lv", 1)) == 2, "直接买2级→落一把2级成品")
	var inv2 := [{"key": "bow", "lv": 1, "dmg": 18, "cd": 0.8}]
	var ok2 := Inventory.merge_or_add(inv2, {"key": "bow", "lv": 1, "dmg": 18, "cd": 0.8}, 6, 6, cfg)
	chk(ok2 and int(inv2[0].get("lv", 1)) == 2, "再买1级 bow→自动合成升到2级")
	var inv3 := [{"key": "staff", "lv": 1, "dmg": 14, "cd": 0.9}]
	var ok3 := Inventory.merge_or_add(inv3, {"key": "staff", "lv": 2, "dmg": 14, "cd": 0.9}, 6, 6, cfg)
	chk(ok3 and inv3.size() == 1 and int(inv3[0].get("lv", 1)) == 2, "买2级且已有1级→升到2级而非新增")

	return {"pass": _p, "fail": _f, "failures": _failures}
