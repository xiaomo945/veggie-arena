extends RefCounted

# 右下技能簇布局守卫（几何关系，肉眼在截图里看不出来的那部分）。
#
# 用户三条诉求都在这里算：
#  ① "左下轮盘的中心跟右边攻击按钮同一个中心点" → 攻击键圆心 = 摇杆底盘水平镜像
#     + 底部安全区回补（摇杆不随 HUD 按钮上移，所以必须补 safe_bottom）；
#  ② "123 技能分别环绕在攻击按钮的左边、左上、上（王者荣耀位置）" → 角度必须正好
#     180 / 225 / 270，且顺序即键盘 J/K/L；
#  ③ "现在这几个技能按钮间隔不一样，太难看" → 相邻两个必须 45° 等角距、轴间隙留够，
#     三个环绕键尺寸统一（SkillButton.ADDON_SIZE）。
#
# 为什么读源码而不实例化：--script 测试模式不注册 autoload，HudLayout 引用 Data
# 会直接编译失败（见 tests/SrcParse.gd 文件头）。一律现解析，不抄常量（抄了就会漂，
# test_hud_layout 真踩过：写 XP_Y=47 而产品是 45，测试全绿、线上压字）。

const SP := preload("res://tests/SrcParse.gd")

const LAYOUT_SRC := "res://ui/HUD/HudLayout.gd"
const BUTTONS_SRC := "res://ui/HUD/SkillButton.gd"

# 轴对齐方块之间的最小可视间隙（px）。≥0 只是"不叠"，留一点才不显得粘在一起。
const MIN_GAP := 8.0

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

# 从 "return Vector2(a, b) if Data.is_landscape() else Vector2(c, d)" 里取分支坐标
func _branch_vec(src: String, sig: String, landscape: bool, n: int) -> float:
	var body := SP.func_body(src, sig)
	var line := ""
	for l in body.split("\n"):
		var t := l.strip_edges()
		if t.begins_with("return ") and t.contains("Vector2("):
			line = t
			break
	if line == "":
		return -1.0
	var marker := " if Data.is_landscape() else "
	var cut := line.find(marker)
	var seg := line
	if cut >= 0:
		seg = line.substr(0, cut) if landscape else line.substr(cut + marker.length())
	else:
		var els := line.find(" else ")
		if els >= 0:
			seg = line.substr(0, els) if landscape else line.substr(els + 6)
	var a := seg.find("Vector2(")
	if a < 0:
		return -1.0
	a += "Vector2(".length()
	var b := seg.find(")", a)
	if b < 0:
		return -1.0
	var parts := seg.substr(a, b - a).split(",")
	if n < 0 or n >= parts.size():
		return -1.0
	return float(parts[n].strip_edges())

