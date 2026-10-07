extends Control

# 角色选择卡片组：标题页里横排 N 张卡，点一下换人。
#
# 只做两件事：画自己（贴图 + 名字 + 属性摘要），以及把点击变成 GameState.set_character。
# 不认识 Player、不认识 Game —— 换人后由 Events.character_changed 通知它们。
#
# 布局：卡片行按角色数量自动缩放（6 卡时整行等比缩小），保证在 540 设计宽度内完整可见。
# 之前写死 4 卡宽，角色加到 5-6 个后末尾卡片被切出屏幕、没法点选。

# D3-4：点卡不再直接换人 —— 改为发出"我要看这个角色的详情"，由详情页的「选他」落定。
# 主页面从此只负责"挑"（形象 + 名字）；特性/买什么/点什么技能全在各自独立页里讲，
# 这样将来扩到 60 个角色只换详情页的文字，不用把卡片越缩越小去塞信息。
signal char_detail_requested(key: String)

# 设计基准尺寸（6 卡以内会按比例缩小）
const CARD_W := 96.0
const CARD_H := 118.0
const GAP := 10.0
# 整行最大宽度（540 设计宽 - 左右各 10px 余量）
const ROW_MAX_W := 520.0
# 网格：每行最多几张。13 个萝卜 → 7 列 2 行（降为 2 行，卡片更大更好点）。
# 列数只决定"横向封顶 ROW_MAX_W 时能排几张"，真正的高由下方 PICKER_MAX_H 收口——
# 角色再多也整体等比缩，绝不把 START 顶出屏幕。
const COLS := 7
# 角色网格可用高度上限：y=530 起，给下方 START(高 78)+间距+解锁提示留足，
# 必须 ≤ ~256，否则 START 会掉到 900 设计高以下（之前 13 角色 3 行把 START 顶到 y=912）。
const PICKER_MAX_H := 250.0
const PICKER_TOP := 530.0

var _keys: Array = []
var _selected := "turnip"
var _hover := -1
# 实际使用的卡片尺寸（_ready 里按网格与卡数缩放）
var _cw := CARD_W
var _ch := CARD_H
var _gap := GAP
var _k := 1.0   # 缩放系数（图标/角标等内部布局同比例跟随）
var _cols := 1  # 网格列数（13 个萝卜 = 7 列 2 行，未来扩到 60 仍整体等比缩）
var _rows := 1
# 网格内容实际尺寸。注意：ScreenMode.fit_overlay 会把本控件 size 撑成整屏 540x900
# （卡片只画在左上角），所以对外暴露内容高度，TitleScreen 用它摆 START，别读 size。
var content_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_keys = Data.characters.keys()
	_keys.sort()
	_selected = GameState.character
	# 网格布局：每行最多 COLS 张，整体宽度封顶 ROW_MAX_W。
	# 高度封顶 PICKER_MAX_H：角色多到网格超高时整体等比缩（卡片变矮但永远在屏内），
	# 这样 START 按钮不会被顶出 900 设计高（之前 13 角色 3 行把 START 顶到 y=912）。
	var n := _keys.size()
	_cols = maxi(1, mini(n, COLS))
	_rows = int(ceil(float(n) / float(_cols)))
	_cw = minf(CARD_W, (ROW_MAX_W - float(_cols - 1) * GAP) / float(_cols))
	_k = _cw / CARD_W
	_ch = CARD_H * _k
	_gap = GAP * _k
	# 高度超限 → 整体等比缩小（卡宽也跟着缩，保持方形，文字截断逻辑照常工作）
	var h := float(_rows) * _ch + float(_rows - 1) * _gap
	if h > PICKER_MAX_H:
		var s := PICKER_MAX_H / h
		_ch *= s
		_gap *= s
		_cw *= s
		_k = _cw / CARD_W
	content_size = Vector2(float(_cols) * _cw + float(_cols - 1) * _gap,
		float(_rows) * _ch + float(_rows - 1) * _gap)
	size = content_size
	Events.character_changed.connect(_on_changed)
	I18n.locale_changed.connect(_on_locale_changed)
	queue_redraw()
	ScreenMode.fit_overlay(self)   # 横屏下把竖屏选角色页缩放到 960x540 视口内、居中

