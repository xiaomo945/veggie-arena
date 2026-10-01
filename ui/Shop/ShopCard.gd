extends Control

# 商店单卡组件（哑组件）：只负责"把一份报价画得好看"，不含任何购买逻辑。
# 购买逻辑全在 Shop.gd（调 GameState / Inventory / Economy）。
# data 字段由 Shop.gd 预计算后通过 setup() 灌入，保证本组件保持轻量（架构守卫 300 行红线）。
#
# 配色统一走数值总表 §8.4：
#   武器合成等级角标 Lv1 灰 / Lv2 绿 / Lv3 蓝 / Lv4 紫
#   道具稀有度边框 rarity1 灰 / rarity2 蓝 / rarity3 紫
#   精英金圈 #ffd24a（此处作"选中/价格"点缀）

# ---- §8.4 配色 ----
const LV_COLORS := [Color(0.60,0.63,0.65), Color(0.44,0.81,0.44), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]
const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]
const GOLD := Color(1.0, 0.82, 0.29)
const CARD_BG := Color(0.13, 0.15, 0.21, 0.97)
const CARD_BG_DIM := Color(0.09, 0.10, 0.14, 0.92)
const BORDER_DIM := Color(0.35, 0.38, 0.45, 0.7)
const RED := Color(0.95, 0.42, 0.40)
const ICON_BOX := 60.0

var _d: Dictionary = {}
var _hover := false
var _font: Font
var on_click: Callable = Callable()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	I18n.locale_changed.connect(_on_locale_changed)

func setup(data: Dictionary) -> void:
	_d = data
	queue_redraw()

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_tap()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_tap()
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var h := get_local_rect().has_point(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()

func _tap() -> void:
	if _d.get("disabled", false) or _d.get("sold", false):
		return
	if on_click.is_valid():
		on_click.call()

func get_local_rect() -> Rect2:
	return Rect2(0, 0, size.x, size.y)

func _draw() -> void:
	if _font == null or _d.is_empty():
		return
	var r := get_local_rect()
	var disabled := bool(_d.get("disabled", false))
	var sold := bool(_d.get("sold", false))
	var afford := bool(_d.get("affordable", true))
	var dim := disabled or (not afford) or sold
	draw_rect(r, CARD_BG if not dim else CARD_BG_DIM)
	# 边框：武器=自身主色（Lv 角标另算）；道具=稀有度色
	var accent: Color = _d.get("accent", GOLD)
	var border := accent
	if disabled:
		border = RED
	elif not afford:
		border = Color(0.6, 0.5, 0.5, 0.9)
	draw_rect(r, border, false, 2.5 if not _hover else 4.0)

	# 左侧图标 / 稀有度宝石
	_draw_icon(r)

	# 名称（为右上角 Lv/稀有度角标预留 80px，避免文字压到角标）
	var tx := 14.0 + ICON_BOX + 10.0
	var name_c := Color(1,1,1,0.97) if not dim else Color(0.6,0.63,0.67,0.8)
	_center(_d.get("name", ""), tx, 20, 17, name_c, r.size.x - tx - 84.0)

	# 类型 + 状态标签
	var tag := str(_d.get("tag", ""))
	var tag_c := accent if not dim else Color(0.55,0.58,0.62,0.8)
	_center(tag, tx, 42, 12, tag_c, r.size.x - tx - 84.0)

	# 描述（按字符换行，最多 2 行，给底部价格留空间）
	var desc := str(_d.get("tip", ""))
	_draw_wrap(desc, tx, 62, 12, Color(0.72,0.75,0.80,0.95) if not dim else Color(0.5,0.53,0.57,0.7),
		r.size.x - tx - 14.0, 2)

	# 价格（右下，金币图标 + 数字；买不起/槽满标红）
	var price_c := RED if (not afford or disabled) else GOLD
	var pstr := str(_d.get("cost", 0))
	_draw_price(pstr, price_c)

	# Lv 角标（武器）或 稀有度 pips（道具）
	if str(_d.get("kind", "")) == "weapon":
		_draw_lv()
	else:
		_draw_rarity()

	# 已售出遮罩
	if sold:
		draw_rect(r, Color(0,0,0,0.5))
		_center(I18n.t("shop_sold"), r.size.x * 0.5, r.size.y * 0.5 + 8, 22, Color(1,1,1,0.9))

func _draw_icon(r: Rect2) -> void:
	var box := Rect2(14.0, (r.size.y - ICON_BOX) * 0.5, ICON_BOX, ICON_BOX)
	draw_rect(box, Color(0,0,0,0.35))
	var tex: Texture2D = _d.get("icon", null)
	var accent: Color = _d.get("accent", GOLD)
	if tex != null and tex is Texture2D:
		var s := ICON_BOX - 10.0
		draw_texture_rect_region(tex, Rect2(box.position.x + 5.0, box.position.y + 5.0, s, s),
			Rect2(Vector2.ZERO, (tex as Texture2D).get_size()))
	else:
		# 无图标（道具）：画一个稀有度/主色菱形宝石
		var c := box.position + box.size * 0.5
		var rad := ICON_BOX * 0.32
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)]),
			accent)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad*0.5), c + Vector2(rad*0.5, 0), c + Vector2(0, rad*0.5), c + Vector2(-rad*0.5, 0)]),
			Color(1,1,1,0.35))

