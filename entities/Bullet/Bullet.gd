extends Node2D

# 子弹：对象池复用，不反复 instantiate（手机上这是帧率关键）。
# 外观在 launch 时画一次；飞行途中不重绘，只改 position。

var active := false
var dir := Vector2.ZERO
var speed := 560.0
var dmg := 0.0
var pierce_left := 0
var aoe_radius := 0.0
var bounce_left := 0    # 剩余撞墙反弹次数（"弹墙"道具）
var radius := 5.0
var life := 0.0
var max_life := 1.0
var tint := Color(1, 1, 1)
var hit_ids := {}

func launch(pos: Vector2, direction: Vector2, stats: Dictionary, c: Color) -> void:
	global_position = pos
	dir = direction.normalized()
	speed = float(stats.get("bullet_speed", 560))
	dmg = float(stats.get("dmg", 1))
	pierce_left = int(stats.get("pierce", 0))
	aoe_radius = float(stats.get("aoe", 0))
	bounce_left = int(stats.get("bounce", 0))
	max_life = float(stats.get("range", 300)) / maxf(speed, 1.0)
	life = 0.0
	radius = 4.0 if aoe_radius <= 0.0 else 7.0
	tint = c
	hit_ids.clear()
	active = true
	visible = true
	rotation = dir.angle()
	queue_redraw()

func recycle() -> void:
	active = false
	visible = false
	hit_ids.clear()

func advance(delta: float) -> void:
	if not active:
		return
	global_position += dir * speed * delta
	life += delta
	if life >= max_life:
		recycle()

func _draw() -> void:
	if not active:
		return
	var col := tint
	# 拖尾让高速子弹看得清（卡通能量尾迹）
	draw_line(Vector2(-14, 0), Vector2(0, 0), Color(col.r, col.g, col.b, 0.28), 4.0)
	# 暗描边：小子弹也有卡通塑料轮廓
	draw_circle(Vector2.ZERO, radius + 1.6, Color(0.06, 0.05, 0.09, 0.9))
	# 本体（武器色）
	draw_circle(Vector2.ZERO, radius, col)
	# 高光点：塑料质感的小亮点
	draw_circle(Vector2(-radius * 0.3, -radius * 0.32), radius * 0.38, Color(1, 1, 1, 0.92))
	if aoe_radius > 0.0:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 16,
			Color(col.r, col.g, col.b, 0.55), 2.0, true)
