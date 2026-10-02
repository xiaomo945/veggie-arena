extends RefCounted

const Spawner := preload("res://core/Spawner.gd")

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

var CFG := {
	"base_rate": 0.55, "per_wave": 0.30, "cap": 4.6, "max_alive": 88,
	"warn_time": 0.45, "edge_offset": 20,
	"fast_from_wave": 2, "fast_chance": 0.28,
	"fly_from_wave": 4, "fly_chance": 0.20,
	"tank_from_wave": 3, "tank_chance": 0.12,
	"tank_late_from_wave": 6, "tank_chance_late": 0.18,
}
var DEFS := {
	"grunt": {"hp_base": 8, "hp_per_wave": 4.5, "speed_base": 48, "speed_per_wave": 1.8,
		"dmg_base": 4, "dmg_per_wave": 0.7, "radius": 14, "gold": 1},
	"fast": {"hp_base": 5, "hp_per_wave": 2.6, "speed_base": 96, "speed_per_wave": 2.2,
		"dmg_base": 3, "dmg_per_wave": 0.5, "radius": 11, "gold": 1},
	"fly": {"hp_base": 4, "hp_per_wave": 2.0, "speed_base": 118, "speed_per_wave": 2.6,
		"dmg_base": 3, "dmg_per_wave": 0.4, "radius": 10, "gold": 2},
	"tank": {"hp_base": 26, "hp_per_wave": 11, "speed_base": 30, "speed_per_wave": 0.7,
		"dmg_base": 9, "dmg_per_wave": 1.3, "radius": 23, "gold": 3},
	"boss": {"hp_base": 240, "hp_per_wave": 46, "speed_base": 34, "speed_per_wave": 1.1,
		"dmg_base": 16, "dmg_per_wave": 2.6, "radius": 40, "gold": 25},
}
var ARENA := {"x": 12, "y": 74, "w": 516, "h": 756, "edge_offset": 20}

