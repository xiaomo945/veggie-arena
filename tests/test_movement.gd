extends RefCounted

# 手感测试：把"跟不跟手"变成可断言的数字。
# 依据：HTML 原型实测变向 83ms（固定原点摇杆）→ 33ms（浮点摇杆 + 死区 3）。
# 人类对操作延迟的感知阈值约 80ms，本项目红线定在 50ms。

const Movement := preload("res://core/Movement.gd")

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

func run(data) -> Dictionary:
	var feel: Dictionary = Movement.feel(data.feel_cfg())
	var radius: float = feel["radius"]
	var dz: float = feel["deadzone"]
	var kf: float = feel["k_forward"]
	var kr: float = feel["k_reverse"]
	var spd := float(data.player_cfg().get("speed", 180))
	var fps := 60.0
	var frame_ms := 1000.0 / fps

	# 1) 死区：手抖不该产生移动
	chk(Movement.stick_direction(1.0, 1.0, dz) == Vector2.ZERO,
		"死区内不产生方向（%.0fpx 抖动被过滤）" % dz)

	# 2) 死区不能太大，否则"推了不动"
	chk(dz <= 5.0, "死区 %.0fpx ≤ 5px（实测原型用 3）" % dz)

	# 3) 死区外必须是单位向量（不能因为推得远就更快）
	var d1 := Movement.stick_direction(30.0, 0.0, dz)
	var d2 := Movement.stick_direction(300.0, 0.0, dz)
	chk(abs(d1.length() - 1.0) < 0.001 and abs(d2.length() - 1.0) < 0.001
		and abs(d1.x - d2.x) < 0.001,
		"方向已归一化：轻推与重推方向一致、速度相同")

	# 4) 浮点摇杆：手指在半径内时原点不动
	var o1 := Movement.follow_origin(100.0, 100.0, 130.0, 120.0, radius)
	chk(abs(o1.x - 100.0) < 0.001 and abs(o1.y - 100.0) < 0.001,
		"手指在摇杆内：原点保持不动")

	# 5) 浮点摇杆：手指推出边界后原点被拖走，偏移始终 = radius
	var o2 := Movement.follow_origin(100.0, 100.0, 400.0, 100.0, radius)
	var off2 := sqrt(pow(400.0 - o2.x, 2) + pow(100.0 - o2.y, 2))
	chk(abs(off2 - radius) < 0.001,
		"手指推出边界：原点跟随，偏移锁定在 %.0fpx（实测 %.1f）" % [radius, off2])

	# 6) 关键：原点跟随意味着"变向不需要回中"——任意角度切换都是满舵
	var o3 := Movement.follow_origin(100.0, 100.0, 100.0, 400.0, radius)
	var off3 := sqrt(pow(100.0 - o3.x, 2) + pow(400.0 - o3.y, 2))
	chk(abs(off3 - radius) < 0.001,
		"反向推行直接满舵，无需手指回中（偏移 %.1f）" % off3)

	# 7) 静止起步响应
	var f_start := Movement.frames_to_percent(kf, 0.9, fps, false)
	var ms_start := float(f_start) * frame_ms
	chk(ms_start < 50.0, "静止→90%%速度：%d 帧 = %.0fms < 50ms" % [f_start, ms_start])

	# 8) 反向急转响应（最苛刻）
	var f_rev := Movement.frames_to_percent(kr, 0.9, fps, true)
	var ms_rev := float(f_rev) * frame_ms
	chk(ms_rev < 50.0, "反向→90%%速度：%d 帧 = %.0fms < 50ms" % [f_rev, ms_rev])

	# 9) 急转不能比顺向慢
	chk(ms_rev <= ms_start + frame_ms,
		"急转不慢于起步（%.0fms vs %.0fms）" % [ms_rev, ms_start])

	# 10) 30fps 弱机也不能失控
	var f30 := Movement.frames_to_percent(kr, 0.9, 30.0, true)
	chk(float(f30) * (1000.0 / 30.0) < 100.0,
		"30fps 下急转仍在 %.0fms 内（弱机保底）" % (float(f30) * 1000.0 / 30.0))

	# 11) 120fps 高刷同样达标
	var f120 := Movement.frames_to_percent(kr, 0.9, 120.0, true)
	chk(float(f120) * (1000.0 / 120.0) < 40.0,
		"120fps 下急转 %.1fms（高刷更跟手）" % (float(f120) * 1000.0 / 120.0))

	# 12) 速度不会超过上限（插值不 overshoot）
	var vx := 0.0
	var vy := 0.0
	var peak := 0.0
	for i in range(120):
		var nv := Movement.step(vx, vy, 1.0, 0.0, spd, 1.0 / fps, kf, kr)
		vx = nv.x
		vy = nv.y
		peak = maxf(peak, Movement.speed_of(vx, vy))
	chk(peak <= spd + 0.01, "速度上限 %.0f，插值无过冲（峰值 %.1f）" % [spd, peak])

	# 13) 松手后要能停下来（不能滑行）
	var rv := Vector2(vx, vy)
	var decel_frames := 0
	for i in range(120):
		var nv := Movement.step(rv.x, rv.y, 0.0, 0.0, spd, 1.0 / fps, kf, kr)
		rv = nv
		decel_frames += 1
		if Movement.speed_of(rv.x, rv.y) < spd * 0.05:
			break
	chk(float(decel_frames) * frame_ms < 80.0,
		"松手 %.0fms 内基本停住（%d 帧）" % [float(decel_frames) * frame_ms, decel_frames])

	# 14) 竞技场边界：不能跑出去
	var arena := Rect2(12, 74, 516, 756)
	var c1 := Movement.clamp_to_arena(Vector2(-500.0, -500.0), arena, 16.0)
	chk(c1.x >= arena.position.x + 15.9 and c1.y >= arena.position.y + 15.9,
		"左上角被夹住：%.0f,%.0f" % [c1.x, c1.y])
	var c2 := Movement.clamp_to_arena(Vector2(9999.0, 9999.0), arena, 16.0)
	chk(c2.x <= arena.position.x + arena.size.x - 15.9
		and c2.y <= arena.position.y + arena.size.y - 15.9,
		"右下角被夹住：%.0f,%.0f" % [c2.x, c2.y])

	# 15) 摇杆半径适合拇指（太小难控，太大挡视野）
	chk(radius >= 40.0 and radius <= 80.0,
		"摇杆半径 %.0fpx 在 40~80 的拇指舒适区" % radius)

	# 16) 反向加速常数不小于顺向，否则急转发黏
	chk(kr >= kf, "急转常数 %.0f ≥ 顺向 %.0f" % [kr, kf])

	print("  ---- 手感实测（60fps，1 帧 = %.1fms）----" % frame_ms)
	print("    静止起步 : %d 帧 / %.0f ms" % [f_start, ms_start])
	print("    反向急转 : %d 帧 / %.0f ms" % [f_rev, ms_rev])
	print("    松手停住 : %d 帧 / %.0f ms" % [decel_frames, float(decel_frames) * frame_ms])

	return {"pass": _p, "fail": _f, "failures": _failures}
