extends Control

# 补给站底部的"套装条"：五套各一枚徽章（套装色 + "刀工 3/4"），凑够档位的亮起来。
#
# 为什么必须有：套装是这一局 build 的骨架，但商店里每张卡只看得到自己的数值 ——
# 没有这行，玩家不知道"我再买一把刀就能到 4 件"，套装等于没上线（没人会去凑
# 看不见的东西）。Brotato 的套装能成为核心，就因为件数始终摆在眼前。
#
# 纯展示：数据由 Shop.gd 用 WeaponSets.progress 算好、翻译好灌进来。
# ⚠️ 不碰 I18n：--script 模式不注册 autoload，一引用就编译失败、连累单测。

const GAP := 6.0

var items: Array = []   # [{label, count, need, tier, color}]（已按件数降序）

func refresh(list: Array) -> void:
	items = list
	queue_redraw()

# n 枚徽章在宽 w 里横排的矩形（纯函数，单测锁"不溢出、不重叠、不除零"）
static func badges(n: int, w: float, h: float) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var bw := (w - float(n - 1) * GAP) / float(n)
	for i in n:
		out.append(Rect2(float(i) * (bw + GAP), 0.0, bw, h))
	return out

func _draw() -> void:
	if items.is_empty():
		return
	var bs := badges(items.size(), size.x, size.y)
	for i in items.size():
		_badge(bs[i], items[i] as Dictionary)

func _badge(r: Rect2, it: Dictionary) -> void:
	var col := Color(str(it.get("color", "#8a7a5a")))
	var on := int(it.get("tier", 0)) > 0
	_sb(Color(0.10, 0.09, 0.07, 0.85), col.lightened(0.30) if on else col.darkened(0.45),
		10.0, 2 if on else 1).draw(get_canvas_item(), r)
	# 两行：套装名在上（小字），件数/下一档在下（大字）。
	# 单行挤不下英文名（"Kitchenware 1/2" 会被截成 "Kitchenware 1/"），分两行就都放得下。
	var need := int(it.get("need", 0))
	var num := str(it.get("count", 0))
	if need > 0:
		num += "/" + str(need)
	var name_c := col.lightened(0.35) if on else Color(0.62, 0.60, 0.56, 0.9)
	_center(str(it.get("label", "")), Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)),
		9, name_c)
	_center(num, Rect2(r.position + Vector2(0, r.size.y * 0.42),
		Vector2(r.size.x, r.size.y * 0.58)), 13,
		Color(1.0, 0.92, 0.70) if on else Color(0.78, 0.74, 0.68, 0.95))

func _center(text: String, r: Rect2, fs: int, c: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > r.size.x - 8.0 and text.length() > 1:
		text = text.substr(0, text.length() - 1)
		w = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(r.position.x + (r.size.x - w) * 0.5,
		r.position.y + r.size.y * 0.5 + float(fs) * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _sb(bg: Color, border: Color, radius: float, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	sb.border_color = border
	sb.set_border_width_all(bw)
	return sb
