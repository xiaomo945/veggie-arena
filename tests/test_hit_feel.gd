extends RefCounted

# 命中顿帧的节流（entities/effects/HitStop.gd）。
#
# 要保的事：连射武器一秒十几次命中，如果每次都顿到 0.05 倍速，画面会变成幻灯片
# （比完全不顿更难受）。所以轻顿帧必须节流，重击不节流。
# 另外：顿帧结束必须把 time_scale 还回 1.0 —— 忘了还，整个游戏就永久慢放。

const HitStop := preload("res://entities/effects/HitStop.gd")

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
	HitStop.reset()
	chk(HitStop.hit_throttled(0.02, 0.5), "第一次普通命中：顿了")
	chk(not HitStop.hit_throttled(0.02, 0.5), "紧接着的第二次被节流吃掉（不顿）")
	chk(not HitStop.hit_throttled(0.02, 0.5), "连点第三次同样被吃掉")
	OS.delay_msec(200)
	chk(HitStop.hit_throttled(0.02, 0.5), "隔了 200ms 又能顿了（节流窗口 120ms）")

	# 重击不节流：哪怕刚顿过也照顿
	HitStop.reset()
	chk(HitStop.hit_throttled(0.02, 0.5), "先来一次轻顿")
	HitStop.hit(0.045, 0.08)
	chk(Engine.time_scale < 1.0, "重击不被节流：time_scale 立刻被压下去")

	# 恢复：tick() 到点后必须还回 1.0，否则整个游戏永久慢放
	HitStop.reset()
	chk(absf(Engine.time_scale - 1.0) < 0.001, "reset 后 time_scale 回到 1.0")
	HitStop.hit(0.03, 0.05)
	chk(Engine.time_scale < 1.0, "顿帧中 time_scale 被压低")
	OS.delay_msec(60)
	HitStop.tick()
	chk(absf(Engine.time_scale - 1.0) < 0.001, "到点后 tick() 把 time_scale 还回 1.0")

	# 定帧时长封顶：单次请求 1 秒也不该把游戏冻住
	HitStop.reset()
	HitStop.hit(1.0, 0.05)
	OS.delay_msec(160)
	HitStop.tick()
	chk(absf(Engine.time_scale - 1.0) < 0.001, "单次长请求被封顶（不会冻住游戏）")
	return {"pass": _p, "fail": _f, "failures": _failures}
