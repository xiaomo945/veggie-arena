extends RefCounted

# 敌人手绘造型（缺贴图时的兜底 + 终局 Boss 装饰）。
# 从 Enemy.gd 拆出来：那边顶着 300 行红线，要给"出场升起"动画腾地方。
# 全是静态绘制函数：参数显式传入（不读调用方私有字段，架构守卫 R3）。

# 怒萌脸：怒眼 + 斜眉 + 龇牙，所有怪物共用；sz 控制大小，look 让眼略朝玩家
static func angry_face(c: CanvasItem, sz: float, look: Vector2, alpha: float) -> void:
	var ex := sz * 0.40
	var ey := -sz * 0.16
	for sgn in [-1, 1]:
		var x: float = sgn * ex + look.x * sz * 0.10
		var y: float = ey + look.y * sz * 0.08
		c.draw_circle(Vector2(x, y), sz * 0.24, Color(1, 1, 1, alpha))
		c.draw_circle(Vector2(x + look.x * sz * 0.07, y + look.y * sz * 0.05),
			sz * 0.13, Color(0.12, 0.10, 0.10, alpha))
		var b0 := Vector2(x - sz * 0.32, y - sz * 0.40)
		var b1 := Vector2(x + sz * 0.30, y - sz * 0.14)
		if sgn < 0:
			b0 = Vector2(x + sz * 0.32, y - sz * 0.40)
			b1 = Vector2(x - sz * 0.30, y - sz * 0.14)
		c.draw_line(b0, b1, Color(0.12, 0.10, 0.10, alpha), maxf(1.6, sz * 0.11))
	var my := sz * 0.46
	c.draw_line(Vector2(-sz * 0.5, my), Vector2(sz * 0.5, my),
		Color(0.12, 0.10, 0.10, alpha), maxf(1.6, sz * 0.11))
	for k in range(-2, 3):
		var tx := float(k) * sz * 0.22
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(tx - sz * 0.085, my), Vector2(tx + sz * 0.085, my),
			Vector2(tx, my + sz * 0.22)]), Color(1, 1, 1, alpha))

# 多边形 + 暗色底描边（卡通贴纸感）
static func poly(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * 1.12)
	c.draw_colored_polygon(out, Color(0.18, 0.10, 0.12, 1.0))
	c.draw_colored_polygon(pts, col)

# 凶萌造型：圆身/尖三角/六边/菱/星 + 怒脸
static func body(c: CanvasItem, etype: String, radius: float, col: Color) -> void:
	var look := Vector2(0.0, 0.2)
	match etype:
		"fast":
			poly(c, PackedVector2Array([
				Vector2(0, -radius * 1.25), Vector2(radius * 0.95, radius * 0.75),
				Vector2(-radius * 0.95, radius * 0.75)]), col)
			angry_face(c, radius * 0.95, look, 1.0)
		"tank":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := TAU * float(i) / 6.0 - PI * 0.5
				pts.append(Vector2(cos(a), sin(a)) * radius)
			poly(c, pts, col)
			c.draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 14,
				Color(0.20, 0.10, 0.26, 0.6), 3.0, true)
			angry_face(c, radius * 0.85, look, 1.0)
		"fly":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-radius*0.5,0),
				Vector2(-radius*1.6,-radius*0.5), Vector2(-radius*1.2,radius*0.45)]),
				Color(1,1,1,0.55))
			c.draw_colored_polygon(PackedVector2Array([Vector2(radius*0.5,0),
				Vector2(radius*1.6,-radius*0.5), Vector2(radius*1.2,radius*0.45)]),
				Color(1,1,1,0.55))
			poly(c, PackedVector2Array([Vector2(0,-radius*1.3), Vector2(radius*0.55,0),
				Vector2(0,radius*1.3), Vector2(-radius*0.55,0)]), col)
			angry_face(c, radius * 0.6, look, 1.0)
		"boss":
			var sp := PackedVector2Array()
			for i in range(24):
				var a2 := TAU * float(i) / 24.0
				sp.append(Vector2(cos(a2), sin(a2)) * radius * (0.62 if i % 2 == 0 else 1.0))
			poly(c, sp, col)
			angry_face(c, radius * 0.92, look, 1.0)
		"swarm":
			poly(c, PackedVector2Array([Vector2(-radius,0), Vector2(0,-radius),
				Vector2(radius,0), Vector2(0,radius)]), col)
			angry_face(c, radius * 0.9, look, 1.0)
		"brute":
			poly(c, PackedVector2Array([Vector2(-radius,-radius*0.9), Vector2(radius,-radius*0.9),
				Vector2(radius,radius*0.9), Vector2(-radius,radius*0.9)]), col)
			angry_face(c, radius * 0.9, look, 1.0)
		"shambler":
			poly(c, PackedVector2Array([Vector2(-radius,-radius*0.8), Vector2(-radius*0.7,-radius),
				Vector2(radius*0.7,-radius), Vector2(radius,-radius*0.8),
				Vector2(radius,radius), Vector2(-radius,radius)]), col)
			angry_face(c, radius * 0.9, look, 1.0)
		_:
			# 小兵：圆身 + 两只小角 + 凶萌脸
			poly(c, PackedVector2Array([Vector2(-radius*0.4,-radius*0.9),
				Vector2(-radius*0.1,-radius*1.25), Vector2(-radius*0.05,-radius*0.9)]), col)
			poly(c, PackedVector2Array([Vector2(radius*0.4,-radius*0.9),
				Vector2(radius*0.1,-radius*1.25), Vector2(radius*0.05,-radius*0.9)]), col)
			poly(c, PackedVector2Array([Vector2(-radius,0), Vector2(radius,0),
				Vector2(radius*0.85,radius), Vector2(0,radius*1.15),
				Vector2(-radius*0.85,radius)]), col)
			angry_face(c, radius * 0.95, look, 1.0)

# Boss 出场时的土坑：脚下越裂越大的黑坑 + 坑沿一圈崩出的土块
static func rise_hole(c: CanvasItem, radius: float, k: float) -> void:
	var r := radius * (0.5 + 0.9 * k)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	c.draw_circle(Vector2.ZERO, r + 3.0, Color(0.02, 0.01, 0.02, 0.85))
	c.draw_circle(Vector2.ZERO, r, Color(0.05, 0.03, 0.03, 0.9))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var n := 9
	for i in n:
		var ang := TAU * float(i) / float(n) + 0.4
		var p := Vector2(cos(ang), sin(ang)) * (r * 0.95 + 6.0)
		var p0 := Vector2(cos(ang), sin(ang)) * (r * 0.95 + 12.0 + 5.0 * (1.0 - k))
		c.draw_colored_polygon(PackedVector2Array([
			p + Vector2(-3.5, 1.5), p + Vector2(3.5, 1.5),
			(p + p0) * 0.5 + Vector2(0, -3.0)]), Color(0.16, 0.10, 0.08, 0.9 * k))

# 终局 Boss 装饰：金色尖刺环 + 双光环（缓慢旋转、外环脉动）
static func final_decor(c: CanvasItem, radius: float, phase: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0 + phase * 0.35
		pts.append(Vector2(cos(a), sin(a)) * (radius + (19.0 if i % 2 == 0 else 9.0)))
	c.draw_colored_polygon(pts, Color(1.0, 0.82, 0.28, 0.5))
	c.draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 28, col.lightened(0.4), 5.0, true)
	c.draw_arc(Vector2.ZERO, radius + 19.0 + 2.5 * sin(phase * 2.0), 0.0, TAU, 28,
		Color(1.0, 0.8, 0.25, 0.55), 3.0, true)
