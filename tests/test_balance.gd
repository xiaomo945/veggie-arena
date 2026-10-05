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

	# 1) 第 1 波：开局只有手枪，也要能造成"可观"伤害。
	#    本作是生存计时制（撑满 60s 即过关，不要求清场），所以不要求手枪单独清掉整波血，
	#    只要起手配置能砍掉整波血量的一个明显份额就算"起手武器有效"，其余靠生存 + 商店养成补上。
	#    口径用"开局真实配置"= 手枪 + 冲锋枪（镜像 GameState.reset），不是只看手枪。
	#    门槛 30%（实测 58%）：用户要求血量大幅增加后，单看手枪只剩 ~21%，
	#    那是"有意的难度提升"而不是"起手无效"，所以改用真实开局配置判定。
	#    （真正的"打不打得完"由 2.5 整局集成验证的"推进到第 2 波"兜底。）
	var pistol: Dictionary = data.weapon("pistol")
	var start_dps := Combat.weapon_dps(pistol) + Combat.weapon_dps(data.weapon("smg"))
	var h1 := Spawner.wave_total_hp(1, spawn_cfg, data.enemies, length)
	var out1 := start_dps * length
	chk(out1 > h1 * 0.30,
		"第1波起手配置能砍掉 ≥30% 血量：%.0f 秒输出 %.0f vs 怪物总血 %.0f" % [int(length), out1, h1])

	# 2) 怪物密度受 max_alive 硬封顶（场上可见数不会超过它），整波刷怪量允许合理周转
	#    （怪会死、会补，所以整波总量可比场上峰值大几倍，只要不超过 max_alive 的若干倍即可）。
	var spawn_n1 := Spawner.wave_budget(1, spawn_cfg, length)
	var alive_cap := float(spawn_cfg.get("max_alive", 60))
	chk(spawn_n1 < alive_cap * 6.5,
		"第1波刷怪量 %.0f 只（< max_alive*6.5=%.0f），周转可控不淹没" % [spawn_n1, alive_cap * 6.5])

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
		# 单属性道具写 stat/value，多属性道具（"有取舍"类）写 stats 字典，二选一即可
		var multi_stats: Dictionary = u.get("stats", {}) as Dictionary
		for f in ["zh", "cost"]:
			if not u.has(f):
				missing.append("upgrade." + k + "." + f)
		if multi_stats.is_empty():
			for f in ["stat", "value"]:
				if not u.has(f):
					missing.append("upgrade." + k + "." + f)
		else:
			# 多属性道具的每一条也必须落在属性目录里，不然买了没效果
			for sk in multi_stats:
				if not Inventory.is_known_stat(str(sk)):
					missing.append("upgrade." + k + ".stats." + str(sk))
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
	chk(ps1 <= pspeed * 0.45,
		"第1波小兵 %.0f ≤ 玩家 %.0f 的 45%%（开局能轻松拉开）" % [ps1, pspeed])
	# 下限从 55% 调到 45%：用户诉求"移动速度太快了"，speed_per_wave 已整体 ×0.45。
	# 这里的下限只是"后期还得有点威胁、不能靠绕圈无脑躲"的保底，不是难度诉求本身。
	chk(ps20 >= pspeed * 0.45,
		"第20波小兵 %.0f ≥ 玩家 %.0f 的 45%%（后期仍构成威胁，但不再是 55%% 的压迫感）"
		% [ps20, pspeed])
	chk(fs10 >= pspeed * 0.45,
		"第10波冲刺兵 %.0f ≥ 玩家 %.0f 的 45%%（快兵要靠冲刺/预判，但不该快到追死）"
		% [fs10, pspeed])

	# 12b) ⚠️ 这条是踩过坑才补的：上面只保证"敌人追得上玩家"，却没保证
	# "玩家跑得掉"。旧数值下第20波冲刺兵 300 > 玩家 240 —— 后期玩家比怪还慢，
	# 无论怎么走位都逃不掉，手感上就表现为"移动不跟手、很黏"。
	# 手机触屏的走位精度远不如鼠标，玩家必须留出明显的速度余量。
	var fastest_late := 0.0
	var fastest_name := ""
	for k in ["grunt", "fast", "tank", "fly", "swarm", "brute", "shambler"]:
		if not data.enemies.has(k):
			continue
		var sp := float(Spawner.stats_for(k, 20, data.enemies).get("speed", 0))
		if sp > fastest_late:
			fastest_late = sp
			fastest_name = k
	chk(fastest_late <= pspeed * 0.90,
		"第20波最快敌人 %s=%.0f ≤ 玩家 %.0f 的 90%%（后期还能拉开，不是被黏死）"
		% [fastest_name, fastest_late, pspeed])

	# 13) 敌人要活得够久，能走到玩家跟前（出生点在边缘，离中心 250px 以上）
	# 存活时间太短 = 出生即死 = 玩家永远看不到怪贴脸
	var g20_hp := float(g20.get("hp", 0))
	chk(g20_hp >= 150.0, "第20波小兵血量 %.0f ≥ 150（不至于出场即蒸发）" % g20_hp)

	# 13b) 终局 Boss 配置：明显强于普通 Boss，且数值只走 JSON
	var fb: Dictionary = data.final_boss_cfg()
	chk(bool(fb.get("enabled", false)), "final_boss 段已启用")
	chk(float(fb.get("hp_mult", 0)) > 2.0, "终局 Boss 血量倍率 %.1f 远高于普通 Boss"
		% float(fb.get("hp_mult", 0)))
	chk(float(fb.get("radius_mult", 0)) > 1.2, "终局 Boss 体型倍率 %.2f 明显更大"
		% float(fb.get("radius_mult", 0)))
	chk(float(fb.get("dmg_mult", 0)) > 1.0, "终局 Boss 伤害倍率 %.2f 更高" % float(fb.get("dmg_mult", 0)))
	chk(float(fb.get("gold_mult", 0)) > 2.0, "终局 Boss 金币倍率 %.1f 值得攒大招去打"
		% float(fb.get("gold_mult", 0)))
	chk(fb.has("phases"), "final_boss 有 phases 开关（是否分阶段走配置）")

	# 13c) 无尽段配置：默认开启 + 成长参数齐全
	chk(bool(wave_cfg.get("endless", false)), "wave.endless 默认开启（通关后可继续）")
	var ec: Dictionary = data.endless_cfg()
	var ec_miss := []
	for f in ["hp_per_wave", "dmg_per_wave", "gold_per_wave", "rate_per_wave", "rate_cap"]:
		if not ec.has(f):
			ec_miss.append("endless." + f)
	chk(ec_miss.is_empty(), "endless 段成长参数齐全"
		+ ("" if ec_miss.is_empty() else " 缺: " + str(ec_miss)))
	chk(float(ec.get("rate_cap", 0)) > float(spawn_cfg.get("cap", 0)),
		"无尽段 rate_cap %.1f 高于常规 cap %.1f（能突破刷怪上限）"
		% [float(ec.get("rate_cap", 0)), float(spawn_cfg.get("cap", 0))])
	# 精英节奏：不再依赖 Boss 波
	var sc2: Dictionary = data.spawn_cfg()
	chk(int(sc2.get("elite_from_wave", 0)) < int(sc2.get("boss_every", 5)),
		"精英从第 %d 波就开始出（早于第一个 Boss 波）" % int(sc2.get("elite_from_wave", 0)))
	chk(Spawner.elite_chance(int(sc2.get("elite_from_wave", 1)), sc2) > 0.0,
		"起始波就有精英概率")
	chk(Spawner.elite_chance(1, sc2) == 0.0, "第 1 波不出精英（开局不被精英劝退）")
	chk(Spawner.elite_chance(8, sc2) > 0.0, "第 8 波（非 Boss 波）也有精英轮")

	# 14) 本轮新增的"多种玩法"道具齐全（商店经济中枢 + 道具改变可玩性）
	var req_up := ["autopick", "fullauto", "wokdmg", "wokknock", "wokslow", "wokcharge"]
	var missing_up := []
	for k in req_up:
		if not data.upgrades.has(k):
			missing_up.append(k)
	chk(missing_up.is_empty(), "新增玩法道具齐全（自动拾取/全屏拾取/颠勺伤害/击退/减速/锅气上限）" + ("" if missing_up.is_empty() else " 缺: " + str(missing_up)))
	# wok 充能上限字段存在（颠勺可存多个充能、按钮常驻）
	chk(data.wok_cfg().has("max_charges"), "wok.max_charges 存在（颠勺可存充能）")
	# 各类新道具 cost > 0，能被买得起（不会白送）
	var cheap_ok := true
	for k in req_up:
		if int(data.upgrade(k).get("cost", 0)) <= 0:
			cheap_ok = false
	chk(cheap_ok, "新道具价格均为正（进商店经济循环）")

	return {"pass": _p, "fail": _f, "failures": _failures}
