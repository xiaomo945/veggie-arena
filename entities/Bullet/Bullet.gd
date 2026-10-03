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
var wkey := ""    # 武器 key，用来画这把武器专属的子弹造型

# 每把武器的子弹造型（卡通化，让"这把枪"一眼认得出）。
# 没列出的走默认圆弹；按 key 映射，以后新加武器只要在这里补一行。
const SHAPES := {
	"pistol": "pistol", "smg": "smg", "shotgun": "shotgun",
	"rocket": "rocket", "bow": "arrow",
	"skewer": "spike", "chopsticks": "spike", "fork": "spike",
	"peeler": "spike", "grater": "spike", "microwave": "spike",
	"staff": "orb_ring", "ladle": "orb_ring",
	"pan": "chunk", "griddle": "chunk", "baking_tray": "chunk",
	"mortar": "chunk", "wok_scoop": "chunk", "clay_pot": "chunk",
	"chili": "drop", "pepper": "drop", "oil_sprayer": "drop",
	"blender": "drop", "whisk": "drop", "egg_beater": "drop",
	"garlic_press": "drop", "strainer": "drop", "teapot": "drop",
}
const INK := Color(0.06, 0.05, 0.09, 0.9)

func launch(pos: Vector2, direction: Vector2, stats: Dictionary, c: Color, key := "") -> void:
	wkey = key
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
	var shape := str(SHAPES.get(wkey, "orb"))
	match shape:
		"rocket":
			_draw_rocket(col)
		"arrow":
			_draw_arrow(col)
		"pistol":
			_draw_pistol(col)
		"smg":
			_draw_smg(col)
		"shotgun":
			_draw_shotgun(col)
		"spike":
			_draw_spike(col)
		"chunk":
			_draw_chunk(col)
		"drop":
			_draw_drop(col)
		"orb_ring":
			_draw_orb(col)
			draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 16,
				Color(col.r, col.g, col.b, 0.6), 2.2, true)
		_:
			_draw_orb(col)
	if aoe_radius > 0.0 and shape != "orb_ring":
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 16,
			Color(col.r, col.g, col.b, 0.55), 2.0, true)

# 默认圆弹：暗描边 + 武器色本体 + 白色高光（卡通塑料质感）
func _draw_orb(col: Color) -> void:
	draw_line(Vector2(-14, 0), Vector2(0, 0), Color(col.r, col.g, col.b, 0.28), 4.0)
	draw_circle(Vector2.ZERO, radius + 1.6, INK)
	draw_circle(Vector2.ZERO, radius, col)
	draw_circle(Vector2(-radius * 0.3, -radius * 0.32), radius * 0.38, Color(1, 1, 1, 0.92))

# 火箭筒：粗胶囊弹体 + 橙色火焰尾巴
func _draw_rocket(col: Color) -> void:
	var ln := radius * 2.6
	var h := radius * 1.05
	draw_rect(Rect2(-ln * 0.5, -h, ln, h * 2.0), INK)
	draw_rect(Rect2(-ln * 0.5 + 1.4, -h + 1.4, ln - 2.8, h * 2.0 - 2.8), col)
	draw_circle(Vector2(ln * 0.5, 0), h, col)
	draw_circle(Vector2(ln * 0.5, 0), h + 1.4, INK)
	draw_circle(Vector2(ln * 0.5 - 1.4, 0), h - 1.6, col)
	# 火焰尾巴：两团橙黄小三角
	for i in 2:
		var s := 1.0 - float(i) * 0.45
		var tip := Vector2(-ln * 0.5 - 12.0 * s, 0)
		var c2 := Color(1.0, 0.72 - float(i) * 0.22, 0.25, 0.95)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-ln * 0.5, -4.5 * s), tip, Vector2(-ln * 0.5, 4.5 * s)]), c2)

# 弓：细杆 + 三角箭头的卡通箭
func _draw_arrow(col: Color) -> void:
	var ln := radius * 2.2
	draw_line(Vector2(-ln, 0), Vector2(ln * 0.4, 0), INK, 5.0)
	draw_line(Vector2(-ln, 0), Vector2(ln * 0.4, 0), col, 2.6)
	var tip := Vector2(ln * 1.1, 0)
	draw_colored_polygon(PackedVector2Array([
		tip, Vector2(ln * 0.25, -5.0), Vector2(ln * 0.25, 5.0)]), INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ln * 0.95, 0), Vector2(ln * 0.32, -3.4), Vector2(ln * 0.32, 3.4)]), col)

