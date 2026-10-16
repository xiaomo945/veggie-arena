extends Node

# 键盘操作（电脑版）。玩家原话：
#   "WSAD 分别代表上下左右，还要能斜着走，AW 就是左上" —— 向量归一化，斜向速率与直走一致；
#   "JKL 分别代表 123 技能" / "U 代表攻击" / "空格冲刺" / "回车键代表下一波"；
#   "J 在商店代表确定，K 在商店代表锁定，L 代表刷新，U 代表商店的关闭"；
#   "ESC 代表暂停，再按一次恢复"（电脑端标配：gamepad 的 START 早接了暂停，键盘不能没有）。
#
# 与触屏摇杆/手柄走同一条信号管线（Events + "hud_buttons" 组公开方法）：
# Player/SkillSystem 只认信号不认来源，这里零战斗耦合、零跨对象私有访问（R3）。
# 一次性按键走 _input（天然边沿，echo 过滤防按住连发）；WASD 方向走 _physics_process
# 轮询（连续状态，只在真的变了时 emit，和触屏摇杆的节流一个节奏）。
#
# ⚠️ 门禁（_live）不能只查 GameState.paused：波间（结算页/补给站）世界的暂停走的是
#    Game.set_paused（只设 Game._paused，不动 GameState.paused），所以必须查
#    GameState.between_waves；再叠加 HUD 可见性（标题页/选武器页 HUD 整层隐藏）。

var _shop_open := false     # 补给站开着：同样的 J/K/L/U 换一套商店语义
var _last_dir := Vector2.ZERO

const HudButtonsScript := preload("res://ui/HUD/HudButtons.gd")

func _ready() -> void:
	Events.shop_opened.connect(_on_shop_opened)
	Events.shop_closed.connect(_on_shop_closed)
	# 触屏摇杆松手会把 Player 方向清成 ZERO；键盘此时还按着，补发一次当前方向
	# （否则左手刚离开摇杆、右手还按着 W，人会定住半秒）
	Events.stick_released.connect(_on_stick_released)

func _on_shop_opened() -> void:
	_shop_open = true

func _on_shop_closed() -> void:
	_shop_open = false

func _on_stick_released() -> void:
	if _last_dir != Vector2.ZERO:
		Events.stick_dir_changed.emit(_last_dir)

# 战斗中才发战斗键：结算页/补给站期间键盘归 ShopKeys / WaveResultScreen 管
func _live() -> bool:
	if not GameState.running or GameState.paused or GameState.between_waves:
		return false
	var hud := get_tree().get_first_node_in_group("hud")
	return hud != null and (hud as CanvasLayer).visible

# ---- WASD（+ 方向键）：斜走归一化，AW 同按 = 左上且速率与直走一致 ----
func _physics_process(_delta: float) -> void:
	if not _live():
		return
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if d.length() > 1.0:
		d = d.normalized()   # 斜向不限速：不归一化斜走是直走的 1.414 倍
	if d != _last_dir:
		_last_dir = d
		Events.stick_dir_changed.emit(d)

# ---- 一次性按键（_input 天然边沿；echo 是长按重复，滤掉）----
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)

func _on_key(e: InputEventKey) -> void:
	var k := e.keycode
	if k == KEY_ESCAPE:
		# 桌面端必备：ESC = 暂停 / 恢复（gamepad 的 START 早就接了暂停，键盘一直没有 ——
		# 电脑玩家只能伸鼠标去点右上角小按钮，太反人类）。补给站开着 = 关店再按。
		if GameState.paused and GameState.running:
			Events.resume_requested.emit()
		elif _shop_open:
			Events.kb_shop_close.emit()
		elif _live():
			Events.pause_requested.emit()
		return
	if _live():
		# 战斗：J/K/L=技能 1/2/3，U=攻击，空格=冲刺（都经按钮层，带白环反馈）
		if k == KEY_J or k == KEY_K or k == KEY_L:
			var i := 0
			if k == KEY_K:
				i = 1
			elif k == KEY_L:
				i = 2
			var b := _buttons()
			if b != null:
				b.press_slot(i)
		elif k == KEY_U:
			var b := _buttons()
			if b != null:
				b.press_attack()
		elif k == KEY_SPACE:
			var b := _buttons()
			if b != null:
				b.press_dash()
	elif _shop_open:
		# 补给站：同样的键换语义，转交 ShopKeys（它自己判开合态）
		if k == KEY_J:
			Events.kb_shop_confirm.emit()
		elif k == KEY_K:
			Events.kb_shop_lock.emit()
		elif k == KEY_L:
			Events.kb_shop_reroll.emit()
		elif k == KEY_U:
			Events.kb_shop_close.emit()
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		# 回车=下一波：结算页（WaveResultScreen）与补给站（ShopKeys）都订阅，
		# 各自判自己的开合态；战斗中无人消费，不发也不会漏。
		Events.kb_next_wave.emit()

# "hud_buttons" 组只有一个成员（HUD 的 HudButtons）
func _buttons() -> HudButtonsScript:
	return get_tree().get_first_node_in_group("hud_buttons") as HudButtonsScript
