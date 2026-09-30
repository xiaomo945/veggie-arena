extends Node2D

# 摇杆的纯绘制层：不处理输入，只负责把状态画出来。
# 这样"手感"和"外观"可以分开改，改外观不会碰坏手感逻辑。

var radius := 52.0
var origin := Vector2.ZERO
var finger := Vector2.ZERO
var active := false

const BASE_ALPHA := 0.10
const RING_ALPHA := 0.30
const KNOB_ALPHA := 0.45

func _draw() -> void:
	if not active:
		return
	# 底盘
	draw_circle(origin, radius, Color(1.0, 1.0, 1.0, BASE_ALPHA))
	# 外圈
	draw_arc(origin, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, RING_ALPHA), 2.0, true)
	# 摇杆头（限制在底盘内，直观展示"满舵"）
	var off := (finger - origin)
	if off.length() > radius:
		off = off.normalized() * radius
	draw_circle(origin + off, radius * 0.42, Color(1.0, 1.0, 1.0, KNOB_ALPHA))
