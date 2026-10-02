extends RefCounted

# 厨房砧板地砖：战场铺成一块块拼接砧板，格子随镜头滚动给"在移动"的空间感。
# 纯绘制层：只画传入的可见范围 vis（已裁到竞技场内），格数 ~9x13，满屏不掉帧。
# 格子对齐竞技场左上角（14 x 21 块正好铺满，边缘不会溢出竞技场）。

const BASE_A := Color(0.416, 0.294, 0.204)
const BASE_B := Color(0.376, 0.259, 0.180)
const GROUT := Color(0.165, 0.110, 0.082)
const GRAIN_DARK := Color(0.255, 0.169, 0.121, 0.55)
const GRAIN_LIGHT := Color(0.553, 0.412, 0.290, 0.20)
const TOP_LIT := Color(1.0, 0.92, 0.80, 0.10)
const BOT_SHADE := Color(0.0, 0.0, 0.0, 0.20)

# 先铺一条深色砖缝底，再错位铺砧板块（块与块留 2px 缝露出底色），每块加上/下边做厚度
static func draw_tiles(c: CanvasItem, vis: Rect2, arena: Rect2, tile: float, grain: Array) -> void:
	c.draw_rect(vis.grow(4.0), GROUT)
	var cols := int(ceilf(arena.size.x / tile))
	var rows := int(ceilf(arena.size.y / tile))
	var i0 := maxi(0, int(floorf((vis.position.x - arena.position.x) / tile)))
	var j0 := maxi(0, int(floorf((vis.position.y - arena.position.y) / tile)))
	var i1 := mini(cols, int(ceilf((vis.end.x - arena.position.x) / tile)) + 1)
	var j1 := mini(rows, int(ceilf((vis.end.y - arena.position.y) / tile)) + 1)
	for j in range(j0, j1):
		var py := arena.position.y + float(j) * tile
		for i in range(i0, i1):
			var px := arena.position.x + float(i) * tile
			var odd := (i + j) & 1 == 1
			var r := Rect2(px + 1.0, py + 1.0, tile - 2.0, tile - 2.0)
			c.draw_rect(r, BASE_B if odd else BASE_A)
			c.draw_line(r.position, r.position + Vector2(r.size.x, 0.0), TOP_LIT, 1.6)
			c.draw_line(r.position + Vector2(0.0, r.size.y),
				r.position + Vector2(r.size.x, r.size.y), BOT_SHADE, 2.0)
	draw_grain(c, vis, grain)

# 木纹：世界坐标线段（ArenaFloor.setup 生成一次），逐条剔除可见范围外的
static func draw_grain(c: CanvasItem, vis: Rect2, grain: Array) -> void:
	var gvis := vis.grow(96.0)
	for g in grain:
		if g[0] < gvis.position.x or g[2] > gvis.end.x:
			continue
		if g[1] < gvis.position.y or g[3] > gvis.end.y:
			continue
		c.draw_line(Vector2(g[0], g[1]), Vector2(g[2], g[3]),
			GRAIN_DARK if g[4] == 0 else GRAIN_LIGHT, g[5])
