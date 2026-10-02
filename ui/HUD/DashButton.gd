extends Control

# 冲刺按钮：圆形 + 冷却扇形（从顶部顺时针扫过）。
#
# 只订阅 Events.dash_state_changed 更新自己的显示；不认识 Player。
#
# ⚠️ 本控件**不处理点击**：mouse_filter = IGNORE，让触摸穿透到 Joystick，
#   由 Joystick 命中 GameState.dash_rect 后统一发 dash_requested。
#   这样移动端/桌面走同一条路径，不会出现"点一下冲刺两次"。

const SIZE := 96.0
const RADIUS := 42.0

var _ratio := 1.0      # 冷却进度 0..1
var _can_dash := true

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(SIZE, SIZE)
	Events.dash_state_changed.connect(_on_state)
	queue_redraw()

func _on_state(ratio: float, ready: bool) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_can_dash = ready
	queue_redraw()

func _draw() -> void:
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var base := Color(0.16, 0.20, 0.28, 0.42)
	var ring := Color(0.55, 0.85, 0.45, 0.95) if _can_dash else Color(0.45, 0.52, 0.62, 0.85)
	draw_circle(c, RADIUS, base)
	# 外圈：冷却完成时用亮色描边，冷却中偏灰
	draw_arc(c, RADIUS, 0.0, TAU, 40, ring, 4.0, true)
	if not _can_dash:
		# 冷却扇形：剩余未冷却的部分画成暗色覆盖（从 -90° 顺时针）
		var span := TAU * (1.0 - _ratio)
		draw_colored_polygon(_wedge(c, RADIUS - 4.0, -PI * 0.5, -PI * 0.5 + span),
			Color(0.05, 0.07, 0.12, 0.55))
	# 中心图标：两条向右的箭头（冲刺符号），冷却中变暗
	var a := 0.95 if _can_dash else 0.35
	var col := Color(0.86, 0.96, 0.84, a)
	for i in 2:
		var x := c.x - 8.0 + float(i) * 11.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 5.0, c.y - 9.0), Vector2(x + 4.0, c.y),
			Vector2(x - 5.0, c.y + 9.0)]), col)
	# 冷却剩余秒数（1 位小数），只在冷却中显示
	if not _can_dash:
		var cd := float(Data.dash_cfg().get("cooldown", 1.8))
		var txt := "%.1f" % ((1.0 - _ratio) * cd)
		var fs := ThemeDB.fallback_font
		if fs != null:
			draw_string(fs, Vector2(c.x - 12.0, c.y + RADIUS - 6.0), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.94, 1.0, 0.9))

# 生成扇形多边形（圆心 + 半径 + 起止角）
func _wedge(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(c)
	var steps := 24
	for i in range(steps + 1):
		var ang := from + (to - from) * (float(i) / float(steps))
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts
