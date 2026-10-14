extends Node

# 键盘操作层（电脑版）：WASD 走位（含斜向）、J/K/L 三个环绕技能、U 攻击、Space 冲刺。
#
# 完全复用现有输入管线：移动发 Events.stick_dir_changed（和触屏摇杆、手柄同一个信号），
# 技能/攻击走 HUD 按钮的 press()（和手指点踩同一条路径），冲刺发 Events.kb_dash_requested。
# Player / Game 只认信号不认来源，所以这一层零引擎外改动、零业务流程复制。
#
# 三层输入源互相隔离：
#   · 触屏摇杆 —— ui/Joystick
#   · 手柄     —— autoload/Gamepad（插着手柄时本层整体让位，见 _input 开头的判据）
#   · 键盘     —— 本文件
# 谁在推杆谁就发信号，回中就发 ZERO/stick_released 交还控制权，不会两个源打架。
#
# 只在"一局进行中且未暂停"时接管：标题页 / 暂停 / 死亡 / 通关页都不响应。
# 商店打开时本层整体停业（_live 盯 shop_opened/shop_closed，见下文），店里的键
# （J 确认 / K 锁定 / L 刷新 / U 关闭 / Enter 下一波）由 ui/Shop/ShopKeys.gd 管。
# ⚠️ 别指望"商店暂停会置 GameState.paused"——那是暂停菜单的旗，开店只置 Game._paused；
#    两个旗语义不同，混用会让店里按 W 一边走位一边被当光标键（真踩过）。

# 冲刺键：Space（也认 Shift）。单独按 = 随机方向；配合方向键 = 冲刺那个方向。
# 方向语义与"往哪走"完全一致（W+A = 左上），所以按着 W 再按 Space 就是向左上冲。
# ⚠️ 本地常量别取名 KEY_UP / KEY_DOWN / KEY_LEFT / KEY_RIGHT / KEY_SPACE：
#    这些名字在 Godot 全局 Key 枚举里本来就是常量，同名单个 const 会解析成自己
#    → "Cyclic reference" 解析失败（真踩过）。所以本地一律用 *_KEYS 后缀。

const UP_KEYS := [KEY_W, KEY_UP]
const DOWN_KEYS := [KEY_S, KEY_DOWN]
const LEFT_KEYS := [KEY_A, KEY_LEFT]
const RIGHT_KEYS := [KEY_D, KEY_RIGHT]
const DASH_KEYS := [KEY_SPACE, KEY_SHIFT]

var _up := false
var _down := false
var _left := false
var _right := false

# 失焦时松开全部按键：Alt-Tab 一圈回来，不会"W 还按着"一路狂奔进怪堆。
# （窗口失焦后 KeyReleased 可能收不到，键态会卡住 —— 只能在这里兜底清一次）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()

func _input(event: InputEvent) -> void:
	if not _live():
		return
	# 手柄优先：最近 1.5s 内手柄有活动就整帧跳过，避免"掌根压键盘 + 正在用手柄"双触发
	if Gamepad.was_pressed():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			if not k.echo:      # echo = 长按自动重复，按一次就够，别连发
				_key(k)
		else:
			_key_up(k)

# 一局进行中、没暂停、且店门关着。⚠️ 商店暂停不走 GameState.paused（那是暂停菜单的旗，
# 见 GameState.paused 注释），只置 Game._paused —— 所以这里必须自己盯 shop_opened /
# shop_closed，否则店里按 W 会一边走位一边被 ShopKeys 当光标键，"两层天然互斥"是句空话。
var _shop_open := false

func _ready() -> void:
	Events.shop_opened.connect(_on_shop_opened)
	Events.shop_closed.connect(_on_shop_closed)

# 进店即停业：方向键全松开。不松的后果 —— 按着 W 撑满一波 → 进店 → 店里的 W 被
# ShopKeys 当光标键、KeyReleased 又被 _live 挡掉不回传 → 出店后 W 永远"按着"，一路狂奔。
func _on_shop_opened() -> void:
	_shop_open = true
	_release_all()

func _on_shop_closed() -> void:
	_shop_open = false

func _live() -> bool:
	return GameState.running and not GameState.paused and not _shop_open

func _key(k: InputEventKey) -> void:
	if k.keycode in DASH_KEYS:
		# 冲刺：方向取当前按键状态。零向量 = 没按方向键 → Player 随机挑一个方向
		Events.kb_dash_requested.emit(_dir())
		return
	if k.keycode == KEY_U:
		_press_attack()
		return
	if k.keycode == KEY_J:
		_press_addon(0)
		return
	if k.keycode == KEY_K:
		_press_addon(1)
		return
	if k.keycode == KEY_L:
		_press_addon(2)
		return
	# 方向键：只记状态，移动信号在 _after_move 里统一发（一次按键只发一次）
	var moved := _set_dir(k, true)
	if moved:
		_emit_move()

func _key_up(k: InputEventKey) -> void:
	var moved := _set_dir(k, false)
	if moved:
		_emit_move()

# 更新四向按键状态，返回"是否真的发生了状态变化"
func _set_dir(k: InputEventKey, down: bool) -> bool:
	var changed := false
	if k.keycode in UP_KEYS:
		if _up != down: _up = down; changed = true
	elif k.keycode in DOWN_KEYS:
		if _down != down: _down = down; changed = true
	elif k.keycode in LEFT_KEYS:
		if _left != down: _left = down; changed = true
	elif k.keycode in RIGHT_KEYS:
		if _right != down: _right = down; changed = true
	return changed

# 当前方向（斜向归一化：W+A = 左上，速度与单方向一致，不会斜着更快）
func _dir() -> Vector2:
	var v := Vector2(
		(1.0 if _right else 0.0) - (1.0 if _left else 0.0),
		(1.0 if _down else 0.0) - (1.0 if _up else 0.0))
	return v.normalized() if v.length_squared() > 0.0 else Vector2.ZERO

func _emit_move() -> void:
	var d := _dir()
	Events.stick_dir_changed.emit(d)
	if d == Vector2.ZERO:
		Events.stick_released.emit()

# ---- 三个环绕技能键 / 攻击键：走 HUD 按钮的公开入口（与触屏同路径）----

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _press_addon(i: int) -> void:
	var hud := _hud()
	if hud == null or not hud.has_method("addon_buttons"):
		return
	var btns: Array = hud.addon_buttons()
	if i < 0 or i >= btns.size():
		return
	var b = btns[i]
	if b != null and b.has_method("press"):
		b.press()

func _press_attack() -> void:
	var hud := _hud()
	if hud == null or not hud.has_method("attack_button"):
		return
	var b = hud.attack_button()
	if b != null and b.has_method("press"):
		b.press()

# 全部方向键抬起（失焦 / 一局结束时调用）
func _release_all() -> void:
	_up = false; _down = false; _left = false; _right = false
	if GameState.running:
		Events.stick_dir_changed.emit(Vector2.ZERO)
		Events.stick_released.emit()
