extends RefCounted

# 配平测试：用真实 data/*.json 检查"游戏能不能玩得下去"
# 这是最重要的测试 —— 数值改坏了，这里会先炸

const Combat := preload("res://core/Combat.gd")
const Spawner := preload("res://core/Spawner.gd")
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

func run(data) -> Dictionary:
	var wave_cfg: Dictionary = data.wave_cfg()
	var spawn_cfg: Dictionary = data.spawn_cfg()
	var shop_cfg: Dictionary = data.shop_cfg()
	var length := float(wave_cfg.get("length", 20))

	# 1) 第 1 波：开局只有手枪，必须打得完
	var pistol: Dictionary = data.weapon("pistol")
	var start_dps := Combat.weapon_dps(pistol)
	var h1 := Spawner.wave_total_hp(1, spawn_cfg, data.enemies, length)
	var out1 := start_dps * length
	chk(out1 > h1 * 0.9,
		"第1波能打完：手枪 %d 秒输出 %.0f vs 怪物总血 %.0f" % [int(length), out1, h1])

	# 2) 怪物不能堆到打不完（第1波场上残留数要可控；随波次时长线性放宽）
	var spawn_n1 := Spawner.wave_budget(1, spawn_cfg, length)
	chk(spawn_n1 < 30.0 * (length / 20.0),
		"第1波刷怪量 %.0f 只（≤%.0f），不至于淹没玩家" % [spawn_n1, 30.0 * (length / 20.0)])

	# 3) 刷怪速率始终受 cap 限制
	var bad := false
	for w in range(1, 31):
		if Spawner.spawn_rate(w, spawn_cfg) > float(spawn_cfg.get("cap", 5)) + 0.001:
			bad = true
	chk(not bad, "1~30 波刷怪速率都不超过 cap %.1f" % float(spawn_cfg.get("cap", 5)))

	# 4) 满配（6 把武器 + 中等强化）在第 10 波要跟得上
	var inv: Array = []
	for k in data.weapon_keys():
		inv.append(data.weapon(k))
	var full_dps := Inventory.total_dps(inv, 0.5, 0.4)
	var h10 := Spawner.wave_total_hp(10, spawn_cfg, data.enemies, length)
	chk(full_dps * length > h10,
		"满配第10波跟得上：6 武器输出 %.0f vs 总血 %.0f" % [full_dps * length, h10])

	# 5) 裸装（只有手枪）在高波次应该打不过 —— 证明养成有意义
	var h15 := Spawner.wave_total_hp(15, spawn_cfg, data.enemies, length)
	chk(start_dps * length < h15,
		"裸装第15波打不过（养成有意义）：%.0f vs %.0f" % [start_dps * length, h15])

	# 6) 经济：一波下来要买得起东西
	var cheapest := 999
	for k in data.weapon_keys():
		cheapest = mini(cheapest, int(data.weapon(k).get("cost", 999)))
	var bonus1 := Economy.wave_bonus(1, wave_cfg)
	chk(bonus1 >= cheapest,
		"第1波奖励 %d 金币 ≥ 最便宜武器 %d 金币（买得起）" % [bonus1, cheapest])

	# 7) 武器强度与价格大致正相关（不出现又便宜又强）
	var pistol_dps := Combat.weapon_dps(pistol)
	var rocket_dps := Combat.weapon_dps(data.weapon("rocket"))
	chk(int(data.weapon("rocket").get("cost")) > int(pistol.get("cost")),
		"火箭筒比手枪贵")
	chk(rocket_dps > pistol_dps, "火箭筒 DPS %.0f > 手枪 %.0f" % [rocket_dps, pistol_dps])

	# 8) 手感参数在合理范围
	var feel: Dictionary = data.feel_cfg()
	chk(float(feel.get("joystick_deadzone", 99)) <= 5, "摇杆死区 ≤ 5px（实际 %s）" % feel.get("joystick_deadzone"))
	chk(float(feel.get("accel_reverse", 0)) >= float(feel.get("accel_forward", 1)), "反向变向不慢于正向")
	# 变向到 90% 速度的时间应低于人眼感知阈值
	var accel_rev := float(feel.get("accel_reverse", 1))
	var ms := (2.303 / accel_rev) * 1000.0 + 16.7
	chk(ms < 80, "变向响应 %.0f ms < 80ms 感知阈值" % ms)

	# 9) 所有武器/敌人/强化字段完整
	var missing := []
	for k in data.weapon_keys():
		var w: Dictionary = data.weapon(k)
		for f in ["zh", "dmg", "cd", "range", "cost", "color"]:
			if not w.has(f):
				missing.append("weapon." + k + "." + f)
	for k in data.enemies.keys():
		var e: Dictionary = data.enemy(k)
		for f in ["hp_base", "speed_base", "dmg_base", "radius", "gold"]:
			if not e.has(f):
				missing.append("enemy." + k + "." + f)
	for k in data.upgrade_keys():
		var u: Dictionary = data.upgrade(k)
		for f in ["zh", "stat", "value", "cost"]:
			if not u.has(f):
				missing.append("upgrade." + k + "." + f)
	chk(missing.is_empty(), "三张数据表字段完整" + ("" if missing.is_empty() else " 缺: " + str(missing)))

	# 10) 玩家初始属性合理
	var pc: Dictionary = data.player_cfg()
	chk(float(pc.get("max_hp", 0)) > 0, "初始血量 > 0")
	chk(float(pc.get("ifr_seconds", 0)) > 0.2, "无敌帧 %.2f 秒，能防止被围秒杀" % float(pc.get("ifr_seconds", 0)))
	chk(float(pc.get("speed", 0)) >= 150, "移速 %s ≥ 150，跑位跟得上" % pc.get("speed"))

	# 11) 玩家初始移速不能慢于任何基础敌人（用户核心诉求：应≥或等于怪物速度，才能风筝走位）
	var pspeed := float(pc.get("speed", 0))
	var slowest_ok := true
	var fastest_enemy := ""
	var fastest_speed := 0.0
	for k in data.enemies.keys():
		var es := float(data.enemy(k).get("speed_base", 0))
		if es > fastest_speed:
			fastest_speed = es
			fastest_enemy = k
		if pspeed < es:
			slowest_ok = false
	chk(slowest_ok, "玩家移速 %.0f ≥ 所有基础敌人（最快 %s=%.0f）" % [pspeed, fastest_enemy, fastest_speed])

	# 12) 敌人必须"追得上人"，否则永远打不到玩家（曾经踩过：怪太慢，
	# 还没走到跟前就被秒，玩家整局 0 次挨打 —— 难度曲线直接塌掉）
	var g1 := Spawner.stats_for("grunt", 1, data.enemies)
	var g20 := Spawner.stats_for("grunt", 20, data.enemies)
	var f10 := Spawner.stats_for("fast", 10, data.enemies)
	var ps20 := float(g20.get("speed", 0))
	var ps1 := float(g1.get("speed", 0))
	var fs10 := float(f10.get("speed", 0))
	chk(ps1 <= pspeed * 0.60,
		"第1波小兵 %.0f ≤ 玩家 %.0f 的 60%%（开局能轻松拉开）" % [ps1, pspeed])
	chk(ps20 >= pspeed * 0.70,
		"第20波小兵 %.0f ≥ 玩家 %.0f 的 70%%（后期无脑绕圈躲不掉）" % [ps20, pspeed])
	chk(fs10 >= pspeed * 0.85,
		"第10波冲刺兵 %.0f ≥ 玩家 %.0f 的 85%%（快兵必须靠冲刺/预判）" % [fs10, pspeed])

	# 13) 敌人要活得够久，能走到玩家跟前（出生点在边缘，离中心 250px 以上）
	# 存活时间太短 = 出生即死 = 玩家永远看不到怪贴脸
	var g20_hp := float(g20.get("hp", 0))
	chk(g20_hp >= 150.0, "第20波小兵血量 %.0f ≥ 150（不至于出场即蒸发）" % g20_hp)

	return {"pass": _p, "fail": _f, "failures": _failures}
