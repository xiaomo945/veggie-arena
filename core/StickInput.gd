extends RefCounted

# 纯函数：手柄/摇杆轴量 → 单位方向（带死区）。
# 抽成无 autoload 依赖的独立模块，既能被 Gamepad 复用，也能在单测里直接调用
# （引用 Events 的 Gamepad.gd 在 --script 测试模式下无法编译，所以纯逻辑必须独立）。
# 不写 class_name：--script 模式下 class_name 不会全局注册，反而会 "not declared"；
# 统一用 preload + 静态方法的调用方式（core/Combat.gd 等已验证可行）。

static func stick_vector(ax: float, ay: float, dead: float) -> Vector2:
	var v := Vector2(ax, ay)
	if v.length() <= dead:
		return Vector2.ZERO
	return v.limit_length(1.0)
