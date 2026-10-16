extends Control

# 调试"跳到第 N 波"面板（用户要求：测试模式直达任意波次，正式版彻底看不到）。
#
# 节点是否创建由 HUD 判定（core/DebugMode.enabled()），本文件不做显隐开关以外的逻辑。
# 纯测试工具：只发 Events.debug_jump_wave，真正的跳波（清场+开波）在 WaveDirector。
#
# 文案刻意全用 ASCII（WAVE / GO / 数字）：调试工具不进 i18n 表，也免去字体补字。

const BTN_STYLE := Color(0.16, 0.14, 0.12, 0.92)
const BTN_EDGE := Color(0.85, 0.70, 0.25)
const HI := Color(0.98, 0.86, 0.32)

var _panel: PanelContainer = null
var _slider: HSlider = null
var _val: Label = null
var _btn: Button = null

func _ready() -> void:
	position = Vector2.ZERO
	size = HudLayout.design_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE     # 自身不挡触摸，只有按钮/面板挡
	_btn = _flat_btn("WAVE >>", Rect2(10, 116, 84, 30), 15)
	add_child(_btn)   # 曾经漏了这句：按钮建成孤儿节点，不渲染也不可点（浏览器里怎么点都没反应）
	_btn.pressed.connect(_toggle)
	_build_panel()
	_place()
	# 横竖屏翻转：入口键/面板按新模式重摆（原竖屏坐标在横屏下压羁绊条、面板出屏）
	ScreenMode.layout_changed.connect(_on_layout_changed)

func _on_layout_changed(_land: bool) -> void:
	_place()

# 双布局坐标：入口键贴顶部 HUD 块下沿（原 (10,116) 在竖屏就压住了羁绊条），
# 面板挂键盘下方；横屏 540 高里原 (104,320) 会把 GO 键挤出屏幕底。
func _place() -> void:
	size = HudLayout.design_size()
	if _btn != null:
		_btn.position = Vector2(10.0, HudLayout.hud_block_h() + 6.0)
	if _panel != null:
		var by: float = HudLayout.hud_block_h() + 44.0
		_panel.position = Vector2(104.0, minf(by, HudLayout.design_size().y - 250.0))

func _toggle() -> void:
	_panel.visible = not _panel.visible

# ---- 面板 ----
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(104, 320)
	_panel.custom_minimum_size = Vector2(330, 0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(300, 0)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "JUMP TO WAVE  (debug)"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", HI)
	vb.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	row.add_child(_mini_btn("-"))
	_slider = HSlider.new()
	_slider.min_value = 1.0
	_slider.max_value = float(int(Data.wave_cfg().get("total", 20)))
	_slider.step = 1.0
	_slider.value = 1.0
	_slider.custom_minimum_size = Vector2(170, 26)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slide)
	row.add_child(_slider)
	row.add_child(_mini_btn("+"))

	var line := HBoxContainer.new()
	vb.add_child(line)
	var cap := Label.new()
	cap.text = "WAVE"
	cap.add_theme_font_size_override("font_size", 15)
	line.add_child(cap)
	_val = Label.new()
	_val.text = "1"
	_val.add_theme_font_size_override("font_size", 20)
	_val.add_theme_color_override("font_color", HI)
	line.add_child(_val)

	var go := _flat_btn("GO", Rect2(0, 0, 0, 0), 18)
	go.custom_minimum_size = Vector2(0, 44)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_on_go)
	vb.add_child(go)

func _mini_btn(txt: String) -> Button:
	var b := _flat_btn(txt, Rect2(0, 0, 0, 0), 17)
	b.custom_minimum_size = Vector2(34, 30)
	b.pressed.connect(_nudge.bind(int(txt == "+") * 2 - 1))
	return b

func _nudge(d: int) -> void:
	_slider.value = clampf(_slider.value + float(d), _slider.min_value, _slider.max_value)

func _on_slide(v: float) -> void:
	_val.text = str(int(v))

func _on_go() -> void:
	Events.debug_jump_wave.emit(int(_slider.value))
	_panel.visible = false

# ---- 通用小按钮（扁平卡通风，和主题按钮一致的手感）----
func _flat_btn(txt: String, rect: Rect2, fs: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color(0.95, 0.89, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.88))
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.10, 0.08))
	var n := StyleBoxFlat.new()
	n.bg_color = BTN_STYLE
	n.set_border_width_all(2)
	n.border_color = BTN_EDGE
	n.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.24, 0.21, 0.17, 0.95)
	b.add_theme_stylebox_override("hover", hov)
	var press := n.duplicate() as StyleBoxFlat
	press.bg_color = HI
	b.add_theme_stylebox_override("pressed", press)
	var dis := n.duplicate() as StyleBoxFlat
	dis.bg_color = Color(BTN_STYLE.r, BTN_STYLE.g, BTN_STYLE.b, 0.55)
	b.add_theme_stylebox_override("disabled", dis)
	return b
