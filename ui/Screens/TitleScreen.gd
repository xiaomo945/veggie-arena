extends CanvasLayer

# 标题页：游戏名 + 一句话玩法 + 开始按钮。
# 开始按钮发 Events.run_requested，由 Main 统一接管开跑（标题页自己只负责隐藏）。
# 出海游戏，主文案用英文；"萝卜突围"作中文品牌副标（项目已嵌 CJK 字体，能正常显示）。

const CharacterPickerScript := preload("res://ui/Screens/CharacterPicker.gd")
const CharTiers := preload("res://ui/Screens/CharTiers.gd")
const WeaponPickerScript := preload("res://ui/Screens/WeaponPicker.gd")
const RunModePickerScript := preload("res://ui/Screens/RunModePicker.gd")
const Save := preload("res://core/Save.gd")

var _root: Control
var _picker_layer: CanvasLayer
var _picker
var _sub_lbl: Label
var _tag_lbl: Label
var _best_lbl: Label
var _next_lbl: Label
var _how_lbl: Label
var _pick_lbl: Label
var _start_btn: Button

func _ready() -> void:
	layer = 50
	_build()
	ScreenMode.fit_overlay(_root)   # 横屏下把竖屏菜单缩放到 960x540 视口内、居中
	Events.run_requested.connect(_on_run_requested)
	Events.quit_to_title_requested.connect(_on_quit_to_title)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 半透明遮罩，让背后的竞技场隐约可见，更有"进游戏"的期待感
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.06, 0.09, 0.82)
	_root.add_child(shade)

	# 全屏"点任意处开始"热区：标题页本就为开始游戏存在，
	# 玩家戳屏幕任意空白处即进入（符合"点一下就关掉标题"的直觉）。
	# 放在遮罩之后、各文案/按钮之前：角色卡与 START 在它之上，仍各自响应自己的点击。
	var catch := Button.new()
	catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	catch.flat = true
	catch.focus_mode = Control.FOCUS_NONE
	catch.mouse_filter = Control.MOUSE_FILTER_STOP
	var inv := StyleBoxFlat.new()
	inv.bg_color = Color(0, 0, 0, 0)
	catch.add_theme_stylebox_override("normal", inv)
	catch.add_theme_stylebox_override("hover", inv)
	catch.add_theme_stylebox_override("pressed", inv)
	catch.add_theme_stylebox_override("focus", inv)
	catch.pressed.connect(_on_start)
	_root.add_child(catch)

	# 游戏名（英文为主，海外玩家一眼看懂）
	var title := Label.new()
	title.text = "TURNIP TROUBLE"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_position(Vector2(0, 172))
	title.set_size(Vector2(540, 60))
	_root.add_child(title)

	# 装饰：标题上方居中一颗星
	var star_ico := TextureRect.new()
	star_ico.texture = Art.ui_icon("star")
	star_ico.custom_minimum_size = Vector2(28, 28)
	star_ico.set_size(Vector2(28, 28))
	star_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star_ico.set_position(Vector2(256, 128))
	_root.add_child(star_ico)

	# 中文品牌副标（仅中文环境显示，英文环境留白）
	var sub := Label.new()
	var sub_txt := I18n.t("title_sub")
	sub.text = sub_txt
	sub.visible = not sub_txt.is_empty()
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_position(Vector2(0, 234))
	sub.set_size(Vector2(540, 40))
	_sub_lbl = sub
	_root.add_child(sub)

	# 一句话定位
	var tag := Label.new()
	tag.text = I18n.t("title_tag")
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(0.70, 0.74, 0.80))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.set_position(Vector2(0, 280))
	tag.set_size(Vector2(540, 28))
	_tag_lbl = tag
	_root.add_child(tag)

	# 历史最佳 + 下一个解锁目标：给玩家一个"再来一局"的具体理由
	var best := Label.new()
	var bs := SaveMgr.best_score()
	best.text = (I18n.t("title_best") % [bs, SaveMgr.best_wave()]) if bs > 0 else I18n.t("title_first")
	best.add_theme_font_size_override("font_size", 14)
	best.add_theme_color_override("font_color", Color(0.95, 0.82, 0.38))
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best.set_position(Vector2(0, 308))
	best.set_size(Vector2(540, 22))
	_best_lbl = best
	_root.add_child(best)

	var nx := SaveMgr.next_unlock()
	if not nx.is_empty():
		var nd := Data.weapon(str(nx["key"]))
		var wname := I18n.pick(nd)
		var next := Label.new()
		next.text = I18n.t("title_next") % [
			wname.to_upper(), int(nx["left"]), I18n.stat_label(str(nx["type"]))]
		next.add_theme_font_size_override("font_size", 13)
		next.add_theme_color_override("font_color", Color(0.66, 0.70, 0.78))
		next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next.set_position(Vector2(0, 732))
		next.set_size(Vector2(540, 22))
		_next_lbl = next
		_root.add_child(next)

	# 玩法说明
	var how := Label.new()
	how.text = I18n.t("title_how")
	how.add_theme_font_size_override("font_size", 17)
	how.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.set_position(Vector2(0, 420))
	how.set_size(Vector2(540, 84))
	_how_lbl = how
	_root.add_child(how)

	# 单局时长三选一：放在"玩法说明"之上、角色卡之上 —— 开局前最后能改的一个决定，
	# 不能埋在 START 底下（埋了就等于没有）。
	var modes = Control.new()
	modes.set_script(RunModePickerScript)
	_root.add_child(modes)
	modes.set_position(Vector2(0.0, 336.0))

	# 角色选择：卡片横排，点一下换人（换的是属性加成 + 外观）
	# ⚠️ 先 add_child 让 CharacterPicker._ready 算出真实宽度（卡数×卡宽），
	#    再按真实宽度居中 —— 写死 4 卡宽（414px）会在角色变 5 个时把末尾卡挤出屏幕
	var picker = Control.new()
	picker.set_script(CharacterPickerScript)
	_root.add_child(picker)
	picker.set_position(Vector2((540.0 - (picker.get("content_size") as Vector2).x) * 0.5, 530.0))
	# 角色网格底部：START 与"下一把解锁"提示都按它定位（角色变多、网格变高也不会被盖）。
	# 用 content_size（网格真实高度），不能用 picker.size —— fit_overlay 已把它撑成整屏。
	var p_bottom: float = 530.0 + (picker.get("content_size") as Vector2).y

	# 这一行是"这条 build 长什么样"：本命/羁绊每一档给多少，开局前就摊开给玩家看。
	# 原来是"选一个萝卜"的提示 —— 卡片网格本身已经够直白，而阶梯才是玩家真正要读的信息。
	var pick_hint := Label.new()
	pick_hint.text = CharTiers.line(Data.character(GameState.character))
	pick_hint.add_theme_font_size_override("font_size", 11)
	pick_hint.add_theme_color_override("font_color", Color(0.60, 0.64, 0.72))
	pick_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_hint.set_position(Vector2(0, 508))
	pick_hint.set_size(Vector2(540, 20))
	_pick_lbl = pick_hint
	_root.add_child(pick_hint)
	Events.character_changed.connect(_on_character_changed)

	# 开始按钮
	var btn := Button.new()
	btn.text = I18n.t("title_start")
	btn.set_size(Vector2(280, 78))
	# 跟随角色网格底部（网格 2 行时不再被 START 压住）
	btn.set_position(Vector2((540 - 280) * 0.5, p_bottom + 8.0))
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
	_start_btn = btn
	_root.add_child(btn)
	# "下一把解锁"提示挪到 START 之下（同样跟随网格高度）
	if _next_lbl != null:
		_next_lbl.position.y = p_bottom + 8.0 + 78.0 + 6.0
	I18n.locale_changed.connect(_on_locale_changed)

	# 开局选武器页：包进 layer=45 的 CanvasLayer，压在 HUD(20) 之上、标题(50)之下。
	# 标题隐藏时它才可见，负责"角色选完 → 选武器 → 开打"的最后一步。
	_picker_layer = CanvasLayer.new()
	_picker_layer.layer = 45
	_picker = WeaponPickerScript.new()
	_picker_layer.add_child(_picker)
	_picker.set_back(_on_picker_back)
	get_parent().add_child(_picker_layer)
	_picker_layer.visible = false

