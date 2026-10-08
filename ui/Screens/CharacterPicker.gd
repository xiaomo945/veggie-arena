extends Control

# 角色选择卡片组：标题页里横排 N 张卡，点一下换人。
# 只做两件事：画自己（图标 + 名字 + 锁），以及把点击变成 GameState.set_character。
# 不认识 Player、不认识 Game —— 换人后由 Events.character_changed 通知它们。
#
# 布局：卡片行按角色数量自动缩放（7 卡时整行等比缩小），保证在 540 设计宽度内完整可见。
# 之前写死 4 卡宽，角色加到 5-7 个后末尾卡片被切出屏幕、没法点选。
#
# D3-4：点卡不再直接换人 —— 改为发出"我要看这个角色的详情"，由详情页的「选他」落定。
# 主页面从此只负责"挑"（形象 + 名字）；特性/买什么/点什么技能全在各自独立页里讲。
#
# ⚠️ 本版用真实 Button 卡片（抽 CharacterCard.gd）：触屏 / 鼠标都可靠触发 pressed，
#    Godot 自动处理 fit_overlay 缩放下的命中坐标，且空白不被卡片拦截 —— 根治
#    "手写 _gui_input 命中 + fit_overlay 缩放错位 → 点不动角色卡" 的老问题。

signal char_detail_requested(key: String)

const CharacterCardScript := preload("res://ui/Screens/CharacterCard.gd")

const CARD_W := 96.0
const CARD_H := 118.0
const GAP := 10.0
const ROW_MAX_W := 520.0
const COLS := 7
# 网格可用高度上限：y=530 起，给下方 START(高 78)+间距+解锁提示留足，必须 ≤ ~256，
# 否则 START 会掉到 900 设计高以下（之前 13 角色 3 行把 START 顶到 y=912）。
const PICKER_MAX_H := 250.0
const PICKER_TOP := 530.0

var _keys: Array = []
var _grid: GridContainer
var _cards: Dictionary = {}
# 网格内容实际尺寸。ScreenMode.fit_overlay 会把本控件 size 撑成整屏 540x900，
# 所以对外暴露内容高度，TitleScreen 用它摆 START，别读 size。
var content_size := Vector2.ZERO
var _cw := CARD_W
var _k := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 背景不吃点击，只有卡片按钮吃
	_keys = SaveMgr.character_order()
	_build()
	Events.character_changed.connect(_on_changed)
	Events.character_unlocked.connect(_on_char_unlocked)
	I18n.locale_changed.connect(_on_locale_changed)

func _cols() -> int:
	return maxi(1, mini(_keys.size(), COLS))

func _rows() -> int:
	return int(ceil(float(_keys.size()) / float(_cols())))

func _ch() -> float:
	return CARD_H * _k

# 整行宽度封顶 ROW_MAX_W；高度超限 → 整体等比缩小（卡宽也跟着缩，保持方形）。
func _compute_scale() -> void:
	_cw = minf(CARD_W, (ROW_MAX_W - float(_cols() - 1) * GAP) / float(_cols()))
	_k = _cw / CARD_W
	var h := float(_rows()) * CARD_H * _k + float(_rows() - 1) * GAP * _k
	if h > PICKER_MAX_H:
		var s := PICKER_MAX_H / h
		_k *= s
		_cw = CARD_W * _k

func _build() -> void:
	_compute_scale()
	_grid = GridContainer.new()
	_grid.columns = _cols()
	_grid.add_theme_constant_override("h_separation", GAP * _k)
	_grid.add_theme_constant_override("v_separation", GAP * _k)
	add_child(_grid)
	for k in _keys:
		_add_card(str(k))
	_relayout()

func _add_card(key: String) -> void:
	var card = CharacterCardScript.new()
	card.setup(key, _cw)
	card.pressed.connect(_on_card.bind(key))
	_grid.add_child(card)
	_cards[key] = card

# 网格内容尺寸 + 居中摆放（横向居中、纵向落在 PICKER_TOP），供 fit_overlay 缩放
func _relayout() -> void:
	var gw := float(_cols()) * _cw + float(_cols() - 1) * GAP * _k
	var gh := float(_rows()) * _ch() + float(_rows() - 1) * GAP * _k
	content_size = Vector2(gw, gh)
	_grid.position = Vector2((540.0 - gw) * 0.5, PICKER_TOP)
	_refresh_selection()

func _on_card(key: String) -> void:
	char_detail_requested.emit(key)

func _refresh_selection() -> void:
	for k in _cards:
		var card = _cards[k] as CharacterCardScript
		if card != null:
			card.set_selected_key(str(k) == GameState.character, _accent(str(k)))

func _accent(key: String) -> Color:
	return Color(str(Data.character(key).get("color", "#ffffff")))

func _on_changed(_key: String = "") -> void:
	_refresh_selection()

# 解锁后顺序会变（锁着的挪到能玩的那堆），名字 / 图标随语言也要换 —— 重建卡片最稳。
func _on_char_unlocked(_key: String) -> void:
	_rebuild()

func _on_locale_changed(_l: String = "") -> void:
	_rebuild()

func _rebuild() -> void:
	var fresh := SaveMgr.character_order()
	if fresh.size() == _keys.size():
		_keys = fresh
	for c in _grid.get_children():
		c.queue_free()
	_cards = {}
	_compute_scale()
	_grid.columns = _cols()
	_grid.add_theme_constant_override("h_separation", GAP * _k)
	_grid.add_theme_constant_override("v_separation", GAP * _k)
	for k in _keys:
		_add_card(str(k))
	_relayout()