# 穿刺类（竹签/筷子/叉子…）：细长菱形尖刺，读起来"能穿透"
func _draw_spike(col: Color) -> void:
	var ln := radius * 3.0
	var w := radius * 0.62
	draw_colored_polygon(PackedVector2Array([
		Vector2(ln, 0), Vector2(0, -w), Vector2(-ln * 0.45, 0), Vector2(0, w)]), INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ln - 1.6, 0), Vector2(0, -w + 0.9),
		Vector2(-ln * 0.45 + 1.0, 0), Vector2(0, w - 0.9)]), col)

# 重型厨具（锅/烤盘/研钵…）：敦实的圆角方块，砸过去的分量感
func _draw_chunk(col: Color) -> void:
	var s := radius * 1.75
	var r := Rect2(-s * 0.5, -s * 0.5, s, s)
	draw_rect(r, INK)
	draw_rect(Rect2(r.position + Vector2(1.5, 1.5), r.size - Vector2(3.0, 3.0)), col)
	draw_circle(Vector2(-s * 0.16, -s * 0.18), s * 0.2, Color(1, 1, 1, 0.9))

# 喷洒/粉末类（辣椒/胡椒/油壶…）：小水滴，前端带尖
func _draw_drop(col: Color) -> void:
	var s := radius * 1.15
	draw_circle(Vector2.ZERO, s + 1.4, INK)
	draw_circle(Vector2.ZERO, s, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(s * 2.0, 0), Vector2(s * 0.3, -s * 0.62), Vector2(s * 0.3, s * 0.62)]), col)
	draw_circle(Vector2(-s * 0.28, -s * 0.3), s * 0.32, Color(1, 1, 1, 0.9))

# 手枪：黄铜小尖头弹（抛物弹头 + 平底弹壳），细长三角一眼是"子弹"
func _draw_pistol(col: Color) -> void:
	var ln := radius * 3.2
	var h := radius * 0.85
	draw_colored_polygon(PackedVector2Array([
		Vector2(ln, 0), Vector2(ln * 0.1, -h), Vector2(-ln * 0.6, -h * 0.72),
		Vector2(-ln * 0.6, h * 0.72), Vector2(ln * 0.1, h)]), INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ln - 1.6, 0), Vector2(ln * 0.1, -h + 1.3),
		Vector2(-ln * 0.6 + 1.2, -h * 0.72 + 1.0),
		Vector2(-ln * 0.6 + 1.2, h * 0.72 - 1.0), Vector2(ln * 0.1, h - 1.3)]), col)
	draw_circle(Vector2(-ln * 0.42, -h * 0.2), h * 0.34, Color(1, 1, 1, 0.85))

# 冲锋枪：短粗圆头弹，弹体胖、弹头圆，飞起来就是一团铜色拳头
func _draw_smg(col: Color) -> void:
	var ln := radius * 2.0
	var h := radius * 1.18
	draw_rect(Rect2(-ln * 0.6, -h, ln * 0.9, h * 2.0), INK)
	draw_circle(Vector2(ln * 0.3, 0), h, INK)
	draw_rect(Rect2(-ln * 0.6 + 1.4, -h + 1.4, ln * 0.9 - 2.0, h * 2.0 - 2.8), col)
	draw_circle(Vector2(ln * 0.3 - 1.0, 0), h - 1.6, col)
	draw_circle(Vector2(ln * 0.05, -h * 0.32), h * 0.3, Color(1, 1, 1, 0.85))

# 霰弹：一束小弹丸沿飞行方向扇形散开（铅灰偏武器色），读起来就是"喷出去的一把砂"
func _draw_shotgun(col: Color) -> void:
	var n := 4
	var spread := 0.62
	for i in n:
		var f := float(i) / float(n - 1) if n > 1 else 0.5
		var ang := -spread * 0.5 + spread * f
		var off := float(i - (n - 1) * 0.5) * 3.4
		var px := cos(ang) * off * 0.55 + off * 0.25
		var py := sin(ang) * off * 0.95
		var r := radius * 0.92
		draw_circle(Vector2(px, py), r + 1.3, INK)
		draw_circle(Vector2(px, py), r, col)
		draw_circle(Vector2(px - r * 0.3, py - r * 0.3), r * 0.4, Color(1, 1, 1, 0.82))
