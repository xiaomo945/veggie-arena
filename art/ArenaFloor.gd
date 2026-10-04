extends Node2D

# 厨房主题战场地面（纯代码绘制，零外部贴图）：
#   砧板地砖格子 + 木纹 + 油渍/水渍/焦痕/刀痕 + 灶台钢边围栏 + 灶台外厨房地面。
# 为什么单独一个节点：Main.gd 已顶着 300 行红线，地面这套"生成 + 剔除 + 绘制"
# 拆出来才放得下；Main 只负责 add_child，一行接上。
#
# 性能：只画镜头可见范围（540x900 → 砧板 ~7x12 块 + 少量污渍），
# 且镜头没动就不重绘 —— 满屏怪时这一层几乎零开销。

const FloorTiles := preload("res://art/FloorTiles.gd")
const FloorGrime := preload("res://art/FloorGrime.gd")
const FloorRim := preload("res://art/FloorRim.gd")

const FAR_K := 0.52                      # 远景视差系数（越小跟得越"慢"）
const VIEW_PAD := 56.0                   # 可见范围外多画一圈：允许镜头小幅移动时不重绘
const REDRAW_STEP_SQ := 36.0             # 镜头移动超过 6px 才重绘地面（配合 VIEW_PAD 不会露边）
const TILE_COLS := 14
const TILE_ROWS := 21

const COUNTER := Color(0.078, 0.082, 0.104)
const COUNTER_LINE := Color(1.0, 1.0, 1.0, 0.040)
const SHADOW_FAR := Color(0.0, 0.0, 0.0, 0.26)

var _arena := Rect2()
var _tile := 77.0
var _cam := Vector2(1e9, 1e9)
var _grain: Array = []
var _stains: Array = []
var _cuts: Array = []
var _far: Array = []

# 开新局也可以重掷一块新砧板（seed 换掉就行）
func setup(arena: Rect2) -> void:
	_arena = arena
	_tile = minf(arena.size.x / float(TILE_COLS), arena.size.y / float(TILE_ROWS))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260412
	_grain = _gen_grain(rng)
	_stains = FloorGrime.gen(rng, arena.grow(-72.0))
	_cuts = FloorGrime.gen_cuts(rng, arena.grow(-40.0))
	_far = _gen_far(rng)
	_cam = Vector2(1e9, 1e9)     # 强制下一帧重绘
	queue_redraw()

func arena() -> Rect2:
	return _arena

# ---- 每帧只做一件事：看镜头动没动 ----
func _process(_delta: float) -> void:
	var cam := _camera()
	if cam.distance_squared_to(_cam) > REDRAW_STEP_SQ:
		_cam = cam
		queue_redraw()

func _camera() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var cam := vp.get_camera_2d()
	return cam.get_screen_center_position() if cam != null else Vector2.ZERO

func _draw() -> void:
	var view := get_viewport_rect().size
	var vis := Rect2(_cam - view * 0.5, view).grow(VIEW_PAD)
	_draw_far(vis)
	draw_rect(vis.grow(8.0), COUNTER)
	_counter_grid(vis)
	var clip := vis.intersection(_arena)
	if clip.has_area():
		FloorTiles.draw_tiles(self, clip, _arena, _tile, _grain)
		FloorGrime.draw_stains(self, clip, _stains)
		FloorGrime.draw_cuts(self, clip, _cuts)
	FloorRim.draw_rim(self, _arena)

# 灶台外的厨房地面：大格暗砖 + 视差柔影（比战场"走得慢"，走出空间纵深）
func _draw_far(vis: Rect2) -> void:
	var off := _cam * (1.0 - FAR_K)
	draw_set_transform(off, 0.0, Vector2.ONE)
	var vis_far := Rect2(vis.position - off, vis.size)
	# 掉帧时只画一层：远景柔影是纯氛围，砍一半的 draw_circle 玩家几乎看不出来
	var layers := 2 if Perf.bool_cap("far_detail", true) else 1
	for b in _far:
		var p: Vector2 = b[0]
		var r: float = b[1]
		if absf(p.x - vis_far.get_center().x) > vis.size.x * 0.5 + r:
			continue
		if absf(p.y - vis_far.get_center().y) > vis.size.y * 0.5 + r:
			continue
		# 三圈同心圆叠出"软阴影"（draw_circle 没有渐变，只能这么糊）
		draw_circle(p, r, Color(SHADOW_FAR.r, SHADOW_FAR.g, SHADOW_FAR.b, 0.14))
		if layers > 1:
			draw_circle(p, r * 0.55, Color(SHADOW_FAR.r, SHADOW_FAR.g, SHADOW_FAR.b, 0.20))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 灶台外的大方格地砖（很淡，只是别让外面是一整块死黑）
func _counter_grid(vis: Rect2) -> void:
	var step := 132.0
	var x0 := floorf(vis.position.x / step) * step
	var y0 := floorf(vis.position.y / step) * step
	var x := x0
	while x < vis.end.x + step:
		draw_line(Vector2(x, vis.position.y), Vector2(x, vis.end.y), COUNTER_LINE, 2.0)
		x += step
	var y := y0
	while y < vis.end.y + step:
		draw_line(Vector2(vis.position.x, y), Vector2(vis.end.x, y), COUNTER_LINE, 2.0)
		y += step

# ---- 生成（setup 时一次）----

func _gen_grain(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var lim := _arena.grow(-10.0)
	for j in TILE_ROWS:
		for i in TILE_COLS:
			var px := _arena.position.x + float(i) * _tile
			var py := _arena.position.y + float(j) * _tile
			for _k in 2:
				if rng.randf() < 0.35:
					continue
				var yy := py + rng.randf_range(0.14, 0.86) * _tile
				var ax := px + rng.randf_range(0.02, 0.30) * _tile
				var bx := px + rng.randf_range(0.70, 0.98) * _tile
				if ax < lim.position.x or bx > lim.end.x or yy < lim.position.y or yy > lim.end.y:
					continue
				out.append([ax, yy, bx, yy + rng.randf_range(-2.5, 2.5),
					0 if rng.randf() < 0.6 else 1, rng.randf_range(1.0, 2.0)])
	return out

# 远景柔影：堆在竞技场外一圈（挂锅的影子投在灶台外的地面上）
func _gen_far(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var outer := _arena.grow(620.0)
	var inner := _arena.grow(-40.0)
	for i in 64:
		var p := Vector2(rng.randf_range(outer.position.x, outer.end.x),
			rng.randf_range(outer.position.y, outer.end.y))
		if inner.has_point(p):
			continue
		out.append([p, rng.randf_range(70.0, 190.0)])
	return out