# 从 addon_slots() 数组里按顺序解析出 [{type, deg}]
func _parse_slots(src: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile('\\{\\s*"type"\\s*:\\s*"([a-z_]+)"\\s*,\\s*"deg"\\s*:\\s*([0-9.]+)\\s*\\}')
	for m in re.search_all(src):
		out.append({"type": m.get_string(1), "deg": float(m.get_string(2))})
	return out

func run(_arg = null) -> Dictionary:
	var layout := SP.read(LAYOUT_SRC)
	var btns := SP.read(BUTTONS_SRC)
	chk(layout.length() > 0, "能读到 HudLayout 源码（路径写错会假通过）")
	chk(btns.length() > 0, "能读到 SkillButton 源码")
	if layout.is_empty() or btns.is_empty():
		return {"pass": _p, "fail": _f, "failures": _failures}

	# ---- 尺寸/安全区常量（现解析，不抄）----
	var addon_half := SP.const_val(btns, "ADDON_SIZE") * 0.5
	var attack_half := SP.const_val(btns, "ATTACK_SIZE") * 0.5
	var dash_half := SP.const_val(btns, "SIZE") * 0.5
	chk(addon_half > 0.0 and attack_half > 0.0 and dash_half > 0.0,
		"三个环绕键统一尺寸 ADDON_SIZE=%.0f（攻击键 %.0f / 冲刺 %.0f）" % [addon_half * 2.0, attack_half * 2.0, dash_half * 2.0])
	var safe_bottom := SP.ret(layout, "func safe_bottom()")
	chk(safe_bottom > 0.0, "底部安全区 safe_bottom=%.0f（攻击键回补值与 HUD 平移同源）" % safe_bottom)

	# ---- 公式必须是"镜像 + 回补"（诉求①，写成别的形状就等于没做）----
	var atk_body := SP.func_body(layout, "func attack_button_center()")
	chk(atk_body.contains("d.x - base.x") and atk_body.contains("base.y + safe_bottom()"),
		"攻击键圆心 = 摇杆底盘水平镜像 + 底部安全区回补（公式本身）")
	chk(SP.func_body(layout, "func addon_arc_r()").length() > 0, "环绕弧半径 addon_arc_r() 存在")
	chk(SP.func_body(layout, "func addon_slots()").length() > 0, "环绕槽位 addon_slots() 存在")

	var slots := _parse_slots(SP.func_body(layout, "func addon_slots()"))
	chk(slots.size() == 3, "环绕技能键正好 3 个（对应 J/K/L，实测 %d）" % slots.size())
	var types: Array = []
	for s in slots:
		types.append(str(s["type"]))
	chk(types == ["skill", "wok", "ff"], "环绕键顺序 = J/K/L = 主动技/锅气/快进（实测 %s）" % str(types))

	# 两种朝向各验一遍（竖屏 540x900 / 横屏 960x540）
	for landscape in [false, true]:
		var tag := "横屏" if landscape else "竖屏"
		var d := Vector2(
			_branch_vec(layout, "func design_size()", landscape, 0),
			_branch_vec(layout, "func design_size()", landscape, 1))
		var joy := Vector2(
			_branch_vec(layout, "func joy_fixed_base()", landscape, 0),
			_branch_vec(layout, "func joy_fixed_base()", landscape, 1))
		var arc_r := SP.ternary_l(layout, "func addon_arc_r()") if landscape \
			else SP.ternary_p(layout, "func addon_arc_r()")
		var zone_w := SP.ternary_l(layout, "func joy_move_zone_w()") if landscape \
			else SP.ternary_p(layout, "func joy_move_zone_w()")
		chk(d.x > 100.0 and d.y > 100.0 and joy.x > 0.0 and arc_r > 100.0,
			"%s 解析到设计尺寸 %.0fx%.0f / 摇杆底盘 (%.0f,%.0f) / 弧半径 %.0f" % [tag, d.x, d.y, joy.x, joy.y, arc_r])

		# 诉求①：攻击键圆心 = 水平镜像 + 安全区回补
		var atk := Vector2(d.x - joy.x, joy.y + safe_bottom)
		chk(absf(atk.x + joy.x - d.x) < 0.01,
			"%s 攻击键与摇杆底盘水平镜像（%.0f + %.0f = %.0f）" % [tag, atk.x, joy.x, d.x])
		chk(absf(atk.y - joy.y - safe_bottom) < 0.01,
			"%s 攻击键与摇杆底盘同一水平线（差 %.0f = 底部安全区回补）" % [tag, atk.y - joy.y])

		# 环绕键圆心
		var centers: Array = []
		for s in slots:
			var a := deg_to_rad(float(s["deg"]))
			centers.append(atk + Vector2(cos(a), sin(a)) * arc_r)

		# 诉求②：角度正好 左/左上/上
		var degs: Array = []
		for s in slots:
			degs.append(float(s["deg"]))
		chk(degs == [180.0, 225.0, 270.0],
			"%s 角度正好 左(180°)/左上(225°)/上(270°)（实测 %s）" % [tag, str(degs)])

		# 诉求③：相邻 45° 等角距（旧版一个 45° 一个 90° 就是"间隔不一样"的由来）
		var equal := absf((degs[1] as float) - (degs[0] as float) - 45.0) < 0.01 \
			and absf((degs[2] as float) - (degs[1] as float) - 45.0) < 0.01
		chk(equal, "%s 相邻环绕键 45° 等角距（弧长一致，间隔才整齐）" % tag)

		# 轴对齐方块防重叠：每一对的 |dx| 或 |dy| 必须 ≥ 两者半宽之和 + MIN_GAP
		var dash := Vector2(
			_branch_vec(layout, "func buttons_dash_center()", landscape, 0),
			_branch_vec(layout, "func buttons_dash_center()", landscape, 1))
		var boxes := [{"n": "attack", "c": atk, "h": attack_half},
			{"n": "dash", "c": dash, "h": dash_half}]
		for i in centers.size():
			boxes.append({"n": "addon[%d]" % i, "c": centers[i], "h": addon_half})
		var worst := 9999.0
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var b1: Dictionary = boxes[i]
				var b2: Dictionary = boxes[j]
				var dx := absf((b1["c"] as Vector2).x - (b2["c"] as Vector2).x)
				var dy := absf((b1["c"] as Vector2).y - (b2["c"] as Vector2).y)
				var need := float(b1["h"]) + float(b2["h"]) + MIN_GAP
				worst = minf(worst, maxf(dx, dy) - need)
				chk(maxf(dx, dy) >= need,
					"%s %s ↔ %s 轴净距 %.1f ≥ 需 %.1f（余量 %.1f）" % [
						tag, b1["n"], b2["n"], maxf(dx, dy), need, maxf(dx, dy) - need])

		# 全部按钮在屏幕内
		for b in boxes:
			var c: Vector2 = b["c"]
			var h := float(b["h"])
			chk(c.x - h >= 0.0 and c.x + h <= d.x and c.y - h >= 0.0 and c.y + h <= d.y,
				"%s %s 完整在屏内 (%.0f,%.0f)±%.0f vs %.0fx%.0f" % [tag, b["n"], c.x, c.y, h, d.x, d.y])

		# 摇杆 generous 区（x<=zone_w 且 y>=zone_y 的整块矩形）不能盖住最左那个技能键，
		# 否则一根手指会同时被摇杆和技能键认领（Joystick._in_zone + SkillButton._rect 双触发）
		var left_edge := (centers[0] as Vector2).x - addon_half
		chk(left_edge - zone_w >= 4.0,
			"%s 最左技能键左缘 %.0f 不侵入摇杆移动区（右界 %.0f，余量 %.0f）" % [
				tag, left_edge, zone_w, left_edge - zone_w])
		chk(worst > 0.0, "%s 所有按钮对间隙均达标（最紧的一对余量 %.1fpx）" % [tag, worst])

	return {"pass": _p, "fail": _f, "failures": _failures}
