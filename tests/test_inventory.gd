extends RefCounted

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

var COMBAT_CFG := {"merge_dmg_multiplier": 1.30, "merge_cd_multiplier": 0.93}

func run() -> Dictionary:
	var MAX_SLOT := 6
	var MAX_LV := 4

	# 1) 两态可买性（用户拍板）：没满槽 → 都能买（占新格，不自动合）；
	#    满槽 → 只有"场上已有一把同 key 同等级、且还没满级"才能买（买下去直接合成升一级）
	var w1: Array = [{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42}]
	chk(Inventory.can_accept_tier(w1, "bow", 1, MAX_SLOT, MAX_LV) == true, "槽位没满，新武器可以买")
	chk(Inventory.can_accept_tier(w1, "pistol", 1, MAX_SLOT, MAX_LV) == true, "槽位没满，同类武器也能买（占新格）")

	var full: Array = []
	for i in MAX_SLOT:
		full.append({"key": "w%d" % i, "lv": 1, "dmg": 10, "cd": 0.5})
	chk(Inventory.can_accept_tier(full, "newgun", 1, MAX_SLOT, MAX_LV) == false,
		"槽位满了，全新武器买不了（没地方放）")
	chk(Inventory.can_accept_tier(full, "w0", 1, MAX_SLOT, MAX_LV) == true,
		"槽位满了，但场上已有 1 级 w0 → 买了直接合成升 2 级")
	chk(Inventory.can_accept_tier(full, "w0", 2, MAX_SLOT, MAX_LV) == false,
		"槽位满了，场上没有 2 级 w0 → 买不了 2 级的")
	# 满级档位在满槽时不能再往上合
	var maxed: Array = [{"key": "pistol", "lv": 4, "dmg": 20, "cd": 0.3}]
	chk(Inventory.can_accept_tier(maxed, "pistol", MAX_LV, 1, MAX_LV) == false,
		"满级档位在满槽时不能再往上合")

	# 2) 合成升级：不占新槽
	var inv: Array = [{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42}]
	var ok := Inventory.merge_or_add(inv, {"key": "pistol", "dmg": 9, "cd": 0.42}, MAX_SLOT, MAX_LV, COMBAT_CFG)
	chk(ok == true, "合成成功")
	chk(inv.size() == 1, "合成不占新槽位（还是 1 把，实际 %d）" % inv.size())
	chk(int(inv[0]["lv"]) == 2, "等级升到 2（实际 %d）" % inv[0]["lv"])
	chk(int(inv[0]["dmg"]) == 12, "伤害 9 ×1.3 → 12（实际 %d）" % inv[0]["dmg"])
	chk(abs(float(inv[0]["cd"]) - 0.42 * 0.93) < 0.001, "冷却 0.42 ×0.93（实际 %.3f）" % float(inv[0]["cd"]))

	# 连升到 4 级
	for i in 3:
		Inventory.merge_or_add(inv, {"key": "pistol", "dmg": 9, "cd": 0.42}, MAX_SLOT, MAX_LV, COMBAT_CFG)
	chk(int(inv[0]["lv"]) == MAX_LV, "连买 4 次升到满级 4（实际 %d）" % inv[0]["lv"])
	var ok2 := Inventory.merge_or_add(inv, {"key": "pistol", "dmg": 9, "cd": 0.42}, MAX_SLOT, MAX_LV, COMBAT_CFG)
	chk(ok2 == true, "满级后再买同 key：仍能买（因为槽位没满，会新开一把）")
	chk(inv.size() == 2, "满级后再买会新开一把（实际 %d 把）" % inv.size())

	# 3) 槽位满 + 不可合成 → 购买失败
	var full2: Array = []
	for i in MAX_SLOT:
		full2.append({"key": "g%d" % i, "lv": 4, "dmg": 10, "cd": 0.5})
	var ok3 := Inventory.merge_or_add(full2, {"key": "newgun", "dmg": 10}, MAX_SLOT, MAX_LV, COMBAT_CFG)
	chk(ok3 == false, "槽满且无法合成 → 购买失败")
	chk(full2.size() == MAX_SLOT, "失败时槽位不变（实际 %d）" % full2.size())

	# 4) 强化生效
	var stats := {"hp": 50, "max_hp": 100, "speed_pct": 0.0, "dmg_pct": 0.0,
		"rate_pct": 0.0, "armor": 0.0, "pickup_pct": 0.0}
	stats = Inventory.apply_upgrade(stats, {"stat": "max_hp", "value": 15})
	chk(float(stats["max_hp"]) == 115, "最大生命 +15（实际 %s）" % stats["max_hp"])
	chk(float(stats["hp"]) == 65, "同时补 15 点血（实际 %s）" % stats["hp"])
	stats = Inventory.apply_upgrade(stats, {"stat": "armor", "value": 2})
	chk(float(stats["armor"]) == 2, "护甲 +2（实际 %s）" % stats["armor"])
	stats = Inventory.apply_upgrade(stats, {"stat": "dmg_pct", "value": 0.10})
	chk(abs(float(stats["dmg_pct"]) - 0.10) < 0.001, "伤害 +10%%（实际 %s）" % stats["dmg_pct"])
	stats = Inventory.apply_upgrade(stats, {"stat": "heal_now", "value": 40})
	chk(float(stats["hp"]) == 105, "立刻回血 40（实际 %s）" % stats["hp"])
	# 回血不会超过上限
	stats = Inventory.apply_upgrade(stats, {"stat": "heal_now", "value": 999})
	chk(float(stats["hp"]) == float(stats["max_hp"]), "回血不超过血量上限")

	# 5) 总 DPS
	var w: Array = [
		{"dmg": 9, "cd": 0.42, "pellets": 1},
		{"dmg": 8, "cd": 0.95, "pellets": 4},
	]
	var t := Inventory.total_dps(w)
	chk(abs(t - (9.0 / 0.42 + 32.0 / 0.95)) < 0.01, "总 DPS = 各武器之和（实际 %.1f）" % t)
	chk(Inventory.total_dps([]) == 0.0, "空武器列表 DPS 为 0")

	# 6) 新增 stat：击杀回血 / 锅气获取
	#    必须被 apply_upgrade 认识，否则买了强化却静默失效（最难查的一类 bug）
	var st2: Dictionary = {"hp": 50, "max_hp": 100}
	st2 = Inventory.apply_upgrade(st2, {"stat": "lifesteal", "value": 3})
	chk(abs(float(st2.get("lifesteal", 0)) - 3.0) < 0.001,
		"lifesteal 记入属性表（实际 %s）" % st2.get("lifesteal"))
	st2 = Inventory.apply_upgrade(st2, {"stat": "wok_pct", "value": 0.25})
	chk(abs(float(st2.get("wok_pct", 0)) - 0.25) < 0.001,
		"wok_pct 记入属性表（实际 %s）" % st2.get("wok_pct"))
	st2 = Inventory.apply_upgrade(st2, {"stat": "lifesteal", "value": 3})
	chk(abs(float(st2.get("lifesteal", 0)) - 6.0) < 0.001,
		"lifesteal 可叠加（实际 %s）" % st2.get("lifesteal"))

	# 7) 两态购买：没满槽 → 占新格不自动合；满槽 → 直接合成进同 key 同等级的那把
	var inv2: Array = [{"key": "pistol", "lv": 1, "dmg": 9, "cd": 0.42, "buy_cost": 20}]
	var defp := {"key": "pistol", "dmg": 9, "cd": 0.42}
	var b1 := Inventory.buy_weapon(inv2, defp, 1, 20, MAX_SLOT, COMBAT_CFG, MAX_LV)
	chk(b1 and inv2.size() == 2, "没满槽 → 买同名武器占新格（不自动合），共 %d 把" % inv2.size())
	chk(int(inv2[0]["lv"]) == 1 and int(inv2[1]["lv"]) == 1, "两把都还是 1 级（未被自动合成）")

	var fullp: Array = []
	for i in MAX_SLOT:
		fullp.append({"key": "k%d" % i, "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20})
	var b2 := Inventory.buy_weapon(fullp, {"key": "k2", "dmg": 10, "cd": 0.5}, 1, 25, MAX_SLOT, COMBAT_CFG, MAX_LV)
	chk(b2 == true, "满槽 → 买同 key 同等级的武器可以买（直接合成）")
	chk(fullp.size() == MAX_SLOT, "满槽合成不占新格（实际 %d 把）" % fullp.size())
	chk(int(fullp[2]["lv"]) == 2, "k2 升到 2 级（实际 %d）" % fullp[2]["lv"])
	chk(int(fullp[2]["buy_cost"]) == 45, "买入价累加 20+25（实际 %d）" % fullp[2]["buy_cost"])
	var b3 := Inventory.buy_weapon(fullp, {"key": "zzz", "dmg": 10, "cd": 0.5}, 1, 25, MAX_SLOT, COMBAT_CFG, MAX_LV)
	chk(b3 == false, "满槽 + 场上没有同 key 同等级的 → 买不了")
	chk(fullp.size() == MAX_SLOT, "买失败时槽位不变（实际 %d）" % fullp.size())

	# 8) 点格子合成：点第 idx 格 → 另一把同 key 同等级的被吸进来并消失，成品停在这一格
	var mg: Array = [
		{"key": "a", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
		{"key": "b", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
		{"key": "a", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
	]
	chk(Inventory.has_partner(mg, 0, MAX_LV) and Inventory.has_partner(mg, 2, MAX_LV), "a 的两格互为搭档")
	chk(Inventory.has_partner(mg, 1, MAX_LV) == false, "b 没有搭档（不该亮合成高亮）")
	var m1 := Inventory.merge_into(mg, 2, MAX_LV, COMBAT_CFG)
	chk(m1 == true, "点第 3 格可以合成")
	chk(mg.size() == 2, "合成后少一把（实际 %d 把）" % mg.size())
	chk(str(mg[0]["key"]) == "a" and int(mg[0]["lv"]) == 2, "合成结果停在两格里靠左的那格")
	chk(str(mg[1]["key"]) == "b", "没参与合成的那把位次不变")
	chk(int(mg[0]["buy_cost"]) == 40, "买入价累加 20+20（实际 %d）" % int(mg[0]["buy_cost"]))
	# 点靠左的那格，结果同样停在靠左那格（点哪边画面都一样）
	var mg2: Array = [
		{"key": "a", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
		{"key": "a", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
		{"key": "c", "lv": 1, "dmg": 10, "cd": 0.5, "buy_cost": 20},
	]
	var m2 := Inventory.merge_into(mg2, 0, MAX_LV, COMBAT_CFG)
	chk(m2 and mg2.size() == 2 and int(mg2[0]["lv"]) == 2, "点第 1 格合成 → 结果仍停在第 1 格")
	chk(str(mg2[1]["key"]) == "c", "移除的是靠右的搭档，后面的补位正常")
	# 满级的格子找不到搭档
	var mg3: Array = [{"key": "a", "lv": MAX_LV, "dmg": 10, "cd": 0.5, "buy_cost": 100},
		{"key": "a", "lv": MAX_LV, "dmg": 10, "cd": 0.5, "buy_cost": 100}]
	chk(Inventory.merge_into(mg3, 0, MAX_LV, COMBAT_CFG) == false, "满级的两把不能再往上合")

	# 9) 守卫：数据表里每个强化的 stat 都必须被游戏某处处理
	#    （曾经出过 upgrades.json 写 heal_now、代码却匹配 heal 的静默失效 bug）
	#
	#    ⚠️ 原来是硬编码一份 known 列表，结果"加一个道具就要改一次测试"，
	#    而且改漏了就静默放过。现在直接扫源码里有没有出现这个字符串 ——
	#    加道具不用碰测试，反过来漏处理就一定会被拦下。
	#    连"扫哪些文件"都不硬编码 —— 之前写成固定列表，结果一拆文件
	#    （Player → PlayerWeapons）就把新文件漏掉、误报。现在全项目扫 .gd，
	#    只排掉 tests/ 与 addons/，以后怎么拆都不会再误报。
	var code := _source_corpus()
	chk(code.length() > 20000, "能读到用于校验 stat 的源码（防止路径写错导致假通过，实际 %d 字符）" % code.length())
	# 直接读 JSON：本测试的 run() 不接收 data 参数，自己读最稳
	var ups: Dictionary = {}
	var f := FileAccess.open("res://data/upgrades.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			ups = j.get_data() as Dictionary
		f.close()
	var bad: Array = []
	for k in ups:
		var d: Dictionary = ups[k] as Dictionary
		var s := str(d.get("stat", ""))
		# 必须在源码里以字符串字面量的形式出现过（"wok_dmg_pct" 这种）
		if not code.contains('"%s"' % s):
			bad.append("%s:%s" % [k, s])
	chk(bad.is_empty(), "upgrades.json 的每个 stat 都在源码里被处理（全项目扫 .gd）" +
		("" if bad.is_empty() else "（没找到处理的 stat: %s）" % str(bad)))

	return {"pass": _p, "fail": _f, "failures": _failures}

# 把全项目的 GDScript 源码拼成一个大字符串，用于"stat 有没有被处理"这类文本扫描。
# 递归遍历 res://，跳过 tests/（否则测试自己提到某个 stat 就会假通过）与 addons/。
func _source_corpus() -> String:
	var out := ""
	var n := 0
	var stack: Array = ["res://"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if name.begins_with("."):
				name = d.get_next()
				continue
			var full: String = dir if dir == "res://" else dir + "/"
			full += name
			if d.current_is_dir():
				if name != "tests" and name != "addons" and name != "web" and name != ".godot":
					stack.append(full)
			else:
				if name.ends_with(".gd"):
					var sf := FileAccess.open(full, FileAccess.READ)
					if sf != null:
						out += sf.get_as_text()
						sf.close()
						n += 1
			name = d.get_next()
		d.list_dir_end()
	return out