func run() -> Dictionary:
	# 1) 刷怪速率
	var r1 := Spawner.spawn_rate(1, CFG)
	var r5 := Spawner.spawn_rate(5, CFG)
	var r30 := Spawner.spawn_rate(30, CFG)
	chk(abs(r1 - 0.85) < 0.01, "第 1 波刷怪速率 0.85/秒（实际 %.2f）" % r1)
	chk(r5 > r1, "刷怪速率随波次递增（第5波 %.2f > 第1波 %.2f）" % [r5, r1])
	chk(abs(r30 - 4.6) < 0.01, "高波次被 cap 限制在 4.6（实际 %.2f）" % r30)

	# 2) 第 1 波不得过于离谱（20 秒内 10~30 只）
	var b1 := Spawner.wave_budget(1, CFG, 20.0)
	chk(b1 > 10 and b1 < 30, "第 1 波总量 %.1f 只在 10~30 之间" % b1)

	# 3) 敌人类型分布
	chk(Spawner.pick_type(1, 0.0, CFG) == "grunt", "第 1 波只有小兵")
	chk(Spawner.pick_type(1, 0.99, CFG) == "grunt", "第 1 波不刷重甲")
	chk(Spawner.pick_type(3, 0.99, CFG) == "tank", "第 3 波开始有重甲")
	chk(Spawner.pick_type(5, 0.1, CFG) == "fast", "第 5 波有冲刺兵")
	# 飞行兵：第 4 波起才出现，且落在 fast 之后的概率带
	chk(Spawner.pick_type(1, 0.4, CFG) == "grunt", "第 1 波无飞行兵")
	chk(Spawner.pick_type(4, 0.3, CFG) == "fly", "第 4 波出现飞行兵（概率带中段）")
	chk(Spawner.pick_type(6, 0.4, CFG) == "fly", "第 6 波飞行兵稳定出现")
	# 首领不走 pick_type（由 Boss 波单独刷），普通刷怪永远不会出 boss
	chk(Spawner.pick_type(5, 0.99, CFG) == "tank", "普通刷怪不刷首领（仍是重甲）")
	# 统计 1000 次，检查比例大致合理
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var cnt := {"grunt": 0, "fast": 0, "tank": 0}
	for i in 1000:
		var t := Spawner.pick_type(6, rng.randf(), CFG)
		cnt[t] = int(cnt.get(t, 0)) + 1
	chk(cnt["fast"] > 200 and cnt["fast"] < 360, "第6波冲刺兵约 28%%（实际 %d/1000）" % cnt["fast"])
	chk(cnt["tank"] > 100 and cnt["tank"] < 260, "第6波重甲约 18%%（实际 %d/1000）" % cnt["tank"])

	# 4) 出生点必须在场外
	for side in 4:
		var p := Spawner.edge_position(side, ARENA, 0.5, 0.5)
		var inside: bool = (p.x >= float(ARENA["x"]) and p.x <= float(ARENA["x"]) + float(ARENA["w"]) \
			and p.y >= float(ARENA["y"]) and p.y <= float(ARENA["y"]) + float(ARENA["h"]))
		chk(not inside, "第 %d 条边的出生点在场外 %s" % [side, p])

	# 5) 属性随波次增长
	var g1 := Spawner.stats_for("grunt", 1, DEFS)
	var g5 := Spawner.stats_for("grunt", 5, DEFS)
	chk(float(g5["hp"]) > float(g1["hp"]), "小兵血量随波次增长（%.1f → %.1f）" % [g1["hp"], g5["hp"]])
	chk(float(Spawner.stats_for("tank", 1, DEFS)["hp"]) > float(g1["hp"]), "重甲比小兵血厚")
	chk(float(Spawner.stats_for("fast", 1, DEFS)["speed"]) > float(g1["speed"]), "冲刺兵比小兵快")
	chk(Spawner.stats_for("不存在的怪", 1, DEFS).is_empty(), "未知敌种返回空字典（不崩溃）")

	# 5.1) 精英缩放：血更厚、体型更大、金币更多、带 elite 标记
	var base_g := Spawner.stats_for("grunt", 5, DEFS)
	var elite_g := Spawner.stats_for("grunt", 5, DEFS, true)
	chk(float(elite_g["hp"]) > float(base_g["hp"]) * 2.0, "精英血量翻倍以上（%.0f vs %.0f）" % [elite_g["hp"], base_g["hp"]])
	chk(float(elite_g["radius"]) > float(base_g["radius"]), "精英体型更大")
	chk(int(elite_g["gold"]) > int(base_g["gold"]), "精英金币更多")
	chk(bool(elite_g.get("elite", false)) == true, "精英带 elite 标记")
	# 非精英默认无标记
	chk(bool(base_g.get("elite", false)) == false, "普通怪无 elite 标记")

	# 5.2) 首领属性合理：血厚、体型最大、高伤、高金币
	var boss := Spawner.stats_for("boss", 5, DEFS)
	chk(float(boss["hp"]) > float(Spawner.stats_for("tank", 5, DEFS)["hp"]), "首领比重甲还厚")
	chk(float(boss["radius"]) > float(Spawner.stats_for("tank", 5, DEFS)["radius"]), "首领体型最大")
	chk(int(boss["gold"]) >= 25, "首领金币丰厚（%d）" % int(boss["gold"]))

	# 6) 波次总血量递增
	var h1 := Spawner.wave_total_hp(1, CFG, DEFS, 20.0)
	var h5 := Spawner.wave_total_hp(5, CFG, DEFS, 20.0)
	chk(h5 > h1 * 2, "第 5 波总血量是第 1 波的两倍以上（%.0f vs %.0f）" % [h5, h1])

	# 7) 精英的独立出场节奏：起波前不出、非精英轮不出、概率随波次递增且封顶
	var ecfg := {"elite_from_wave": 4, "elite_every": 2, "elite_chance": 0.10,
		"elite_chance_per_wave": 0.015, "elite_chance_cap": 0.30}
	chk(Spawner.elite_chance(1, ecfg) == 0.0, "第 1 波不出精英")
	chk(Spawner.elite_chance(3, ecfg) == 0.0, "未到 elite_from_wave 不出精英")
	chk(Spawner.elite_chance(4, ecfg) > 0.0, "第 4 波开始出精英")
	chk(Spawner.elite_chance(5, ecfg) == 0.0, "第 5 波不是精英轮（隔一波来一轮）")
	chk(Spawner.elite_chance(6, ecfg) > Spawner.elite_chance(4, ecfg), "精英概率随波次递增")
	chk(abs(Spawner.elite_chance(40, ecfg) - 0.30) < 0.001, "精英概率封顶 0.30（实际 %.2f）"
		% Spawner.elite_chance(40, ecfg))
	# 精英不再依赖 Boss 波：非 5 的倍数的普通波也有精英轮
	chk(Spawner.elite_chance(8, ecfg) > 0.0, "第 8 波（非 Boss 波）也出精英")

	# 8) 终局 Boss：在普通 boss 上叠倍率，明显更硬更大更值钱
	var fb := {"enabled": true, "hp_mult": 3.4, "radius_mult": 1.5, "dmg_mult": 1.25,
		"gold_mult": 3.5, "speed_mult": 1.05, "phases": true,
		"phase_steps": [0.75, 0.5, 0.25], "color": "#ff3b5c", "zh": "终局首领"}
	var nb := Spawner.stats_for("boss", 20, DEFS)
	var fin := Spawner.final_boss_stats(20, DEFS, fb)
	chk(float(fin["hp"]) > float(nb["hp"]) * 3.0, "终局 Boss 血量是普通 Boss 的 3 倍以上（%.0f vs %.0f）"
		% [float(fin["hp"]), float(nb["hp"])])
	chk(float(fin["radius"]) > float(nb["radius"]), "终局 Boss 体型更大")
	chk(float(fin["damage"]) > float(nb["damage"]), "终局 Boss 伤害更高")
	chk(int(fin["gold"]) > int(nb["gold"]) * 3, "终局 Boss 金币是普通 Boss 的 3 倍以上")
	chk(bool(fin.get("final", false)), "终局 Boss 带 final 标记（Enemy 据此换造型）")
	chk(str(fin["color"]) == "#ff3b5c", "终局 Boss 换色（可区分）")
	chk((fin["phase_steps"] as Array).size() == 3, "终局 Boss 分 4 个阶段（3 个阈值）")
	chk(not bool(nb.get("final", false)), "普通 Boss 不带 final 标记")
	# 关掉分阶段：阈值数组为空
	var no_ph := {"enabled": true, "hp_mult": 2.0, "phases": false}
	chk((Spawner.final_boss_stats(20, DEFS, no_ph)["phase_steps"] as Array).is_empty(),
		"phases=false 时不分阶段")

	# 9) 无尽段：刷怪速率突破常规 cap、属性按倍率放大
	var rate_cap := float(CFG.get("cap", 5.0))
	chk(abs(Spawner.spawn_rate(30, CFG, 0) - rate_cap) < 0.01, "常规段仍受 cap %.1f 限制" % rate_cap)
	var endless_cfg := {"rate_per_wave": 0.6, "rate_cap": 16.0}
	chk(Spawner.spawn_rate(21, CFG, 1, endless_cfg) > rate_cap,
		"无尽段刷怪速率突破常规 cap（%.2f > %.1f）"
		% [Spawner.spawn_rate(21, CFG, 1, endless_cfg), rate_cap])
	chk(Spawner.spawn_rate(25, CFG, 5, endless_cfg) > Spawner.spawn_rate(21, CFG, 1, endless_cfg),
		"无尽段刷怪速率随超出波数继续涨")
	chk(Spawner.spawn_rate(999, CFG, 978, endless_cfg) <= 16.0 + 0.001, "无尽段速率封顶 rate_cap 16")
	# 属性放大
	var eg := Spawner.stats_for("grunt", 20, DEFS)
	var eg25 := Spawner.stats_for("grunt", 25, DEFS, false, {"hp": 2.0, "dmg": 1.5, "gold": 2.0})
	chk(float(eg25["hp"]) > float(eg["hp"]) * 1.9, "无尽段血量翻倍（%.0f vs %.0f）"
		% [float(eg25["hp"]), float(eg["hp"])])
	chk(float(eg25["damage"]) > float(eg["damage"]), "无尽段伤害更高")
	chk(int(eg25["gold"]) > int(eg["gold"]), "无尽段金币更多（%.0f vs %.0f）"
		% [float(eg25["gold"]), float(eg["gold"])])
	# 精英 + 无尽叠加：精英标记仍在
	chk(bool(Spawner.stats_for("grunt", 25, DEFS, true, {"hp": 2.0})["elite"]),
		"精英与无尽倍率可以叠加")

	return {"pass": _p, "fail": _f, "failures": _failures}
