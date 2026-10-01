extends Node2D

# 玩家外观层：承接 Player 的全部手绘/贴图绘制，与物理逻辑解耦。
# 通过 player 引用读取实时状态（GDScript 无真私有，player._xxx 可直接访问）。
# 本节点 position 默认(0,0)、无旋转缩放，其局部坐标系与 Player 自身一致，
# 因此 draw_* 画出来的位置与原 Player._draw 完全重合。

var player: Node = null

const Weapon := preload("res://core/Weapon.gd")
const MOUNT_RADIUS := 42.0
const SPRITE_SCALE := 2.8
const MOUNT_ICON := 30.0

const SKIN := Color(0.97, 0.96, 0.92)
const SHADE := Color(0.86, 0.85, 0.80)
const LEAF := Color(0.35, 0.68, 0.30)
const LEAF2 := Color(0.27, 0.56, 0.24)
const EYE := Color(0.16, 0.14, 0.12)

func _ready() -> void:
	player = get_parent()

func _draw() -> void:
	_draw_trails()
	var squash := 1.0 + 0.05 * sin(player._bob)
	var stretch := 1.0 / squash
	# 受伤闪烁：无敌帧内半透明，让玩家知道"刚才挨打了"
	var alpha := 1.0 if player._ifr <= 0.0 else 0.55
	var tex := _skin_texture()
	# 冲刺瞬间沿冲刺方向拉长（速度感），武器图标不跟着变形，所以画完马上复位
	if player.Dash.active(player._dash):
		var ang: float = (player._dash["dir"] as Vector2).angle()
		draw_set_transform(Vector2.ZERO, ang, Vector2(1.45, 0.72))
		if tex != null:
			_draw_sprite(tex, 1.0, 1.0, 1.0)
		else:
			_draw_body(1.0, 1.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_mounts()
		return
	if tex != null:
		_draw_sprite(tex, squash, stretch, alpha)
	else:
		_draw_body(squash, stretch, alpha)
	_draw_mounts()

# 贴图版：squash/stretch 一样作用到贴图上，保证"贴图一接入，动画不会消失"
func _draw_sprite(tex: Texture2D, squash: float, stretch: float, alpha: float) -> void:
	var w: float = player._radius * SPRITE_SCALE * stretch
	var h: float = player._radius * SPRITE_SCALE * squash
	draw_texture_rect_region(tex, Rect2(-w * 0.5, -h * 0.5, w, h),
		Rect2(Vector2.ZERO, tex.get_size()), Color(1, 1, 1, alpha))

func _draw_body(squash: float, stretch: float, alpha: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, -12), Vector2(-3, -30), Vector2(0, -11)]), Color(LEAF.r, LEAF.g, LEAF.b, alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(9, -12), Vector2(3, -30), Vector2(0, -11)]), Color(LEAF2.r, LEAF2.g, LEAF2.b, alpha))
	var body := PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(10 * stretch, 6 * squash),
		Vector2(0, 18 * squash),
		Vector2(-10 * stretch, 6 * squash),
	])
	draw_colored_polygon(body, Color(SKIN.r, SKIN.g, SKIN.b, alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(13 * stretch, -4 * squash),
		Vector2(-13 * stretch, -4 * squash)]), Color(SHADE.r, SHADE.g, SHADE.b, alpha))
	var look: Vector2 = player._dir
	if look == Vector2.ZERO:
		look = Vector2(0, -1)
	else:
		look = look.limit_length(1.0)
	draw_circle(Vector2(-4.6 + look.x * 2.2, -2 + look.y * 1.6), 2.3,
		Color(EYE.r, EYE.g, EYE.b, alpha))
	draw_circle(Vector2(4.6 + look.x * 2.2, -2 + look.y * 1.6), 2.3,
		Color(EYE.r, EYE.g, EYE.b, alpha))

# 角色贴图：优先 char_<角色>，缺图退回通用 player，再缺图就走手绘
func _skin_texture() -> Texture2D:
	var t := Art.sprite("char_" + GameState.character)
	if t != null:
		return t
	return Art.sprite("player")

# 冲刺残影：只画几个半透明的淡影，位置存的是世界坐标（画的时候转回局部）
func _draw_trails() -> void:
	for item in player._dash_trail:
		var t: Dictionary = item as Dictionary
		var k := clampf(float(t.get("t", 0.0)) / 0.22, 0.0, 1.0)
		var lp: Vector2 = to_local(t.get("w", global_position) as Vector2)
		draw_circle(lp, player._radius * 0.85 * (0.6 + 0.4 * k),
			Color(0.98, 0.98, 1.0, 0.30 * k))

# 武器图标绕着角色站位（位置由 core/Weapon.mount_position 算，跟开火点是同一个）
# 缺图时退化成一个色点，玩家至少能看出"我带了几把武器"
func _draw_mounts() -> void:
	var n: int = player._weapons.size()
	if n == 0:
		return
	for i in n:
		var w: Dictionary = player._weapons[i]
		var p := Weapon.mount_position(Vector2.ZERO, i, n, MOUNT_RADIUS)
		var s := MOUNT_ICON
		var tex := Art.icon("weapon_" + str(w["key"]))
		if tex == null:
			draw_circle(p, s * 0.42, w["color"] as Color)
			continue
		draw_texture_rect_region(tex, Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
