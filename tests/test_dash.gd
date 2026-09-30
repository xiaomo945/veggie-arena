extends RefCounted

# 冲刺闪避测试：冷却门控、方向、无敌时长、速度倍率、冷却进度。
#
# 冲刺是"自动开火 + 手动走位"玩法里唯一的主动技巧，配平错一点手感就垮：
#   - 冷却太短 → 一直冲，走位失去意义
#   - 冲刺太长 → 冲进怪堆送死
#   - 无敌太短 → 冲出去照样挨打，等于没用

const Dash := preload("res://core/Dash.gd")

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
	var raw: Dictionary = {}
	if data != null and data.balance.has("dash"):
		raw = data.balance["dash"] as Dictionary
	var c := Dash.cfg(raw)
	var cd := float(c["cooldown"])
	var dur := float(c["duration"])
	var mult := float(c["speed_mult"])
	var ifr := float(c["ifr"])

	# 1) 配表存在且合理
	chk(not raw.is_empty(), "balance.json 存在 dash 配置段")
	chk(cd > 0.0 and dur > 0.0, "冷却 %.1fs / 持续 %.2fs 均为正" % [cd, dur])
	chk(ifr >= dur, "无敌 %.2fs 不短于冲刺本身 %.2fs（冲出去不会立刻挨打）" % [ifr, dur])
	chk(mult > 1.5, "冲刺速度倍率 %.1f 明显快于常速（有爆发感）" % mult)

	# 2) 开局可用
	var s := Dash.make()
	chk(Dash.can_start(s, c), "开局冲刺可用")
	chk(not Dash.active(s), "开局不在冲刺中")

	# 3) 触发后进入冲刺 + 冷却
	var ok := Dash.start(s, Vector2(1, 0), c)
	chk(ok, "可以触发冲刺")
	chk(Dash.active(s), "触发后处于冲刺状态")
	chk(not Dash.can_start(s, c), "冲刺中不能再次触发")
	chk(absf((s["dir"] as Vector2).x - 1.0) < 0.001, "冲刺方向被归一化保存")
	chk(absf(float(s["cd"]) - cd) < 0.001, "触发后进入 %.1fs 冷却" % cd)
	chk(absf(Dash.ifr_left(s, c) - ifr) < 0.001, "触发后获得 %.2fs 无敌" % ifr)

	# 4) 零向量不能冲刺（没方向就没法冲）
	var s2 := Dash.make()
	chk(not Dash.start(s2, Vector2.ZERO, c), "零方向无法触发冲刺")
	chk(not Dash.active(s2), "零方向触发后仍在非冲刺状态")

	# 5) 冷却中不触发
	var s3 := Dash.make()
	Dash.start(s3, Vector2(0, 1), c)
	var ended := false
	for _i in 60:   # 跑 1 秒，冲刺早结束但冷却未满
		if Dash.step(s3, 1.0 / 60.0):
			ended = true
	chk(ended, "冲刺在 %.2fs 后结束" % dur)
	chk(not Dash.active(s3), "冲刺结束后不再是冲刺状态")
	chk(not Dash.can_start(s3, c), "冷却未满时不能再次冲刺")
	chk(not Dash.start(s3, Vector2(1, 0), c), "冷却中触发返回 false")

	# 6) 冷却走完后恢复可用
	var s4 := Dash.make()
	Dash.start(s4, Vector2(1, 0), c)
	var steps := 0
	while not Dash.can_start(s4, c) and steps < 600:
		Dash.step(s4, 1.0 / 60.0)
		steps += 1
	chk(Dash.can_start(s4, c), "%.1fs 冷却走完后恢复可用（%d 帧）" % [cd, steps])
	chk(absf(Dash.cooldown_ratio(s4, c) - 1.0) < 0.001, "冷却完成后进度 = 1.0")
	# 冷却时长不能显著偏离配表
	var secs := float(steps) / 60.0
	chk(absf(secs - cd) < 0.15, "实测冷却 %.2fs 与配表 %.1fs 一致" % [secs, cd])

	# 7) 速度倍率
	var s5 := Dash.make()
	var base := 200.0
	chk(absf(Dash.speed(s5, base, c) - base) < 0.001, "非冲刺时速度 = 基础速度")
	Dash.start(s5, Vector2(1, 0), c)
	chk(absf(Dash.speed(s5, base, c) - base * mult) < 0.001,
		"冲刺时速度 = 基础 × %.1f" % mult)

	# 8) 无敌覆盖：冲刺结束后仍有一段无敌（比冲刺长）
	var s6 := Dash.make()
	Dash.start(s6, Vector2(1, 0), c)
	var guard := 0
	while Dash.active(s6) and guard < 300:
		Dash.step(s6, 1.0 / 60.0)
		guard += 1
	chk(not Dash.active(s6), "冲刺已结束")
	chk(Dash.ifr_left(s6, c) > 0.0, "冲刺结束后仍有 %.2fs 无敌缓冲" % Dash.ifr_left(s6, c))
	# 再走一会儿无敌归零
	for _j in 60:
		Dash.step(s6, 1.0 / 60.0)
	chk(absf(Dash.ifr_left(s6, c)) < 0.001, "无敌最终归零（不会永久无敌）")

	# 9) 冷却进度用于 HUD 扇形：单调不回头
	var s7 := Dash.make()
	Dash.start(s7, Vector2(1, 0), c)
	var last := -1.0
	var monotone := true
	for _k in 120:
		Dash.step(s7, 1.0 / 60.0)
		var r := Dash.cooldown_ratio(s7, c)
		if r < last - 0.0001:
			monotone = false
			break
		last = r
	chk(monotone, "冷却进度单调上升（HUD 扇形不会倒着转）")
	chk(last <= 1.0 and last >= 0.0, "冷却进度始终在 0..1")

	# 10) 冲刺距离配平：不能太短（没手感）也不能太长（冲进怪堆送死）
	var dist := Dash.distance(240.0, c)
	chk(dist > 60.0, "冲刺距离 %.0fpx 够远（有位移感）" % dist)
	chk(dist < 180.0, "冲刺距离 %.0fpx 不至于冲太远（可控）" % dist)

	return {"pass": _p, "fail": _f, "failures": _failures}
