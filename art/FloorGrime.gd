extends RefCounted

# 砧板上的"做旧"层：油渍 / 水渍 / 刀痕 / 焦痕。
# 全部是 setup 时用随机数生成、逐帧按可见范围剔除后用 draw_* 画的多边形，
# 没有任何外部贴图 —— 换个 seed 就是一块新砧板。

const OIL := Color(0.145, 0.098, 0.070, 0.34)
const OIL_RIM := Color(0.075, 0.050, 0.038, 0.30)
const WATER := Color(0.760, 0.830, 0.900, 0.055)
const WATER_EDGE := Color(0.820, 0.890, 0.960, 0.075)
const SCORCH := Color(0.110, 0.082, 0.072, 0.26)
const CUT_L := Color(0.640, 0.500, 0.360, 0.40)
const CUT_D := Color(0.205, 0.138, 0.100, 0.55)

# kind: 0=油渍 1=水渍 2=焦痕
# 油渍/焦痕：不规则闭合多边形（半径带噪声），水渍：淡色 + 一圈更淡的边
static func draw_stains(c: CanvasItem, vis: Rect2, stains: Array) -> void:
	for s in stains:
		var p: Vector2 = s["p"]
		var r: float = s["r"]
		if p.x + r < vis.position.x or p.x - r > vis.end.x:
			continue
		if p.y + r < vis.position.y or p.y - r > vis.end.y:
			continue
		var kind := int(s["k"])
		var pts: PackedVector2Array = s["pts"]
		match kind:
			0:
				c.draw_colored_polygon(pts, OIL)
				c.draw_polyline(_loop(pts), OIL_RIM, 2.0, true)
				_shine(c, p, r)
			1:
				c.draw_colored_polygon(pts, WATER)
				c.draw_polyline(_loop(pts), WATER_EDGE, 1.6, true)
			2:
				c.draw_colored_polygon(pts, SCORCH)
				c.draw_circle(p, r * 0.45, SCORCH)

# 油渍中央一粒小小的反光，让"湿"的感觉出来
static func _shine(c: CanvasItem, p: Vector2, r: float) -> void:
	c.draw_circle(p + Vector2(-r * 0.25, -r * 0.28), r * 0.16, Color(1, 1, 1, 0.07))

static func _loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

# 刀痕：一对平行细线（亮在下、暗在上 = 刻进去的凹槽）
static func draw_cuts(c: CanvasItem, vis: Rect2, cuts: Array) -> void:
	for ct in cuts:
		var a: Vector2 = ct["a"]
		var b: Vector2 = ct["b"]
		if maxf(a.x, b.x) < vis.position.x or minf(a.x, b.x) > vis.end.x:
			continue
		if maxf(a.y, b.y) < vis.position.y or minf(a.y, b.y) > vis.end.y:
			continue
		var n: Vector2 = ct["n"]
		var w: float = ct["w"]
		c.draw_line(a, b, CUT_D, w)
		c.draw_line(a + n, b + n, CUT_L, w * 0.55)

# ---- 生成（ArenaFloor.setup 调一次）----

static func make_blob(rng: RandomNumberGenerator, p: Vector2, r: float) -> PackedVector2Array:
	var n := 12 + rng.randi() % 5
	var pts := PackedVector2Array()
	var wob := rng.randf() * TAU
	for i in n:
		var ang := TAU * float(i) / float(n)
		# 半径上叠一层低频噪声：让轮廓有大波浪，不再是"齿轮多边形"
		var rr := r * (0.92 + 0.30 * sin(ang * 2.0 + wob) + rng.randf_range(-0.10, 0.14))
		pts.append(p + Vector2(cos(ang), sin(ang)) * rr)
	return pts

static func gen(rng: RandomNumberGenerator, arena: Rect2) -> Array:
	var out: Array = []
	var area := arena.get_area()
	# 油渍：大颗的少、小颗的多
	var n_oil := int(area / 26000.0)
	for i in n_oil:
		var r := rng.randf_range(10.0, 30.0) if rng.randf() < 0.3 else rng.randf_range(4.0, 13.0)
		var p := Vector2(rng.randf_range(arena.position.x, arena.end.x),
			rng.randf_range(arena.position.y, arena.end.y))
		out.append({"p": p, "r": r, "k": 0, "pts": make_blob(rng, p, r)})
	# 水渍：更大更淡，像刚泼过水
	for i in int(area / 90000.0):
		var r2 := rng.randf_range(26.0, 62.0)
		var p2 := Vector2(rng.randf_range(arena.position.x, arena.end.x),
			rng.randf_range(arena.position.y, arena.end.y))
		out.append({"p": p2, "r": r2, "k": 1, "pts": make_blob(rng, p2, r2)})
	# 焦痕（颠勺/爆炒留下的）
	for i in int(area / 130000.0):
		var r3 := rng.randf_range(16.0, 34.0)
		var p3 := Vector2(rng.randf_range(arena.position.x, arena.end.x),
			rng.randf_range(arena.position.y, arena.end.y))
		out.append({"p": p3, "r": r3, "k": 2, "pts": make_blob(rng, p3, r3)})
	return out

# 刀痕：短直线段，方向各有不同，n 是法线（决定刻痕高光在哪一侧）
static func gen_cuts(rng: RandomNumberGenerator, arena: Rect2) -> Array:
	var out: Array = []
	var area := arena.get_area()
	for i in int(area / 12000.0):
		var ang := rng.randf() * TAU
		var d := Vector2(cos(ang), sin(ang))
		var n := Vector2(-d.y, d.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var ln := rng.randf_range(14.0, 52.0)
		var a := Vector2(rng.randf_range(arena.position.x, arena.end.x),
			rng.randf_range(arena.position.y, arena.end.y))
		var b := a + d * ln
		out.append({"a": a, "b": b, "n": n, "w": rng.randf_range(1.0, 2.2)})
	return out