func _on_changed(key: String) -> void:
	_selected = key
	queue_redraw()

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()

func _key_at(p: Vector2) -> String:
	var pitch_x := _cw + _gap
	var pitch_y := _ch + _gap
	if pitch_x <= 0.0 or pitch_y <= 0.0:
		return ""
	var col := int(p.x / pitch_x)
	var row := int(p.y / pitch_y)
	if col < 0 or col >= _cols or row < 0 or row >= _rows:
		return ""
	# 落在行列间隙里不算
	if p.x > float(col) * pitch_x + _cw or p.y > float(row) * pitch_y + _ch:
		return ""
	var idx := row * _cols + col
	if idx < 0 or idx >= _keys.size():
		return ""
	return str(_keys[idx])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var k := _key_at(t.position)
			if not k.is_empty():
				char_detail_requested.emit(k)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var k := _key_at(mb.position)
			if not k.is_empty():
				char_detail_requested.emit(k)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var k := _key_at(mm.position)
		var idx := _keys.find(k) if not k.is_empty() else -1
		if idx != _hover:
			_hover = idx
			queue_redraw()

func _draw() -> void:
	var pitch_x := _cw + _gap
	var pitch_y := _ch + _gap
	for i in _keys.size():
		var key := str(_keys[i])
		var col := i % _cols
		var row := i / _cols
		var r := Rect2(float(col) * pitch_x, float(row) * pitch_y, _cw, _ch)
		_draw_card(r, key, i == _hover, key == _selected)

func _draw_card(r: Rect2, key: String, hovered: bool, selected: bool) -> void:
	var entry: Dictionary = Data.character(key)
	var accent := Color(str(entry.get("color", "#ffffff")))
	# 底板：统一到商店暖棕（深棕面板 + 金描边 + 圆角），选中/悬停更亮
	var bg := Color(0.18, 0.12, 0.07, 0.92)
	if selected:
		bg = Color(0.27, 0.18, 0.09, 0.98)
	elif hovered:
		bg = Color(0.22, 0.15, 0.08, 0.95)
	var border := accent if selected else Color(0.60, 0.46, 0.22, 0.85)
	var bw := 3.0 * _k if selected else 1.5 * _k
	Art.round_rect(self, r, bg, border, bw, 9.0 * _k)

	# 立绘：优先 char_<key>；缺图退化成一个主色圆点，玩家仍能分辨
	var tex := Art.sprite("char_" + key)
	var icon_r := 30.0 * _k
	var c := Vector2(r.position.x + _cw * 0.5, r.position.y + _ch * 0.40)
	if tex != null:
		var s := icon_r * 2.2
		draw_texture_rect_region(tex, Rect2(c.x - s * 0.5, c.y - s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
	else:
		draw_circle(c, icon_r * 0.8, accent)
		draw_arc(c, icon_r * 0.8, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 2.0, true)

	# 名字（按当前语言切换）
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var name := I18n.pick(entry)
	var nfs := int(maxf(9.0, 15.0 * _k))
	var nw := fs.get_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, -1, nfs)
	draw_string(fs, Vector2(c.x - nw.x * 0.5, r.position.y + _ch * 0.80), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, nfs,
		Color(1, 1, 1, 0.96) if selected else Color(0.78, 0.82, 0.88, 0.9))

	# 选中标记：右上角一个小三角
	if selected:
		var tp := Vector2(r.position.x + _cw - 14.0 * _k, r.position.y + 10.0 * _k)
		draw_colored_polygon(PackedVector2Array([
			tp, tp + Vector2(10.0, 0.0) * _k, tp + Vector2(5.0, 8.0) * _k]), accent)
