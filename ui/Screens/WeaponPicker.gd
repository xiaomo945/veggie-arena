extends Control

# 开局选初始武器页：标题页"开始"之后、正式开打之前弹出。
# 从 data/unlocks.json 的 start_weapons 取 6 把基础武器，2 列卡片网格，选 1 把。
# 确认：写 GameState.start_weapon（所选 + 手枪保底），再发 Events.run_requested 开跑。
# 返回：回到标题页（back_pressed 回调由 TitleScreen 注入）。
#
# 不使用 class_name（见 SettingsWidgets.gd 头注释：headless 下全局类表不重建会报错）。
# 本节点自身是 Control，由 TitleScreen 包进 layer=45 的 CanvasLayer 以正确压在 HUD 之上。

const TITLE_Y := 56.0
const HINT_Y := 112.0
const GRID_Y := 150.0
const CARD_W := 247.0
const CARD_H := 148.0
const GAP := 14.0
const COLS := 2
const MARGIN_X := 16.0
const CONFIRM_Y := 690.0
const CONFIRM_W := 360.0
const CONFIRM_H := 72.0
const BACK_Y := 786.0
const BACK_W := 200.0
const BACK_H := 52.0

# 配色（与数值总表 §8.4 统一：精英金圈 #ffd24a）
const GOLD := Color(1.0, 0.82, 0.29)
const PANEL_BG := Color(0.10, 0.12, 0.17, 0.96)
const CARD_BG := Color(0.14, 0.16, 0.22, 0.96)
const CARD_BG_SEL := Color(0.20, 0.22, 0.30, 0.98)
const BORDER_DIM := Color(0.35, 0.38, 0.45, 0.8)

var _keys: Array = []
var _selected := 0
var _hover := -1
# 返回标题的回调（由 TitleScreen 注入）。用公开属性 + set_back() 避免外部直接写私有成员
var back_cb: Callable = Callable()
var _card_rects: Array = []      # [{key, rect}]
var _confirm_rect := Rect2()
var _back_rect := Rect2()
var _font: Font

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(540.0, 900.0)
	# start_weapons 取前 6 把作为可选初始武器（数值总表规定新手只开放基础武器）。
	# 手枪是保底武器，从"可选"里剔除，避免玩家选了手枪后本局只剩一把武器。
	var list: Array = Data.unlocks_cfg().get("start_weapons", [])
	list = list.filter(func(k): return str(k) != "pistol")
	_keys = list.duplicate()
	if _keys.size() > 6:
		_keys = _keys.slice(0, 6)
	if _keys.is_empty():
		_keys = ["smg", "shotgun", "bow", "staff", "rocket", "cleaver"]
	_selected = 0
	_font = ThemeDB.fallback_font
	I18n.locale_changed.connect(_on_locale_changed)
	_build_rects()
	queue_redraw()

func _build_rects() -> void:
	_card_rects = []
	var row_h := CARD_H + GAP
	for i in _keys.size():
		var col := i % COLS
		var row := i / COLS
		var x := MARGIN_X + float(col) * (CARD_W + GAP)
		var y := GRID_Y + float(row) * row_h
		_card_rects.append({"key": _keys[i], "rect": Rect2(x, y, CARD_W, CARD_H)})
	_confirm_rect = Rect2((540.0 - CONFIRM_W) * 0.5, CONFIRM_Y, CONFIRM_W, CONFIRM_H)
	_back_rect = Rect2((540.0 - BACK_W) * 0.5, BACK_Y, BACK_W, BACK_H)

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()

func _hit(p: Vector2) -> Dictionary:
	for i in _card_rects.size():
		var r: Rect2 = _card_rects[i]["rect"]
		if r.has_point(p):
			return {"type": "card", "i": i}
	if _confirm_rect.has_point(p):
		return {"type": "confirm"}
	if _back_rect.has_point(p):
		return {"type": "back"}
	return {"type": ""}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_tap(t.position)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_tap(mb.position)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var h := _hit(mm.position)
		var idx := -1
		if h.get("type", "") == "card":
			idx = int(h["i"])
		if idx != _hover:
			_hover = idx
			queue_redraw()

func set_back(cb: Callable) -> void:
	back_cb = cb

func _on_tap(p: Vector2) -> void:
	var h := _hit(p)
	var t := str(h.get("type", ""))
	if t == "card":
		_selected = int(h["i"])
		Sfx.ui_click()
		queue_redraw()
	elif t == "confirm":
		Sfx.ui_click()
		_confirm()
	elif t == "back":
		Sfx.ui_click()
		if back_cb.is_valid():
			back_cb.call()
	elif t == "":
		# 点空白不误触：只有命中卡片 / 按钮才响应
		pass

