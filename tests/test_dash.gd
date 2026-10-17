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

	# 11) 无参重载 random_dir()：无方向输入时随机冲刺方向，必须非零、单位长、且真的会转
	#     （纯逻辑层面：不设种子连抽 N 次，角度应覆盖不止一个象限）
	var nonzero := true
	var unit := true
	var seen_free: Array[Vector2] = []
	for _m in 64:
		var d := Dash.random_dir()
		if d.length_squared() < 0.0001:
			nonzero = false
		if absf(d.length() - 1.0) > 0.0001:
			unit = false
		if seen_free.size() < 8:
			seen_free.append(d)
	chk(nonzero, "random_dir() 从不返回零向量（零向量 start 会拒）")
	chk(unit, "random_dir() 始终是单位向量（start 里还要再 normalized）")
	var distinct := 0
	for a in seen_free:
		var dup := false
		for b in seen_free:
			if a != b and absf(a.angle_to(b)) < 0.01:
				dup = true
		if not dup:
			distinct += 1
	chk(distinct >= 4, "random_dir() 多次调用方向互不相同（真的随机：%d/8 个不同朝向）" % distinct)
	# 随机方向能直接启动冲刺（玩家无方向按冲刺 = 随机冲一个方向）
	var s8a := Dash.make()
	chk(Dash.start(s8a, Dash.random_dir(), c), "random_dir() 的返回值可直接启动冲刺")

	# 12) 带种子重载 random_dir(rng)：8 离散方向、单位长、可复现（键盘冲刺与模拟器共用口径）
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lens_ok := true
	var quant_ok := true
	var cx := 0.0
	var cy := 0.0
	for _i in 400:
		var v := Dash.random_dir(rng)
		cx += v.x
		cy += v.y
		if absf(v.length() - 1.0) > 0.001:
			lens_ok = false
		if not (_is_eight(absf(v.x)) and _is_eight(absf(v.y))):
			quant_ok = false
	chk(lens_ok, "随机冲刺方向始终单位长（斜向不比直向快/慢）")
	chk(quant_ok, "随机冲刺方向量化到 8 个离散方向（与键盘 WASD 的 8 个方向一致）")

	# 8 个方向都要出现：400 次抽样只出 4 个 = 分布有偏（等概率才叫"随机"）
	var r2 := RandomNumberGenerator.new()
	r2.seed = 2024
	var seen := {}
	for _i in 400:
		var v := Dash.random_dir(r2)
		seen[_dir_key(v)] = true
	chk(seen.size() == 8, "400 次抽样覆盖全部 8 个方向（实测 %d 个）" % seen.size())
	# 方向分布无系统偏向（平均值应接近原点）：每轴均值偏移 < 0.12
	chk(absf(cx / 400.0) < 0.12 and absf(cy / 400.0) < 0.12,
		"随机冲刺方向无系统偏向（均值 %.3f, %.3f）" % [cx / 400.0, cy / 400.0])

	# 同种子可复现（测试/模拟都靠这个；不复现说明 rng 传错了）
	var r3 := RandomNumberGenerator.new(); r3.seed = 99
	var r4 := RandomNumberGenerator.new(); r4.seed = 99
	var repro := true
	for _i in 50:
		if Dash.random_dir(r3) != Dash.random_dir(r4):
			repro = false
	chk(repro, "同种子随机冲刺方向可复现")

	# 13) Player 侧：随机方向必须真能起冲刺（零向量会被 Dash.start 拒绝，接错线就永远冲不出去）
	var s8 := Dash.make()
	chk(Dash.start(s8, Dash.random_dir(rng), c), "随机方向可以触发冲刺")

	return {"pass": _p, "fail": _f, "failures": _failures}

# 方向的离散化键（用于统计覆盖面，避免浮点比较）
func _dir_key(v: Vector2) -> String:
	return "%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0)]

# 8 离散方向判定：分量只能是 0 / ±1 / ±0.7071（45° 的 cos/sin）
func _is_eight(a: float) -> bool:
	return a < 0.001 or absf(a - 1.0) < 0.001 or absf(a - 0.7071) < 0.001
