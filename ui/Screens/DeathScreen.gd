extends CanvasLayer

# 死亡页：告诉玩家"你撑到第几波、杀了多少、攒了多少分"，然后一键重开。
# 重开发 Events.run_requested —— 由 Main 调 Game.start_run() 回收并重置，比 reload 场景更干净。
# 结算分与胜利页共用 core/Run.gd 的口径。
#
# 卡通基调：不搞灰暗失败页 —— 暖橙夜色 + 瘫倒冒圈的萝卜 + 绕头打转的小星星，
# "这局输啦，没事，再来一局！"的轻松感。

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
	shade.color = Color(0.10, 0.05, 0.03, 0.85)   # 暖棕夜色，不是冷灰
	_root.add_child(shade)

	# 晕头转向的萝卜（瘫倒 + 星星绕圈）
	var dizzy: Control = Dizzy.new()
	dizzy.position = Vector2(270, 212)
	dizzy.size = Vector2(8, 8)
	_root.add_child(dizzy)

	_title = Label.new()
	_title.text = I18n.t("death_title")
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color(1.0, 0.68, 0.38))
	_title.add_theme_color_override("font_outline_color", Color(0.28, 0.12, 0.05))
	_title.add_theme_constant_override("outline_size", 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_size(Vector2(540, 54))
	_title.set_position(Vector2(0, 306))
	_root.add_child(_title)

	# 结算卡片：和胜利页同一套"数字捧起来"的画法，口径一致
	var card := Panel.new()
	card.set_size(Vector2(368, 118))
	card.set_position(Vector2(86, 384))
	card.add_theme_stylebox_override("panel", _card_box())
	_root.add_child(card)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 19)
	_stat.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
	_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat.set_size(Vector2(368, 112))
	_stat.set_position(Vector2(86, 387))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = I18n.t("death_again")
	_btn.set_size(Vector2(300, 76))
	_btn.set_position(Vector2(120, 536))
	_btn.add_theme_font_size_override("font_size", 25)
	Art.style_button(_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.11, 0.07, 0.92)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.76, 0.50, 0.24, 0.9)
	sb.set_border_width_all(2)
	return sb

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

# 阵亡装饰：萝卜躺平冒圈圈（转 90° 瘫倒）+ 三颗星星绕头打转——
# 经典卡通"晕了"的语言，一看就懂，不苦大仇深。仅旋转角度入 _process，单节点重绘。
class Dizzy extends Control:
	var _orb := 0.0
	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	func _process(delta: float) -> void:
		_orb += delta * 2.4
		if visible:
			queue_redraw()
	func _draw() -> void:
		# 地上一小片影子，让"躺平"贴地
		draw_set_transform(Vector2(0, 62), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 62.0, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var hero := Art.sprite("player")
		if hero != null:
			var hs := 124.0
			draw_set_transform(Vector2(0, 6), PI * 0.5, Vector2.ONE)
			draw_texture_rect_region(hero, Rect2(-hs * 0.5, -hs * 0.5, hs, hs),
				Rect2(Vector2.ZERO, hero.get_size()))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 绕头打转的三颗星星
		for i in 3:
			var a := _orb + TAU * float(i) / 3.0
			var p := Vector2(cos(a) * 70.0, sin(a) * 24.0 - 46.0)
			_star(p, 9.0, Color(1.0, 0.82, 0.30))
	func _star(p: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0
			pts.push_back(p + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, col)
