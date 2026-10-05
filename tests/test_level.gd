extends RefCounted

# 经验 / 等级系统测试：分段曲线、连升、封顶、升级奖励、击杀经验权重、整局量级。
#
# 关键守卫（都是真实踩过的坑，不是凑数）：
#   1) 曲线必须严格单调递增 —— 否则"经验越多需要越多"，玩家永远升不了级；
#   2) 封顶后 add() 不能继续涨等级，否则 HUD 显示 61 级、奖励却一直发；
#   3) 升级奖励里 heal 不能超过 max_hp（算法层就不越界，不靠调用方 clamp）；
#   4) 击杀经验必须"精英 > 普通 > 虫群"，否则玩家没有优先打精英的动机；
#   5) **整局量级守卫**：用真实击杀数跑一遍，等级必须落在合理区间。
#      这条最有价值 —— 曲线参数改错时前面 20 条断言全绿，只有它会红。

const Level := preload("res://core/Level.gd")

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


func run(data = null) -> Dictionary:
	# 自包含读表
	var cfg: Dictionary = {}
	if data != null and data.level_cfg != null and not data.level_cfg().is_empty():
		cfg = data.level_cfg()
	if cfg.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				cfg = (j.get_data() as Dictionary).get("level", {}) as Dictionary
			f.close()

	chk(not cfg.is_empty(), "balance.json 有 level 配置段")
	chk(float(cfg.get("base", 0.0)) > 0.0, "level.base > 0（1 级所需经验为正）")
	chk(float(cfg.get("step", 0.0)) > 0.0, "level.step > 0（否则曲线会走平）")
	chk(float(cfg.get("span", -1.0)) >= 1.0, "level.span >= 1（二次加速起点合法）")
	# ⚠️ 不再有 growth：纯指数曲线是踩过的坑。若有人加回来，说明以为指数更好 ——
	#    提醒他看 core/Level.gd 文件头的实测数据（1500 杀冲到 29 级）。
	chk(not cfg.has("growth"), "level 没有 growth 字段（纯指数曲线已被实测否掉）")
	chk(Level.needed(1, {}) == Level.needed(1, cfg),
		"不传 cfg 时回落到内置常量（1 级所需一致）")

	# 1) 曲线严格单调递增
	var prev := 0
	var mono := true
	for lv in range(1, 60):
		var n := Level.needed(lv, cfg)
		if n <= prev:
			mono = false
			break
		prev = n
	chk(mono, "每级所需经验严格递增（1~59 级）")
	chk(Level.needed(1, cfg) == int(round(float(cfg.get("base", 20.0)))),
		"1 级所需 = base（实测 %d）" % Level.needed(1, cfg))

	# 2) 分段点前后都连续
	var span := int(cfg.get("span", 10))
	if span >= 2 and span + 1 < Level.MAX_LEVEL:
		var a := Level.needed(span - 1, cfg)
		var b := Level.needed(span, cfg)
		var c := Level.needed(span + 1, cfg)
		chk(c > b and b > a, "span=%d 附近曲线连续无断层（%d → %d → %d）" % [span, a, b, c])
		var early := Level.needed(6, cfg) - Level.needed(5, cfg)
		var late := Level.needed(span + 6, cfg) - Level.needed(span + 5, cfg)
		chk(late > early, "span 之后每级增量更大（%d > %d，高等级才有追求）" % [late, early])

	# 3) 封顶
	chk(Level.needed(Level.MAX_LEVEL, cfg) > 0,
		"%d 级（满级）仍返回所需经验，不会除零" % Level.MAX_LEVEL)
	chk(int(Level.breakdown(int(Level.total_for(Level.MAX_LEVEL, cfg)) * 3, cfg)["level"])
		== Level.MAX_LEVEL, "远超满级经验时等级封顶在 %d" % Level.MAX_LEVEL)
	chk(Level.needed(999, cfg) > 0, "越界等级号返回合法值（不崩）")

	# 4) breakdown 内部自洽
	chk(int(Level.breakdown(0, cfg)["level"]) == 1, "0 经验 = 1 级")
	chk(int(Level.breakdown(0, cfg)["pct"]) == 0, "0 经验进度 0%")
	var one := Level.breakdown(int(Level.needed(1, cfg)), cfg)
	chk(int(one["level"]) == 2, "刚好 1 级所需经验 = 2 级（实测 %d）" % int(one["level"]))
	chk(int(one["into"]) == 0, "刚升级时 into 归零（不是溢出到下一级）")
	var mid := Level.breakdown(int(Level.needed(1, cfg)) * 3, cfg)
	chk(int(mid["level"]) >= 2, "3 倍于 1 级所需经验至少 2 级（实测 %d）" % int(mid["level"]))
	chk(float(mid["pct"]) > 0.0 and float(mid["pct"]) <= 1.0, "进度落在 (0,1]")
	chk(int(mid["into"]) < int(mid["need"]), "into < need（否则该升级却没升）")

	# 5) add 的一次连升多级
	var n1 := int(Level.needed(1, cfg))
	var n2 := int(Level.needed(2, cfg))
	var n3 := int(Level.needed(3, cfg))
	var big := Level.add(0, n1 + n2 + n3, cfg)
	chk(int(big["gained"]) == 3, "一次给足 3 级所需 → 连升 3 级（实测 %d）" % int(big["gained"]))
	chk(int(big["level"]) == 4, "连升后等级 = 4（实测 %d）" % int(big["level"]))
	chk(int(Level.add(0, 1, cfg)["gained"]) == 0, "经验不够一级时 gained = 0（不发升级事件）")
	chk(int(Level.add(0, -999, cfg)["xp"]) == 0, "负经验被夹到 0（不会把等级算成负数）")
	chk(int(Level.add(500, 0, cfg)["gained"]) == 0, "加 0 经验不会触发升级")

	# 6) 升级奖励
	var r1 := Level.level_up_reward(1, 100, cfg)
	chk(int(r1["heal"]) == 14, "满血 100 时升 1 级回 14 血（实测 %d）" % int(r1["heal"]))
	chk(int(r1["heal"]) <= 100, "回血量不超过 max_hp（算法层就不越界）")
	var r3 := Level.level_up_reward(3, 100, cfg)
	chk(int(r3["heal"]) == 42, "连升 3 级按 3 倍回血（实测 %d）" % int(r3["heal"]))
	chk(float(r3["frenzy"]) > float(r1["frenzy"]), "连升时狂暴时长更长")
	chk(int(Level.level_up_reward(0, 100, cfg)["heal"]) > 0, "gained=0 也按 1 级算（不会给 0 奖励）")
	chk(int(Level.level_up_reward(1, 10, cfg)["heal"]) <= 10, "低血上限时也不会超（clamp 生效）")
	chk(int(Level.level_up_reward(50, 100, cfg)["heal"]) == 100, "极端连升也不超过上限")

	# 7) 击杀经验权重
	var bp := int(cfg.get("xp_per_kill", 2))
	var normal := Level.xp_for("grunt", bp)
	var fast := Level.xp_for("fast", bp)
	var tank := Level.xp_for("tank", bp)
	var swarm := Level.xp_for("swarm", bp)
	var elite := Level.xp_for("elite", bp)
	var boss := Level.xp_for("boss", bp)
	chk(bp >= 1, "level.xp_per_kill >= 1（配 0 会让权重全被 round 抹平）")
	chk(normal >= 1, "普通怪至少 1 点经验（实测 %d）" % normal)
	chk(fast == normal, "快兵与普通怪同档（都是 %d 点）" % normal)
	chk(tank > normal, "重甲兵 > 普通怪（%d > %d）" % [tank, normal])
	chk(elite > tank * 2, "精英 > 重甲兵的 2 倍（%d > %d）" % [elite, tank * 2])
	chk(boss > elite * 2, "Boss > 精英的 2 倍（%d > %d）" % [boss, elite * 2])
	chk(boss >= normal * 10, "Boss ≥ 普通怪的 10 倍（%d vs %d）" % [boss, normal])
	chk(swarm < normal, "虫群 < 普通怪（%d < %d，防刷等级）" % [swarm, normal])
	chk(Level.xp_for("grunt", 0) >= 1, "xp_per_kill 配成 0 时仍保底给 1 点（不会经验为 0）")

	# 8) 整局量级守卫（最有价值的一条）
	# 实测整局约 3.9 杀/秒、20 波 × 60 秒 ≈ 4700 杀。混合权重按
	# 普通 70% / 虫群 20% / 精英 8% / Boss 2% 估算（接近实际刷怪表）。
	var per_kill := 0.7 * float(normal) + 0.2 * float(swarm) \
		+ 0.08 * float(elite) + 0.02 * float(boss)
	var lv_1500: int = int(Level.breakdown(int(per_kill * 1500.0), cfg)["level"])
	var lv_4700: int = int(Level.breakdown(int(per_kill * 4700.0), cfg)["level"])
	chk(lv_1500 >= 8 and lv_1500 <= 30, "1500 杀约到 Lv%d（期望 8~30，太低=没爽点）" % lv_1500)
	chk(lv_4700 >= 20 and lv_4700 <= 45, "整局 4700 杀约到 Lv%d（期望 20~45）" % lv_4700)
	chk(lv_4700 > lv_1500, "打得久等级更高（Lv%d > Lv%d）" % [lv_4700, lv_1500])
	# 升级节奏：一波约 230 杀（实测 3.9 杀/秒 × 60 秒）。理想是"一波升 0.5~1.5 级"，
	# 即平均每 150~450 杀一级 —— 太密会变成"数字在跳没人看"，太疏则整局没几次正反馈。
	var avg_need: float = (per_kill * 4700.0) / float(maxi(1, lv_4700))
	chk(avg_need <= 450.0, "整局平均每 %.0f 杀升 1 级（一波至少升 0.5 级）" % avg_need)
	chk(avg_need >= 150.0, "整局平均每 %.0f 杀升 1 级（一波不超过 1.5 级）" % avg_need)
	# 满级必须可达但遥远（对应"未来 60 个萝卜职业"的终局目标）
	var need_max := Level.total_for(Level.MAX_LEVEL, cfg)
	var per_run := per_kill * 4700.0
	chk(need_max > per_run * 2.0,
		"满级需 %.0f 点，一整局的 %.0f 点不够（要靠无尽段）" % [need_max, per_run])
	chk(need_max < per_run * 200.0,
		"满级需 %.0f 点，无尽段 200 波内可达（不是永远够不着）" % need_max)

	return {"pass": _p, "fail": _f, "failures": _failures}
