extends CanvasLayer

# 商店货架上的武器/道具【独立详情页】：点小卡后弹出，在【这一页】讲清楚
#   「这把是什么 / 怎么打 / 套装进度 / 羁绊收益 / 价格」，并提供
#   购买 / 锁定 / 单张刷新 / 关闭 四个操作。
# 照 ui/Screens/CharDetail.gd 的对话框范式（layer 55、遮罩 + 居中面板 + 宽滚动条）。
#
# 与 ui/Screens/WeaponDetail.gd 的区别：那个是【开局选武器】用的（按武器 key 查定义，
# 只有"选哪把"）；这个是按【商店卡位下标】拉实时报价（含价格 / 等级 / 套装进度 /
# 买得起吗），并直接驱动购买 / 锁定 / 单张刷新。两者互不干扰。

const GOLD := Color(1.0, 0.82, 0.29)
const RED := Color(0.95, 0.42, 0.40)
const DetailText := preload("res://ui/Shop/ShopDetailText.gd")

signal buy_requested(index: int)
signal lock_requested(index: int)
signal reroll_one_requested(index: int)

# 拉取最新卡数据（Shop.card_data(index)），公开字段避免跨对象读私有字段（R3）
var data_cb: Callable = Callable()

var _root: Control
var _icon: TextureRect
var _name_lbl: Label
var _tag_lbl: Label
var _price_lbl: Label
var _body: VBoxContainer
var _buy_btn: Button
var _lock_btn: Button
var _reroll_btn: Button
var _close_btn: Button
var _index := -1
var _open := false
var _rerolled_once := false   # 本页打开期间是否已刷新过一次（刷新只允许一次）

