extends Control

# 补给站里的"我的武器"格子条：固定画 max_slot 个方格（默认 6），一眼看得出还剩几个空位。
#   · 空格   —— 暗色虚位 + 一个淡淡的"+"，明确"这里还能放一把"
#   · 有武器 —— 分级描边（白1/绿2/蓝3/紫4/红5/传说6）+ 图标 + Lv 角标 + 底部"售 N"按钮
#   · 可合成 —— 场上存在另一把"同 key 同等级"时，两格同时亮金边 + 左上角"合"角标，
#                点其中一格 → 另一把被吸进来并消失、本格升一级（用户拍板的合成手感）
# 本组件只做展示与点击派发；售出/合成的真实状态改动都在 Shop.gd。

const Art := preload("res://autoload/Art.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const Inventory := preload("res://core/Inventory.gd")

signal sell_requested(index: int)
signal merge_requested(index: int)

# 分级配色（与 ShopCard 一致：白1/绿2/蓝3/紫4/红5/传说6）
const LV_COLORS := [Color(0.85,0.86,0.90), Color(0.25,0.77,0.32), Color(0.18,0.55,1.0),
	Color(0.63,0.29,1.0), Color(1.0,0.30,0.24), Color(1.0,0.71,0.12)]
const GOLD := Color(1.0, 0.82, 0.29)
const GAP := 6.0
const TITLE_H := 16.0
const EMPTY_BG := Color(0.10, 0.09, 0.07, 0.50)
const EMPTY_BD := Color(0.40, 0.36, 0.29, 0.55)
const MERGE_TXT := "合"

var _weapons: Array = []
var _max_lv := 10
var _max_slot := 6
var _font: Font
var _tiers := ShopTiers.new()
var _sbs: Dictionary = {}          # StyleBoxFlat 缓存（按参数去重，避免每帧 new）
var _sell_rects: Array = []        # [{rect, idx}] 底部"售"按钮，命中=售出
var _slot_rects: Array = []        # [{rect, idx}] 已占用格子，命中=合成

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func refresh(weapons: Array, max_lv: int, max_slot: int) -> void:
	_weapons = weapons
	_max_lv = max_lv
	_max_slot = maxi(1, max_slot)
	queue_redraw()

func _sb(bg: Color, border: Color, radius: float, bw: int) -> StyleBoxFlat:
	var k := "%s|%s|%s|%d" % [bg, border, radius, bw]
	if not _sbs.has(k):
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg; sb.set_corner_radius_all(int(radius))
		sb.border_color = border; sb.set_border_width_all(bw)
		_sbs[k] = sb
	return _sbs[k]

# 画一段居中的小字（超出 maxw 就截断，防止糊到邻格）
func _center(text: String, cx: float, y: float, fs: int, c: Color, maxw := 9999.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > maxw and text.length() > 1:
		text = text.substr(0, text.length() - 1)
		w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _draw() -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(0, TITLE_H - 3), I18n.t("shop_myweapons"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.78, 0.55))
	var cnt := "%d/%d" % [_weapons.size(), _max_slot]
	var cw := _font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(_font, Vector2(size.x - cw, TITLE_H - 3), cnt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.60, 0.52))
	_sell_rects = []
	_slot_rects = []
	var sw := (size.x - float(_max_slot - 1) * GAP) / float(_max_slot)
	var y := TITLE_H + 2.0
	var sh := size.y - TITLE_H - 2.0
	for i in _max_slot:
		var r := Rect2(float(i) * (sw + GAP), y, sw, sh)
		if i < _weapons.size() and _weapons[i] is Dictionary:
			_draw_chip(_weapons[i] as Dictionary, r, i)
		else:
			_draw_empty(r)

# 空格：暗底 + 细边 + 一个"+"（明确"还能再放一把"，而不是"这里没有东西"）
func _draw_empty(r: Rect2) -> void:
	draw_style_box(_sb(EMPTY_BG, EMPTY_BD, 8.0, 2), r)
	_center("+", r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 9.0, 22,
		Color(0.46, 0.43, 0.36, 0.75))

