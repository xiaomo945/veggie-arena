extends Control

# 开局选初始武器页：标题页"开始"之后、正式开打之前弹出（由 TitleScreen 包进 layer=45）。
#
# 【本轮改动】候选池从"写死 6 把基础武器"改成"**所有已解锁的武器**"。
# 之前就算你把 40 把全解锁了，开局也只能挑那 6 把 —— 解锁系统一半的意义被这里吃掉了。
# 列表变长后顺带做三件事：
#   1) 网格可滚动（ScrollContainer），不再靠"截前 6 个"来塞进一屏
#   2) 点卡片不再直接选中，改为弹**武器详情独立页**（数值/打法/套装/谁拿它最狠），
#      详情页里的「选它」才落定 —— 与角色选角的交互完全对称
#   3) 卡片本身抽成 ui/Screens/WeaponCard.gd（架构守卫 R1：单文件 ≤300 行）
#
# 确认：写 GameState.start_weapon（所选 + 手枪保底），再发 Events.run_requested 开跑。
# 返回：回到标题页（back_cb 回调由 TitleScreen 注入）。

const WeaponCardScript := preload("res://ui/Screens/WeaponCard.gd")
const WeaponDetailScript := preload("res://ui/Screens/WeaponDetail.gd")
const WeaponInfo := preload("res://ui/WeaponInfo.gd")

# 手枪是保底武器，任何时候都带：从"可选列表"里剔除，
# 免得玩家选了手枪后本局开局只剩一把武器。
const BACKUP := "pistol"

const MARGIN_X := 16.0
const COLS := 2
const GAP := 12.0
# 卡宽按屏幕宽算死（不是读 grid.size.x）：_ready 那一刻容器还没布局，
# 读出来是 0，会让第一批卡被塞成 64px 的细条之后再也不修正。
const CARD_W := (540.0 - 2.0 * MARGIN_X - float(COLS - 1) * GAP) / float(COLS)

var back_cb: Callable = Callable()
var _keys: Array = []
var _selected := ""
var _cards: Dictionary = {}   # key → WeaponCard
var _detail = null            # WeaponDetail：详情由本页自己持有，跟着本页一起显隐
var _loadout_lbl: Label
var _count_lbl: Label

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(540.0, 900.0)
	_build_layout()
	_refresh_pool()
	I18n.locale_changed.connect(_on_locale_changed)
	ScreenMode.fit_overlay(self)   # 横屏下把竖屏选武器页缩放到 960x540 视口内、居中
	_build_detail()

# 骨架：标题 / 提示 / 可滚动网格 / 阵容提示 / 确认 / 返回
# 用容器（而不是自绘）的原因：候选池最多 40 把，滚动必须由引擎来管才不会拧巴
func _build_layout() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.06, 0.09, 0.86)
	add_child(shade)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = MARGIN_X
	vb.offset_right = -MARGIN_X
	vb.offset_top = 24.0
	vb.offset_bottom = -20.0
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)

	var title := Label.new()
	title.text = I18n.t("pick_weapon_title")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.99, 0.87, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var hint := Label.new()
	hint.text = I18n.t("pick_weapon_hint")
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 12)
	_count_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_count_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.name = "Grid"
	scroll.add_child(grid)

	_loadout_lbl = Label.new()
	_loadout_lbl.add_theme_font_size_override("font_size", 15)
	_loadout_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40))
	_loadout_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_loadout_lbl)

	var confirm := Button.new()
	confirm.text = I18n.t("pick_weapon_confirm")
	confirm.custom_minimum_size = Vector2(360.0, 70.0)
	confirm.add_theme_font_size_override("font_size", 26)
	Art.style_button(confirm, Color(0.98, 0.86, 0.32), Color(0.07, 0.08, 0.05), Color(0.72, 0.60, 0.16))
	confirm.pressed.connect(_on_confirm)
	vb.add_child(confirm)

	var back := Button.new()
	back.text = I18n.t("pick_weapon_back")
	back.custom_minimum_size = Vector2(200.0, 48.0)
	back.add_theme_font_size_override("font_size", 18)
	Art.style_button(back, Color(0.22, 0.15, 0.08, 0.9), Color(0.85, 0.88, 0.92), Color(0.55, 0.44, 0.26, 0.9))
	back.pressed.connect(_on_back)
	vb.add_child(back)

# 详情是本页自己持有的 —— 挂在最后一层子节点上才有正确的盖层顺序，
# 而且主页一收起（返回标题 / 开局）详情自动一起消失，不会留下孤儿浮层。
func _build_detail() -> void:
	_detail = WeaponDetailScript.new()
	add_child(_detail)
	_detail.picked.connect(select)

# 候选池 = 所有已解锁武器（去重、剔除保底手枪）。
# 一局结束后可能新解锁了武器，所以每次页面显示都要重算，不能只在 _ready 里算一次。
func _refresh_pool() -> void:
	var grid := _grid()
	if grid == null:
		return
	var unlocked: Array = SaveMgr.unlocked_weapons()
	var keys := []
	for k in unlocked:
		var key := str(k)
		if key == BACKUP or keys.has(key):
			continue
		keys.append(key)
	keys.sort()
	_keys = keys
	_rebuild_cards(grid)
	if not _keys.has(_selected):
		_selected = str(_keys[0]) if not _keys.is_empty() else ""
	_count_lbl.text = WeaponInfo.pool_hint(unlocked.size(), Data.weapons.size(), I18n.locale)
	_refresh_selection()

func _grid() -> GridContainer:
	var node := find_child("Grid", true, false)
	return node as GridContainer if node != null else null

func _rebuild_cards(grid: GridContainer) -> void:
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	_cards = {}
	for key in _keys:
		var card = WeaponCardScript.new()
		card.setup(str(key), CARD_W)
		grid.add_child(card)
		card.pressed.connect(_on_card.bind(str(key)))
		_cards[str(key)] = card

func set_back(cb: Callable) -> void:
	back_cb = cb

func show_page() -> void:
	visible = true
	_refresh_pool()

func hide_page() -> void:
	visible = false
	if _detail != null:
		_detail.hide_page()

# 详情页「选它」 → 落定选择并高亮那张卡
func select(key: String) -> void:
	if not _keys.has(key):
		return
	_selected = key
	_refresh_selection()

func _refresh_selection() -> void:
	for k in _cards:
		(_cards[k] as Button).set_selected(str(k) == _selected)
	var name := I18n.pick(Data.weapon(_selected)) if not _selected.is_empty() else "-"
	_loadout_lbl.text = I18n.t("pick_weapon_loadout") % name

# 点卡 = 想看详情（不再直接选中）：开局这一选决定整局打法，先看懂再定
func _on_card(key: String) -> void:
	Sfx.ui_click()
	if _detail != null:
		_detail.show_for(key)

func _on_confirm() -> void:
	Sfx.ui_click()
	if not _selected.is_empty():
		GameState.start_weapon = _selected
	Events.run_requested.emit()

func _on_back() -> void:
	Sfx.ui_click()
	if back_cb.is_valid():
		back_cb.call()

func _on_locale_changed(_l: String = "") -> void:
	_refresh_pool()