func _ready() -> void:
	layer = 55
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.06, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_shade_input)
	_root.add_child(shade)

	var panel := Panel.new()
	panel.set_size(Vector2(470, 690))
	panel.position = Vector2((540 - 470) * 0.5, (900 - 690) * 0.5)
	panel.add_theme_stylebox_override("panel", _flat(Color(0.14, 0.10, 0.07, 0.99), GOLD.darkened(0.3), 18))
	_root.add_child(panel)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.custom_minimum_size = Vector2(76, 76)
	_icon.set_position(Vector2(20, 54))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_icon)

	_name_lbl = _mk_label(22, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_name_lbl.set_position(Vector2(108, 52))
	_name_lbl.set_size(Vector2(330, 34))
	panel.add_child(_name_lbl)

	_tag_lbl = _mk_label(14, Color(0.78, 0.80, 0.86), HORIZONTAL_ALIGNMENT_LEFT)
	_tag_lbl.set_position(Vector2(108, 90))
	_tag_lbl.set_size(Vector2(330, 22))
	panel.add_child(_tag_lbl)

	_price_lbl = _mk_label(16, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_price_lbl.set_position(Vector2(20, 138))
	_price_lbl.set_size(Vector2(420, 24))
	panel.add_child(_price_lbl)

	var scroll := ScrollContainer.new()
	scroll.set_position(Vector2(20, 168))
	scroll.set_size(Vector2(430, 392))
	scroll.scroll_horizontal = false
	scroll.add_theme_constant_override("scrollbar_width", 28)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.11, 0.16, 0.0)
	scroll.add_theme_stylebox_override("bg", bg)
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(410, 0)
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_buy_btn = Button.new()
	_buy_btn.set_size(Vector2(232, 60))
	_buy_btn.set_position(Vector2(20, 622))
	_buy_btn.add_theme_font_size_override("font_size", 21)
	Art.style_button(_buy_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_buy_btn.pressed.connect(_on_buy)
	panel.add_child(_buy_btn)

	_lock_btn = Button.new()
	_lock_btn.set_size(Vector2(94, 60))
	_lock_btn.set_position(Vector2(260, 622))
	_lock_btn.add_theme_font_size_override("font_size", 16)
	Art.style_button(_lock_btn, Color(0.30, 0.24, 0.30, 0.95), Color(0.99, 0.84, 0.35), Color(0.62, 0.55, 0.30))
	_lock_btn.pressed.connect(_on_lock)
	panel.add_child(_lock_btn)

	_reroll_btn = Button.new()
	_reroll_btn.set_size(Vector2(110, 60))
	_reroll_btn.set_position(Vector2(360, 622))
	_reroll_btn.add_theme_font_size_override("font_size", 16)
	Art.style_button(_reroll_btn, Color(0.20, 0.30, 0.42, 0.95), Color(0.72, 0.90, 1.0), Color(0.45, 0.62, 0.80))
	_reroll_btn.pressed.connect(_on_reroll)
	panel.add_child(_reroll_btn)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.set_size(Vector2(34, 34))
	_close_btn.set_position(Vector2(470 - 44, 14))
	_close_btn.add_theme_font_size_override("font_size", 20)
	Art.style_button(_close_btn, Color(0.40, 0.30, 0.18, 0.95), Color(0.98, 0.86, 0.50), Color(0.60, 0.46, 0.24))
	_close_btn.pressed.connect(_on_close)
	panel.add_child(_close_btn)

func _mk_label(fs: int, c: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _flat(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	sb.border_color = border
	sb.set_border_width_all(2)
	return sb

func _section(title: String, text: String) -> void:
	if str(text).is_empty():
		return
	var h := _mk_label(16, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = title
	h.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(h)
	var t := _mk_label(15, Color(0.88, 0.90, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	t.text = str(text)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(410, 0)
	_body.add_child(t)

func show_for(index: int) -> void:
	_index = index
	_rerolled_once = false
	_refresh()
	_open = true
	_root.visible = true

func refresh() -> void:
	if _open:
		_refresh()

func hide_page() -> void:
	_open = false
	_root.visible = false

func _on_shade_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		hide_page()

func is_open() -> bool:
	return _open

func _on_locale_changed(_l: String = "") -> void:
	refresh()

func _refresh() -> void:
	if _index < 0 or not data_cb.is_valid():
		return
	var d: Dictionary = data_cb.call(_index)
	if d.is_empty():
		return
	var name := str(d.get("name", ""))
	_name_lbl.text = name
	_tag_lbl.text = str(d.get("tag", ""))
	_icon.texture = d.get("icon", null)
	var cost := int(d.get("cost", 0))
	var afford := bool(d.get("affordable", true))
	var disabled := bool(d.get("disabled", false))
	var sold := bool(d.get("sold", false))
	var ok := afford and not disabled and not sold
	_price_lbl.text = I18n.t("shop_gold") % cost
	_price_lbl.add_theme_color_override("font_color", GOLD if ok else RED)
	if bool(d.get("inflated", false)):
		_price_lbl.text += "（涨 %d%%）" % int(d.get("infl_pct", 0))

	for c in _body.get_children():
		c.queue_free()
	_section(DetailText.t("intro", I18n.locale), str(d.get("tip", "")))
	if str(d.get("kind", "")) == "weapon":
		_section(DetailText.t("play", I18n.locale), str(d.get("behavior_zh", "")))
		if d.has("set_name") and str(d.get("set_name", "")) != "":
			var prog := "%s  %d/%d（第 %d 档）" % [str(d.get("set_name", "")),
				int(d.get("set_count", 0)), int(d.get("set_need", 0)), int(d.get("set_tier", 0))]
			_section(DetailText.t("set", I18n.locale), prog)
	var gain := str(d.get("syn_gain", ""))
	if gain != "":
		_section(DetailText.t("bond", I18n.locale), gain)

	_buy_btn.text = DetailText.t("buy", I18n.locale) % cost
	_buy_btn.disabled = not ok
	_lock_btn.text = DetailText.t("unlock", I18n.locale) if bool(d.get("locked", false)) else DetailText.t("lock", I18n.locale)
	_lock_btn.disabled = sold
	_reroll_btn.text = I18n.t("shop_reroll") % int(d.get("reroll_one_cost", 0))
	_reroll_btn.disabled = sold or bool(d.get("locked", false)) or not afford or _rerolled_once

func _on_buy() -> void:
	if _index < 0 or _buy_btn.disabled:
		return
	Sfx.ui_click()
	buy_requested.emit(_index)
	hide_page()   # 用户选了"购买"即自动关闭，不再多一次关闭点击

func _on_lock() -> void:
	if _index < 0 or _lock_btn.disabled:
		return
	Sfx.ui_click()
	lock_requested.emit(_index)
	hide_page()   # 用户选了"锁定"即自动关闭

func _on_reroll() -> void:
	if _index < 0 or _reroll_btn.disabled:
		return
	Sfx.ui_click()
	reroll_one_requested.emit(_index)
	_rerolled_once = true   # 刷新只允许一次，刷新后禁用刷新按钮
	refresh()

func _on_close() -> void:
	Sfx.ui_click()
	hide_page()
