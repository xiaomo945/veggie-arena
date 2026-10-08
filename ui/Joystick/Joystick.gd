extends CanvasLayer

# 虚拟摇杆：动态（浮动）底盘 —— 你手指落哪儿，底盘就出现在哪儿，旋钮跟着手指走。
#
# 之前是"底盘写死在左下角、只算相对偏移"，于是想往下走、手指却已经滑到上方时，
# 旋钮被半径卡住、整个轮盘"下不来"。改成浮动底盘后，底盘跟着第一下落指出现，
# 之后旋钮在半径内跟着手指移动，方向按"落指点→当前点"的相对位移算，全方向都顺手。
#
# 多指触控：本摇杆只认领"落在左下移动区、且还没被别的控件占用的那根手指"，
# 记住它的 touch index；按钮（锅气/冲刺/快进）各自认领自己矩形内的手指。
# 两根手指互不干扰 —— 左手按住摇杆的同时，右手点任意按钮都生效。
#
# 桌面鼠标：仍走 _index == -1 的路径，落点即底盘位置（手机手感一致），不回归。

const Movement := preload("res://core/Movement.gd")

# 兜底半径（满舵距离）与死区；实际值从手感配置读，这里给放大后的下限。
const RADIUS := 70.0
const DEADZONE := 4.0

# 左下 generous 移动区：左 ~46% 宽、y 在下半屏。右侧按钮（锅气/冲刺/快进）都
# 在 x>MOVE_ZONE_W 的区外，互不抢指。横屏下随宽屏放宽。
var MOVE_ZONE_W := 250.0
var MOVE_ZONE_Y := 400.0
# 浮动底盘的安全边界：钳到这里，旋钮（半径 70）无论如何都不会冲出屏幕 / 压到顶部 UI
var BASE_MIN_X := 80.0
var BASE_MAX_X := 220.0
var BASE_MIN_Y := 430.0
var BASE_MAX_Y := 850.0

var _active := false
var _index := -1
var _radius := RADIUS
var _deadzone := DEADZONE
# 本次按压的"起点"（= 落地时的手指位置，作为浮动底盘中心）：方向 = 当前点 - 起点，
# 钳制到 _radius。这样底盘跟着落指走、旋钮跟手指走，不会一按就满舵。
var _base := Vector2.ZERO
var _anchor := Vector2.ZERO
var _knob := Vector2.ZERO   # 绘制用：_base + 钳制后的偏移

@onready var _view: Node2D = $StickView

func _ready() -> void:
	var f := Movement.feel(Data.feel_cfg())
	_radius = maxf(float(f["radius"]), RADIUS)   # 放大底盘，手机更好操作
	_deadzone = float(f["deadzone"])
	# 横屏：移动区随宽屏放宽（竖屏保持原值）
	MOVE_ZONE_W = HudLayout.joy_move_zone_w()
	MOVE_ZONE_Y = HudLayout.joy_move_zone_y()
	_base = HudLayout.joy_fixed_base()
	_anchor = _base
	_knob = _base
	_view.radius = _radius
	_view.base = _base
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

# 把浮动底盘钳在屏幕安全区：不会贴边、不会被顶部 HUD 盖住
func _clamp_base(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, BASE_MIN_X, BASE_MAX_X),
		clampf(pos.y, BASE_MIN_Y, BASE_MAX_Y))

func _start(index: int, pos: Vector2) -> void:
	_active = true
	_index = index
	_base = _clamp_base(pos)   # 底盘落在落指点（浮动）
	_anchor = _base
	_knob = _base
	Events.stick_dir_changed.emit(Vector2.ZERO)
	_sync()

func _move(pos: Vector2) -> void:
	var off := pos - _base
	if off.length() > _radius:
		off = off.normalized() * _radius
	_knob = _base + off
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
	_view.base = _base
	_view.knob = _knob
	_view.queue_redraw()
