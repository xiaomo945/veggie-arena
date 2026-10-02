extends RefCounted

# Boss 登场时从屏幕中心裂开的地缝（给 FxBossIntro 用的纯绘制工具）。
# 一条主干 + 若干分叉，端点在演出开始时就随机定好（存进调用方存不下的场合，
# 这里用"固定 seed + 调用次数无关"的方式保证每帧形状一致 —— 不能每帧换形状）。

const INK := Color(0.03, 0.02, 0.03, 0.9)
const DEEP := Color(0.02, 0.01, 0.02, 0.98)
const GLOW := Color(1.0, 0.36, 0.20, 0.5)

# 主干方向固定（每次演出同一条缝，形状稳定像"这块地就该裂在这"）
const BRANCHES := 6

# 在屏幕中心画放射状地缝；k ∈ 0..1 控制生长长度，k<=0 不画
static func paint(c: CanvasItem, center: Vector2, k: float) -> void:
	if k <= 0.01:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var max_len := c.get_viewport_rect().size.y * 0.34
	# 主干：从中心向外的折线，两三层描边叠出卡通裂缝
	for i in BRANCHES + 1:
		var ang := TAU * float(i) / float(BRANCHES + 1) + 0.35
		_trunk(c, center, ang, max_len * (0.72 if i > 0 else 1.0), k, rng)
	# 中心一块焦黑"裂口"
	if k > 0.4:
		var a := (k - 0.4) / 0.6
		c.draw_circle(center, 26.0 * a, DEEP)
		c.draw_circle(center, 15.0 * a, INK)

static func _trunk(c: CanvasItem, from: Vector2, ang: float, ln: float, k: float,
		rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	var p := from
	var d := Vector2(cos(ang), sin(ang))
	var n := 5
	pts.append(p)
	for i in n:
		var seg := ln / float(n)
		d = d.rotated(rng.randf_range(-0.22, 0.22))
		p += d * seg
		pts.append(p)
	# 生长：只画到 k 比例的长度
	var cut := int(float(pts.size() - 1) * clampf(k, 0.0, 1.0))
	if cut < 1:
		return
	var vis := PackedVector2Array()
	for i in cut + 1:
		vis.append(pts[i])
	var w := 9.0
	c.draw_polyline(vis, INK, w, true)
	c.draw_polyline(vis, DEEP, w * 0.55, true)
	# 缝里透出的热光（越靠中心越亮）
	c.draw_polyline(vis, GLOW, w * 0.22, true)
	# 分叉
	if k > 0.55:
		for i in 2:
			var at := vis[vis.size() - 1 - i * 2]
			_twig(c, at, d.rotated(0.9 if i == 0 else -0.9), ln * 0.3)

static func _twig(c: CanvasItem, from: Vector2, dir: Vector2, ln: float) -> void:
	var p := from
	var d := dir.normalized()
	var pts := PackedVector2Array([p])
	for i in 3:
		# 固定偏移：演出每帧重绘，形状必须一致（不能每帧随机抖）
		d = d.rotated(0.22 if i % 2 == 0 else -0.30)
		p += d * (ln / 3.0)
		pts.append(p)
	c.draw_polyline(pts, INK, 4.0, true)
	c.draw_polyline(pts, DEEP, 2.2, true)

# 全屏边缘暗晕（一层层往里叠，柔边）
static func vignette(c: CanvasItem, view: Vector2, col: Color) -> void:
	var cx := view.x + view.x * 0.5
	var cy := view.y + view.y * 0.5
	var rmax := view.length() * 0.62
	for i in 10:
		var f := float(i) / 10.0
		var rr := lerpf(rmax * 0.52, rmax, f)
		c.draw_arc(Vector2(cx, cy), rr, 0.0, TAU, 48,
			Color(col.r, col.g, col.b, col.a * (1.0 - f) * 0.5),
			rmax * 0.06, true)
