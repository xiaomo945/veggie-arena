extends Node2D

# 摇杆的纯绘制层：不处理输入，只负责把状态画出来。
# 底盘画在固定位置（base），钮（knob）画在底盘 + 偏移处。

var radius := 52.0
var base := Vector2.ZERO
var knob := Vector2.ZERO
var active := false

# 近乎透明：底盘环 ~10% 透明度，钮稍亮一点但仍低调，不挡视线
const BASE_ALPHA := 0.08
const RING_ALPHA := 0.12
const KNOB_ALPHA := 0.30

func _draw() -> void:
	if not active:
		return
	# 底盘
	draw_circle(base, radius, Color(1.0, 1.0, 1.0, BASE_ALPHA))
	# 外圈
	draw_arc(base, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, RING_ALPHA), 2.0, true)
	# 摇杆头（限制在底盘内，直观展示"满舵"）
	var off := (knob - base)
	if off.length() > radius:
		off = off.normalized() * radius
	draw_circle(base + off, radius * 0.42, Color(1.0, 1.0, 1.0, KNOB_ALPHA))
