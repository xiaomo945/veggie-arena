extends RefCounted

# 竞技场边界：卡通描边的"灶台不锈钢包边"。
# 出了砧板就是深色厨房地面，包边让地图读起来是"一块有边界的战场"，
# 不再是无限黑。全部 draw_* 代码绘制。

const STEEL_L := Color(0.716, 0.745, 0.788)
const STEEL_M := Color(0.502, 0.533, 0.580)
const STEEL_D := Color(0.278, 0.298, 0.333)
const INK := Color(0.086, 0.078, 0.094)
const SHADOW := Color(0.0, 0.0, 0.0, 0.30)

const BAND := 15.0        # 钢边带宽
const RIVET_STEP := 88.0  # 铆钉间距（稀疏一点：每帧都要随地面重画，省不少 draw call）

# ⚠️ 包边全部画在场地【内侧】，不是外侧。
#   镜头贴边后"屏幕边 = 场地边"，画在外侧的部分会被裁到屏幕外（用户实测：边框整条消失）。
#   从边界往里依次是：ink 外沿 → 钢带（亮上暗下）→ ink 内沿 → 砧板内侧投影 → 铆钉。
static func draw_rim(c: CanvasItem, arena: Rect2) -> void:
	if not _near_edge(c, arena):
		return
	_band(c, arena, INK, 4.0)                    # 外沿描边（贴着边界往里 4px）
	var m := arena.grow(-4.0)
	_band(c, m, STEEL_M, BAND)                   # 钢带本体
	_edge_line(c, m.grow(-1.5), STEEL_L, 2.4)    # 上缘高光
	var inner := m.grow(-BAND)
	_edge_line(c, inner.grow(1.5), STEEL_D, 2.0) # 下缘暗边
	_band(c, inner, INK, 2.0)                    # 内描边
	_shadow_band(c, inner.grow(-2.0))            # 砧板内侧投影（往里 11px）
	_rivets(c, arena)

# 只在镜头看得见任一边时才画（视野中心到边界的距离 < 半屏 + 带宽）
static func _near_edge(c: CanvasItem, arena: Rect2) -> bool:
	var view: Vector2 = c.get_viewport_rect().size
	var cam := _cam(c)
	var half := view * 0.5 + Vector2(BAND + 8.0, BAND + 8.0)
	var vis := Rect2(cam - half, half * 2.0)
	return vis.intersects(arena.grow(BAND + 6.0))

static func _cam(c: CanvasItem) -> Vector2:
	var vp := c.get_viewport()
	if vp != null:
		var cam := vp.get_camera_2d()
		if cam != null:
			return cam.get_screen_center_position()
	return Vector2.ZERO

# 四条边各画一条矩形，厚度 t，方向恒为【往里】（画到角上互相覆盖，反正同色）
static func _band(c: CanvasItem, r: Rect2, col: Color, t: float = BAND + 3.0) -> void:
	c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, t), col)
	c.draw_rect(Rect2(r.position.x, r.end.y - t, r.size.x, t), col)
	c.draw_rect(Rect2(r.position.x, r.position.y, t, r.size.y), col)
	c.draw_rect(Rect2(r.end.x - t, r.position.y, t, r.size.y), col)

# 沿矩形四边走一圈细线（用 polyline，四段各画）
static func _edge_line(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var d := r.end
	var e := Vector2(r.position.x, r.end.y)
	c.draw_line(a, b, col, w)
	c.draw_line(b, d, col, w)
	c.draw_line(d, e, col, w)
	c.draw_line(e, a, col, w)

# 内侧投影：只画"贴边的一条暗带"，四边各一条，中间不挡
static func _shadow_band(c: CanvasItem, r: Rect2) -> void:
	var t := 11.0
	c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, t), SHADOW)
	c.draw_rect(Rect2(r.position.x, r.end.y - t, r.size.x, t), SHADOW)
	c.draw_rect(Rect2(r.position.x, r.position.y, t, r.size.y), SHADOW)
	c.draw_rect(Rect2(r.end.x - t, r.position.y, t, r.size.y), SHADOW)

# 铆钉：钢带上一颗颗小圆钉（亮面 + 暗底），让包边读起来是金属而不是色条
static func _rivets(c: CanvasItem, arena: Rect2) -> void:
	# 铆钉走在钢带中线：钢带现在是往里 4 ~ 4+BAND，所以中线是往里 4 + BAND*0.5
	var mid := arena.grow(-4.0 - BAND * 0.5)
	var cam := _cam(c)
	var view := c.get_viewport_rect().size
	var half := view * 0.5 + Vector2(24.0, 24.0)
	var vis := Rect2(cam - half, half * 2.0)
	_row(c, Vector2(mid.position.x, mid.position.y), Vector2(0, 1), arena.size.y, vis)
	_row(c, Vector2(mid.end.x, mid.position.y), Vector2(0, 1), arena.size.y, vis)
	_row(c, Vector2(mid.position.x, mid.position.y), Vector2(1, 0), arena.size.x, vis)
	_row(c, Vector2(mid.position.x, mid.end.y), Vector2(1, 0), arena.size.x, vis)

static func _row(c: CanvasItem, from: Vector2, dir: Vector2, ln: float, vis: Rect2) -> void:
	var d := Vector2(dir.x, dir.y) * RIVET_STEP
	var p := from
	var n := int(ln / RIVET_STEP)
	for i in n + 1:
		if vis.has_point(p):
			c.draw_circle(p + Vector2(0.8, 1.2), 3.4, INK)
			c.draw_circle(p, 2.6, STEEL_L)
			c.draw_circle(p - Vector2(0.8, 0.9), 1.1, Color(1, 1, 1, 0.85))
		p += d