func _draw_chip(w: Dictionary, rect: Rect2, idx: int) -> void:
	var lv := int(w.get("lv", 1))
	var accent: Color = LV_COLORS[clampi(lv, 1, 6) - 1]
	var can_merge := Inventory.has_partner(_weapons, idx, _max_lv)
	# 可合成：整格套一圈金边（Brotato 式"这两把能合"的视觉暗示）
	if can_merge:
		draw_style_box(_sb(Color(0, 0, 0, 0), GOLD, 11.0, 2), rect.grow(2.0))
	draw_style_box(_sb(Color(0.16, 0.12, 0.07, 0.97), accent, 8.0, 2), rect)
	# 武器图标
	var tex: Texture2D = Art.icon("weapon_" + str(w.get("key", "")))
	var s := mini(rect.size.x - 14.0, rect.size.y - 46.0)
	if tex != null and tex is Texture2D:
		draw_texture_rect_region(tex,
			Rect2(rect.position.x + (rect.size.x - s) * 0.5, rect.position.y + 20.0, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
	# Lv 角标（右上）
	var lvtxt := "Lv%d" % lv
	var tw := _font.get_string_size(lvtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var lr := Rect2(rect.position.x + rect.size.x - tw - 7.0, rect.position.y + 3.0, tw + 5.0, 15.0)
	draw_style_box(_sb(accent.darkened(0.3), accent, 5.0, 1), lr)
	draw_string(_font, Vector2(lr.position.x + 2.5, lr.position.y + 12.0), lvtxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.06, 0.07, 0.09))
	# 可合成角标（左上金色"合"，点一下就合）
	if can_merge:
		var c := rect.position + Vector2(11.0, 11.0)
		draw_circle(c, 9.0, GOLD)
		draw_circle(c, 9.0, Color(1.0, 0.95, 0.72), false, 1.5, true)
		_center(MERGE_TXT, c.x, c.y + 4.0, 11, Color(0.35, 0.20, 0.02))
	# 售按钮（底部整条，加高到 22px、字号加大、金色"卖出 +N"，手机好点中）
	var sv := _tiers.sell_price(int(w.get("buy_cost", 0)))
	var bar_h := 22.0
	var sb_rect := Rect2(rect.position.x + 3.0, rect.position.y + rect.size.y - bar_h - 3.0,
		rect.size.x - 6.0, bar_h)
	draw_style_box(_sb(Color(0.30, 0.18, 0.06, 0.98), Color(0.85, 0.66, 0.22), 6.0, 1), sb_rect)
	_center(I18n.t("shop_sell_btn") + "%d" % sv, rect.position.x + rect.size.x * 0.5,
		sb_rect.position.y + bar_h * 0.5 + 7.0, 14, GOLD, rect.size.x - 8.0)
	_sell_rects.append({"rect": sb_rect, "idx": idx})
	_slot_rects.append({"rect": rect, "idx": idx})

# 同一次点按可能被重复投递（不同输入事件落到相近坐标）：短时同位置只认一次，
# 杜绝"点一下卖出却卖了两把"。手机上触屏 + 模拟鼠标事件最容易触发这种双投。
var _last_tap_pos := Vector2.INF
var _last_tap_ms := -1000.0

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var press := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		press = t.pressed
		pos = t.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		press = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
		pos = mb.position
	else:
		return
	accept_event()
	if not press:
		return
	# 去重：300ms 内、坐标差 < 6px 的第二次按下，视为同一次点按的重复投递
	var now := Time.get_ticks_msec()
	if pos.distance_to(_last_tap_pos) < 6.0 and (now - _last_tap_ms) < 300:
		return
	_last_tap_pos = pos
	_last_tap_ms = now
	_tap(pos)

# 命中优先级：先判"售"按钮（小目标优先），再判整格（合成）
func _tap(pos: Vector2) -> void:
	for e in _sell_rects:
		if (e["rect"] as Rect2).has_point(pos):
			sell_requested.emit(int(e["idx"]))
			return
	for e in _slot_rects:
		if (e["rect"] as Rect2).has_point(pos):
			merge_requested.emit(int(e["idx"]))
			return
