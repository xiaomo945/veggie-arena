extends RefCounted

# 顶部 HUD 布局守卫：把"控件互相遮挡"这类目检才能发现的 bug 变成硬断言。
#
# 真实 bug（用户报："第3格第4格第5格的武器显示不了"）：
#   武器槽 WeaponBar 原本画在 y=30，而暂停按钮占 y=16~64 / x=484~532，
#   两者整块重叠。5 把武器时第 4、5 格被暂停按钮盖死，玩家只看到 3 把。
#   根因是 WeaponBar.gd 里有个 SLOT_Y=30 的常量没被用上，实际坐标硬编码在 _draw() 里。
#
# 这个文件的价值：布局回归肉眼难发现（挪一个数字可能刚好挪进另一个控件），
# 所以把"HUD 各控件的矩形不能相交"钉死在这里，谁挪谁红。
#
# 为什么读源码而不 preload ui/HUD/HudLayout.gd：
#   HudLayout 用的是 autoload 标识符 Data（编译期注入），--script 单测环境没有 autoload，
#   preload 它会直接 Compile Error。项目里 test_bgm.gd / test_gamepad.gd 已有同样的
#   "读源码做断言"模式（FileAccess.get_file_as_string），这里沿用。
#   读源码还能顺带防住"改了布局表但忘了同步到用它的节点"这类漂移。

# ---- 另一处定义的常量（ui/HUD/HudBars.gd 的血条/锅气条/经验条）。
#      HudBars 是 Node2D，_draw() 里坐标全是字面量，同样没法在单测里实例化。
const BAR_Y := 8.0
const BAR_H := 14.0
const WOK_Y := 24.0
const WOK_H := 16.0
const XP_Y := 44.0
const XP_H := 6.0
const LABEL_ROW_TOP := 62.0     # GOLD / KILLS / COMBO 文字行顶部
const LABEL_ROW_H := 14.0

# 与 ui/HUD/WeaponBar.gd 保持一致的槽位尺寸
const SLOT_SIZE := 32.0
const SLOT_GAP := 6.0
const PAUSE_SIZE := 48.0
const BAR_X := 40.0
const WOK_X := 40.0
const XP_X := 40.0
const PORTRAIT_W := 540.0
const LANDSCAPE_W := 960.0

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
	var max_slots := int(data.shop_cfg().get("max_slot", 6))

	# 读生产代码的真实坐标（而不是在这里抄一份常量）
	var layout_src := FileAccess.get_file_as_string("res://ui/HUD/HudLayout.gd")
	chk(layout_src.length() > 0, "能读到 HudLayout.gd 源码（路径写错会导致假通过，实际 %d 字符）"
		% layout_src.length())
	var slot_y := _extract_return(layout_src, "func slot_y()")
	var slot_right_portrait := _extract_ternary_portrait(layout_src, "func slot_right()")
	var pause_x_portrait := PORTRAIT_W - 56.0
	chk(slot_y >= 0.0, "HudLayout.slot_y() 能解析出数值（%.0f）" % slot_y)
	chk(slot_right_portrait >= 0.0, "HudLayout.slot_right() 能解析出竖屏值（%.0f）"
		% slot_right_portrait)

	if slot_y < 0.0 or slot_right_portrait < 0.0:
		return {"pass": _p, "fail": _f, "failures": _failures}

	# WeaponBar 必须真的用 HudLayout 的值（防"布局表改了但节点没跟上"的漂移）
	var wb_src := FileAccess.get_file_as_string("res://ui/HUD/WeaponBar.gd")
	chk(wb_src.length() > 0, "能读到 WeaponBar.gd 源码（实际 %d 字符）" % wb_src.length())
	chk("HudLayout.slot_y()" in wb_src and "HudLayout.slot_right()" in wb_src,
		"WeaponBar 的 Y 与右边界都取自 HudLayout（没写死自己的坐标）")
	# 本 bug 的根因就是"定义了 SLOT_Y 却没在绘制处用"，所以钉死"绘制路径必须用 SLOT_Y 变量"
	var draw_body := _func_body(wb_src, "func _draw()")
	chk(draw_body.find("SLOT_Y") >= 0,
		"WeaponBar 的绘制函数用 SLOT_Y 变量，而不是又写死一个 Y 数字"
		+ ("（本次 bug 的根因就是这个）" if draw_body.find("SLOT_Y") < 0 else ""))

	for landscape in [false, true]:
		_check_layout(landscape, max_slots, slot_y, slot_right_portrait,
			pause_x_portrait)

	# 满槽时最左槽不能画出屏幕（竖屏更窄，先保竖屏）
	var left := slot_right_portrait - _slots_width(max_slots)
	chk(left >= 4.0,
		"竖屏满 %d 槽（总宽 %.0f）最左槽 x=%.0f ≥4，不画到屏幕外"
		% [max_slots, _slots_width(max_slots), left])

	return {"pass": _p, "fail": _f, "failures": _failures}

