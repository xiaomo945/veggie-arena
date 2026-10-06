extends CanvasLayer

# 胜利页：撑过最后一波后弹出，展示通关结算（波次 / 击杀 / 金币 / 总分），一键重开。
# 重开发 Events.run_requested —— 由 Main 接管 Game.start_run() 回收并重置，比 reload 场景干净。
# 结算分复用 core/Run.gd 的纯逻辑，和死亡页保持一致口径。
#
# 卡通仪式感：旋转金光（节点自转零重绘）+ 萝卜主厨举锅铲 + 撒星星金币，
# 统计收进圆角卡片，金色大按钮收官。

const Run := preload("res://core/Run.gd")
const Recap := preload("res://ui/Screens/RunSynergyRecap.gd")

var _root: Control
var _deco: Control
var _title: Label
var _stat: Label
var _recap: Label
var _btn: Button

func _ready() -> void:
	layer = 41
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)   # 横屏下把竖屏菜单缩放到 960x540 视口内、居中
	Events.run_won.connect(_show)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.07, 0.05, 0.02, 0.86)   # 暖夜色，不压庆祝感
	_root.add_child(shade)

	# 旋转金光：慢慢转的高光时刻背景（只改 rotation，不重绘）
	var rays: Control = Rays.new()
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rays)

	# 庆祝装饰：萝卜主厨 + 撒花
	_deco = Celebration.new()
	_deco.position = Vector2(270, 205)
	_deco.size = Vector2(8, 8)
	_root.add_child(_deco)

	_title = Label.new()
	_title.text = I18n.t("victory_title")
	_title.add_theme_font_size_override("font_size", 46)
	_title.add_theme_color_override("font_color", Color(0.99, 0.86, 0.40))
	_title.add_theme_color_override("font_outline_color", Color(0.30, 0.18, 0.05))
	_title.add_theme_constant_override("outline_size", 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_size(Vector2(540, 56))
	_title.set_position(Vector2(0, 306))
	_root.add_child(_title)

	# 结算卡片：把数字捧起来，别让它们飘在黑底上
	var card := Panel.new()
	card.set_size(Vector2(368, 118))
	card.set_position(Vector2(86, 384))
	card.add_theme_stylebox_override("panel", _card_box())
	_root.add_child(card)

	_stat = Label.new()
	_stat.add_theme_font_size_override("font_size", 19)
	_stat.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat.set_size(Vector2(368, 112))
	_stat.set_position(Vector2(86, 387))
	_root.add_child(_stat)

	_btn = Button.new()
	_btn.text = I18n.t("victory_again")
	_btn.set_size(Vector2(300, 76))
	# 羁绊复盘：通关也要复盘（"我这次是靠堆满手枪赢的"，下一局才知道怎么复制）
	_recap = Label.new()
	_recap.add_theme_font_size_override("font_size", 13)
	_recap.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	_recap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recap.set_size(Vector2(540, 22))
	_recap.set_position(Vector2(0, 508))
	_root.add_child(_recap)

	_btn.set_position(Vector2(120, 536))
	_btn.add_theme_font_size_override("font_size", 25)
	Art.style_button(_btn, Color(0.98, 0.80, 0.22), Color(0.30, 0.19, 0.05), Color(0.88, 0.66, 0.16))
	_btn.pressed.connect(_restart)
	_root.add_child(_btn)

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.12, 0.06, 0.92)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.80, 0.60, 0.26, 0.9)
	sb.set_border_width_all(2)
	return sb

func _show() -> void:
	var sc := Run.score(GameState.kills, GameState.gold, GameState.wave)
	_stat.text = I18n.t("victory_stat") % [
		GameState.wave, GameState.kills, GameState.gold, sc]
	_recap.text = Recap.text()   # 羁绊复盘：这局堆到哪了，下一局才知道该往哪走
	_root.visible = true
	# 登场小动画：装饰从 0.4 弹到 1（一次性 Tween，弹完就不占性能）
	_deco.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(_deco, "scale", Vector2.ONE, 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_locale_changed(_l: String = "") -> void:
	_title.text = I18n.t("victory_title")
	_btn.text = I18n.t("victory_again")
	# 若结算页正显示，顺带刷新统计文案
	if _root != null and _root.visible:
		_show()

func _restart() -> void:
	_root.visible = false
	Events.run_requested.emit()

# 通关金光：12 道淡金扇形从中心辐射，节点自转（_process 只加 rotation，不重绘）
class Rays extends Control:
	var _pivot := Vector2(270, 340)
	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		rotation += delta * 0.3
	func _draw() -> void:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var col := Color(1.0, 0.85, 0.35, 0.12 if i % 2 == 0 else 0.06)
			draw_colored_polygon(PackedVector2Array([
				_pivot,
				_pivot + Vector2.from_angle(a) * 460.0,
				_pivot + Vector2.from_angle(a + 0.10) * 460.0]), col)

# 庆祝装饰：萝卜主厨高举锅铲 + 两侧星星金币撒花（一次画好，弹出时整体弹跳）
class Celebration extends Control:
	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	func _draw() -> void:
		var hero := Art.sprite("player")
		if hero != null:
			var hs := 150.0
			draw_texture_rect_region(hero, Rect2(-hs * 0.5, -hs * 0.58, hs, hs),
				Rect2(Vector2.ZERO, hero.get_size()))
		var ladle := Art.icon("weapon_ladle")
		if ladle != null:
			# 举过头顶右侧的锅铲：转 40°，别挡住笑脸
			var ls := 58.0
			draw_set_transform(Vector2(88, -68), -0.7, Vector2.ONE)
			draw_texture_rect_region(ladle, Rect2(-ls * 0.5, -ls * 0.5, ls, ls),
				Rect2(Vector2.ZERO, ladle.get_size()))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_star(Vector2(-126, -66), 16.0, Color(1.0, 0.82, 0.30))
		_star(Vector2(120, -74), 13.0, Color(1.0, 0.62, 0.36))
		_star(Vector2(-100, 52), 11.0, Color(0.72, 0.90, 0.48))
		_star(Vector2(104, 58), 14.0, Color(1.0, 0.85, 0.42))
		var coin := Art.coin_icon()
		if coin != null:
			draw_texture_rect_region(coin, Rect2(-152, -16, 30, 30),
				Rect2(Vector2.ZERO, coin.get_size()))
			draw_texture_rect_region(coin, Rect2(126, 14, 24, 24),
				Rect2(Vector2.ZERO, coin.get_size()))
	func _star(p: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0
			pts.push_back(p + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, col)
