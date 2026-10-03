extends Control

# HUD 顶部信息区：血条 / 波次进度 / 锅气条 / 武器槽（HudBars）
#                 + 波次 / 金币 / 击杀 / 连击文本 + 暂停按钮。
#
# 职责边界（行业里的"哑组件 / dumb component"）：
#   - 只提供"被塞数据"的接口（set_*），不订阅任何 Events、不认识 Player / Game；
#   - 订阅与编排全部交给 HUD.gd —— 这样这块 UI 可以单独改样式而不碰逻辑。
#
# 布局约束：手机竖屏 540x900，顶部 74px 是 HUD 区（竞技场从 y=74 开始）。

const HudBarsScript := preload("res://ui/HUD/HudBars.gd")
const WeaponBarScript := preload("res://ui/HUD/WeaponBar.gd")

var _bars: Node2D
var _weapon_bar: Node2D
var _wave: Label
var _gold: Label
var _kill: Label
var _combo_label: Label
var _pause_btn: Button

func _ready() -> void:
	# 容器本身不吃触摸：让事件穿透到按钮 / Joystick（否则整块会挡住摇杆）
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(540.0, 900.0)

	_bars = HudBarsScript.new()
	add_child(_bars)

	# 武器槽单独一层（画在血条之上）：带行为符文，见 ui/HUD/WeaponBar.gd
	_weapon_bar = WeaponBarScript.new()
	_weapon_bar.name = "WeaponBar"
	add_child(_weapon_bar)

	# 血条左侧红心图标（代表血量），血条已右移到 x=40 给图标腾出空间
	_mk_icon("heart", Vector2(10, 4), 26)

	_wave = _mk_label(Vector2(40, 44), 16, Color(0.95, 0.95, 0.95))
	_gold = _mk_label(Vector2(40, 62), 14, Color(0.98, 0.84, 0.35))
	_kill = _mk_label(Vector2(180, 62), 12, Color(0.75, 0.75, 0.78))
	# 连击显示（基于击杀信号，短时间内连续击杀累加）
	_combo_label = _mk_label(Vector2(300, 62), 12, Color(1.0, 0.8, 0.3))
	_combo_label.text = ""

	# 金币左侧金币图标，金币标签已右移到 x=40 避免遮挡
	# （用 Art.coin_icon 的卡通金饼替换旧的 48px 方块coin；缩小到 16px 不再显大）
	_mk_icon("coin", Vector2(14, 60), 16, Art.coin_icon())

	# 暂停按钮：右上角，游戏中显示，暂停 / 结算时隐藏
	_pause_btn = Button.new()
	_pause_btn.custom_minimum_size = Vector2(48, 48)
	_pause_btn.size = Vector2(48, 48)
	_pause_btn.position = Vector2(540 - 56, 16)
	var iv := Art.ui_icon("pause")
	if iv != null:
		_pause_btn.icon = iv
	else:
		_pause_btn.text = "II"
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.pressed.connect(_on_pause_pressed)
	_pause_btn.visible = false
	add_child(_pause_btn)

func _mk_label(pos: Vector2, size: int, c: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	add_child(l)
	return l

# 在 HUD 上放一个小图标（TextureRect）。没图时（Art 兜底）直接跳过，不影响布局。
# override 传纹理时用它代替按名字查的图；HUD 图标都是大图缩小，统一走线性+mipmap。
func _mk_icon(name: String, pos: Vector2, sz: float, override: Texture2D = null) -> void:
	if override == null and not Art.has_ui_icon(name):
		return
	var tex = TextureRect.new()
	tex.texture = override if override != null else Art.ui_icon(name)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# ⚠️ expand_mode 必须在 size 之前设：默认 EXPAND_KEEP_SIZE 下最小尺寸=贴图原尺寸
	#    （金币 64px / 红心更大），先设 size 会被撑到 64px 且之后不会自己缩回去 ——
	#    截图目检发现"金币图标巨大、盖住 GOLD 文字"就是这个顺序问题。
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(sz, sz)
	tex.size = Vector2(sz, sz)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.position = pos
	add_child(tex)

# ---- 对外接口（由 HUD.gd 调用）----

# 把数据塞给 HudBars（hp_ratio / wave_progress / wok_ratio / wok_tier /
# run_wave / run_total）并请求重绘。slots 是武器槽专属，交给 WeaponBar。
func set_bar(prop: String, value: Variant) -> void:
	if prop == "slots":
		_weapon_bar.set("slots", value)
		_weapon_bar.queue_redraw()
		return
	_bars.set(prop, value)
	_bars.queue_redraw()

func set_wave_text(t: String) -> void:
	_wave.text = t

func set_gold_text(t: String) -> void:
	_gold.text = t

func set_kills_text(t: String) -> void:
	_kill.text = t

func set_combo_text(t: String) -> void:
	_combo_label.text = t

func set_pause_visible(v: bool) -> void:
	_pause_btn.visible = v

# 暂停按钮的屏幕矩形（共享给 Joystick 做避让）。容器自身会被安全区平移，
# 所以这里必须加上容器的 position，不能用按钮的局部坐标。
func pause_rect() -> Rect2:
	return Rect2(position + _pause_btn.position, _pause_btn.size)

# 竖屏安全区：整块顶部 HUD 下移，避开刘海 / 状态栏。
func apply_safe_area(top: float) -> void:
	position += Vector2(0.0, top)

func _on_pause_pressed() -> void:
	Events.pause_requested.emit()
