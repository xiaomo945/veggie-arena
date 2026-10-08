extends Button

# 选角色页的一张角色卡（抽独立文件守架构守卫 R1）。
#
# 用真实 Button：① 触屏 / 鼠标都可靠触发 pressed（与已修好的武器卡同范式）；
# ② Godot 自动处理 fit_overlay 缩放下的命中坐标，不再手写 _gui_input 命中；
# ③ 卡片是独立小按钮、背景不吃点击，空白不会被卡片拦截，也不会吞掉 START。
#
# 锁着的角色：整体压暗 + 一把小锁（纯几何绘制，不依赖美术素材），点不动；
# 差什么写在详情页（CharDetail）第一节，玩家点开一眼就看到。

const CARD_H := 118.0
const _BG := Color(0.18, 0.12, 0.07, 0.92)
const _BG_SEL := Color(0.27, 0.18, 0.09, 0.98)
const _GOLD := Color(0.98, 0.86, 0.32)
const _DIM := Color(0.60, 0.46, 0.22, 0.85)

var char_key := ""

func setup(key: String, w: float) -> void:
	char_key = key
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(w, CARD_H)
	var entry: Dictionary = Data.character(key)
	var accent := Color(str(entry.get("color", "#ffffff")))
	# 子节点容器（图标 + 名字）：必须 IGNORE，否则吃掉点击、按钮收不到 pressed
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var tex := Art.sprite("char_" + key)
	var ico := TextureRect.new()
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.custom_minimum_size = Vector2(w, 64.0)
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		ico.texture = tex
	vb.add_child(ico)
	var nm := Label.new()
	nm.text = I18n.pick(entry)
	nm.add_theme_font_size_override("font_size", 15)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	_style(accent, false)
	if not SaveMgr.is_character_unlocked(key):
		disabled = true
		_lock_overlay(accent)

func _style(accent: Color, sel: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _BG_SEL if sel else _BG
	sb.border_color = accent if sel else _DIM
	sb.set_border_width_all(3.0 if sel else 2.0)
	sb.set_corner_radius_all(9.0)
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", sb)
	add_theme_stylebox_override("pressed", sb)
	add_theme_stylebox_override("focus", sb)

func set_selected_key(on: bool, accent: Color) -> void:
	_style(accent, on)

# 锁：半透明压暗 + 一把小锁（方身体 + 半圆梁），纯几何绘制
func _lock_overlay(accent: Color) -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var lk := Control.new()
	lk.set_anchors_preset(Control.PRESET_FULL_RECT)
	lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lk.draw.connect(func(): _lock_draw(lk))
	add_child(lk)
	lk.queue_redraw()

func _lock_draw(c: Control) -> void:
	var p := c.size * 0.5
	var w := 16.0
	var h := 13.0
	c.draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.15, w, h), Color(0.92, 0.76, 0.30), true)
	c.draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.15, w, h), Color(0.32, 0.24, 0.08), false, 1.5)
	c.draw_arc(Vector2(p.x, p.y - h * 0.15), w * 0.38, PI, TAU, 14,
		Color(0.95, 0.82, 0.38), 2.0, true)
