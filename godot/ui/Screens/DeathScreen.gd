extends CanvasLayer

# 死亡页：告诉玩家"你撑到第几波、杀了多少"，然后一键重开。
# 重开发 Events.run_requested —— 由 Main 调 Game.start_run() 回收并重置，比 reload 场景更干净。

var _root: Control
var _title: Label
var _stat: Label
var _btn: Button

func _ready() -> void:
	layer = 40
	_build()
	_root.visible = false
	Events.player_died.connect(_show)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.02, 0.03, 0.78)
	_root.add_child(shade)

	_title = Label.new()
	_title.text = "GAME OVER"
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.96, 0.55, 0.45))
	_title.set_position(Vector2(150, 300))
	_root.add_child(_title)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 20)
	_stat.set_position(Vector2(150, 372))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = "PLAY AGAIN"
	_btn.set_size(Vector2(300, 74))
	_btn.set_position(Vector2(120, 470))
	_btn.add_theme_font_size_override("font_size", 24)
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _show() -> void:
	_stat.text = "Reached Wave %d  ·  %d Kills" % [GameState.wave, GameState.kills]
	_root.visible = true

func _restart() -> void:
	_root.visible = false
	Events.run_requested.emit()
