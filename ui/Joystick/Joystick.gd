extends CanvasLayer

# 虚拟摇杆：固定底盘在左下角 + 左下 generous 区域任意落指都算摇杆触点。
#
# 多指触控：本摇杆只认领"落在左下移动区、且还没被别的控件占用的那根手指"，
# 记住它的 touch index；按钮（锅气/冲刺/快进）各自认领自己矩形内的手指。
# 两根手指互不干扰 —— 左手按住摇杆的同时，右手点任意按钮都生效。
#
# 桌面鼠标：仍走 _index == -1 的路径，落点不决定底盘位置（底盘固定），
# 方向按"按下点 → 当前点"的相对拖拽算，手感与手机一致，不回归。

const Movement := preload("res://core/Movement.gd")

# 固定底盘位置（屏幕坐标，左下角）。不随落点漂移。横屏下移到左下、避开水技能簇。
var FIXED_BASE := Vector2(118.0, 786.0)
# 底盘半径（满舵距离）与死区：默认从手感配置读，这里给兜底值
const RADIUS := 54.0
const DEADZONE := 4.0

# 左下 generous 移动区：左 ~46% 宽、y 在下半屏。右侧按钮（锅气/冲刺/快进）都
# 在 x>MOVE_ZONE_W 的区外，互不抢指。横屏下随宽屏放宽。
var MOVE_ZONE_W := 250.0
var MOVE_ZONE_Y := 400.0

var _active := false
var _index := -1
var _radius := RADIUS
var _deadzone := DEADZONE
# 本次按压的"起点"（相对拖拽参考点）：方向 = 当前点 - 起点，钳制到 _radius。
# 这样底盘固定、但 generous 区域里随便哪落指都能推，不会一按就满舵。
var _anchor := Vector2.ZERO
var _knob := Vector2.ZERO   # 绘制用：FIXED_BASE + 钳制后的偏移

@onready var _view: Node2D = $StickView

func _ready() -> void:
	var f := Movement.feel(Data.feel_cfg())
	_radius = float(f["radius"])
	_deadzone = float(f["deadzone"])
	# 横屏：底盘挪到左下、移动区随宽屏放宽（竖屏保持原值）
	FIXED_BASE = HudLayout.joy_fixed_base()
	MOVE_ZONE_W = HudLayout.joy_move_zone_w()
	MOVE_ZONE_Y = HudLayout.joy_move_zone_y()
	_view.radius = _radius
	_view.base = FIXED_BASE
	_view.visible = bool(f.get("joystick_visible", true))

func _input(event: InputEvent) -> void:
	# 只有"一局进行中"才接管触摸：标题页 / 暂停 / 死亡 / 通关页都不响应
	if not GameState.running or GameState.paused:
		return
	# 触屏（手机真机）
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _index == -1 and _in_zone(t.position):
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
			if mb.pressed and _index == -1 and _in_zone(mb.position):
				_start(-1, mb.position)
			elif not mb.pressed and _index == -1:
				_release()
		return
	if event is InputEventMouseMotion:
		if _index == -1 and _active:
			_move((event as InputEventMouseMotion).position)
		return

# 左下 generous 区域：左 56% 宽、下（900-400=500px）高
func _in_zone(pos: Vector2) -> bool:
	return pos.x <= MOVE_ZONE_W and pos.y >= MOVE_ZONE_Y

func _start(index: int, pos: Vector2) -> void:
	_active = true
	_index = index
	_anchor = pos
	_knob = FIXED_BASE
	Events.stick_dir_changed.emit(Vector2.ZERO)
	_sync()

func _move(pos: Vector2) -> void:
	var off := pos - _anchor
	if off.length() > _radius:
		off = off.normalized() * _radius
	_knob = FIXED_BASE + off
	var dir := Movement.stick_direction(off.x, off.y, _deadzone)
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
	_view.knob = _knob
	_view.queue_redraw()
