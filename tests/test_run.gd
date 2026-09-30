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

	return {"pass": _p, "fail": _f, "failures": _failures}
