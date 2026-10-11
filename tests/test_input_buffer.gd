extends RefCounted

# 输入缓冲（core/InputBuffer.gd）："跟不跟手"的分水岭，必须锁死行为。

const Buf := preload("res://core/InputBuffer.gd")

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

func run(_data = null) -> Dictionary:
	var b: Dictionary = {}
	# 1) 按下 → 窗口内有效
	Buf.arm(b, "dash")
	chk(Buf.pending(b, "dash"), "按下后窗口内是待发状态")

	# 2) 消费后不再重复触发（否则一次按下会连冲两段）
	Buf.consume(b, "dash")
	chk(not Buf.pending(b, "dash"), "补发后消费掉，不会重复触发")

	# 3) 窗口走完就丢弃：过期的输入不该在几秒后突然自己放出来
	var b2: Dictionary = {}
	Buf.arm(b2, "frost")
	Buf.tick(b2, 0.10)
	chk(Buf.pending(b2, "frost"), "0.10s 后仍在窗口内（窗口 %.2fs）" % Buf.WINDOW)
	Buf.tick(b2, 0.10)
	chk(not Buf.pending(b2, "frost"), "超过窗口就丢弃，绝不延迟补发")

	# 4) 重复按下刷新窗口，但不叠加（不能变成 0.3s 的超长窗口）
	var b3: Dictionary = {}
	Buf.arm(b3, "dash")
	Buf.tick(b3, 0.10)
	Buf.arm(b3, "dash")
	Buf.tick(b3, 0.10)
	chk(Buf.pending(b3, "dash"), "重复按下刷新窗口（仍在窗口内）")
	Buf.tick(b3, 0.10)
	chk(not Buf.pending(b3, "dash"), "刷新而非叠加：再走 0.10s 就过期")

	# 5) 多个 key 互不干扰（冲刺缓冲不会把技能也放出去）
	var b4: Dictionary = {}
	Buf.arm(b4, "dash")
	Buf.arm(b4, "frost")
	Buf.consume(b4, "dash")
	chk(not Buf.pending(b4, "dash") and Buf.pending(b4, "frost"),
		"冲刺与技能的缓冲各自独立")

	# 6) 没按过就不该有
	var b5: Dictionary = {}
	chk(not Buf.pending(b5, "dash"), "没按过就是没有（不会凭空触发）")

	# 7) 窗口长度必须是"覆盖提前量但不失控"的量级
	chk(Buf.WINDOW >= 0.10 and Buf.WINDOW <= 0.20,
		"窗口 %.2fs 落在 0.10~0.20s（超 0.2s 就变成玩家觉得失控）" % Buf.WINDOW)

	return {"pass": _p, "fail": _f, "failures": _failures}