func _draw_lv() -> void:
	var lv := int(_d.get("lv", 1))
	var ci := clampi(lv, 1, 4) - 1
	var col: Color = LV_COLORS[ci]
	var txt := "Lv %d" % lv
	var fs := 13
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 7.0
	var h := 22.0
	var x := size.x - tw - pad * 2 - 12.0
	var y := 12.0
	var rr := Rect2(x, y, tw + pad * 2, h)
	draw_rect(rr, col)
	_center(txt, rr.position.x + rr.size.x * 0.5, rr.position.y + h * 0.5 + fs * 0.35, fs, Color(0.06,0.07,0.09))

func _draw_rarity() -> void:
	var rar := clampi(int(_d.get("rarity", 1)), 1, 3)
	var col: Color = RARITY_COLORS[rar - 1]
	var pip := 9.0
	var gap := 4.0
	var total := float(rar) * pip + float(rar - 1) * gap
	var x0 := size.x - total - 12.0
	var y := 16.0
	for i in rar:
		draw_rect(Rect2(x0 + float(i) * (pip + gap), y, pip, pip), col)

func _draw_price(text: String, c: Color) -> void:
	var fs := 17
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var coin := Art.ui_icon("coin")
	var coin_s := 22.0
	var gap := 5.0
	var total := tw + gap + coin_s
	var x := size.x - 14.0 - total
	var y := size.y - 26.0
	if coin != null:
		draw_texture_rect_region(coin, Rect2(x, y - 1.0, coin_s, coin_s),
			Rect2(Vector2.ZERO, coin.get_size()))
	_center(text, x + coin_s + gap + tw * 0.5, y + fs * 0.35 + 2.0, fs, c)

func _draw_wrap(text: String, x0: float, y0: float, fs: int, c: Color, maxw: float, max_lines: int) -> void:
	var line := ""
	var lines := 0
	var i := 0
	while i < text.length() and lines < max_lines:
		var ch := text[i]
		var test := line + ch
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw and line != "":
			_center(line, x0 + maxw * 0.5, y0 + float(lines) * (fs + 4), fs, c)
			lines += 1
			line = ch
		else:
			line = test
		i += 1
	if line != "" and lines < max_lines:
		_center(line, x0 + maxw * 0.5, y0 + float(lines) * (fs + 4), fs, c)

func _center(text: String, cx: float, y: float, fs: int, c: Color, maxw := 9999.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > maxw and maxw < 9999.0:
		# 超宽截断，避免糊到邻区
		while w > maxw and text.length() > 1:
			text = text.substr(0, text.length() - 1)
			w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