func _check_layout(landscape: bool, max_slots: int, slot_y: float,
		slot_right_portrait: float, pause_x_portrait: float) -> void:
	var tag := "横屏" if landscape else "竖屏"
	var sw := LANDSCAPE_W if landscape else PORTRAIT_W
	var slot_right := (sw - 12.0) if landscape else slot_right_portrait
	var pause_x := (sw - 56.0) if landscape else pause_x_portrait
	var bar_w := (sw - 40.0) if landscape else 486.0
	var pause_r := Rect2(Vector2(pause_x, 16.0), Vector2(PAUSE_SIZE, PAUSE_SIZE))
	var row := _slot_row_rect(max_slots, slot_y, slot_right)

	# ---- 1) 武器槽 vs 暂停按钮（本 bug 的正主）----
	# 槽数越多越往左伸，右端固定，所以撞的总是最右那几格。逐格查，撞了就报是第几格。
	var hit_slot := -1
	for n in range(1, max_slots + 1):
		var x0 := slot_right - _slots_width(n)
		for i in n:
			if _slot_rect(x0, i, slot_y).intersects(pause_r):
				hit_slot = i + 1
	chk(hit_slot < 0,
		"%s：%d 个武器槽（y=%.0f~%.0f）与暂停按钮 %s 完全不相交（撞上的最右格：第 %d）"
		% [tag, max_slots, slot_y, slot_y + SLOT_SIZE, str(pause_r), hit_slot])

	# ---- 2) 武器槽行 vs 经验条（经验条横跨几乎整个屏宽，最容易横穿武器图标）----
	var xp_r := Rect2(Vector2(XP_X, XP_Y), Vector2(bar_w, XP_H))
	chk(not row.intersects(xp_r),
		"%s：武器槽行 y=%.0f~%.0f 不与经验条 y=%.0f~%.0f 相交"
		% [tag, slot_y, slot_y + SLOT_SIZE, XP_Y, XP_Y + XP_H])

	# ---- 3) 武器槽行 vs 锅气条 ----
	var wok_r := Rect2(Vector2(WOK_X, WOK_Y), Vector2(bar_w, WOK_H))
	chk(not row.intersects(wok_r),
		"%s：武器槽行不与锅气条 y=%.0f~%.0f 相交" % [tag, WOK_Y, WOK_Y + WOK_H])

	# ---- 4) 武器槽行 vs 血条 ----
	var bar_r := Rect2(Vector2(BAR_X, BAR_Y), Vector2(bar_w, BAR_H))
	chk(not row.intersects(bar_r),
		"%s：武器槽行不与血条 y=%.0f~%.0f 相交" % [tag, BAR_Y, BAR_Y + BAR_H])

	# ---- 5) 武器槽行 vs GOLD/KILLS/COMBO 文字行 ----
	# COMBO 标签 x=300 起（竖屏），满槽时最左槽 x=306，确实会撞 ——
	# 所以要求整行压在文字行之下，而不是只算最右那一格。
	var label_r := Rect2(Vector2(0.0, LABEL_ROW_TOP), Vector2(sw, LABEL_ROW_H))
	chk(not row.intersects(label_r),
		"%s：武器槽行 y=%.0f~%.0f 不与文字行 y=%.0f~%.0f 相交"
		% [tag, slot_y, slot_y + SLOT_SIZE, LABEL_ROW_TOP, LABEL_ROW_TOP + LABEL_ROW_H])

# 取出某个函数从签名到下一个顶层 func 之间的源码（缩进法：找到下一个顶格 func）
func _func_body(src: String, func_sig: String) -> String:
	var idx := src.find(func_sig)
	if idx < 0:
		return ""
	var next_top := src.find("\nfunc ", idx + func_sig.length())
	if next_top < 0:
		return src.substr(idx)
	return src.substr(idx, next_top - idx)

# ---- 源码解析小工具（只认 "return <数字>" 这种最简形式，够用且不会误匹配）----
func _extract_return(src: String, func_sig: String) -> float:
	var idx := src.find(func_sig)
	if idx < 0:
		return -1.0
	var end := src.find("\n", idx)
	if end < 0:
		return -1.0
	var line := src.substr(idx, end - idx)
	var r := line.find("return ")
	if r < 0:
		return -1.0
	return _to_float(line.substr(r + 7))

# 取 "X if Data.is_landscape() else Y" 里的 Y（竖屏分支，与 HudLayout 的写法一致）。
# 写法比想象中更笨（找 else 之后第一个数字），但 HudLayout 是本项目自己的代码，
# 格式统一；真解析不动了就该改产品代码而不是把测试写成正则地狱。
func _extract_ternary_portrait(src: String, func_sig: String) -> float:
	var idx := src.find(func_sig)
	if idx < 0:
		return -1.0
	var end := src.find("\n", idx)
	if end < 0:
		return -1.0
	var line := src.substr(idx, end - idx)
	var els := line.find(" else ")
	if els < 0:
		return -1.0
	return _to_float(line.substr(els + 6))

func _to_float(s: String) -> float:
	var out := ""
	for i in s.length():
		var ch := s[i]
		if (ch >= "0" and ch <= "9") or ch == ".":
			out += ch
		elif out != "":
			break
	return float(out) if out != "" else -1.0

func _slots_width(n: int) -> float:
	return float(n) * SLOT_SIZE + float(n - 1) * SLOT_GAP

func _slot_rect(x0: float, i: int, slot_y: float) -> Rect2:
	return Rect2(Vector2(x0 + float(i) * (SLOT_SIZE + SLOT_GAP), slot_y),
		Vector2(SLOT_SIZE, SLOT_SIZE))

func _slot_row_rect(n: int, slot_y: float, slot_right: float) -> Rect2:
	var w := _slots_width(n)
	return Rect2(Vector2(slot_right - w, slot_y), Vector2(w, SLOT_SIZE))
