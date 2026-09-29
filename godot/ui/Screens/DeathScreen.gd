extends CanvasLayer

# 死亡页：告诉玩家"你撑到第几波、杀了多少"，然后一键重开。
# 重开用 reload_current_scene —— GameState 会在 Game._ready() 里自动 reset，不用手动清状态。

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
	_title.text = "被吃掉了"
	_title.add_theme_font_size_override("font_size", 38)
	_title.set_position(Vector2(150, 300))
	_root.add_child(_title)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 20)
	_stat.set_position(Vector2(150, 370))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = "再来一局"
	_btn.set_size(Vector2(300, 74))
	_btn.set_position(Vector2(120, 470))
	_btn.add_theme_font_size_override("font_size", 24)
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _show() -> void:
	_stat.text = "撑到第 %d 波 · 击杀 %d 个" % [GameState.wave, GameState.kills]
	_root.visible = true

func _restart() -> void:
	get_tree().reload_current_scene()
