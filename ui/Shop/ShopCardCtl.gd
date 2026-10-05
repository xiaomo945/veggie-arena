extends RefCounted

# 商店单卡右上角的"单卡可控"小按钮（锁定 / 单张刷新）：度量 + 命中 + 绘制。
#
# 为什么单独成文件：卡片高度是【自适应】的（大商店 6 张时只有约 68px 高）。
# 固定的 30px 竖排会溢出卡片底部、还会压住价格药丸，所以布局必须跟着卡高变：
#   高卡（≥110px）：右上角竖排（避开顶部 Lv 角标）
#   矮卡（<110px）：右上角横排，缩到 22px，紧贴 Lv 角标下方
# ShopCard.gd 已贴架构守卫 300 行红线，装不下这套度量逻辑，故抽出。

const BTN_MAX := 30.0
const BTN_MIN := 22.0
const COMPACT_H := 110.0    # 低于这个卡高就切紧凑（横排）布局
const MARGIN := 8.0

static func btn_size(card_h: float) -> float:
	return BTN_MAX if card_h >= COMPACT_H else clampf(card_h * 0.30, BTN_MIN, BTN_MAX)

# 矮卡（大商店 6 张时约 68px）要砍掉描述行、缩小图标、把价格药丸挪到左侧，
# 否则文字会糊成一团并钻到按钮底下。
static func is_compact(card_h: float) -> bool:
	return card_h < COMPACT_H

static func icon_box(card_h: float) -> float:
	return 60.0 if card_h >= COMPACT_H else clampf(card_h - 16.0, 34.0, 60.0)

# 卡片区总高度固定（top~bottom）：卡多就变矮，卡少则封顶 max_h 并在区内垂直居中。
# 返回 [卡高, 第一张的 y]。抽成纯函数是为了能单测 —— 6 张卡时高度算错就会互相压住。
static func layout(n: int, top: float, bottom: float, gap: float, max_h: float) -> Array:
	var k := maxi(1, n)
	var total := maxf(0.0, bottom - top)
	var h := minf((total - gap * float(k - 1)) / float(k), max_h)
	var used := h * float(n) + gap * float(maxi(0, n - 1))
	return [h, top + maxf(0.0, (total - used) * 0.5)]

# [0]=锁定 [1]=单张刷新
static func rects(size: Vector2) -> Array:
	var b := btn_size(size.y)
	var gap := 6.0 if b >= 28.0 else 4.0
	var x := size.x - MARGIN - b
	if size.y >= COMPACT_H:
		var y0 := 44.0   # 让开顶部的 Lv 角标（y 12~34）
		return [Rect2(x, y0, b, b), Rect2(x, y0 + b + gap, b, b)]
	var y := 30.0
	return [Rect2(x - b - gap, y, b, b), Rect2(x, y, b, b)]

# ---- 价格药丸 ----
# 金底 + 币图标 + 数字；买不起/槽满换红底，一眼分清"买得起吗"。
# 高度收到 24px 并贴底 y=size.y-28：给描述行（y=60 起）让出垂直空间，二者不再叠
# （旧版 30px 高、y=size.y-30，100px 矮卡上会压住描述第一行）。
const PRICE_FS := 15
const PRICE_H := 24.0
const PRICE_COIN := 17.0

static func price_rect(size: Vector2, text_w: float, compact: bool, tx: float) -> Rect2:
	var w := PRICE_COIN + text_w + 18.0
	var px := (size.x - 14.0 - w) if not compact else tx
	var py := (size.y - 28.0) if not compact else (size.y - 34.0)
	return Rect2(px, py, w, PRICE_H)

static func draw_price(c: Control, size: Vector2, font: Font, cost: String, ok: bool,
		compact: bool, tx: float, gold: Color, coin: Texture2D) -> void:
	if font == null:
		return
	var tw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FS).x
	var rr := price_rect(size, tw, compact, tx)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.21, 0.06, 0.96) if ok else Color(0.28, 0.10, 0.08, 0.96)
	sb.set_corner_radius_all(14)
	sb.border_color = (Color(0.85, 0.66, 0.22) if ok else Color(0.95, 0.42, 0.40))
	sb.set_border_width_all(2)
	c.draw_style_box(sb, rr)
	if coin != null:
		c.draw_texture_rect_region(coin,
			Rect2(rr.position.x + 8.0, rr.position.y + 4.0, PRICE_COIN, PRICE_COIN),
			Rect2(Vector2.ZERO, coin.get_size()))
	_center(c, font, cost, rr.position.x + 8.0 + PRICE_COIN + 4.0 + tw * 0.5,
		rr.position.y + PRICE_H * 0.5 + PRICE_FS * 0.35, PRICE_FS,
		gold if ok else Color(1.0, 0.72, 0.66))

