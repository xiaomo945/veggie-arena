extends RefCounted

# 设置菜单的控件工厂：只管"造出来的控件长什么样"，不含任何文案 / 业务。
#
# 为什么拆出来：SettingsMenu.gd 已经顶到架构守卫的 300 行红线，而它还在不断加
# 条目（画质、语言、帧率、移动速度……）。把纯造控件的代码挪走，菜单本体就只剩
# "布局 + 接线"，再加新条目也不会碰红线。
#
# ⚠️ 不用 class_name：check.sh 会清 .godot/editor，headless 下全局类表不重建，
# 写了就会 "Identifier not declared"。一律 preload 引用。

const WIDTH := 540.0

# 居中标签。返回引用，文案由调用方填（可能随语言变化）
static func label(parent: Node, y: float, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_position(Vector2(0, y))
	l.set_size(Vector2(WIDTH, 26))
	parent.add_child(l)
	return l

# 滑块（默认 0~100；调用方可再改 min/max/step）
static func slider(parent: Node, y: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.custom_minimum_size = Vector2(360, 30)
	s.size = Vector2(360, 30)
	s.position = Vector2((WIDTH - 360) * 0.5, y)
	s.add_theme_font_size_override("font_size", 14)
	parent.add_child(s)
	return s

# 开关按钮（震屏 / 粒子）。回调由调用方连接
static func toggle(parent: Node, y: float) -> Button:
	var b := Button.new()
	b.set_size(Vector2(300, 52))
	b.set_position(Vector2((WIDTH - 300) * 0.5, y))
	b.add_theme_font_size_override("font_size", 18)
	parent.add_child(b)
	return b

# 一排居中按钮（画质三选一 / 语言二选一），返回 [{btn, val}]
static func button_row(parent: Node, count: int, y: float, cb: Callable) -> Array:
	var w := 100.0
	var gap := 10.0
	var start := (WIDTH - (float(count) * w + float(count - 1) * gap)) * 0.5
	var out: Array = []
	for i in count:
		var b := Button.new()
		b.set_size(Vector2(w, 56))
		b.set_position(Vector2(start + float(i) * (w + gap), y))
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(cb.bind(i))
		parent.add_child(b)
		out.append({"btn": b, "val": i})
	return out

# 选中 / 未选中的高亮底（normal + pressed 两套，按下时更亮一点）
static func set_active(b: Button, on: bool) -> void:
	if b == null:
		return
	var sb := StyleBoxFlat.new()
	if on:
		sb.bg_color = Color(0.92, 0.42, 0.26, 0.35)
		sb.border_color = Color(1.0, 0.72, 0.42, 1.0)
	else:
		sb.bg_color = Color(0.2, 0.22, 0.28, 0.6)
		sb.border_color = Color(0.4, 0.45, 0.55, 0.8)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(1.0, 0.6, 0.4, 0.5)
	b.add_theme_stylebox_override("pressed", sbp)
