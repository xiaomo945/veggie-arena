extends Control

# 武器详情独立页：开局选武器时点卡片弹出，盖在选武器页之上。
#
# 为什么要独立成一页：卡片上塞不下"这把武器怎么打、数值多少、谁拿它最狠"，
# 而开局这一选直接决定整局的打法 —— 玩家在按下之前需要看得懂。
# 与角色详情（CharDetail）同一套路：主页面只留"形象 + 名字"，点开才是详情。
#
# 用 Control 而不是 CanvasLayer 的理由：由选武器页把它挂成自己的最后一个子节点，
# 于是"收起选武器页"天然把详情一起收掉，不需要再管一层 CanvasLayer 的显隐生命周期；
# 以后商店里要复用这一页，挂进 shop 的 CanvasLayer 即可，逻辑一行不用改。
#
# 文案全部走 ui/WeaponInfo.gd（自带中英双语、纯函数），不碰已经满载的 I18n.gd。

const WeaponInfo := preload("res://ui/WeaponInfo.gd")

signal picked(key: String)

var _root: Control
var _icon: TextureRect
var _name_lbl: Label
var _class_lbl: Label
var _body: VBoxContainer
var _pick_btn: Button
var _key: String = ""
var _open := false

func _ready() -> void:
	# ⚠️ anchors 必须配显式 size：本页在 _ready 时已经入树，
	#    只 set_anchors_preset 会把 offsets 改写成"保持当前 0x0 矩形"，页面永远画不出来。
	#    （WeaponPicker 同款写法能活，靠的就是它多给了 size = 540x900 这一行。）
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(540.0, 900.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.size = Vector2(540.0, 900.0)
	_root.visible = false
	add_child(_root)
	_build()
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.size = Vector2(540.0, 900.0)
	shade.color = Color(0.02, 0.03, 0.06, 0.88)
	_root.add_child(shade)

	var panel := Panel.new()
	# 自带一块不透明底板：不赌引擎默认主题的 Panel 样式长什么样
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.15, 0.985)
	sb.border_color = Color(0.72, 0.60, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_size(Vector2(470, 700))
	panel.position = Vector2((540 - 470) * 0.5, (900 - 700) * 0.5)
	_root.add_child(panel)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.custom_minimum_size = Vector2(88, 88)
	_icon.set_position(Vector2(470 * 0.5 - 44, 20))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_icon)

	_name_lbl = _mk_label(22, Color(0.98, 0.86, 0.32), HORIZONTAL_ALIGNMENT_CENTER)
	_name_lbl.set_position(Vector2(20, 118))
	_name_lbl.set_size(Vector2(430, 30))
	panel.add_child(_name_lbl)

	_class_lbl = _mk_label(14, Color(0.62, 0.66, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_class_lbl.set_position(Vector2(20, 152))
	_class_lbl.set_size(Vector2(430, 22))
	panel.add_child(_class_lbl)

	var scroll := ScrollContainer.new()
	scroll.set_position(Vector2(20, 186))
	scroll.set_size(Vector2(430, 414))
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(410, 0)
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_pick_btn = Button.new()
	_pick_btn.set_size(Vector2(210, 60))
	_pick_btn.set_position(Vector2(470 * 0.5 - 215, 626))
	_pick_btn.add_theme_font_size_override("font_size", 22)
	Art.style_button(_pick_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_pick_btn.pressed.connect(_on_pick)
	panel.add_child(_pick_btn)

	var close := Button.new()
	close.text = I18n.t("char_detail_close")
	close.set_size(Vector2(190, 60))
	close.set_position(Vector2(470 * 0.5 + 5, 626))
	close.add_theme_font_size_override("font_size", 20)
	Art.style_button(close, Color(0.70, 0.62, 0.50), Color(0.22, 0.16, 0.08), Color(0.60, 0.54, 0.44))
	close.pressed.connect(_on_close)
	panel.add_child(close)

func _mk_label(fs: int, c: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func show_for(key: String) -> void:
	_key = key
	_refresh()
	_open = true
	_root.visible = true

func hide_page() -> void:
	_open = false
	_root.visible = false

func is_open() -> bool:
	return _open

func _on_locale_changed(_l: String = "") -> void:
	if _open:
		_refresh()

func _section(title: String, text: String) -> void:
	if text.is_empty():
		return
	var h := _mk_label(16, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = title
	_body.add_child(h)
	var t := _mk_label(15, Color(0.88, 0.90, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(410, 0)
	_body.add_child(t)

# 数值：两列小表，比一长串文字好扫
func _stat_section() -> void:
	var rows := WeaponInfo.stat_rows(Data.weapon(_key), I18n.locale)
	if rows.is_empty():
		return
	var h := _mk_label(16, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = WeaponInfo.title_stat(I18n.locale)
	_body.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	_body.add_child(grid)
	for r in rows:
		var kk := _mk_label(14, Color(0.66, 0.70, 0.76), HORIZONTAL_ALIGNMENT_LEFT)
		kk.text = str((r as Dictionary).get("label", ""))
		grid.add_child(kk)
		var vv := _mk_label(14, Color(0.95, 0.96, 0.98), HORIZONTAL_ALIGNMENT_LEFT)
		vv.text = str((r as Dictionary).get("value", ""))
		grid.add_child(vv)

func _refresh() -> void:
	if _key.is_empty():
		return
	var def: Dictionary = Data.weapon(_key)
	_icon.texture = Art.icon("weapon_" + _key)
	_name_lbl.text = I18n.pick(def)
	_name_lbl.add_theme_color_override("font_color", Color(str(def.get("color", "#ffffff"))))
	_class_lbl.text = _class_text(def)
	_pick_btn.text = WeaponInfo.btn_pick(I18n.locale)

	for c in _body.get_children():
		c.queue_free()

	# 1) 一句话卖点
	_section(WeaponInfo.title_summary(I18n.locale), I18n.tip(def))
	# 2) 打法特点（哪些机制真的改变了操作）
	var traits: Array = WeaponInfo.trait_lines(def, I18n.locale)
	if not traits.is_empty():
		_section(WeaponInfo.title_trait(I18n.locale), "\n".join(traits))
	# 3) 数值表
	_stat_section()
	# 4) 套装 / 羁绊类：它归哪一类，决定了"和什么一起买"
	var sets := _class_text(def)
	if not sets.is_empty():
		_section(WeaponInfo.title_set(I18n.locale), sets)
	# 5) 谁拿它最狠：把"角色 × 武器"这条线明说出来
	var masters: Array = WeaponInfo.masters(_key, Data.characters)
	if not masters.is_empty():
		var names := []
		for c in masters:
			names.append(I18n.pick(Data.character(str(c))))
		_section(WeaponInfo.title_master(I18n.locale), "、".join(names))

# 归类标签（gun/blade/heavy/elemental/kitchen → 玩家看得懂的套装名）
func _class_text(def: Dictionary) -> String:
	var out := []
	for t in (def.get("tags", []) as Array):
		var key := "set_" + str(t)
		var name := I18n.t(key)
		if not name.is_empty() and name != key:
			out.append(name)
	return " / ".join(out) if not out.is_empty() else str(def.get("type", ""))

func _on_pick() -> void:
	if _key.is_empty():
		return
	Sfx.ui_click()
	picked.emit(_key)
	hide_page()

func _on_close() -> void:
	Sfx.ui_click()
	hide_page()
