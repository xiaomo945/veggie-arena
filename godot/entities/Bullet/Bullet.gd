extends Node2D

# 子弹：对象池复用，不反复 instantiate（手机上这是帧率关键）。
# 外观在 launch 时画一次；飞行途中不重绘，只改 position。

var active := false
var dir := Vector2.ZERO
var speed := 560.0
var dmg := 0.0
var pierce_left := 0
var aoe_radius := 0.0
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
	# 拖尾让高速子弹看得清
	draw_line(Vector2(-14, 0), Vector2(0, 0), Color(tint.r, tint.g, tint.b, 0.30), 4.0)
	draw_circle(Vector2.ZERO, radius, tint)
	if aoe_radius > 0.0:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 16,
			Color(tint.r, tint.g, tint.b, 0.55), 2.0, true)
