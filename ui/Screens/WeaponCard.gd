extends Button

# 开局选武器页的一张武器卡：图标 + 名字 + 一句话。
#
# 抽成独立文件的直接原因是架构守卫 R1（单文件 ≤300 行）：可滚动网格 + 详情接线 +
# 这张卡的绘制逻辑塞在一起必然超限。顺带的好处是以后给卡片加"本命角标""稀有度框"
# 时只改这里，不用动页面骨架。
#
# ⚠️ Button 里放子节点是 Godot 的常规做法，但必须：
#   1) Button 自己设 custom_minimum_size（否则它被内容挤成一条）
#   2) 子节点容器设 MOUSE_FILTER_IGNORE（否则子节点吃掉了点击，按钮收不到 pressed）

const CARD_H := 152.0

const _GOLD := Color(0.99, 0.87, 0.40)
const _DIM := Color(0.60, 0.46, 0.22, 0.85)
const _BG := Color(0.18, 0.12, 0.07, 0.96)
const _BG_SEL := Color(0.27, 0.18, 0.09, 0.98)

var weapon_key: String = ""

func setup(key: String, width: float) -> void:
	weapon_key = key
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(width, CARD_H)
	var def: Dictionary = Data.weapon(key)
	var accent := Color(str(def.get("color", "#ffffff")))

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)

	var tex := Art.icon("weapon_" + key)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(width, 62.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		tr.texture = tex
		vb.add_child(tr)
	else:
		# 缺图退化成一枚主色方块（居中）：玩家仍能靠颜色分辨它属于哪一类
		var ph := ColorRect.new()
		ph.color = accent
		ph.custom_minimum_size = Vector2(44, 44)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.custom_minimum_size = Vector2(width, 62.0)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(ph)
		vb.add_child(cc)

	var nm := Label.new()
	nm.text = I18n.pick(def)
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	var tp := Label.new()
	tp.text = I18n.tip(def)
	tp.add_theme_font_size_override("font_size", 12)
	tp.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	tp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tp.set_custom_minimum_size(Vector2(width - 16.0, 0))
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tp)
	set_selected(false)

func set_selected(on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _BG_SEL if on else _BG
	sb.set_border_width_all(4 if on else 2)
	sb.border_color = _GOLD if on else _DIM
	sb.set_corner_radius_all(14)
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", sb)
	add_theme_stylebox_override("pressed", sb)
	add_theme_stylebox_override("focus", sb)
	var nm := _find_label()
	if nm != null:
		nm.add_theme_color_override("font_color",
			Color(1.0, 0.92, 0.62) if on else Color(0.98, 0.96, 0.92))

# 卡片里的第一个 Label 就是名字（见 setup 的构建顺序）
func _find_label() -> Label:
	for c in get_children():
		var vb := c as VBoxContainer
		if vb == null:
			continue
		for cc in vb.get_children():
			if cc is Label:
				return cc as Label
	return null
