extends RefCounted

# 敌人卡通造型（缺贴图时的兜底 + 终局 Boss 装饰）。
# 从 Enemy.gd 拆出来：那边顶着 300 行红线，要给"出场升起"动画腾地方。
# 全是静态绘制函数：参数显式传入（不读调用方私有字段，架构守卫 R3）。
#
# 卡通贴纸风四件套（这次美化统一上身，之前是纯色多边形，很平很丑）：
#   1) 厚描边  —— poly() 里 1.14 倍暗色底，轮廓更墩实
#   2) 底部阴影 —— _shade() 压暗下半身，立刻有体积
#   3) 顶部高光 —— _gloss() 左上一块反光，果冻/塑料质感
#   4) 专属小装饰 —— 犄角/引线/炮口/叶片/缝合线…，一眼认出是谁
# 手绘兜底主要服务：swarm/brute/shambler/shooter/charger/splitter/bomber/splitling

const OUTLINE := Color(0.18, 0.10, 0.12, 1.0)

# ---- 怒萌脸：怒眼 + 斜眉 + 龇牙，所有怪物共用 ----
# 这次加了瞳孔高光（卡通眼）和腮红，比原来"两个黑点"精神多了
static func angry_face(c: CanvasItem, sz: float, look: Vector2, alpha: float) -> void:
	var ex := sz * 0.40
	var ey := -sz * 0.16
	for sgn in [-1, 1]:
		var x: float = sgn * ex + look.x * sz * 0.10
		var y: float = ey + look.y * sz * 0.08
		# 腮红（先画，压在眼下）
		c.draw_set_transform(Vector2(x, y + sz * 0.34), 0.0, Vector2(1.0, 0.62))
		c.draw_circle(Vector2.ZERO, sz * 0.17, Color(1.0, 0.45, 0.42, alpha * 0.35))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 眼白 + 瞳孔 + 高光
		c.draw_circle(Vector2(x, y), sz * 0.24, Color(1, 1, 1, alpha))
		var px: float = x + look.x * sz * 0.07
		var py: float = y + look.y * sz * 0.05
		c.draw_circle(Vector2(px, py), sz * 0.13, Color(0.12, 0.10, 0.10, alpha))
		c.draw_circle(Vector2(px - sz * 0.05, py - sz * 0.05), sz * 0.05,
			Color(1, 1, 1, alpha * 0.9))
		# 斜眉（越靠内越低 = 越凶）
		var b0 := Vector2(x - sz * 0.32, y - sz * 0.40)
		var b1 := Vector2(x + sz * 0.30, y - sz * 0.14)
		if sgn < 0:
			b0 = Vector2(x + sz * 0.32, y - sz * 0.40)
			b1 = Vector2(x - sz * 0.30, y - sz * 0.14)
		c.draw_line(b0, b1, Color(0.12, 0.10, 0.10, alpha), maxf(1.6, sz * 0.11))
	# 龇牙嘴
	var my := sz * 0.46
	c.draw_line(Vector2(-sz * 0.5, my), Vector2(sz * 0.5, my),
		Color(0.12, 0.10, 0.10, alpha), maxf(1.6, sz * 0.11))
	for k in range(-2, 3):
		var tx := float(k) * sz * 0.22
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(tx - sz * 0.085, my), Vector2(tx + sz * 0.085, my),
			Vector2(tx, my + sz * 0.22)]), Color(1, 1, 1, alpha))

# ---- 卡通体积：底部阴影 + 顶部高光 ----
static func _shade(c: CanvasItem, radius: float) -> void:
	c.draw_set_transform(Vector2(0.0, radius * 0.44), 0.0, Vector2(1.0, 0.5))
	c.draw_circle(Vector2.ZERO, radius * 0.80, Color(0.05, 0.02, 0.04, 0.20))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _gloss(c: CanvasItem, radius: float) -> void:
	c.draw_set_transform(Vector2(-radius * 0.30, -radius * 0.40), 0.0, Vector2(1.0, 0.60))
	c.draw_circle(Vector2.ZERO, radius * 0.28, Color(1.0, 1.0, 1.0, 0.34))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 落地阴影：脚下软椭圆（与 Boss 出场的土坑区分——这是"站在地上"的投影）。
# 用显式多边形点画，不碰 draw_set_transform，所以无论被调用时本体处于
# squash/rise 的什么变换下都不会打乱后续绘制，也不会被缩放乱跑。
static func ground_shadow(c: CanvasItem, radius: float) -> void:
	var cy := radius * 0.95
	var outer := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		outer.append(Vector2(cos(a) * radius * 0.95, cy + sin(a) * radius * 0.27))
	c.draw_colored_polygon(outer, Color(0.0, 0.0, 0.0, 0.13))
	var inner := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		inner.append(Vector2(cos(a) * radius * 0.72, cy + sin(a) * radius * 0.20))
	c.draw_colored_polygon(inner, Color(0.0, 0.0, 0.0, 0.22))

