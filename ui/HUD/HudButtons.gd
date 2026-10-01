extends Control

# HUD 底部按钮区：颠勺（全屏甩锅）/ 冲刺。
#
# 职责边界：
#   - 只管"按钮长什么样、在哪个矩形里"；点击后的语义交给 Events 广播。
#   - 两个按钮的屏幕矩形通过 toss_rect() / dash_rect() 共享给 Joystick，
#     让摇杆知道"这块地盘不是走位用的"。容器被安全区平移后矩形必须跟着变，
#     所以这里一律返回 容器位置 + 按钮局部位置。
#
# 冲刺按钮位置：右下角，避开中间的颠勺按钮（210..330）与左下拇指区。
# 颠勺按钮：中心 (270, 766)，在火候条上方。

const DashButtonScript := preload("res://ui/HUD/DashButton.gd")

const TOSS_POS := Vector2(210, 706)
const TOSS_SIZE := Vector2(120, 120)
const DASH_POS := Vector2(398, 748)
const DASH_SIZE := 96.0

var _toss_btn: Button
var _dash_btn: Control
var _charges := 0          # 当前已存颠勺充能数（按钮常驻显示用）

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(540.0, 900.0)

	_toss_btn = Button.new()
	_toss_btn.custom_minimum_size = TOSS_SIZE
	_toss_btn.size = TOSS_SIZE
	_toss_btn.position = TOSS_POS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.42, 0.26, 0.28)
	sb.border_color = Color(1.0, 0.72, 0.42, 0.95)
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 60
	sb.corner_radius_top_right = 60
	sb.corner_radius_bottom_left = 60
	sb.corner_radius_bottom_right = 60
	_toss_btn.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(1.0, 0.6, 0.4, 0.5)
	_toss_btn.add_theme_stylebox_override("pressed", sbp)
	_toss_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_toss_btn.add_theme_font_size_override("font_size", 22)
	_toss_btn.text = I18n.t("hud_toss")
	_toss_btn.visible = false
	_toss_btn.pressed.connect(_on_toss_pressed)
	add_child(_toss_btn)

	_dash_btn = DashButtonScript.new()
	_dash_btn.position = DASH_POS
	add_child(_dash_btn)

# ---- 对外接口（由 HUD.gd 调用）----

# 颠勺按钮常驻：只要有充能就一直可见（不再"攒满闪一下又消失"）。
# 充能 >1 时显示 "颠勺 x{n}"，提示玩家手里存了好几个，危险时连放。
func set_charges(n: int) -> void:
	_charges = n
	_refresh()

func _refresh() -> void:
	_toss_btn.visible = _charges > 0
	if _charges > 1:
		_toss_btn.text = "%s x%d" % [I18n.t("hud_toss"), _charges]
	else:
		_toss_btn.text = I18n.t("hud_toss")

func toss_rect() -> Rect2:
	return Rect2(position + _toss_btn.position, TOSS_SIZE)

func dash_rect() -> Rect2:
	return Rect2(position + _dash_btn.position, Vector2(DASH_SIZE, DASH_SIZE))

# 颠勺按钮有充能时呼吸闪烁，提示玩家"戳这里放颠勺"
func tick(_delta: float) -> void:
	if _toss_btn.visible:
		_toss_btn.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 110.0)

# 竖屏安全区：底部按钮上移，避开全面屏手势条 / Home Indicator。
func apply_safe_area(bottom: float) -> void:
	position -= Vector2(0.0, bottom)

func _on_toss_pressed() -> void:
	Events.wok_toss_requested.emit()
