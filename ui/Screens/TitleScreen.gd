extends CanvasLayer

# 标题页：游戏名 + 一句话玩法 + 开始按钮。
# 开始按钮发 Events.run_requested，由 Main 统一接管开跑（标题页自己只负责隐藏）。
# 出海游戏，主文案用英文；"萝卜突围"作中文品牌副标（项目已嵌 CJK 字体，能正常显示）。

const CharacterPickerScript := preload("res://ui/Screens/CharacterPicker.gd")
const CharDetailScript := preload("res://ui/Screens/CharDetail.gd")
const CharTiers := preload("res://ui/Screens/CharTiers.gd")
const UnlockText := preload("res://ui/UnlockText.gd")
const WeaponPickerScript := preload("res://ui/Screens/WeaponPicker.gd")
const RunModePickerScript := preload("res://ui/Screens/RunModePicker.gd")
const UnlockTreeScript := preload("res://ui/Screens/UnlockTree.gd")
const Save := preload("res://core/Save.gd")

var _root: Control
var _picker_layer: CanvasLayer
var _char_detail: CanvasLayer = null   # D3-4：角色详情独立页（layer 55，盖在本标题页之上）
var _tree: Control = null              # 解锁关系树（layer 54：盖住标题，但低于角色详情 55）
var _tree_layer: CanvasLayer = null
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

	# ⚠️ 不再放"点任意处开始"的全屏热区：它会把角色卡之间的空白、误触都当成"开始"，
	#    在手机上尤其容易跳页（用户反馈"误触返回/乱跳"）。开始只走下方明确的 START 按钮。

	# 游戏名（英文为主，海外玩家一眼看懂）
	var title := _mk_label(44, Color(0.98, 0.86, 0.32), 172.0, 60.0)
	title.text = "TURNIP TROUBLE"
	_root.add_child(title)

	var star_ico := TextureRect.new()
	star_ico.texture = Art.ui_icon("star")
	star_ico.custom_minimum_size = Vector2(28, 28)
	star_ico.set_size(Vector2(28, 28))
	star_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star_ico.set_position(Vector2(256, 128))
	_root.add_child(star_ico)

	# 中文品牌副标（仅中文环境显示，英文环境留白）
	var sub := _mk_label(26, Color(0.92, 0.94, 0.96), 234.0, 40.0)
	var sub_txt := I18n.t("title_sub")
	sub.text = sub_txt
	sub.visible = not sub_txt.is_empty()
	_sub_lbl = sub
	_root.add_child(sub)

	var tag := _mk_label(16, Color(0.70, 0.74, 0.80), 280.0, 28.0)
	tag.text = I18n.t("title_tag")
	_tag_lbl = tag
	_root.add_child(tag)

	# 历史最佳 + 下一个解锁目标：给玩家一个"再来一局"的具体理由
	var bs0 := SaveMgr.best_score()
	var best := _mk_label(14, Color(0.95, 0.82, 0.38), 308.0, 22.0)
	best.text = (I18n.t("title_best") % [bs0, SaveMgr.best_wave()]) if bs0 > 0 else I18n.t("title_first")
	_best_lbl = best
	_root.add_child(best)

	var next := _mk_label(13, Color(0.66, 0.70, 0.78), 732.0, 22.0)
	next.text = _next_text()
	# 没有目标就不留空行（全解锁后）
	next.visible = not next.text.is_empty()
	_next_lbl = next
	_root.add_child(next)

	var how := _mk_label(17, Color(0.82, 0.85, 0.90), 408.0, 72.0)
	how.text = I18n.t("title_how")
	_how_lbl = how
	_root.add_child(how)

	# 单局时长三选一：放在"玩法说明"之上、角色卡之上 —— 开局前最后能改的一个决定，
	# 不能埋在 START 底下（埋了就等于没有）。
	var modes = Control.new()
	modes.set_script(RunModePickerScript)
	_root.add_child(modes)
	modes.set_position(Vector2(0.0, 336.0))

	# ⚠️ 先 add_child 让 CharacterPicker._ready 算真实宽度（卡数×卡宽）再居中 ——
	#    写死 4 卡宽会在角色变多时把末尾卡挤出屏幕
	var picker = Control.new()
	picker.set_script(CharacterPickerScript)
	_root.add_child(picker)
	picker.set_position(Vector2((540.0 - (picker.get("content_size") as Vector2).x) * 0.5, 530.0))
	# D3-4：点角色卡 → 详情独立页（layer 55，必须盖住本页 50，否则点不到）
	_char_detail = CharDetailScript.new()
	get_parent().add_child(_char_detail)
	picker.char_detail_requested.connect(_on_char_detail_requested)
	_char_detail.picked.connect(_on_char_picked)
	# 网格底部（用 content_size 而非 size —— fit_overlay 已把 picker 撑成整屏）
	var p_bottom: float = 530.0 + (picker.get("content_size") as Vector2).y

	# 开局前把这条 build 摊开给玩家看（卡片网格本身够直白，阶梯才是要读的信息）
	var pick_hint := _mk_label(10, Color(0.60, 0.64, 0.72), 482.0, 48.0)
	pick_hint.text = CharTiers.full(Data.character(GameState.character))
	# 英文下阶梯能超一屏宽，必须 autowrap 自由折行（留 3 行高刚好填满不溢出）
	pick_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick_lbl = pick_hint
	_root.add_child(pick_hint)
	Events.character_changed.connect(_on_character_changed)

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
	_next_lbl.position.y = p_bottom + 8.0 + 78.0 + 6.0
	I18n.locale_changed.connect(_on_locale_changed)

	# 开局选武器页：layer=45，压在 HUD(20) 之上、标题(50)之下
	_picker_layer = CanvasLayer.new()
	_picker_layer.layer = 45
	_picker = WeaponPickerScript.new()
	_picker_layer.add_child(_picker)
	_picker.set_back(_on_picker_back)
	get_parent().add_child(_picker_layer)
	_picker_layer.visible = false
	_build_route()

