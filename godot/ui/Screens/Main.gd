extends Node2D

# 主场景（阶段 2.1：竞技场 + 一个能跑的萝卜 + 摇杆）
# 后面每加一个功能，只在这里加一行 add_child，不改已有逻辑。

const PlayerScene := preload("res://entities/Player/Player.tscn")
const JoystickScene := preload("res://ui/Joystick/Joystick.tscn")

const BG := Color(0.06, 0.07, 0.10)
const FLOOR := Color(0.11, 0.13, 0.17)
const GRID := Color(1.0, 1.0, 1.0, 0.035)
const BORDER := Color(0.45, 0.75, 0.40, 0.55)

func _ready() -> void:
	var a := Data.arena()
	var cx := float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5
	var cy := float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5

	var player = PlayerScene.instantiate()
	player.position = Vector2(cx, cy)
	add_child(player)

	add_child(JoystickScene.instantiate())
	queue_redraw()

func _draw() -> void:
	var a := Data.arena()
	var r := Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	draw_rect(Rect2(0, 0, 540, 900), BG)
	draw_rect(r, FLOOR)
	# 地砖网格：给移动一个参照物，否则看不出自己在动
	var step := 60.0
	var x := r.position.x
	while x <= r.position.x + r.size.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y), GRID, 1.0)
		x += step
	var y := r.position.y
	while y <= r.position.y + r.size.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), GRID, 1.0)
		y += step
	draw_rect(r, BORDER, false, 2.0)
