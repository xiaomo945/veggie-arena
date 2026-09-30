extends CanvasLayer

# 胜利页：撑过最后一波后弹出，展示通关结算（波次 / 击杀 / 金币 / 总分），一键重开。
# 重开发 Events.run_requested —— 由 Main 接管 Game.start_run() 回收并重置，比 reload 场景干净。
# 结算分复用 core/Run.gd 的纯逻辑，和死亡页保持一致口径。

const Run := preload("res://core/Run.gd")

var _root: Control
var _title: Label
var _stat: Label
var _btn: Button

func _ready() -> void:
	layer = 41
	_build()
	_root.visible = false
	Events.run_won.connect(_show)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.06, 0.04, 0.80)
	_root.add_child(shade)

	_title = Label.new()
	_title.text = "VICTORY!"
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.45))
	_title.set_position(Vector2(160, 290))
	_root.add_child(_title)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 20)
	_stat.set_position(Vector2(150, 366))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = "PLAY AGAIN"
	_btn.set_size(Vector2(300, 74))
	_btn.set_position(Vector2(120, 470))
	_btn.add_theme_font_size_override("font_size", 24)
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _show() -> void:
	var sc := Run.score(GameState.kills, GameState.gold, GameState.wave)
	_stat.text = "Cleared Wave %d\n%d Kills  ·  %d Gold\nSCORE %d" % [
		GameState.wave, GameState.kills, GameState.gold, sc]
	_root.visible = true

func _restart() -> void:
	_root.visible = false
	Events.run_requested.emit()