# 本页的 Label 清一色是"字号/颜色/居中/整行宽"四件套，抽个工厂省掉一半样板。
# ⚠️ MOUSE_FILTER_IGNORE 是必须的：文字层在"点任意处开始"热区之上，
#    默认的 STOP 会把落在标题/简介文字上的那一下吃掉 —— 那片区域将怎么戳都没反应。
func _mk_label(fs: int, c: Color, y: float, h: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_position(Vector2(0.0, y))
	l.set_size(Vector2(540.0, h))
	return l

# 解锁关系树：一张图回答"下一个能解锁谁"。layer 54 —— 盖住本页(50)但低于角色
# 详情(55)，所以在树里点节点会顺势叠出那个角色的详情页；入口放右上角空白处，
# 因为它讲的是"还没拿到的萝卜"，不该挤进开始流程那一坨。
func _build_route() -> void:
	_tree_layer = CanvasLayer.new()
	_tree_layer.layer = 54
	_tree = UnlockTreeScript.new()
	_tree_layer.add_child(_tree)
	_tree_layer.visible = false
	get_parent().add_child(_tree_layer)
	_tree.char_detail_requested.connect(_on_char_detail_requested)
	_tree.close_requested.connect(_on_tree_close)
	var btn := Button.new()
	btn.text = UnlockText.btn_route(I18n.locale)
	btn.set_position(Vector2(402.0, 26.0))
	btn.set_size(Vector2(124.0, 38.0))
	btn.add_theme_font_size_override("font_size", 15)
	Art.style_button(btn, Color(0.22, 0.16, 0.09, 0.92), Color(0.98, 0.86, 0.42), Color(0.62, 0.50, 0.20))
	btn.pressed.connect(_on_route)
	_root.add_child(btn)

func _on_route() -> void:
	Sfx.ui_click()
	_tree.show_page()
	_tree_layer.visible = true

func _on_tree_close() -> void:
	Sfx.ui_click()
	_tree_layer.visible = false

# 换角色 = 换一整套阶梯，这行字必须跟着换（不换就会显示上一个角色的 build）
func _on_character_changed(_key: String = "") -> void:
	if _pick_lbl != null:
		_pick_lbl.text = CharTiers.full(Data.character(GameState.character))

# D3-4：点角色卡 → 弹该角色的独立详情页（本命/买什么/点什么技能/怎么玩）
func _on_char_detail_requested(key: String) -> void:
	if _char_detail != null:
		_char_detail.show_for(key)

# 详情页「选他」→ 真正换人（才走 GameState.set_character，触发重算血量/羁绊）
func _on_char_picked(key: String) -> void:
	GameState.set_character(key)
	if _pick_lbl != null:
		_pick_lbl.text = CharTiers.full(Data.character(GameState.character))

func _on_start() -> void:
	# START 是整局的第一次点击：在这里出第一声，保证 Web/iOS 的 AudioContext
	# 在"用户手势内"被解锁（iOS 上手势外出的第一声可能整局静音）。
	Sfx.ui_click()
	# 存档里记过上次的角色就默认选它（省得每次重选）；
	# 但上一个角色已经"被锁"的情况要挡掉 —— 例如清过档、或旧存档里玩的角色现在是阶梯后段的
	var last := SaveMgr.last_character()
	if not last.is_empty() and SaveMgr.is_character_unlocked(last):
		GameState.set_character(last)
	# 兜底：万一当前选中的是锁着的角色（旧存档 / 改过解锁表），退回第一个免费角色，
	# 绝不让"开始"带着一个不该能玩的角色进局
	if not SaveMgr.is_character_unlocked(GameState.character):
		var open := SaveMgr.unlocked_characters()
		if not open.is_empty():
			GameState.set_character(str(open[0]))
	_root.visible = false
	# 进入"选初始武器"页（角色选完 → 选武器 → 开打）。死亡页"再来一局"走
	# run_requested 直接开打、不复用此页，因此仍保留上次选择的初始武器。
	_picker_layer.visible = true

func _on_picker_back() -> void:
	# 从选武器页返回标题：重新显示标题，隐藏选武器页
	_picker.hide_page()   # 顺带收起可能开着的武器详情，下次进来不会顶着一张旧浮层
	_picker_layer.visible = false
	_root.visible = true

func _on_run_requested() -> void:
	# 死亡页"再来一局"也会发这个；标题页本就隐藏，选武器页也要一并收起
	_root.visible = false
	if _picker != null:
		_picker.hide_page()
	if _picker_layer != null:
		_picker_layer.visible = false

func _on_quit_to_title() -> void:
	# 从暂停菜单退出：重新显示标题页（游戏进行中标题页是隐藏的）
	_root.visible = true
	if _picker != null:
		_picker.hide_page()
	if _picker_layer != null:
		_picker_layer.visible = false

func _on_locale_changed(_l: String = "") -> void:
	var sub_txt := I18n.t("title_sub")
	_sub_lbl.text = sub_txt
	_sub_lbl.visible = not sub_txt.is_empty()
	_tag_lbl.text = I18n.t("title_tag")
	var bs := SaveMgr.best_score()
	_best_lbl.text = (I18n.t("title_best") % [bs, SaveMgr.best_wave()]) if bs > 0 else I18n.t("title_first")
	_how_lbl.text = I18n.t("title_how")
	_pick_lbl.text = CharTiers.full(Data.character(GameState.character))
	_start_btn.text = I18n.t("title_start")
	_next_lbl.text = _next_text()
	_next_lbl.visible = not _next_lbl.text.is_empty()

# 标题页底部那行"下一把能拿到什么"：**优先报角色**，没有才报武器。
# 角色比武器值钱 —— 它是"一整条新玩法路线"，玩家看见它更想再来一局（土豆兄弟的做法）。
func _next_text() -> String:
	var nc := SaveMgr.next_character_unlock()
	if not nc.is_empty():
		var key := str(nc.get("key", ""))
		var dep := str(nc.get("char", ""))
		var who := I18n.pick(Data.character(dep)) if Data.characters.has(dep) else ""
		# next_hint 里留着角色 key 的占位，这里换成显示名（中英两套词都在 ui/UnlockText.gd）
		return UnlockText.next_hint(nc, who, I18n.locale).replace(key, I18n.pick(Data.character(key)))
	var nx := SaveMgr.next_unlock()
	if nx.is_empty():
		return ""
	var wname := I18n.pick(Data.weapon(str(nx["key"])))
	return I18n.t("title_next") % [
		wname.to_upper(), int(nx["left"]), I18n.stat_label(str(nx["type"]))]
