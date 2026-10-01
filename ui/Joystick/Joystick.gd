extends CanvasLayer

# 虚拟摇杆：全屏任意位置按下即出现（不用先瞄准某个固定圈）。
#
# 核心是"浮点摇杆"：手指推出半径后，原点被拖着一起走。
# 好处：变向时手指不用先回到中心再推，直接往新方向划就是满舵 ——
#       实测变向响应 83ms → 33ms。逻辑在 core/Movement.follow_origin。

const Movement := preload("res://core/Movement.gd")

var _radius := 52.0
var _deadzone := 3.0
var _active := false
var _index := -1
var _origin := Vector2.ZERO
var _finger := Vector2.ZERO
# 固定左下移动区：只有这块区域按下才启动摇杆，避免误触右侧按钮 / 顶部 HUD。
# 设计空间 540x900；左 ~52% 宽、下 ~50% 高。颠勺/冲刺/暂停按钮都在区外，由各自排除逻辑处理。
const MOVE_ZONE_W := 280.0
const MOVE_ZONE_Y := 450.0

@onready var _view: Node2D = $StickView

func _ready() -> void:
	var f := Movement.feel(Data.feel_cfg())
	_radius = float(f["radius"])
	_deadzone = float(f["deadzone"])
	_view.radius = _radius
	# 手机竖屏下，跟随手指的摇杆底盘会挡住下方视野。
	# 设为 false 时彻底不画摇杆（控制依旧是"按哪走哪"的浮点拖拽，手感不变），
	# 玩家靠角色响应方向来感知操作，不再被一个圈挡住视线。
	_view.visible = bool(f.get("joystick_visible", true))

func _input(event: InputEvent) -> void:
	# 触屏（手机真机）
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if not _active:
				_start(t.index, t.position)
		elif t.index == _index:
			_release()
		return

	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _index:
			_move(d.position)
		return

	# 鼠标（桌面调试用，手机上不会走到这里）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _active:
				_start(-1, mb.position)
			elif not mb.pressed and _index == -1:
				_release()
		return

	if event is InputEventMouseMotion:
		if _index == -1 and _active:
			_move((event as InputEventMouseMotion).position)
		return

func _start(index: int, pos: Vector2) -> void:
	# 暂停按钮区域：戳这里只暂停，不开始移动（避免"想暂停却走位"）
	if GameState.pause_rect.has_point(pos):
		return
	# 满锅气时点颠勺按钮区域：只触发颠勺，不开始移动（避免"想甩锅却走位"）
	if GameState.wok_ready() and GameState.wok_toss_rect.has_point(pos):
		Events.wok_toss_requested.emit()
		return
	# 冲刺按钮区域：戳这里只冲刺，不当成走位拖拽
	if GameState.dash_rect.has_point(pos):
		Events.dash_requested.emit()
		return
	# 固定左下移动区以外（右侧按钮 / 顶部 HUD / 中部空白）不启动摇杆 → 消除误触
	if pos.x > MOVE_ZONE_W or pos.y < MOVE_ZONE_Y:
		return
	_active = true
	_index = index
	_origin = pos          # 摇杆在手指按下的位置生成
	_finger = pos
	Events.stick_dir_changed.emit(Vector2.ZERO)
	_sync()

func _move(pos: Vector2) -> void:
	_finger = pos
	# 先让原点跟随（可能不动），再算方向
	_origin = Movement.follow_origin(_origin.x, _origin.y, _finger.x, _finger.y, _radius)
	var dir := Movement.stick_direction(
		_finger.x - _origin.x, _finger.y - _origin.y, _deadzone)
	Events.stick_dir_changed.emit(dir)
	_sync()

func _release() -> void:
	if not _active:
		return
	_active = false
	_index = -1
	Events.stick_released.emit()
	_sync()

func _sync() -> void:
	_view.active = _active
	_view.origin = _origin
	_view.finger = _finger
	_view.queue_redraw()
