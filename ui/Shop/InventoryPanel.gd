extends Control

# 补给站里的"我的武器"小条：把当前持有的武器画成一格格芯片，每格底部一个"售 N"按钮。
# 纯展示 + 点击售出，不碰玩法状态（售出逻辑在 Shop.gd 的 _sell）。

const Art := preload("res://autoload/Art.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")

signal sell_requested(index: int)

# 分级配色（与 ShopCard 一致：白1/绿2/蓝3/紫4/红5/传说6）
const LV_COLORS := [Color(0.85,0.86,0.90), Color(0.25,0.77,0.32), Color(0.18,0.55,1.0),
	Color(0.63,0.29,1.0), Color(1.0,0.30,0.24), Color(1.0,0.71,0.12)]
const GOLD := Color(1.0, 0.82, 0.29)
const CHIP_GAP := 6.0
const TITLE_H := 16.0

var _weapons: Array = []
var _max_lv := 4
var _font: Font
var _sell_rects: Array = []   # [{rect, idx}] 每格"售"按钮的局部矩形，用于点击命中

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func refresh(weapons: Array, max_lv: int) -> void:
	_weapons = weapons
	_max_lv = max_lv
	queue_redraw()

func _draw() -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(0, TITLE_H - 3), I18n.t("shop_myweapons"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.78, 0.55))
	_sell_rects = []
	var n := _weapons.size()
	if n == 0:
		draw_string(_font, Vector2(2, TITLE_H + 28), I18n.t("shop_new"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.6))
		return
	var gap := CHIP_GAP
	var cw := mini((size.x - float(maxi(1, n - 1)) * gap) / float(maxi(1, n)), 78.0)
	var y := TITLE_H + 2.0
	var ch := size.y - TITLE_H - 2.0
	var x := 0.0
	for i in n:
		var w = _weapons[i]
		if w is Dictionary:
			_draw_chip(w, Rect2(x, y, cw, ch), i)
		x += cw + gap

func _draw_chip(w: Dictionary, rect: Rect2, idx: int) -> void:
	var lv := int(w.get("lv", 1))
	var accent: Color = LV_COLORS[clampi(lv, 1, 6) - 1]
	draw_style_box(_sb(Color(0.16, 0.12, 0.07, 0.97), accent, 8.0, 2), rect)
	# 武器图标
	var tex: Texture2D = Art.icon("weapon_" + str(w.get("key", "")))
	if tex != null and tex is Texture2D:
		var s := mini(rect.size.y - 28.0, rect.size.x - 8.0)
		draw_texture_rect_region(tex, Rect2(rect.position.x + 4.0, rect.position.y + 4.0, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
	# Lv 角标
	var lvtxt := "Lv%d" % lv
	var fs := 11
	var tw := _font.get_string_size(lvtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lr := Rect2(rect.position.x + rect.size.x - tw - 8.0, rect.position.y + 3.0, tw + 6.0, 15.0)
	draw_style_box(_sb(accent.darkened(0.3), accent, 5.0, 1), lr)
	draw_string(_font, Vector2(lr.position.x + 3.0, lr.position.y + 12.0), lvtxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.06, 0.07, 0.09))
	# 售按钮（底部整条）
	var sv := ShopTiers.new().sell_price(int(w.get("buy_cost", 0)))
	var sb_rect := Rect2(rect.position.x + 3.0, rect.position.y + rect.size.y - 19.0, rect.size.x - 6.0, 16.0)
	draw_style_box(_sb(Color(0.30, 0.18, 0.06, 0.98), Color(0.85, 0.66, 0.22), 6.0, 1), sb_rect)
	draw_string(_font, Vector2(rect.position.x + rect.size.x * 0.5, sb_rect.position.y + 12.0),
		I18n.t("shop_sell") + "%d" % sv, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, GOLD)
	_sell_rects.append({"rect": sb_rect, "idx": idx})

func _sb(bg: Color, border: Color, radius: float, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.set_corner_radius_all(int(radius)); sb.border_color = border; sb.set_border_width_all(bw)
	return sb

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_tap((event as InputEventScreenTouch).position)
		accept_event(); return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_tap(mb.position)
		accept_event(); return

func _tap(pos: Vector2) -> void:
	for e in _sell_rects:
		if (e["rect"] as Rect2).has_point(pos):
			sell_requested.emit(int(e["idx"]))
			return
