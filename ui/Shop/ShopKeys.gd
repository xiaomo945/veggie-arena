extends Node

# 补给站的键盘操作（电脑版）：
#   W/S 或 ↑/↓ —— 光标在可见卡片间上下移动（金边高亮跟随）
#   J —— 确定（买当前光标那张卡）
#   K —— 锁定/解锁当前光标那张卡
#   L —— 整店刷新
#   U / Enter —— 下一波（关店开打）
#
# 为什么挂在 Shop 下、而不是并进 autoload/Keyboard：
#   ① 店里的键语义（确定/锁定/刷新/下一波）和战斗完全不同，混在一起就要层层判断"现在在哪一层"；
#   ② 战斗键层（autoload/Keyboard）自己盯 shop_opened/shop_closed 停业 ——
#      两层各管一段、互不打扰，比"一个大 if-else 分支"好维护。
#
# 入口全部复用触屏那一条路：卡片 on_click / on_lock 是 Shop._build 里绑好的 Callable，
# 按钮走 pressed 信号 —— 键盘只是"再按一次"，不复制任何购买/刷新/锁定的业务判断。

var _active := false
var _cursor := 0
var _panel = null
var _hl: Panel = null          # 金边高亮框，跟随焦点卡

func _ready() -> void:
	_panel = get_parent().panel()   # Shop.panel() 公开访问器（R3：不摸 _panel 私有字段）
	_build_hl()
	Events.shop_opened.connect(_on_opened)
	Events.shop_closed.connect(_on_closed)

# 金边高亮框：作为 _panel 的子节点、排在最后 → 永远盖在卡片上面
func _build_hl() -> void:
	if _panel == null:
		return
	_hl = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = Color(1.0, 0.85, 0.35, 0.95)
	sb.set_corner_radius_all(8)
	_hl.add_theme_stylebox_override("panel", sb)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.visible = false
	_panel.add_child(_hl)

func _on_opened() -> void:
	_active = true
	_cursor = 0
	if _hl != null:
		_hl.visible = true

func _on_closed() -> void:
	_active = false
	if _hl != null:
		_hl.visible = false

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)

func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_W, KEY_UP:
			_move(-1)
		KEY_S, KEY_DOWN:
			_move(1)
		KEY_J:
			_card_callable("on_click").call()
		KEY_K:
			_card_callable("on_lock").call()
		KEY_L:
			_emit("reroll_btn")
		KEY_U, KEY_ENTER, KEY_KP_ENTER:
			_emit("next_btn")

# 光标上下移动：只在"可见"的卡片之间走（卡少时剩下的卡片是 visible=false，不能落上去）
func _move(delta: int) -> void:
	var cards: Array = _panel.cards
	var n := cards.size()
	if n == 0:
		return
	var i := _cursor
	for _step in n:
		i = (i + delta + n) % n
		if (cards[i] as Control).visible:
			_cursor = i
			return

# 当前焦点卡的公开 Callable（on_click / on_lock 都是 Shop 绑好的，公开字段可直接取）
func _card_callable(what: String):
	var cards: Array = _panel.cards
	if _cursor < 0 or _cursor >= cards.size():
		return null
	return (cards[_cursor] as Object).get(what)

# 按面板上的按钮（reroll / next）：走 pressed 信号，与鼠标点击完全同一条路径
func _emit(btn: String) -> void:
	if _panel == null:
		return
	var b = _panel.get(btn)
	if b != null and b.has_signal("pressed"):
		b.pressed.emit()

func _process(_delta: float) -> void:
	if not _active or _hl == null or _panel == null:
		return
	var cards: Array = _panel.cards
	if _cursor < 0 or _cursor >= cards.size():
		_hl.visible = false
		return
	var c := cards[_cursor] as Control
	if not c.visible:
		_hl.visible = false
		return
	_hl.visible = true
	# 高亮框贴在焦点卡外扩 3px（卡片是 _panel 的直接子节点，local 坐标即卡片 position）
	_hl.set_position(c.position - Vector2(3.0, 3.0))
	_hl.set_size(c.size + Vector2(6.0, 6.0))
