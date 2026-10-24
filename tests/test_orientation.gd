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

	# ---- 首屏体检（2026-10-24，按"评审第一次打开"的视角钉死）----
	# 三件事曾经都是坏的：标题页内容超过 900 高把 START 挤出屏（横屏只剩半截）、
	# 新玩家进局没有任何操作提示、标题页底部摊着三行 build 阶梯（与角色详情页重复）。
	_check_first_impression()

	return {"pass": _p, "fail": _f, "failures": _failures}

func _check_first_impression() -> void:
	const SrcParse := preload("res://tests/SrcParse.gd")
	var hint := SrcParse.read("res://ui/HUD/HintLine.gd")
	chk(hint.length() > 0, "开局提示脚本存在")
	chk(hint.contains("MOUSE_FILTER_IGNORE"), "开局提示不挡点击（mouse_filter=IGNORE）")
	chk(hint.contains("run_started"), "开局提示在 run_started 时亮（不是一进游戏就常驻）")
	chk(hint.contains("is_touchscreen_available"), "提示文案按设备分（手机说摇杆、桌面说 WASD）")
	chk(hint.contains("set_anchors_and_offsets_preset"),
		"提示铺满视口宽（只设 anchors 会停在文字宽，居中失效、左半截被裁）")
	chk(hint.contains("0.30 if ScreenMode.is_widescreen() else 0.20"),
		"提示位置竖 20% / 横 30%（避开连击按钮与顶部第二行）")
	var hud := SrcParse.read("res://ui/HUD/HUD.gd")
	chk(hud.contains("HintLineScript.new()"), "HUD 真的挂上了开局提示")
	var ts := SrcParse.read("res://ui/Screens/TitleScreen.gd")
	chk(ts.contains("_scale_text()") and ts.contains("title_scale"),
		"标题页底部报内容量（19 位蔬菜 / 40 把武器）")
	chk(not ts.contains("CharTiers.full("),
		"标题页不再重复 build 阶梯（阶梯在角色详情页，省出的高度留给 START）")
	chk(ts.contains("offset_bottom = -28.0"),
		"标题页留底部安全区（-8 时 START 底边压在手势条/窗口边，真机横屏被裁）")
