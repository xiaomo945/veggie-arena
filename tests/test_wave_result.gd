extends RefCounted

# 每波结算页（D3-3）的纯逻辑测试：只验 core/WaveStats.gd 的快照与连击衰减。
# 不依赖任何 autoload（Events/Data 在 --script 模式下未注册），且字段名全部公开，
# 不碰私有字段（_combo_t 由 add_kill/tick 内部维护），满足架构守卫 R3。

const WaveStats := preload("res://core/WaveStats.gd")

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

func run(_arg = null) -> Dictionary:
	var s = WaveStats.new()
	# 本波开局快照：当时持有 30 金 / 累计 5 杀
	s.snapshot(30, 5)
	# 本波统计 = 当前值 − 本波开局快照
	chk(s.gold_earned(50) == 20, "本波金币 = 持有−开局 = %d（期望 20）" % s.gold_earned(50))
	chk(s.kills_this_wave(7) == 2, "本波击杀 = 累计−开局 = %d（期望 2）" % s.kills_this_wave(7))

	# 连击：每次击杀 +1，最高连击跟随刷新
	s.add_kill()
	s.add_kill()
	s.add_kill()
	chk(s.combo == 3, "连续击杀后本波连击 = %d（期望 3）" % s.combo)
	chk(s.best_combo == 3, "最高连击 = %d（期望 3）" % s.best_combo)
	chk(s.kills_this_wave(10) == 5, "击杀后本波击杀 = %d（期望 5）" % s.kills_this_wave(10))

	# 连击超时归零（tick 是纯函数，不碰 Events，可单测）
	s.tick(3.0)
	chk(s.combo == 0, "超过窗口无击杀 → 连击归零（实际 %d）" % s.combo)
	chk(s.best_combo == 3, "最高连击保留历史峰值 = %d（期望 3）" % s.best_combo)

	# 起一段新连击：要连到 4 超过历史峰值 3 才刷新最高
	s.add_kill()
	s.add_kill()
	s.add_kill()
	chk(s.best_combo == 3, "新连击未超历史峰值时不刷新 = %d（期望 3）" % s.best_combo)
	s.add_kill()
	chk(s.best_combo == 4, "新连击超过历史峰值才刷新 = %d（期望 4）" % s.best_combo)

	# 开新波：快照重算后本波统计清零
	s.snapshot(100, 20)
	chk(s.gold_earned(100) == 0, "开新波后本波金币归零 = %d（期望 0）" % s.gold_earned(100))
	chk(s.kills_this_wave(20) == 0, "开新波后本波击杀归零 = %d（期望 0）" % s.kills_this_wave(20))
	chk(s.best_combo == 0, "开新波后本波最高连击归零 = %d（期望 0）" % s.best_combo)
	chk(s.combo == 0, "开新波后本波连击归零 = %d（期望 0）" % s.combo)

	# 负数保护（gold 可能因波末损耗回吐而低于快照）
	s.snapshot(200, 30)
	chk(s.gold_earned(150) == 0, "本波金币不为负（实际 %d）" % s.gold_earned(150))

	return {"pass": _p, "fail": _f, "failures": _failures}
