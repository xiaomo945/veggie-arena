extends Control

# 首局引导：只在"从未玩过"这一局显示，把核心操作摊在战场之上，
# 玩家一移动或点一下就收起，并记 onboarded=true 永不再弹。
#
# 放在 HUD（CanvasLayer 20）之下、HUD 按钮之上：所以暂停菜单(30)能盖住它，
# 而它本身会挡住底部按钮，直到玩家"看懂了"把它关掉。
# 文案走英文（游戏主文案是英文，且避开 CJK 字体子集的坑）。

const GOLD := Color(0.98, 0.86, 0.32)
const PANEL := Color(0.10, 0.08, 0.06, 0.93)
const TEXT := Color(0.92, 0.94, 0.97)

var _shown := false
var _auto_t := 0.0
var _font: Font

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = HudLayout.design_size()
	_font = ThemeDB.fallback_font
	visible = false
	# 已在跑（极少见的边缘情况）就直接显示；否则等 run_started（HUD 在 Game._ready 已先建好）
	if SaveMgr.needs_onboarding():
		Events.run_started.connect(_on_run_started)
		Events.stick_dir_changed.connect(_on_move)
		if GameState.running:
			_show()
	else:
		# 非首局：本节点没用，立刻拆掉，不占渲染/输入
		queue_free()

func _on_run_started() -> void:
	_show()

# 第一次推杆就说明"看懂了" → 收起（dir 为零是回中，不算）
func _on_move(d: Vector2) -> void:
	if _shown and d != Vector2.ZERO:
		_dismiss()

func _show() -> void:
	if _shown:
		return
	_shown = true
	_auto_t = 0.0
	visible = true
	queue_redraw()

# 点任意处 / 移动 / 超时 都收起；headless 模拟里不写存档（避免误标 onboarded）
func _gui_input(event: InputEvent) -> void:
	if not _shown:
		return
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if pressed:
		_dismiss()
		accept_event()

func _process(delta: float) -> void:
	if not _shown:
		return
	_auto_t += delta
	# 兜底：12 秒不动也自动收起，别让玩家卡在引导层
	if _auto_t > 12.0:
		_dismiss()

func _dismiss() -> void:
	if not _shown:
		return
	_shown = false
	visible = false
	if not OS.has_feature("headless"):
		SaveMgr.mark_onboarded()

func _draw() -> void:
	if not _shown:
		return
	var W := size.x
	var H := size.y
	draw_rect(Rect2(0, 0, W, H), Color(0.03, 0.04, 0.07, 0.72))
	var lines := _lines()
	var lh := 25.0
	var pw := minf(500.0, W - 60.0)
	var ph := 54.0 + float(lines.size()) * lh + 44.0
	var px := (W - pw) * 0.5
	var py := (H - ph) * 0.5
	Art.round_rect(self, Rect2(px, py, pw, ph), PANEL, GOLD, 3.0, 18.0)
	var cx := W * 0.5
	_center("HOW TO PLAY", cx, py + 34.0, 26, GOLD)
	var ty := py + 74.0
	for ln in lines:
		_center(ln, cx, ty, 15, TEXT)
		ty += lh
	_center("tap anywhere or move to start", cx, py + ph - 22.0, 13, Color(0.98, 0.86, 0.32))

func _lines() -> Array:
	return [
		"Move: drag joystick (bottom-left) or WASD",
		"Attack: auto-fires - or press U",
		"Skills: J / K / L (rings on the right)",
		"Dash: Space (or Shift) to escape",
		"Wok toss: the K-ring clears the crowd",
		"Survive waves - grab gold - upgrade",
	]

func _center(t: String, cx: float, y: float, fs: int, c: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(cx - w * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
