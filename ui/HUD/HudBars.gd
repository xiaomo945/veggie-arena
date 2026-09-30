extends Node2D

# HUD 的绘制层：血条 + 武器槽。
# 单独拆出来，是为了让"画什么"和"什么时候更新"分开，改样式不会碰坏逻辑。

var hp_ratio := 1.0
var wave_progress := 0.0
var slots: Array = []      # [{key, level, color, zh}]
var wok_ratio := 0.0       # 0..1 火候
var wok_tier := 0          # 0 微温 / 1 翻炒 / 2 爆炒

const BAR_X := 14.0
const BAR_Y := 8.0
const BAR_W := 512.0
const BAR_H := 14.0

const SLOT_SIZE := 30.0
const SLOT_GAP := 6.0
const SLOT_Y := 32.0

# 锅气条放在底部中央（拇指区，但只是进度条不影响操作；颠勺按钮在其上方）
const WOK_X := 120.0
const WOK_Y := 852.0
const WOK_W := 300.0
const WOK_H := 16.0

func _draw() -> void:
	_draw_hp_bar()
	_draw_slots()
	_draw_wok()

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

func _draw_wok() -> void:
	# 底槽
	draw_rect(Rect2(WOK_X, WOK_Y, WOK_W, WOK_H), Color(0, 0, 0, 0.55))
	# 档位刻度：翻炒(34%) 与 爆炒(68%) 的分界，玩家一眼知道火候到哪了
	_draw_tick(float(Data.wok_cfg().get("stir_from", 34)) / 100.0, Color(1, 0.8, 0.4, 0.8))
	_draw_tick(float(Data.wok_cfg().get("wokhei_from", 68)) / 100.0, Color(1, 0.45, 0.3, 0.9))
	# 满锅气线（颠勺就绪）
	_draw_tick(1.0, Color(1, 1, 1, 0.9))
	# 火候填充：档位越高越"炽热"
	var r := clampf(wok_ratio, 0.0, 1.0)
	var c := Color(0.55, 0.55, 0.55)
	if wok_tier >= 2:
		c = Color(1.0, 0.42, 0.26)     # 爆炒：红热
	elif wok_tier >= 1:
		c = Color(1.0, 0.66, 0.28)     # 翻炒：橙
	elif r > 0.01:
		c = Color(0.85, 0.78, 0.6)     # 微温：暖灰
	draw_rect(Rect2(WOK_X, WOK_Y, WOK_W * r, WOK_H), c)
	# 爆炒档描一圈"滋滋"高光，强化"热"的反馈
	if wok_tier >= 2:
		draw_rect(Rect2(WOK_X - 2.0, WOK_Y - 2.0, WOK_W + 4.0, WOK_H + 4.0),
			Color(1.0, 0.6, 0.4, 0.5), false, 2.0)

func _draw_tick(frac: float, c: Color) -> void:
	var x := WOK_X + WOK_W * clampf(frac, 0.0, 1.0)
	draw_line(Vector2(x, WOK_Y - 2.0), Vector2(x, WOK_Y + WOK_H + 2.0), c, 1.5)
