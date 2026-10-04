extends RefCounted

# 横屏双布局测试：校验 Data.arena() 在竖屏 / 横屏下返回正确的竞技场尺寸与中心。
# 竖屏默认 1080x1620（中心 270,450）；横屏 1620x1080（居中原点 0,0）。
# 不依赖 Data 单例（--script 模式下 autoload 不注册），直接用传入的 data 实例。

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
	# 竖屏：默认竞技场（零改动基线）
	data.set_landscape(false)
	var a: Dictionary = data.arena()
	chk(not data.is_landscape(), "竖屏标志为 false")
	chk(float(a.get("w")) == 1080.0 and float(a.get("h")) == 1620.0, "竖屏竞技场 1080x1620")
	var cx := float(a.get("x")) + float(a.get("w")) * 0.5
	var cy := float(a.get("y")) + float(a.get("h")) * 0.5
	chk(cx == 270.0 and cy == 450.0, "竖屏竞技场中心 (270,450)")

	# 横屏：放大竞技场（docs/07 §5.6）
	data.set_landscape(true)
	var l: Dictionary = data.arena()
	chk(data.is_landscape(), "横屏标志为 true")
	chk(float(l.get("w")) == 1620.0 and float(l.get("h")) == 1080.0, "横屏竞技场 1620x1080")
	var lx := float(l.get("x")) + float(l.get("w")) * 0.5
	var ly := float(l.get("y")) + float(l.get("h")) * 0.5
	chk(lx == 0.0 and ly == 0.0, "横屏竞技场居中原点 (0,0)")

	# 复位，避免污染后续测试
	data.set_landscape(false)

	return {"pass": _p, "fail": _f, "failures": _failures}