# 换角色 = 换一整套阶梯，这行字必须跟着换（不换就会显示上一个角色的 build）
func _on_character_changed(_key: String = "") -> void:
	if _pick_lbl != null:
		_pick_lbl.text = CharTiers.line(Data.character(GameState.character))

func _on_start() -> void:
	# START 是整局的第一次点击：在这里出第一声，保证 Web/iOS 的 AudioContext
	# 在"用户手势内"被解锁（iOS 上手势外出的第一声可能整局静音）。
	Sfx.ui_click()
	# 存档里记过上次的角色就默认选它（省得每次重选）
	var last := SaveMgr.last_character()
	if not last.is_empty() and Data.characters.has(last):
		GameState.set_character(last)
	_root.visible = false
	# 进入"选初始武器"页（角色选完 → 选武器 → 开打）。死亡页"再来一局"走
	# run_requested 直接开打、不复用此页，因此仍保留上次选择的初始武器。
	_picker_layer.visible = true

func _on_picker_back() -> void:
	# 从选武器页返回标题：重新显示标题，隐藏选武器页
	_picker_layer.visible = false
	_root.visible = true

func _on_run_requested() -> void:
	# 死亡页"再来一局"也会发这个；标题页本就隐藏，选武器页也要一并收起
	_root.visible = false
	if _picker_layer != null:
		_picker_layer.visible = false

func _on_quit_to_title() -> void:
	# 从暂停菜单退出：重新显示标题页（游戏进行中标题页是隐藏的）
	_root.visible = true
	if _picker_layer != null:
		_picker_layer.visible = false

func _on_locale_changed(_l: String = "") -> void:
	var sub_txt := I18n.t("title_sub")
	_sub_lbl.text = sub_txt
	_sub_lbl.visible = not sub_txt.is_empty()
	_tag_lbl.text = I18n.t("title_tag")
	var bs := SaveMgr.best_score()
	_best_lbl.text = (I18n.t("title_best") % [bs, SaveMgr.best_wave()]) if bs > 0 else I18n.t("title_first")
	if _next_lbl != null:
		var nx := SaveMgr.next_unlock()
		if not nx.is_empty():
			var wname := I18n.pick(Data.weapon(str(nx["key"])))
			_next_lbl.text = I18n.t("title_next") % [wname.to_upper(), int(nx["left"]), I18n.stat_label(str(nx["type"]))]
	_how_lbl.text = I18n.t("title_how")
	_pick_lbl.text = I18n.t("title_pick")
	_start_btn.text = I18n.t("title_start")
