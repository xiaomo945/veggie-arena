extends RefCounted

# 相机限位测试（纯函数 CamLimits，不依赖场景树/autoload）。
# 要保的两件事：
#   1) 玩家在场地中间时，限位区间必须【包含】玩家位置 —— 否则镜头停跟、玩家跑出屏幕
#      （真机踩过：相机挂在玩家身上时 limit 被当成父节点局部坐标，内缩限位把镜头钉死）。
#   2) 玩家到边缘时，钳制后的相机中心 ± 半视口 必须落在场地内 —— 否则露黑框。
# 另测：视口比场地大时限位不得反转（反转=镜头锁死）。

const CamLimits := preload("res://core/CamLimits.gd")

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

# 钳制后的相机中心 -> 视野矩形是否完全落在场地内
func _view_ok(a: Dictionary, center: Vector2, view: Vector2) -> bool:
	var l := float(a["x"]); var t := float(a["y"])
	var r := l + float(a["w"]); var b := t + float(a["h"])
	return center.x - view.x * 0.5 >= l - 0.5 and center.x + view.x * 0.5 <= r + 0.5 \
		and center.y - view.y * 0.5 >= t - 0.5 and center.y + view.y * 0.5 <= b + 0.5

func _clamped_pt(a: Dictionary, view: Vector2, p: Vector2) -> Vector2:
	var m := CamLimits.limits(a, view)
	return Vector2(clampf(p.x, m["left"], m["right"]), clampf(p.y, m["top"], m["bottom"]))

func run(_data) -> Dictionary:
	# --- 竖屏：视口 540x900，场地 1080x1620（中心 270,450）---
	var a := {"x": -270.0, "y": -360.0, "w": 1080.0, "h": 1620.0}
	var v := Vector2(540.0, 900.0)
	var m := CamLimits.limits(a, v)
	chk(m["left"] == 0.0 and m["right"] == 540.0, "竖屏横向限位 [0,540]（内缩半视口）")
	chk(m["top"] == 90.0 and m["bottom"] == 810.0, "竖屏纵向限位 [90,810]")

	# 场地中心：钳制后原地不动 = 镜头正常跟随
	var c := _clamped_pt(a, v, Vector2(270.0, 450.0))
	chk(c == Vector2(270.0, 450.0), "场地中心玩家不被钳制（镜头跟随）")

	# 左下角：钳到 (0,90)，视野贴住场地左边和下边
	var lb := _clamped_pt(a, v, Vector2(-270.0, -360.0))
	chk(lb == Vector2(0.0, 90.0), "左下角相机中心钳到 (0,90)")
	chk(_view_ok(a, lb, v), "左下角视野不越界（无黑框）")

	# 右上角：钳到 (540,810)，视野贴住场地右边和上边
	var rt := _clamped_pt(a, v, Vector2(810.0, 1260.0))
	chk(rt == Vector2(540.0, 810.0), "右上角相机中心钳到 (540,810)")
	chk(_view_ok(a, rt, v), "右上角视野不越界（无黑框）")

	# --- 视口比场地大：内缩会反转，必须退化为中心而不是留下反转区间 ---
	var big := Vector2(1200.0, 1800.0)
	var mb := CamLimits.limits(a, big)
	chk(mb["left"] == mb["right"] and mb["top"] == mb["bottom"], "视口大于场地时限位退化为中心点")
	chk(mb["left"] == 270.0 and mb["top"] == 450.0, "退化中心=场地中心 (270,450)")

	# --- 横屏：视口 960x540，场地 1620x1080（中心 0,0）---
	var al := {"x": -810.0, "y": -540.0, "w": 1620.0, "h": 1080.0}
	var vl := Vector2(960.0, 540.0)
	var ml := CamLimits.limits(al, vl)
	chk(ml["left"] == -330.0 and ml["right"] == 330.0, "横屏横向限位 [-330,330]")
	chk(ml["top"] == -270.0 and ml["bottom"] == 270.0, "横屏纵向限位 [-270,270]")
	var cl := _clamped_pt(al, vl, Vector2(-810.0, 540.0))
	chk(_view_ok(al, cl, vl), "横屏左下角视野不越界（无黑框）")

	return {"pass": _p, "fail": _f, "failures": _failures}
