extends Node2D

# HUD 的绘制层：血条 + 武器槽。
# 单独拆出来，是为了让"画什么"和"什么时候更新"分开，改样式不会碰坏逻辑。

var hp_ratio := 1.0
var wave_progress := 0.0
var slots: Array = []      # [{key, level, color, zh}]

const BAR_X := 14.0
const BAR_Y := 8.0
const BAR_W := 512.0
const BAR_H := 14.0

const SLOT_SIZE := 30.0
const SLOT_GAP := 6.0
const SLOT_Y := 32.0

func _draw() -> void:
	_draw_hp_bar()
	_draw_slots()

func _draw_hp_bar() -> void:
	# 底槽
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W, BAR_H), Color(0, 0, 0, 0.55))
	# 波次进度（细条，叠在血条下方，让玩家知道"还有多久这波结束"）
	draw_rect(Rect2(BAR_X, BAR_Y + BAR_H + 2.0, BAR_W, 3.0), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(BAR_X, BAR_Y + BAR_H + 2.0, BAR_W * clampf(wave_progress, 0.0, 1.0), 3.0),
		Color(0.55, 0.85, 0.55, 0.75))
	# 血量：低于 30% 变红，危险感要一眼看到
	var r := clampf(hp_ratio, 0.0, 1.0)
	var c := Color(0.85, 0.30, 0.28) if r < 0.3 else Color(0.45, 0.80, 0.42)
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W * r, BAR_H), c)
	# 分段刻度，方便估算还剩多少血
	for i in range(1, 5):
		var x := BAR_X + BAR_W * float(i) / 5.0
		draw_line(Vector2(x, BAR_Y), Vector2(x, BAR_Y + BAR_H), Color(0, 0, 0, 0.35), 1.0)

func _draw_slots() -> void:
	var n := maxi(slots.size(), 1)
	var total_w := float(n) * SLOT_SIZE + float(n - 1) * SLOT_GAP
	var x0 := 526.0 - total_w
	for i in slots.size():
		var s: Dictionary = slots[i]
		var x := x0 + float(i) * (SLOT_SIZE + SLOT_GAP)
		var rect := Rect2(x, SLOT_Y, SLOT_SIZE, SLOT_SIZE)
		draw_rect(rect, Color(0, 0, 0, 0.45))
		var c: Color = s.get("color", Color(1, 1, 1))
		draw_rect(rect.grow(-2.0), c)
		# 等级：右下角小圆点，一颗代表一级
		var lv := int(s.get("lv", 1))
		for k in lv:
			var px := x + 5.0 + float(k) * 6.0
			draw_circle(Vector2(px, SLOT_Y + SLOT_SIZE - 5.0), 2.2, Color(1, 1, 1, 0.9))