# ---- 道具兜底宝石 ----
# 道具没有专属贴图时画这颗切面宝石（比原来的纯色菱形更有"这是件装备"的分量）：
# 冠部亮 face + 亭部暗 face + 左上高光，外面套一圈深色 rim。
static func draw_gem(c: CanvasItem, box: Rect2, accent: Color) -> void:
	var ctr := box.position + box.size * 0.5
	var rad := box.size.y * 0.34
	var crown := PackedVector2Array([
		ctr + Vector2(-rad * 0.72, -rad * 0.38), ctr + Vector2(-rad * 0.44, -rad),
		ctr + Vector2(rad * 0.44, -rad), ctr + Vector2(rad * 0.72, -rad * 0.38)])
	var table := PackedVector2Array([
		ctr + Vector2(-rad * 0.44, -rad), ctr + Vector2(rad * 0.44, -rad),
		ctr + Vector2(rad * 0.34, -rad * 0.52), ctr + Vector2(-rad * 0.34, -rad * 0.52)])
	# 深色 rim（外扩一圈省一次描边 draw）
	var rim := PackedVector2Array([ctr + Vector2(-rad * 0.86, -rad * 0.46),
		ctr + Vector2(-rad * 0.52, -rad * 1.14), ctr + Vector2(rad * 0.52, -rad * 1.14),
		ctr + Vector2(rad * 0.86, -rad * 0.46), ctr + Vector2(0, rad * 1.12)])
	c.draw_colored_polygon(rim, accent.darkened(0.62))
	# 亭部（下半，压暗）+ 冠部
	c.draw_colored_polygon(PackedVector2Array([crown[0], crown[3], ctr + Vector2(0, rad)]),
		accent.darkened(0.18))
	c.draw_colored_polygon(crown, accent)
	# 台面 + 左上高光
	c.draw_colored_polygon(table, accent.lightened(0.22))
	c.draw_colored_polygon(PackedVector2Array([table[0], table[1],
		ctr + Vector2(rad * 0.16, -rad * 0.72), ctr + Vector2(-rad * 0.30, -rad * 0.70)]),
		Color(1, 1, 1, 0.40))

# 命中哪个：1=锁定 2=单张刷新 0=都不是（走购买）
static func hit(size: Vector2, p: Vector2) -> int:
	var r := rects(size)
	if (r[0] as Rect2).has_point(p):
		return 1
	if (r[1] as Rect2).has_point(p):
		return 2
	return 0

static func draw(c: Control, size: Vector2, d: Dictionary, font: Font) -> void:
	if font == null:
		return
	var rs := rects(size)
	var locked := bool(d.get("locked", false))
	var lc := Color(0.99, 0.84, 0.35, 0.95) if locked else Color(0.62, 0.63, 0.66, 0.55)
	var r0 := rs[0] as Rect2
	var r1 := rs[1] as Rect2
	# 锁定：锁上时金色实心 + 锁梁，未锁时空心灰
	c.draw_rect(r0, Color(0.10, 0.08, 0.06, 0.85), true)
	c.draw_rect(r0, lc, false, 2.0)
	var c0 := r0.get_center()
	c.draw_rect(Rect2(c0.x - 7.0, c0.y - 1.0, 14.0, 10.0), lc, true)
	c.draw_arc(Vector2(c0.x, c0.y - 1.0), 5.0, PI, TAU, 10, lc, 2.2, true)
	# 单张刷新：圆弧箭头 + 价格（花更少的钱只换这一张）
	c.draw_rect(r1, Color(0.10, 0.08, 0.06, 0.85), true)
	c.draw_rect(r1, Color(0.55, 0.80, 0.95, 0.7), false, 2.0)
	var c1 := r1.get_center()
	c.draw_arc(c1, 7.0, -2.2, 2.2, 12, Color(0.72, 0.90, 1.0, 0.95), 2.4, true)
	c.draw_line(c1 + Vector2(6.4, -4.4), c1 + Vector2(9.6, -7.6), Color(0.72, 0.90, 1.0, 0.95), 2.4)
	var rc := int(d.get("reroll_one_cost", 0))
	if rc > 0:
		_center(c, font, "%d" % rc, c1.x, c1.y + 11.0, 10, Color(0.72, 0.90, 1.0, 0.9))

static func _center(c: Control, font: Font, text: String, cx: float, y: float,
		fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
