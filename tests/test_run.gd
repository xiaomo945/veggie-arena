extends RefCounted

# 一局流程纯逻辑测试：是否最后一波、通关结算分。
# 直接测 core/Run.gd（不依赖 autoload，--script 模式可跑）。

const Run := preload("res://core/Run.gd")

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

func run(_data) -> Dictionary:
	# 默认通关波数 20
	var cfg := {"total": 20}
	chk(not Run.is_last_wave(1, cfg), "第1波不是通关波")
	chk(not Run.is_last_wave(19, cfg), "第19波不是通关波")
	chk(Run.is_last_wave(20, cfg), "第20波 = 通关波")
	chk(Run.is_last_wave(21, cfg), "超过20波也算已通关")

	# total = 0 → 无限模式，永不通关
	chk(not Run.is_last_wave(999, {"total": 0}), "total=0 无限模式永不通关")

	# 结算分：击杀*10 + 金币 + 波次*50
	chk(Run.score(10, 50, 3) == 10 * 10 + 50 + 3 * 50, "分数 = 击杀*10 + 金币 + 波次*50")
	chk(Run.score(0, 0, 1) == 50, "0击杀0金币第1波 = 50分")
	chk(Run.score(100, 200, 20) == 100 * 10 + 200 + 20 * 50, "满局高分计算正确")
	# 无尽波数要能从结算分里体现出来（越往后越值钱）
	chk(Run.score(100, 200, 26) > Run.score(100, 200, 20), "无尽波次的结算分更高")

	# ---- 终局波（终局 Boss 那一波）----
	var cfg20 := {"total": 20, "endless": true}
	chk(Run.is_final_wave(20, cfg20), "第 20 波 = 终局波")
	chk(not Run.is_final_wave(19, cfg20), "第 19 波不是终局波")
	chk(not Run.is_final_wave(21, cfg20), "第 21 波不是终局波（终局 Boss 只有一只）")

	# ---- 无尽段判定 ----
	chk(not Run.is_endless_wave(20, cfg20), "第 20 波还没进无尽段")
	chk(Run.is_endless_wave(21, cfg20), "第 21 波进入无尽段")
	chk(Run.endless_over(20, cfg20) == 0, "最终波的超出波数 = 0")
	chk(Run.endless_over(25, cfg20) == 5, "第 25 波超出最终波 5 波")
	var off := {"total": 20, "endless": false}
	chk(not Run.is_endless_wave(25, off), "wave.endless=false 时永远没有无尽段")
	chk(Run.endless_over(25, off) == 0, "关掉无尽后超出波数恒为 0")
	var inf := {"total": 0, "endless": true}
	chk(Run.endless_over(30, inf) == 0, "total=0（纯无尽）没有超出波数")

	# ---- 无尽段成长倍率 ----
	var ec := {"hp_per_wave": 0.2, "hp_cap": 3.0}
	chk(abs(Run.endless_mult(0, ec, "hp") - 1.0) < 0.001, "未进无尽段倍率 = 1")
	chk(abs(Run.endless_mult(5, ec, "hp") - 2.0) < 0.001, "超出 5 波血量 x2.0")
	chk(abs(Run.endless_mult(50, ec, "hp") - 3.0) < 0.001, "倍率封顶在 hp_cap 3.0")
	chk(abs(Run.endless_mult(5, ec, "dmg") - 1.0) < 0.001, "未配的项倍率保持 1")
	var sc := Run.endless_scales(25, cfg20,
		{"hp_per_wave": 0.2, "dmg_per_wave": 0.1, "gold_per_wave": 0.05})
	chk(abs(float(sc["hp"]) - 2.0) < 0.001, "endless_scales 血量 x2.0")
	chk(abs(float(sc["dmg"]) - 1.5) < 0.001, "endless_scales 伤害 x1.5")
	chk(abs(float(sc["gold"]) - 1.25) < 0.001, "endless_scales 金币 x1.25")

	return {"pass": _p, "fail": _f, "failures": _failures}