# 多边形 + 厚暗色描边 + 内侧亮边（卡通贴纸感 + 果冻感 rim light）
static func poly(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var out := PackedVector2Array()
	var rim := PackedVector2Array()
	for p in pts:
		out.append(p * 1.16)
		rim.append(p * 1.11)
	c.draw_colored_polygon(out, OUTLINE)
	c.draw_colored_polygon(rim, col.lightened(0.55))
	c.draw_colored_polygon(pts, col)

# ---- 凶萌造型：每种怪一个形状 + 专属装饰 ----
static func body(c: CanvasItem, etype: String, radius: float, col: Color) -> void:
	ground_shadow(c, radius)   # 先画脚下投影，本体随后压在上面
	var look := Vector2(0.0, 0.2)
	match etype:
		"fast":
			poly(c, PackedVector2Array([
				Vector2(0, -radius * 1.25), Vector2(radius * 0.95, radius * 0.75),
				Vector2(-radius * 0.95, radius * 0.75)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 冲刺残影小尾巴
			c.draw_line(Vector2(-radius * 0.5, radius * 0.2), Vector2(-radius * 1.1, radius * 0.5),
				Color(1, 1, 1, 0.45), maxf(1.6, radius * 0.12))
			angry_face(c, radius * 0.95, look, 1.0)
		"tank":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := TAU * float(i) / 6.0 - PI * 0.5
				pts.append(Vector2(cos(a), sin(a)) * radius)
			poly(c, pts, col)
			_shade(c, radius); _gloss(c, radius)
			# 铆钉装甲带
			for i in 4:
				var rx: float = -radius * 0.6 + float(i) * radius * 0.4
				c.draw_circle(Vector2(rx, radius * 0.62), radius * 0.09,
					Color(0.25, 0.14, 0.18, 0.8))
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
			_shade(c, radius); _gloss(c, radius)
			# 触角
			for s in [-1, 1]:
				c.draw_line(Vector2(float(s) * radius * 0.18, -radius * 1.15),
					Vector2(float(s) * radius * 0.42, -radius * 1.62),
					OUTLINE, maxf(1.4, radius * 0.1))
				c.draw_circle(Vector2(float(s) * radius * 0.42, -radius * 1.66),
					radius * 0.10, Color(1.0, 0.9, 0.3, 0.95))
			angry_face(c, radius * 0.6, look, 1.0)
		"boss":
			var sp := PackedVector2Array()
			for i in range(24):
				var a2 := TAU * float(i) / 24.0
				sp.append(Vector2(cos(a2), sin(a2)) * radius * (0.62 if i % 2 == 0 else 1.0))
			poly(c, sp, col)
			_shade(c, radius); _gloss(c, radius)
			angry_face(c, radius * 0.92, look, 1.0)
		"swarm":
			poly(c, PackedVector2Array([Vector2(-radius,0), Vector2(0,-radius),
				Vector2(radius,0), Vector2(0,radius)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 小细腿（虫群感）
			for s in [-1, 1]:
				c.draw_line(Vector2(float(s) * radius * 0.45, radius * 0.55),
					Vector2(float(s) * radius * 0.85, radius * 1.05),
					OUTLINE, maxf(1.4, radius * 0.1))
			angry_face(c, radius * 0.9, look, 1.0)
		"brute":
			poly(c, PackedVector2Array([Vector2(-radius,-radius*0.9), Vector2(radius,-radius*0.9),
				Vector2(radius,radius*0.9), Vector2(-radius,radius*0.9)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 肩甲尖刺
			for s in [-1, 1]:
				c.draw_colored_polygon(PackedVector2Array([
					Vector2(float(s) * radius * 0.55, -radius * 0.9),
					Vector2(float(s) * radius * 1.0, -radius * 1.45),
					Vector2(float(s) * radius * 1.05, -radius * 0.75)]), OUTLINE)
			c.draw_arc(Vector2.ZERO, radius * 1.25, 0.0, TAU, 6, Color(0.2, 0.1, 0.14, 0.5), 3.0, true)
			angry_face(c, radius * 0.9, look, 1.0)
		"shambler":
			poly(c, PackedVector2Array([Vector2(-radius,-radius*0.8), Vector2(-radius*0.7,-radius),
				Vector2(radius*0.7,-radius), Vector2(radius,-radius*0.8),
				Vector2(radius,radius), Vector2(-radius,radius)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 缝合线（丧尸感）
			c.draw_line(Vector2(-radius * 0.8, -radius * 0.15), Vector2(radius * 0.8, -radius * 0.15),
				Color(0.1, 0.08, 0.1, 0.85), maxf(1.4, radius * 0.09))
			for i in 4:
				var sx: float = -radius * 0.55 + float(i) * radius * 0.37
				c.draw_line(Vector2(sx, -radius * 0.32), Vector2(sx, radius * 0.02),
					Color(0.1, 0.08, 0.1, 0.85), maxf(1.2, radius * 0.07))
			angry_face(c, radius * 0.9, look, 1.0)
		"charger":
			poly(c, PackedVector2Array([Vector2(0,-radius*1.3), Vector2(radius*1.05,radius*0.9),
				Vector2(radius*0.5,radius*0.7), Vector2(-radius*0.5,radius*0.7),
				Vector2(-radius*1.05,radius*0.9)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 速度线 + 双角（"要撞过来了"）
			for i in 3:
				var yy: float = -radius * 0.1 + float(i) * radius * 0.42
				c.draw_line(Vector2(-radius * 1.35, yy), Vector2(-radius * 1.75, yy),
					Color(1, 1, 1, 0.5), maxf(1.4, radius * 0.1))
			for s in [-1, 1]:
				c.draw_colored_polygon(PackedVector2Array([
					Vector2(float(s) * radius * 0.35, -radius * 1.0),
					Vector2(float(s) * radius * 0.78, -radius * 1.62),
					Vector2(float(s) * radius * 0.62, -radius * 0.92)]), OUTLINE)
			angry_face(c, radius * 0.85, look, 1.0)
		"shooter":
			var so := PackedVector2Array()
			for i in range(8):
				var a := TAU * float(i) / 8.0
				so.append(Vector2(cos(a), sin(a)) * radius)
			poly(c, so, col)
			_shade(c, radius); _gloss(c, radius)
			# 炮口 + 蓄能光点（朝玩家）
			var mz: Vector2 = look * radius * 0.95
			c.draw_circle(mz, radius * 0.30, Color(0.12, 0.10, 0.12, 0.85))
			c.draw_circle(mz, radius * 0.17, Color(0.85, 0.6, 1.0, 0.9))
			angry_face(c, radius * 0.70, look, 1.0)
		"splitter":
			poly(c, PackedVector2Array([Vector2(-radius,-radius*0.9), Vector2(radius,-radius*0.9),
				Vector2(radius,radius*0.9), Vector2(-radius,radius*0.9)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 中缝：虚线（暗示"一分为二"）
			for i in 6:
				var sy: float = -radius * 0.75 + float(i) * radius * 0.3
				c.draw_line(Vector2(0, sy), Vector2(0, sy + radius * 0.16),
					Color(0.12, 0.10, 0.12, 0.85), maxf(1.5, radius * 0.12))
			angry_face(c, radius * 0.9, look, 1.0)
		"bomber":
			poly(c, PackedVector2Array([Vector2(-radius*0.95,0), Vector2(0,-radius),
				Vector2(radius*0.95,0), Vector2(0,radius*0.95)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 引线 + 火花（"我马上炸"）
			c.draw_line(Vector2(0,-radius), Vector2(0,-radius*1.4),
				Color(0.3,0.2,0.1,0.9), maxf(1.6, radius*0.12))
			c.draw_circle(Vector2(0,-radius*1.5), radius*0.18, Color(1.0,0.8,0.3,1.0))
			c.draw_circle(Vector2(0,-radius*1.5), radius*0.32, Color(1.0,0.55,0.2,0.35))
			angry_face(c, radius * 0.7, look, 1.0)
		"splitling":
			poly(c, PackedVector2Array([Vector2(-radius,0), Vector2(0,-radius),
				Vector2(radius,0), Vector2(0,radius)]), col)
			_shade(c, radius); _gloss(c, radius)
			# 头顶两片小嫩叶（"刚分出来的芽"）
			for s in [-1, 1]:
				c.draw_colored_polygon(PackedVector2Array([
					Vector2(0.0, -radius * 0.95),
					Vector2(float(s) * radius * 0.62, -radius * 1.55),
					Vector2(float(s) * radius * 0.18, -radius * 0.85)]), Color(0.45, 0.85, 0.35, 0.95))
			angry_face(c, radius * 0.8, look, 1.0)
		_:
			# 小兵：圆身 + 两只小角 + 凶萌脸
			poly(c, PackedVector2Array([Vector2(-radius*0.4,-radius*0.9),
				Vector2(-radius*0.1,-radius*1.25), Vector2(-radius*0.05,-radius*0.9)]), col)
			poly(c, PackedVector2Array([Vector2(radius*0.4,-radius*0.9),
				Vector2(radius*0.1,-radius*1.25), Vector2(radius*0.05,-radius*0.9)]), col)
			poly(c, PackedVector2Array([Vector2(-radius,0), Vector2(radius,0),
				Vector2(radius*0.85,radius), Vector2(0,radius*1.15),
				Vector2(-radius*0.85,radius)]), col)
			_shade(c, radius); _gloss(c, radius)
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
