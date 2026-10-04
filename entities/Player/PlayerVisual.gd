extends Node2D

# 玩家外观层：承接 Player 的全部手绘/贴图绘制，与物理逻辑解耦。
# 通过 player 引用读取实时状态，且只走 Player 暴露的只读访问器
# （bob_phase() / ifr_left() / dash_state() / radius() / move_dir() / ...），
# 不直接读 player._xxx —— 谁能改这些状态，只有 Player 自己说了算。
# 本节点 position 默认(0,0)、无旋转缩放，其局部坐标系与 Player 自身一致，
# 因此 draw_* 画出来的位置与原 Player._draw 完全重合。

var player: Node = null
var _anim_t := 0.0   # 动画时钟：驱动呼吸/眨眼（idle 也要有"活着"的呼吸感）

const Weapon := preload("res://core/Weapon.gd")
const MOUNT_RADIUS := 42.0
# 贴图边长 = radius × 系数。之前 2.8（≈45px）比 brute/shambler 这些大怪还小，
# 混在怪堆里根本找不着；放大到 3.3（≈53px）与大体型怪物同量级。
const SPRITE_SCALE := 3.3
const MOUNT_ICON := 30.0

const SKIN := Color(0.97, 0.96, 0.92)
const SHADE := Color(0.86, 0.85, 0.80)
const LEAF := Color(0.35, 0.68, 0.30)
const LEAF2 := Color(0.27, 0.56, 0.24)
const EYE := Color(0.16, 0.14, 0.12)

func _ready() -> void:
	player = get_parent()

# 每帧推进动画并重绘：呼吸/眨眼必须连续，攒帧画会看出"一顿一顿"
func _process(delta: float) -> void:
	_anim_t += delta
	queue_redraw()

