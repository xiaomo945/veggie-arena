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

# 钳制后的相机中心 -> 视野矩形超出场地的宽度不超过 margin（围栏要能露出来，但不能露大片黑区）
func _view_ok(a: Dictionary, center: Vector2, view: Vector2, margin: float) -> bool:
	var l := float(a["x"]); var t := float(a["y"])
	var r := l + float(a["w"]); var b := t + float(a["h"])
	return center.x - view.x * 0.5 >= l - margin - 0.5 and center.x + view.x * 0.5 <= r + margin + 0.5 \
		and center.y - view.y * 0.5 >= t - margin - 0.5 and center.y + view.y * 0.5 <= b + margin + 0.5

func _clamped_pt(a: Dictionary, view: Vector2, p: Vector2, margin: float = 0.0) -> Vector2:
	var m := CamLimits.limits(a, view, margin)
	return Vector2(clampf(p.x, m["left"], m["right"]), clampf(p.y, m["top"], m["bottom"]))

func run(_data) -> Dictionary:
	# --- 竖屏：视口 540x900，场地 1080x1620（中心 270,450）---
	var a := {"x": -270.0, "y": -360.0, "w": 1080.0, "h": 1620.0}
	var v := Vector2(540.0, 900.0)
	var mg := 24.0
	var m := CamLimits.limits(a, v, mg)
	chk(m["left"] == -24.0 and m["right"] == 564.0, "竖屏横向限位 [-24,564]（内缩半视口 + 露围栏 24）")
	chk(m["top"] == 66.0 and m["bottom"] == 834.0, "竖屏纵向限位 [66,834]")
	# margin=0 时必须严格贴边（围栏露出功能可关）
	var m0 := CamLimits.limits(a, v)
	chk(m0["left"] == 0.0 and m0["right"] == 540.0 and m0["top"] == 90.0 and m0["bottom"] == 810.0,
		"margin=0 时严格贴边 [0,540]x[90,810]")

	# 场地中心：钳制后原地不动 = 镜头正常跟随
	var c := _clamped_pt(a, v, Vector2(270.0, 450.0), mg)
	chk(c == Vector2(270.0, 450.0), "场地中心玩家不被钳制（镜头跟随）")

	# 左下角：钳到 (0,90)，视野贴住场地左边和下边
	var lb := _clamped_pt(a, v, Vector2(-270.0, -360.0), mg)
	chk(lb == Vector2(-24.0, 66.0), "左下角相机中心钳到 (-24,66)")
	chk(_view_ok(a, lb, v, mg), "左下角最多只露 24px 围栏（不是半屏黑区）")

	# 右上角：钳到 (540,810)，视野贴住场地右边和上边
	var rt := _clamped_pt(a, v, Vector2(810.0, 1260.0), mg)
	chk(rt == Vector2(564.0, 834.0), "右上角相机中心钳到 (564,834)")
	chk(_view_ok(a, rt, v, mg), "右上角最多只露 24px 围栏（不是半屏黑区）")

	# --- 视口比场地大：内缩会反转，必须退化为中心而不是留下反转区间 ---
	var big := Vector2(1200.0, 1800.0)
	var mb := CamLimits.limits(a, big)
	chk(mb["left"] == mb["right"] and mb["top"] == mb["bottom"], "视口大于场地时限位退化为中心点")
	chk(mb["left"] == 270.0 and mb["top"] == 450.0, "退化中心=场地中心 (270,450)")

	# --- 横屏：视口 960x540，场地 1620x1080（中心 0,0）---
	var al := {"x": -810.0, "y": -540.0, "w": 1620.0, "h": 1080.0}
	var vl := Vector2(960.0, 540.0)
	var ml := CamLimits.limits(al, vl, mg)
	chk(ml["left"] == -354.0 and ml["right"] == 354.0, "横屏横向限位 [-354,354]")
	chk(ml["top"] == -294.0 and ml["bottom"] == 294.0, "横屏纵向限位 [-294,294]")
	var cl := _clamped_pt(al, vl, Vector2(-810.0, 540.0), mg)
	chk(_view_ok(al, cl, vl, mg), "横屏左下角最多只露 24px 围栏")

	return {"pass": _p, "fail": _f, "failures": _failures}
