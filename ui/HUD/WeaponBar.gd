extends Node2D

# HUD 武器槽：一眼看出"我带了哪几把、几级、各是什么打法"。
#
# 为什么单独拆出来：以前武器槽只是 HudBars 里 20 行的一小段，
# 加了 behavior（光束 / 脉冲 / 链式 / 回旋 / 制导）之后，"每把武器画成什么样"
# 变成了一整套符文绘制，塞回 HudBars 会把它顶到红线，而且血条和武器槽
# 本来就不是一个东西 —— 血条看数值，武器槽看"打法"。
#
# 职责边界（和 HudBars 一样是"哑组件"）：只认一个 slots 数组，不订阅 Events，
# 不认识 Player / Game。数据由 HUD.gd 塞进来，塞什么画什么。

var slots: Array = []    # [{key, lv, color, name, behavior}]

# 位置与 HudBars 的旧槽位完全一致（顶部 HUD 区右侧，避开左边的心/金币/波次文字）
const SLOT_SIZE := 32.0
const SLOT_GAP := 6.0
const SLOT_Y := 30.0
const SLOT_RIGHT := 528.0

const INK := Color(0.05, 0.04, 0.08, 0.92)
const LIT := Color(1.0, 1.0, 1.0, 0.95)

func _draw() -> void:
	if slots.is_empty():
		return
	var n := slots.size()
	var total_w := float(n) * SLOT_SIZE + float(n - 1) * SLOT_GAP
	var x0 := SLOT_RIGHT - total_w
	for i in n:
		if not (slots[i] is Dictionary):
			continue
		_draw_slot(x0 + float(i) * (SLOT_SIZE + SLOT_GAP), SLOT_Y, slots[i])

func _draw_slot(x: float, y: float, s: Dictionary) -> void:
	var c: Color = s.get("color", Color(1, 1, 1))
	var beh := str(s.get("behavior", "projectile"))
	# 凹槽：深色底 + 暖色描边（和背包格一套视觉语言）
	_round(x, y, SLOT_SIZE, SLOT_SIZE, Color(0.04, 0.04, 0.06, 0.62),
		Color(0.34, 0.27, 0.16), 2, 8.0)
	# 武器色本体：上半原色、下半压暗，卡通塑料的体积感
	var inset := 2.0
	var iw := SLOT_SIZE - inset * 2.0
	_round(x + inset, y + inset, iw, iw, c, Color(0, 0, 0, 0.0), 0, 6.0)
	_round(x + inset, y + SLOT_SIZE * 0.52, iw, SLOT_SIZE * 0.48 - inset,
		c.darkened(0.30), Color(0, 0, 0, 0.0), 0, 6.0)
	# 行为符文：不用看名字也知道这把"怎么打"
	_rune(x + SLOT_SIZE * 0.5, y + SLOT_SIZE * 0.44, SLOT_SIZE * 0.30, beh)
	# 等级点：右下角，一颗代表一级
	_pips(x, y, int(s.get("lv", 1)))

func _pips(x: float, y: float, lv: int) -> void:
	var n := clampi(lv, 1, 4)
	var w := float(n) * 6.0
	var px := x + (SLOT_SIZE - w) * 0.5 + 3.0
	var py := y + SLOT_SIZE - 6.0
	for k in n:
		draw_circle(Vector2(px + float(k) * 6.0, py), 3.0, INK)
		draw_circle(Vector2(px + float(k) * 6.0, py), 2.0, LIT)

# ---- 行为符文 ----
# 每个符文都画两遍：先粗的暗描边、再细的亮线 —— 武器底色花花绿绿，
# 纯白符文在亮色武器上会糊掉，暗描边保证在任何底色上都读得出来。
func _rune(cx: float, cy: float, r: float, beh: String) -> void:
	match beh:
		"beam":
			# 一条贯穿的直线：瞬发光束
			draw_line(Vector2(cx - r * 1.5, cy), Vector2(cx + r * 1.5, cy), INK, 5.0)
			draw_line(Vector2(cx - r * 1.5, cy), Vector2(cx + r * 1.5, cy), LIT, 2.4)
		"chain":
			# 折线闪电：命中后跳到下一只
			var pts := PackedVector2Array([
				Vector2(cx - r, cy - r), Vector2(cx - r * 0.1, cy - r * 0.15),
				Vector2(cx - r * 0.55, cy + r * 0.2), Vector2(cx + r * 0.9, cy + r)])
			draw_polyline(pts, INK, 5.0)
			draw_polyline(pts, LIT, 2.2)
		"boomerang":
			# 一段圆弧 + 端点：飞出去还会拐回来
			draw_arc(Vector2(cx, cy), r * 1.05, -2.2, 1.0, 14, INK, 4.6, true)
			draw_arc(Vector2(cx, cy), r * 1.05, -2.2, 1.0, 14, LIT, 2.0, true)
			draw_circle(Vector2(cx + r * 0.45, cy - r * 0.95), r * 0.26, INK)
			draw_circle(Vector2(cx + r * 0.45, cy - r * 0.95), r * 0.16, LIT)
		"homing":
			# 螺旋尾 + 头：自己会拐弯咬住目标
			draw_arc(Vector2(cx - r * 0.35, cy + r * 0.4), r * 1.15, 2.4, 5.0, 12, INK, 4.2, true)
			draw_arc(Vector2(cx - r * 0.35, cy + r * 0.4), r * 1.15, 2.4, 5.0, 12, LIT, 1.8, true)
			draw_circle(Vector2(cx + r * 0.6, cy - r * 0.5), r * 0.42, INK)
			draw_circle(Vector2(cx + r * 0.6, cy - r * 0.5), r * 0.28, LIT)
		"pulse":
			# 两圈同心环：以自己为心炸一圈
			draw_arc(Vector2(cx, cy), r * 1.25, 0.0, TAU, 16, INK, 3.6, true)
			draw_arc(Vector2(cx, cy), r * 1.25, 0.0, TAU, 16, LIT, 1.6, true)
			draw_arc(Vector2(cx, cy), r * 0.58, 0.0, TAU, 12, INK, 3.4, true)
			draw_arc(Vector2(cx, cy), r * 0.58, 0.0, TAU, 12, LIT, 1.5, true)
		"melee":
			# 三角刀刃：贴身挥砍
			var pts := PackedVector2Array([
				Vector2(cx + r * 1.1, cy - r * 1.1), Vector2(cx - r * 0.9, cy - r * 0.2),
				Vector2(cx - r * 0.35, cy + r * 1.05)])
			draw_colored_polygon(pts, INK)
			draw_colored_polygon(_shrink(pts, 0.34), LIT)
		_:
			# 普通弹：一颗弹头 + 短尾迹
			draw_line(Vector2(cx - r * 1.3, cy), Vector2(cx - r * 0.15, cy), INK, 4.0)
			draw_circle(Vector2(cx + r * 0.45, cy), r * 0.56, INK)
			draw_circle(Vector2(cx + r * 0.45, cy), r * 0.36, LIT)

# 多边形朝重心缩一圈（给实心符文留一圈暗边）
func _shrink(pts: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(maxi(pts.size(), 1))
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * (1.0 - k))
	return out

func _round(x: float, y: float, w: float, h: float, fill: Color, frame: Color, bw: int, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(rad))
	if frame.a > 0.001:
		sb.border_color = frame
		sb.set_border_width_all(bw)
	draw_style_box(sb, Rect2(x, y, w, h))
