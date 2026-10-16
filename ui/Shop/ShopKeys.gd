extends Control

# 补给站的键盘操作（电脑版）。玩家原话：
#   "J 在商店代表确定，K 在商店代表锁定，L 代表刷新，U 代表攻击和商店的关闭"；
#   "回车键代表下一波"（Events.kb_next_wave，与结算页共用同一个信号）。
# WASD/方向键在 3 列卡片网格里移焦点（每按一次走一格），焦点画金圈（见 _draw）。
#
# 键→信号映射全在 autoload/Keyboard（战斗里/商店里两套语义在那里分流），本文件只做
# "补给站语义"：订阅 kb_shop_* + kb_next_wave，各自判开合态。自 wiring：Shop._build
# 里 new 出来挂到 _root 下（与卡片同父级，自动继承 ScreenMode 横屏缩放），shop 引用
# 由 Shop 注入，经 Callable(shop, "_buy") 字符串形式回调业务方法 —— 不碰私有字段（R3）。

const COLS := 3   # 卡片网格列数（与 ShopPanel.layout_cards 的 cols 一致）
const DetailScript := preload("res://ui/Shop/ShopOfferDetail.gd")

var shop: CanvasLayer = null   # 由 Shop 注入（供 Callable 回调它的业务方法）
var _open := false
var _focus := 0
var _buy: Callable = Callable()
var _lock: Callable = Callable()
var _reroll: Callable = Callable()
var _next: Callable = Callable()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_buy = Callable(shop, "_buy")
	_lock = Callable(shop, "_lock_toggle")
	_reroll = Callable(shop, "_reroll_bought")
	_next = Callable(shop, "_next_wave")
	Events.shop_opened.connect(_on_opened)
	Events.shop_closed.connect(_on_closed)
	Events.kb_shop_confirm.connect(_on_confirm)
	Events.kb_shop_lock.connect(_on_lock)
	Events.kb_shop_reroll.connect(_on_reroll)
	Events.kb_shop_close.connect(_on_close)
	Events.kb_next_wave.connect(_on_next)

func _on_opened() -> void:
	_open = true
	_focus = 0
	queue_redraw()

func _on_closed() -> void:
	_open = false
	queue_redraw()

# ---- 键盘信号 → 补给站语义（详情页开着时键盘归详情页，不在背后买卡）----
func _on_confirm() -> void:   # J = 确定：买焦点卡
	if _detail_open():
		_detail().kb_confirm()
	elif _open:
		_buy.call(_focus)

func _on_lock() -> void:      # K = 锁定焦点卡（整店刷新时保留）
	if _open and not _detail_open():
		_lock.call(_focus)

func _on_reroll() -> void:    # L = 整店刷新（锁定的卡保留）
	if _open and not _detail_open():
		_reroll.call()

func _on_close() -> void:     # U = 关闭：详情页开着先关详情，否则关店（= 下一波）
	if _detail_open():
		_detail().hide_page()
	elif _open:
		_next.call()

func _on_next() -> void:      # 回车 = 下一波（详情页开着先关详情，再按才开打）
	if _detail_open():
		_detail().hide_page()
	elif _open:
		_next.call()

# ---- WASD/方向键：三列网格移焦点（每按一次走一格；echo 是长按重复，滤掉）----
func _input(event: InputEvent) -> void:
	if not _open or _detail_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_W or k == KEY_UP:
			_move(-COLS)
		elif k == KEY_S or k == KEY_DOWN:
			_move(COLS)
		elif k == KEY_A or k == KEY_LEFT:
			_move(-1)
		elif k == KEY_D or k == KEY_RIGHT:
			_move(1)

func _move(delta: int) -> void:
	var n := _cards().size()
	if n <= 0:
		return
	var f := clampi(_focus + delta, 0, n - 1)
	if f != _focus:
		_focus = f
		queue_redraw()

# ---- 焦点金圈：与卡片同一父级，全局矩形→本地矩形（横屏缩放也一致）----
func _draw() -> void:
	if not _open:
		return
	var cards := _cards()
	if _focus < 0 or _focus >= cards.size():
		return
	var c: Control = cards[_focus]
	if not c.visible:
		return
	var m := get_global_transform().affine_inverse()
	var r := c.get_global_rect()
	var a := m * r.position
	var b := m * r.end
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.82, 0.29, 0.95)   # 商店金，圆角/描边跟随卡片语言
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	draw_style_box(sb, Rect2(a, b - a).grow(3.0))

# 详情页（Shop 的兄弟节点，入组 "shop_offer_detail"）：开着的时候键盘归它
func _detail() -> DetailScript:
	return get_tree().get_first_node_in_group("shop_offer_detail") as DetailScript

func _detail_open() -> bool:
	var d := _detail()
	return d != null and d.has_method("is_open") and d.is_open()

# "shop_cards" 组（ShopPanel 建卡时入组）：按布局坐标排序还原下标顺序（组遍历无序），
# 只收可见的 —— 隐藏的占位卡（下标 >= 本场卡数）不是焦点目标。
func _cards() -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group("shop_cards"):
		if (c as Control).visible:
			out.append(c)
	out.sort_custom(func(a, b):
		var pa := (a as Control).position
		var pb := (b as Control).position
		return pa.y < pb.y or (absf(pa.y - pb.y) < 1.0 and pa.x < pb.x))
	return out
