extends Label

# 开局一行操作提示：6 秒后自动淡出，不挡点击、不用面板、不用图标。
#
# 为什么是这个形态：上一版 Onboarding 是居中的面板 + 标题 + 关闭按钮，被玩家说
# "太像错误提醒"，已删。但评审/新玩家第一次进局看到满屏怪 + 四个技能按钮，仍然
# 不知道能干什么 —— 所以这里只保留"一行淡字"，看完就消失，不打断任何操作。
#
# 文案按设备分：触屏说摇杆，键鼠说 WASD。判断用 is_touchscreen_available()，
# Web 端手机返回 true、桌面浏览器返回 false（触屏笔记本两者都成立，用键鼠文案也不亏）。

const SHOW_SECS := 6.0
const FADE_SECS := 0.9

var _tw: Tween = null

func _ready() -> void:
	# ⚠️ 必须 IGNORE：本控件铺满全屏，默认 STOP 会把整块屏幕的点击/触摸全吃掉
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ 必须 set_anchors_**and_offsets**_preset：只设 anchors 时，CanvasLayer 下的
	#    Control 不会拉伸到视口宽，size 会停在文字本身宽度（实测 318/540），
	#    结果"居中"变成从 x=0 开始、左半截被裁。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 16.0
	offset_right = -16.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 17)
	add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	# 描边而不是底板：地面有浅色木纹，纯白字会糊掉；描边比半透明黑条更不"像弹窗"
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.55))
	add_theme_constant_override("outline_size", 4)
	text = _hint_text()
	modulate.a = 0.0
	_place()
	Events.run_started.connect(_on_run_started)
	ScreenMode.layout_changed.connect(_on_layout)

func _hint_text() -> String:
	return I18n.t("hint_touch") if DisplayServer.is_touchscreen_available() else I18n.t("hint_keys")

# 位置：竖屏 20% / 横屏 30%（顶部状态条下方、战斗区上沿的空白带）。
# ⚠️ 别放 70%：那里正好压住"连击"按钮（竖屏 540x900 实测），提示和按钮叠成一团。
# ⚠️ 横屏要更大比例：视口只有 540 高，20% 会压住顶部第二行（本命/套装）文字。
# 不写死 y：竖屏 900 / 横屏 540 / 手机浏览器可视高度各不相同。
func _place() -> void:
	var h := get_viewport().get_visible_rect().size.y
	var c := h * (0.30 if ScreenMode.is_widescreen() else 0.20)
	offset_top = c - 100.0
	offset_bottom = (c + 100.0) - h

func _on_layout(_land: bool) -> void:
	_place()
	text = _hint_text()

func _on_run_started() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	modulate.a = 1.0
	visible = true
	_tw = create_tween()
	_tw.tween_interval(SHOW_SECS)
	_tw.tween_property(self, "modulate:a", 0.0, FADE_SECS)
