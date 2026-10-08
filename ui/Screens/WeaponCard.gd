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

const CARD_H := 160.0

const Weapon := preload("res://core/Weapon.gd")

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
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)

	vb.add_child(_icon_node(Art.icon("weapon_" + key), accent, width))

	var nm := Label.new()
	nm.text = I18n.pick(def)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	# 行为类型彩色药丸：一眼看懂"这把怎么打"（追踪 / 散射 / 穿透 / 近战…）
	var beh := Weapon.behavior_zh(def)
	if beh != "":
		vb.add_child(_badge(beh, accent, width))

	# 套装 / 羁绊名：知道它归哪一类（决定"和什么一起买"）
	var st := _set_text(def)
	if st != "":
		var sl := Label.new()
		sl.text = st
		sl.add_theme_font_size_override("font_size", 13)
		sl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(sl)

	var tp := Label.new()
	tp.text = I18n.tip(def)
	tp.add_theme_font_size_override("font_size", 14)
	tp.add_theme_color_override("font_color", Color(0.74, 0.78, 0.84))
	tp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tp.set_custom_minimum_size(Vector2(width - 16.0, 0))
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tp)
	set_selected(false)

# 图标节点（缩小到 44px 高，不再占半张卡）；缺图退化成主色方块
func _icon_node(tex: Texture2D, accent: Color, width: float) -> Control:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(width, 44.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		tr.texture = tex
		return tr
	var ph := ColorRect.new()
	ph.color = accent
	ph.custom_minimum_size = Vector2(40, 40)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(width, 44.0)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(ph)
	return cc

# 行为类型小药丸（武器主色描底、深色字）
func _badge(text: String, accent: Color, width: float) -> Panel:
	var bh := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lightened(0.12)
	sb.set_corner_radius_all(8)
	bh.add_theme_stylebox_override("panel", sb)
	bh.custom_minimum_size = Vector2(width, 22.0)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := Label.new()
	bl.text = text
	bl.add_theme_font_size_override("font_size", 12)
	bl.add_theme_color_override("font_color", Color(0.07, 0.08, 0.10))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(bl)
	return bh

# 套装 / 羁绊名（取第一个 tag 映射；没有就空）
func _set_text(def: Dictionary) -> String:
	var tags: Array = def.get("tags", [])
	if tags.is_empty():
		return ""
	var key := "set_" + str(tags[0])
	var name := I18n.t(key)
	return name if (name != "" and name != key) else ""

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
