extends CharacterBody2D

# 玩家角色（阶段 2.1：只做跑位，不做战斗）
#
# 手感三要素全部来自 core/Movement —— 本文件只负责"把方向变成位移"。
# 不在这里写任何数值：速度、死区、加速常数一律读 balance.json。

const Movement := preload("res://core/Movement.gd")

var _dir := Vector2.ZERO
var _vx := 0.0
var _vy := 0.0
var _radius := 16.0
var _speed := 180.0
var _k_forward := 90.0
var _k_reverse := 110.0
var _arena := Rect2()
var _bob := 0.0

const SKIN := Color(0.97, 0.96, 0.92)   # 白萝卜
const SHADE := Color(0.86, 0.85, 0.80)
const LEAF := Color(0.35, 0.68, 0.30)
const LEAF2 := Color(0.27, 0.56, 0.24)
const EYE := Color(0.16, 0.14, 0.12)

func _ready() -> void:
	var pc := Data.player_cfg()
	_radius = float(pc.get("radius", 16))
	_speed = float(pc.get("speed", 180))
	var f := Movement.feel(Data.feel_cfg())
	_k_forward = float(f["k_forward"])
	_k_reverse = float(f["k_reverse"])
	var a := Data.arena()
	_arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))

	Events.stick_dir_changed.connect(_on_dir)
	Events.stick_released.connect(_on_release)

func _on_dir(d: Vector2) -> void:
	_dir = d

func _on_release() -> void:
	_dir = Vector2.ZERO

func _physics_process(delta: float) -> void:
	var nv := Movement.step(_vx, _vy, _dir.x, _dir.y,
		_speed, delta, _k_forward, _k_reverse)
	_vx = nv.x
	_vy = nv.y
	global_position = Movement.clamp_to_arena(
		global_position + Vector2(_vx, _vy) * delta, _arena, _radius)
	_bob += delta * 6.0 * (Movement.speed_of(_vx, _vy) / maxf(_speed, 1.0))
	queue_redraw()

func _draw() -> void:
	var squash := 1.0 + 0.05 * sin(_bob)
	var stretch := 1.0 / squash
	# 叶子
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, -12), Vector2(-3, -30), Vector2(0, -11)]), LEAF)
	draw_colored_polygon(PackedVector2Array([
		Vector2(9, -12), Vector2(3, -30), Vector2(0, -11)]), LEAF2)
	# 身体（萝卜：上宽下尖）
	var body := PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(10 * stretch, 6 * squash),
		Vector2(0, 18 * squash),
		Vector2(-10 * stretch, 6 * squash),
	])
	draw_colored_polygon(body, SKIN)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(13 * stretch, -4 * squash),
		Vector2(-13 * stretch, -4 * squash)]), SHADE)
	# 眼睛：看向移动方向
	var look := _dir
	if look == Vector2.ZERO:
		look = Vector2(0, -1)
	else:
		look = look.limit_length(1.0)
	var ex := look.x * 2.2
	var ey := look.y * 1.6
	draw_circle(Vector2(-4.6 + ex, -2 + ey), 2.3, EYE)
	draw_circle(Vector2(4.6 + ex, -2 + ey), 2.3, EYE)
