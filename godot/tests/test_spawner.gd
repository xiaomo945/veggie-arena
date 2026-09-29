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
	"tank_from_wave": 3, "tank_chance": 0.12,
	"tank_late_from_wave": 6, "tank_chance_late": 0.18,
}
var DEFS := {
	"grunt": {"hp_base": 8, "hp_per_wave": 4.5, "speed_base": 48, "speed_per_wave": 1.8,
		"dmg_base": 4, "dmg_per_wave": 0.7, "radius": 14, "gold": 1},
	"fast": {"hp_base": 5, "hp_per_wave": 2.6, "speed_base": 96, "speed_per_wave": 2.2,
		"dmg_base": 3, "dmg_per_wave": 0.5, "radius": 11, "gold": 1},
	"tank": {"hp_base": 26, "hp_per_wave": 11, "speed_base": 30, "speed_per_wave": 0.7,
		"dmg_base": 9, "dmg_per_wave": 1.3, "radius": 23, "gold": 3},
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

	# 6) 波次总血量递增
	var h1 := Spawner.wave_total_hp(1, CFG, DEFS, 20.0)
	var h5 := Spawner.wave_total_hp(5, CFG, DEFS, 20.0)
	chk(h5 > h1 * 2, "第 5 波总血量是第 1 波的两倍以上（%.0f vs %.0f）" % [h5, h1])

	return {"pass": _p, "fail": _f, "failures": _failures}
