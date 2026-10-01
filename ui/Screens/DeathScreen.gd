extends CanvasLayer

# 死亡页：告诉玩家"你撑到第几波、杀了多少、攒了多少分"，然后一键重开。
# 重开发 Events.run_requested —— 由 Main 调 Game.start_run() 回收并重置，比 reload 场景更干净。
# 结算分与胜利页共用 core/Run.gd 的口径。

var _root: Control
var _title: Label
var _stat: Label
var _btn: Button

const Run := preload("res://core/Run.gd")

func _ready() -> void:
	layer = 40
	_build()
	_root.visible = false
	Events.player_died.connect(_show)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.02, 0.03, 0.78)
	_root.add_child(shade)

	_title = Label.new()
	_title.text = I18n.t("death_title")
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.96, 0.55, 0.45))
	_title.set_position(Vector2(150, 300))
	_root.add_child(_title)

	# 装饰：标题上方居中的 "失败" 图标
	var lose_ico := TextureRect.new()
	lose_ico.texture = Art.ui_icon("lose")
	lose_ico.custom_minimum_size = Vector2(28, 28)
	lose_ico.set_size(Vector2(28, 28))
	lose_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lose_ico.set_position(Vector2(256, 252))
	_root.add_child(lose_ico)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 20)
	_stat.set_position(Vector2(150, 372))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = I18n.t("death_again")
	_btn.set_size(Vector2(300, 74))
	_btn.set_position(Vector2(120, 470))
	_btn.add_theme_font_size_override("font_size", 24)
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _show() -> void:
	var sc := Run.score(GameState.kills, GameState.gold, GameState.wave)
	_stat.text = I18n.t("death_stat") % [
		GameState.wave, GameState.kills, GameState.gold, sc]
	_root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_title.text = I18n.t("death_title")
	_btn.text = I18n.t("death_again")
	if _root != null and _root.visible:
		_show()

func _restart() -> void:
	_root.visible = false
	Events.run_requested.emit()