func _draw() -> void:
	_draw_trails()
	var squash := 1.0 + 0.05 * sin(player.bob_phase())
	var stretch := 1.0 / squash
	# 受伤闪烁：i-frames 期间快速明灭，提示"刚挨打且无敌"
	var alpha := 1.0
	if player.ifr_left() > 0.0:
		alpha = 0.35 + 0.45 * (0.5 + 0.5 * sin(player.ifr_left() * 40.0))
	var tex := _skin_texture()
	# 冲刺瞬间沿冲刺方向拉长（速度感），武器图标不跟着变形，所以画完马上复位
	if player.Dash.active(player.dash_state()):
		var ang: float = (player.dash_state()["dir"] as Vector2).angle()
		draw_set_transform(Vector2.ZERO, ang, Vector2(1.45, 0.72))
		if tex != null:
			_draw_sprite(tex, 1.0, 1.0, 1.0)
		else:
			_draw_body(1.0, 1.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_mounts()
		return
	# 呼吸 + 眨眼（仅非冲刺时；冲刺已有拉伸形变，叠加会抖）。
	# 呼吸 = 缓慢整体缩放（一直有，站着也呼吸）；眨眼 = 每 ~3 秒一次快速纵向压扁，
	# 50px 左右的体型下读起来就是"眨了一下眼"，比静态图多一份生气。
	var breath := 1.0 + 0.02 * sin(_anim_t * 2.3)
	var blink := 1.0
	var cyc := fmod(_anim_t, 3.1)
	if cyc > 2.94:
		blink = 1.0 - 0.24 * sin((cyc - 2.94) / 0.16 * PI)
	squash *= breath * blink
	stretch *= breath
	if tex != null:
		_draw_sprite(tex, squash, stretch, alpha)
	else:
		_draw_body(squash, stretch, alpha)
	_draw_mounts()

# 职业主色（当前角色的 characters.json color），用于给萝卜/贴图染色。
# 主角永远是萝卜，职业只改颜色 —— 一眼能分清选了远程/近战/法师哪套。
func _class_tint() -> Color:
	return Color(str(Data.character(GameState.character).get("color", "#f4f1e8")))

# 贴图版：squash/stretch 一样作用到贴图上，保证"贴图一接入，动画不会消失"
func _draw_sprite(tex: Texture2D, squash: float, stretch: float, alpha: float) -> void:
	var w: float = player.radius() * SPRITE_SCALE * stretch
	var h: float = player.radius() * SPRITE_SCALE * squash
	_draw_separators(maxf(w, h) * 0.5, alpha)
	# 贴图也按职业染色：贴图是白模时 modulate 往职业色染 35%，保留萝卜轮廓
	var tint := _class_tint()
	var mod := Color(1.0, 1.0, 1.0, alpha).lerp(Color(tint.r, tint.g, tint.b, alpha), 0.35)
	draw_texture_rect_region(tex, Rect2(-w * 0.5, -h * 0.5, w, h),
		Rect2(Vector2.ZERO, tex.get_size()), mod)

# 贴纸分离圈：外亮内深两道描边。怪群从身下压过来时，靠这两道圈把主角"抠"出来，
# 否则同色系的萝卜身子会和怪糊成一团。
func _draw_separators(r: float, alpha: float) -> void:
	draw_circle(Vector2.ZERO, r + 5.0, Color(1.0, 1.0, 1.0, alpha * 0.80))
	draw_circle(Vector2.ZERO, r + 2.4, Color(0.28, 0.15, 0.19, alpha * 0.95))

func _draw_body(squash: float, stretch: float, alpha: float) -> void:
	# 职业配色：把奶白萝卜身往当前职业主色染 30%，不同萝卜一眼能分清
	var tint := _class_tint()
	var skin := SKIN.lerp(tint, 0.30)
	var root := Color(0.92, 0.78, 0.82).lerp(tint, 0.22)
	var bw := 18.0 * stretch
	var bh := 19.0 * squash
	# 萝卜尾（根须）在身体下方
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3, bh * 0.62), Vector2(3, bh * 0.62), Vector2(0, bh + 9.0)]),
		Color(root.r, root.g, root.b, alpha))
	_draw_separators(maxf(bw, bh), alpha)
	# 身体（奶白偏粉的萝卜身，按职业染色）
	draw_circle(Vector2.ZERO, bh, Color(skin.r, skin.g, skin.b, alpha))
	# 下半身淡粉红晕（萝卜根部的红，同样带职业色）
	draw_circle(Vector2(0, bh * 0.34), bh * 0.78, Color(root.r + 0.06, root.g + 0.02, root.b + 0.02, alpha * 0.9))
	# 头顶两片小叶
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, -bh), Vector2(-12, -bh - 13), Vector2(-1, -bh - 4)]),
		Color(LEAF.r, LEAF.g, LEAF.b, alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(2, -bh), Vector2(12, -bh - 13), Vector2(1, -bh - 4)]),
		Color(LEAF2.r, LEAF2.g, LEAF2.b, alpha))
	# 脸：看向移动方向
	var look: Vector2 = player.move_dir()
	if look == Vector2.ZERO:
		look = Vector2(0, -1)
	else:
		look = look.limit_length(1.0)
	# 腮红
	draw_circle(Vector2(-7.5 + look.x, -1 + look.y), 3.0, Color(1.0, 0.66, 0.70, alpha * 0.7))
	draw_circle(Vector2(7.5 + look.x, -1 + look.y), 3.0, Color(1.0, 0.66, 0.70, alpha * 0.7))
	# 大眼睛（白眼 + 黑瞳 + 高光）
	for sgn in [-1, 1]:
		var ex: float = sgn * 5.5 + look.x * 1.5
		var ey: float = -3.0 + look.y * 1.2
		draw_circle(Vector2(ex, ey), 4.2, Color(1, 1, 1, alpha))
		draw_circle(Vector2(ex + look.x * 1.2, ey + look.y * 0.8), 2.3, Color(EYE.r, EYE.g, EYE.b, alpha))
		draw_circle(Vector2(ex - 1.2, ey - 1.4), 1.1, Color(1, 1, 1, alpha))
	# 小嘴（微笑弧）
	draw_arc(Vector2(look.x * 1.5, 4.0 + look.y), 3.2, 0.15 * PI, 0.85 * PI, 10,
		Color(0.55, 0.22, 0.26, alpha), 1.6, true)

# 角色贴图：优先 char_<角色>，缺图退回通用 player，再缺图就走手绘
func _skin_texture() -> Texture2D:
	var t := Art.sprite("char_" + GameState.character)
	if t != null:
		return t
	return Art.sprite("player")

# 冲刺残影：只画几个半透明的淡影，位置存的是世界坐标（画的时候转回局部）
func _draw_trails() -> void:
	for item in player.dash_trail():
		var t: Dictionary = item as Dictionary
		var k := clampf(float(t.get("t", 0.0)) / 0.22, 0.0, 1.0)
		var lp: Vector2 = to_local(t.get("w", global_position) as Vector2)
		draw_circle(lp, player.radius() * 0.85 * (0.6 + 0.4 * k),
			Color(0.98, 0.98, 1.0, 0.30 * k))

# 武器图标绕着角色站位（位置由 core/Weapon.mount_position 算，跟开火点是同一个）
# 缺图时退化成一个色点，玩家至少能看出"我带了几把武器"
func _draw_mounts() -> void:
	var n: int = player.weapon_caches().size()
	if n == 0:
		return
	for i in n:
		var w: Dictionary = player.weapon_caches()[i]
		var p := Weapon.mount_position(Vector2.ZERO, i, n, MOUNT_RADIUS)
		var s := MOUNT_ICON
		var tex := Art.icon("weapon_" + str(w["key"]))
		if tex == null:
			draw_circle(p, s * 0.42, w["color"] as Color)
			continue
		draw_texture_rect_region(tex, Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
