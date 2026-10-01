extends Node

const Stick := preload("res://core/StickInput.gd")

# 手柄支持（Steam Deck / 通用控制器）。
# 完全复用现有输入管线：左摇杆 → Events.stick_dir_changed（和触屏摇杆同一个信号），
# A/X 或 RT → Events.dash_requested，START/BACK → 暂停/恢复（与触屏暂停键同信号）。
# Player 只认信号不认来源，所以这里零 UI 耦合。
#
# 关键：只在摇杆真的偏转时"接管"移动；回中后发一次 ZERO 交还控制权给触屏，
# 避免手柄和触屏互相打架。没有手柄连接时直接 return，对手机/桌面零影响。

const DEAD := 0.22          # 左摇杆死区，避免漂移误触
const TRIGGER := 0.5        # RT 模拟量当作"按下"的阈值

var _driving := false
var _dash_prev := false
var _pause_prev := false
var _paused := false

func _ready() -> void:
	Events.run_paused.connect(_on_run_paused)

func _on_run_paused(p: bool) -> void:
	_paused = p

func _physics_process(_delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	var jid := int(pads[0])

	# 暂停态：只监听 START/BACK(原SELECT) 恢复，不转发移动/冲刺（避免恢复瞬间乱动）
	if _paused:
		var resume := Input.is_joy_button_pressed(jid, JOY_BUTTON_START) \
			or Input.is_joy_button_pressed(jid, JOY_BUTTON_BACK)
		if resume and not _pause_prev:
			Events.resume_requested.emit()
		_pause_prev = resume
		return

	# —— 左摇杆移动 ——
	var ax := Input.get_joy_axis(jid, JOY_AXIS_LEFT_X)
	var ay := Input.get_joy_axis(jid, JOY_AXIS_LEFT_Y)
	var dir := Stick.stick_vector(ax, ay, DEAD)
	if dir != Vector2.ZERO:
		_driving = true
		Events.stick_dir_changed.emit(dir)
	elif _driving:
		_driving = false
		Events.stick_dir_changed.emit(Vector2.ZERO)

	# —— 冲刺：A(0)/X(1) 数字键，或 RT 模拟量过阈，检测"刚按下"边沿 ——
	var rt := Input.get_joy_axis(jid, JOY_AXIS_TRIGGER_RIGHT)
	var dash_now := Input.is_joy_button_pressed(jid, JOY_BUTTON_A) \
		or Input.is_joy_button_pressed(jid, JOY_BUTTON_X) \
		or rt > TRIGGER
	if dash_now and not _dash_prev:
		Events.dash_requested.emit()
	_dash_prev = dash_now

	# —— 暂停：START/BACK(原SELECT) 边沿（游戏中按下=暂停，交给 PauseScreen 处理）——
	var pause_now := Input.is_joy_button_pressed(jid, JOY_BUTTON_START) \
		or Input.is_joy_button_pressed(jid, JOY_BUTTON_BACK)
	if pause_now and not _pause_prev:
		Events.pause_requested.emit()
	_pause_prev = pause_now
