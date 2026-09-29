extends Node2D

# 主场景（阶段 2.1：竞技场 + 一个能跑的萝卜 + 摇杆）
# 后面每加一个功能，只在这里加一行 add_child，不改已有逻辑。

const PlayerScene := preload("res://entities/Player/Player.tscn")
const JoystickScene := preload("res://ui/Joystick/Joystick.tscn")
const GameScene := preload("res://scenes/Game.tscn")

var player: Node2D
var game: Node

const BG := Color(0.06, 0.07, 0.10)
const FLOOR := Color(0.11, 0.13, 0.17)
const GRID := Color(1.0, 1.0, 1.0, 0.035)
const BORDER := Color(0.45, 0.75, 0.40, 0.55)

func _ready() -> void:
	var a := Data.arena()
	var cx := float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5
	var cy := float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5

	player = PlayerScene.instantiate()
	player.position = Vector2(cx, cy)
	add_child(player)

	# 战斗管理器（刷怪/子弹/命中/波次）
	game = GameScene.instantiate()
	game.player = player
	add_child(game)

	add_child(JoystickScene.instantiate())
	queue_redraw()

	# headless 自测：godot --headless -- --sim=30 会跑 30 秒战斗并打印结果
	# 画面看不到，就用数字确认"怪刷出来了、被打死了、玩家会掉血"
	var secs := _sim_arg()
	if OS.get_cmdline_user_args().has("--sim") or secs > 0.0:
		_run_simulation(secs if secs > 0.0 else 30.0)

func _sim_arg() -> float:
	# 注意：Godot 4 里 "--" 之后的参数只在 get_cmdline_user_args() 里，
	# get_cmdline_args() 拿不到（踩过坑，别改回去）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			return float(a.substr(6))
	return 0.0

func _run_simulation(seconds: float) -> void:
	var steps := int(seconds * 60.0)
	var peak_alive := 0
	var survived := 0
	for i in steps:
		player._physics_process(1.0 / 60.0)
		game._physics_process(1.0 / 60.0)
		var n := int(game.alive_enemy_count())
		if n > peak_alive:
			peak_alive = n
		survived = i + 1
		if not GameState.running:
			break
	print("")
	print("=== 战斗模拟 %.0f 秒（玩家站着不动）===" % seconds)
	print("  存活时长    : %.1f 秒" % (float(survived) / 60.0))
	print("  波次        : %d" % GameState.wave)
	print("  场上敌人峰值: %d" % peak_alive)
	print("  累计击杀    : %d" % GameState.kills)
	print("  金币        : %d" % GameState.gold)
	print("  玩家血量    : %d / %d" % [GameState.hp, GameState.max_hp])
	print("  玩家状态    : %s" % ("存活" if GameState.running else "已死亡"))
	get_tree().quit(0)

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