func _confirm() -> void:
	if _selected >= 0 and _selected < _keys.size():
		GameState.start_weapon = str(_keys[_selected])
	Events.run_requested.emit()

func _center(text: String, cx: float, y: float, fs: int, c: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _draw() -> void:
	if _font == null:
		return
	# 半透明遮罩：背后竞技场隐约可见，更有"进游戏"的期待感
	var shade := Color(0.05, 0.06, 0.09, 0.86)
	draw_rect(Rect2(0, 0, 540, 900), shade)
	# 标题
	_center(I18n.t("pick_weapon_title"), 270, TITLE_Y, 34, GOLD)
	# 提示
	_center(I18n.t("pick_weapon_hint"), 270, HINT_Y, 16, Color(0.80, 0.84, 0.90))

	for i in _card_rects.size():
		_draw_card(_card_rects[i]["rect"] as Rect2, str(_card_rects[i]["key"]),
			i == _hover, i == _selected)

	# 阵容提示
	var sel_key := str(_keys[_selected]) if _selected < _keys.size() else ""
	var sel_name := I18n.pick(Data.weapon(sel_key)) if not sel_key.is_empty() else ""
	var loadout := I18n.t("pick_weapon_loadout") % sel_name
	_center(loadout, 270, 656, 15, Color(0.95, 0.82, 0.40))

	_draw_button(_confirm_rect, I18n.t("pick_weapon_confirm"), GOLD, Color(0.07, 0.08, 0.05), 26)
	_draw_button(_back_rect, I18n.t("pick_weapon_back"), Color(0.20, 0.22, 0.28, 0.9),
		Color(0.85, 0.88, 0.92), 20, true)

func _draw_card(r: Rect2, key: String, hovered: bool, selected: bool) -> void:
	var def: Dictionary = Data.weapon(key)
	var accent := Color(str(def.get("color", "#ffffff")))
	draw_rect(r, CARD_BG_SEL if selected else CARD_BG)
	var bw := 4.0 if selected else (2.0 if hovered else 1.5)
	var bc := GOLD if selected else (accent if hovered else BORDER_DIM)
	draw_rect(r, bc, false, bw)

	# 图标：优先 weapon_<key> 贴图，缺图退化成主色圆点
	var tex := Art.icon("weapon_" + key)
	var ic := Vector2(r.position.x + CARD_W * 0.5, r.position.y + 44.0)
	if tex != null:
		var s := 60.0
		draw_texture_rect_region(tex, Rect2(ic.x - s * 0.5, ic.y - s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
	else:
		draw_circle(ic, 26.0, accent)
		draw_arc(ic, 26.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 2.0, true)

	# 名称（按语言切换）
	var name := I18n.pick(def)
	_center(name, ic.x, r.position.y + 86.0, 18,
		Color(1, 1, 1, 0.98) if selected else Color(0.82, 0.85, 0.90))

	# 一句话描述（按可用宽度按字符换行，最多 3 行）
	_draw_wrap(I18n.tip(def), r, r.position.y + 108.0, 12, Color(0.66, 0.70, 0.76), 3)

	# 选中角标：右上角金色 "已选" 小胶囊
	if selected:
		var tag := I18n.t("pick_weapon_sel")
		var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var pad := 8.0
		var tr := Rect2(r.position.x + CARD_W - tw - pad * 2 - 8.0, r.position.y + 8.0,
			tw + pad * 2, 22.0)
		draw_rect(tr, GOLD)
		_center(tag, tr.position.x + tr.size.x * 0.5, tr.position.y + 16.0, 12, Color(0.07, 0.08, 0.05))

func _draw_wrap(text: String, r: Rect2, y0: float, fs: int, c: Color, max_lines: int) -> void:
	var maxw := CARD_W - 24.0
	var cx := r.position.x + CARD_W * 0.5
	var line := ""
	var lines := 0
	var i := 0
	while i < text.length() and lines < max_lines:
		var ch := text[i]
		var test := line + ch
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw and line != "":
			_center(line, cx, y0 + float(lines) * (fs + 4), fs, c)
			lines += 1
			line = ch
		else:
			line = test
		i += 1
	if line != "" and lines < max_lines:
		_center(line, cx, y0 + float(lines) * (fs + 4), fs, c)

func _draw_button(r: Rect2, text: String, bg: Color, fg: Color, fs: int, outline := false) -> void:
	if outline:
		draw_rect(r, Color(0.20, 0.22, 0.28, 0.85))
		draw_rect(r, Color(0.45, 0.48, 0.56, 0.9), false, 2.0)
	else:
		draw_rect(r, bg)
		draw_rect(r, Color(0.72, 0.60, 0.16), false, 4.0)
	_center(text, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.35, fs, fg)
