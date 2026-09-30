extends RefCounted

# 手柄模块测试：
# 1) stick_vector 死区/归一化几何逻辑（headless 没手柄，测纯函数最稳）
# 2) Gamepad.gd 接线的契约：必须 emit 移动信号与冲刺信号（删了接线会挂）

var _p := 0
var _f := 0
var _failures: Array = []

const Stick := preload("res://core/StickInput.gd")

func chk(cond: bool, msg: String) -> bool:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)
	return cond

func run(_arg = null) -> Dictionary:
	# 纯逻辑在 core/StickInput.gd（无 autoload 依赖，可在 --script 模式编译）
	# 死区内 → ZERO（含边界）
	chk(Stick.stick_vector(0.0, 0.0, 0.22) == Vector2.ZERO, "零向量 → ZERO")
	chk(Stick.stick_vector(0.1, 0.0, 0.22) == Vector2.ZERO, "死区内(0.1) → ZERO")
	chk(Stick.stick_vector(0.22, 0.0, 0.22) == Vector2.ZERO, "边界(0.22=dead) → ZERO")

	# 死区外 → 保留模拟量大小（limit_length 是钳制不是归一化：
	# 推一半走一半速，这才是手柄该有的手感；满推才到 1.0）
	chk(Stick.stick_vector(1.0, 0.0, 0.22).is_equal_approx(Vector2(1.0, 0.0)), "右满 → (1,0)")
	chk(Stick.stick_vector(0.23, 0.0, 0.22).is_equal_approx(Vector2(0.23, 0.0)), "刚过死区(0.23) → 原样(0.23,0)")
	var d := Stick.stick_vector(0.3, 0.4, 0.22)
	chk(d.is_equal_approx(Vector2(0.3, 0.4)), "斜向(0.3,0.4) → 原样")
	var dl := Stick.stick_vector(-0.5, -0.5, 0.22)
	chk(dl.length() <= 1.0001, "长度不超 1（实测 %.3f）" % dl.length())

	# 接线契约：移动 + 冲刺两个信号都接了
	var src := FileAccess.get_file_as_string("res://autoload/Gamepad.gd")
	chk(src.contains("Events.stick_dir_changed.emit"), "Gamepad 发射移动信号")
	chk(src.contains("Events.dash_requested.emit"), "Gamepad 发射冲刺信号")
	chk(src.contains("JOY_AXIS_LEFT_X") and src.contains("JOY_AXIS_LEFT_Y"), "Gamepad 读左摇杆轴")
	chk(src.contains("JOY_BUTTON_A") or src.contains("JOY_BUTTON_X"), "Gamepad 绑定冲刺按键")

	return {"pass": _p, "fail": _f, "failures": _failures}
