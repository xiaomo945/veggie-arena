extends CanvasLayer

# 标题页：游戏名 + 一句话玩法 + 开始按钮。
# 开始按钮发 Events.run_requested，由 Main 统一接管开跑（标题页自己只负责隐藏）。
# 出海游戏，主文案用英文；"萝卜突围"作中文品牌副标（项目已嵌 CJK 字体，能正常显示）。

var _root: Control

func _ready() -> void:
	layer = 50
	_build()
	Events.run_requested.connect(_on_run_requested)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 半透明遮罩，让背后的竞技场隐约可见，更有"进游戏"的期待感
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.06, 0.09, 0.82)
	_root.add_child(shade)

	# 装饰：顶部一条细金线
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.color = Color(0.0, 0.0, 0.0, 0.0)
	_root.add_child(line)

	# 游戏名（英文为主，海外玩家一眼看懂）
	var title := Label.new()
	title.text = "TURNIP TROUBLE"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_position(Vector2(0, 196))
	title.set_size(Vector2(540, 60))
	_root.add_child(title)

	# 中文品牌副标
	var sub := Label.new()
	sub.text = "萝 卜 突 围"
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_position(Vector2(0, 258))
	sub.set_size(Vector2(540, 40))
	_root.add_child(sub)

	# 一句话定位
	var tag := Label.new()
	tag.text = "Survive the veggie apocalypse"
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(0.70, 0.74, 0.80))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.set_position(Vector2(0, 304))
	tag.set_size(Vector2(540, 28))
	_root.add_child(tag)

	# 玩法说明
	var how := Label.new()
	how.text = "Drag the joystick to move\nWeapons fire on their own\nClear waves · grab gold · get stronger"
	how.add_theme_font_size_override("font_size", 17)
	how.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.set_position(Vector2(0, 400))
	how.set_size(Vector2(540, 96))
	_root.add_child(how)

	# 开始按钮
	var btn := Button.new()
	btn.text = "START"
	btn.set_size(Vector2(280, 78))
	btn.set_position(Vector2((540 - 280) * 0.5, 600))
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_color_override("font_color", Color(0.07, 0.08, 0.05))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.98, 0.86, 0.32)
	n.border_width_bottom = 5
	n.border_color = Color(0.72, 0.60, 0.16)
	btn.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat
	hov.bg_color = Color(1.0, 0.94, 0.50)
	btn.add_theme_stylebox_override("hover", hov)
	btn.pressed.connect(_on_start)
	_root.add_child(btn)

func _on_start() -> void:
	_root.visible = false
	Events.run_requested.emit()

func _on_run_requested() -> void:
	# 死亡页"再来一局"也会发这个；标题页本就隐藏，无需再处理
	_root.visible = false
