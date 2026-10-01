extends CanvasLayer

# 设置菜单：从暂停菜单进入。改动实时写 Settings 并持久化。
# 竖屏 540x900，内容留安全区内边距（顶部避开刘海，底部避开圆角/手势条）。
# 画质选"低"时自动关粒子 / 震屏（降级）并禁用对应开关。
# 多语言：所有文案经 I18n.t；底部"语言"切换（中文 / English）实时生效并持久化。

# 帧率选项：0 = 引擎默认
const FPS_OPTIONS := [0, 30, 60, 120]
# 安全区内边距（设计坐标）
const TOP_INSET := 40.0
const BOTTOM_INSET := 28.0

var _root: Control
var _title_lbl: Label
var _music_lbl: Label
var _sfx_lbl: Label
var _quality_lbl: Label
var _shake_lbl: Label
var _particle_lbl: Label
var _fps_lbl: Label
var _lang_lbl: Label
var _music_slider: HSlider
var _sfx_slider: HSlider
var _quality_btns: Array = []      # [{btn, val}]
var _shake_btn: Button
var _particle_btn: Button
var _fps_option: OptionButton
var _lang_btns: Array = []          # [{btn, val}] 0=中文 1=English
var _back_btn: Button
# 低画质强制降级标记：离开低画质时把被强制关的开关恢复为开
var _forced_low := false

# 返回暂停菜单的回调（由 PauseScreen 注入）
var back_pressed: Callable = Callable()

func _ready() -> void:
	layer = 35
	_build()
	_root.visible = false

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.92)
	_root.add_child(shade)

	_title_lbl = _mk_label(TOP_INSET, 34, 0.98, 0.86, 0.32)

	# 音乐音量
	_music_lbl = _mk_label(TOP_INSET + 52, 16, 0.85, 0.88, 0.92)
	_music_slider = _mk_slider(TOP_INSET + 80)
	_music_slider.value = float(Settings.music_volume)
	_music_slider.value_changed.connect(_on_music_vol)

	# 音效音量
	_sfx_lbl = _mk_label(TOP_INSET + 120, 16, 0.85, 0.88, 0.92)
	_sfx_slider = _mk_slider(TOP_INSET + 148)
	_sfx_slider.value = float(Settings.sfx_volume)
	_sfx_slider.value_changed.connect(_on_sfx_vol)

	# 画质档
	_quality_lbl = _mk_label(TOP_INSET + 192, 16, 0.85, 0.88, 0.92)
	var qw := 100.0
	var qgap := 10.0
	var qstart := (540.0 - (3.0 * qw + 2.0 * qgap)) * 0.5
	for i in 3:
		var b := Button.new()
		b.set_size(Vector2(qw, 56))
		b.set_position(Vector2(qstart + float(i) * (qw + qgap), TOP_INSET + 222))
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_quality.bind(i))
		_root.add_child(b)
		_quality_btns.append({"btn": b, "val": i})

	# 震屏开关
	_shake_lbl = _mk_label(TOP_INSET + 302, 16, 0.85, 0.88, 0.92)
	_shake_btn = _mk_toggle(TOP_INSET + 332)
	_shake_btn.pressed.connect(_on_shake)

	# 粒子开关
	_particle_lbl = _mk_label(TOP_INSET + 392, 16, 0.85, 0.88, 0.92)
	_particle_btn = _mk_toggle(TOP_INSET + 422)
	_particle_btn.pressed.connect(_on_particle)

	# 帧率目标
	_fps_lbl = _mk_label(TOP_INSET + 502, 16, 0.85, 0.88, 0.92)
	_fps_option = OptionButton.new()
	_fps_option.set_size(Vector2(300, 50))
	_fps_option.set_position(Vector2((540 - 300) * 0.5, TOP_INSET + 532))
	_fps_option.add_theme_font_size_override("font_size", 18)
	_fps_option.item_selected.connect(_on_fps)
	_root.add_child(_fps_option)

	# 语言切换（中文 / English）
	_lang_lbl = _mk_label(TOP_INSET + 592, 16, 0.85, 0.88, 0.92)
	var lstart := (540.0 - (2.0 * qw + qgap)) * 0.5
	for i in 2:
		var b := Button.new()
		b.set_size(Vector2(qw, 56))
		b.set_position(Vector2(lstart + float(i) * (qw + qgap), TOP_INSET + 622))
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_lang.bind(i))
		_root.add_child(b)
		_lang_btns.append({"btn": b, "val": i})

	# 返回：回到暂停菜单
	_back_btn = Button.new()
	_back_btn.set_size(Vector2(300, 60))
	_back_btn.set_position(Vector2((540 - 300) * 0.5, 900 - BOTTOM_INSET - 60))
	_back_btn.add_theme_font_size_override("font_size", 22)
	_back_btn.pressed.connect(_on_back)
	_root.add_child(_back_btn)

	I18n.locale_changed.connect(_on_locale_changed)
	_refresh_texts()
	_refresh_from_settings()

# 居中标签（无文字，由调用方填 I18n 文案），返回引用供后续刷新
func _mk_label(y: float, size: int, r: float, g: float, b: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(r, g, b))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_position(Vector2(0, y))
	l.set_size(Vector2(540, 26))
	_root.add_child(l)
	return l

func _mk_slider(y: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.custom_minimum_size = Vector2(360, 30)
	s.size = Vector2(360, 30)
	s.position = Vector2((540 - 360) * 0.5, y)
	s.add_theme_font_size_override("font_size", 14)
	_root.add_child(s)
	return s

func _mk_toggle(y: float) -> Button:
	var b := Button.new()
	b.set_size(Vector2(300, 52))
	b.set_position(Vector2((540 - 300) * 0.5, y))
	b.add_theme_font_size_override("font_size", 18)
	# 具体回调在 _build 里按用途分别连接（震屏 / 粒子 / 语言）
	_root.add_child(b)
	return b

# 帧率选项文本（首个为"默认"，其余 N FPS）
func _fps_label(i: int) -> String:
	if i == 0:
		return I18n.t("fps_default")
	return "%d FPS" % FPS_OPTIONS[i]

# 写入所有随语言变化的文案
func _refresh_texts() -> void:
	_title_lbl.text = I18n.t("settings_title")
	_music_lbl.text = I18n.t("settings_music")
	_sfx_lbl.text = I18n.t("settings_sfx")
	_quality_lbl.text = I18n.t("settings_quality")
	_shake_lbl.text = I18n.t("settings_shake")
	_particle_lbl.text = I18n.t("settings_particles")
	_fps_lbl.text = I18n.t("settings_fps")
	_lang_lbl.text = I18n.t("settings_language")
	_back_btn.text = I18n.t("settings_back")
	var qnames := [I18n.t("quality_low"), I18n.t("quality_mid"), I18n.t("quality_high")]
	for e in _quality_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 1))
		b.text = qnames[v]
	var lnames := [I18n.t("lang_zh"), I18n.t("lang_en")]
	for e in _lang_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 0))
		b.text = lnames[v]
	# 帧率选项文本随语言重建
	_fps_option.clear()
	for i in FPS_OPTIONS.size():
		_fps_option.add_item(_fps_label(i), FPS_OPTIONS[i])

# 用当前 Settings 刷新所有控件状态（含随状态变化的开关文案 / 选中高亮）
func _refresh_from_settings() -> void:
	_music_slider.value = float(Settings.music_volume)
	_sfx_slider.value = float(Settings.sfx_volume)
	for e in _quality_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 1))
		_set_btn_active(b, v == Settings.quality)
	_shake_btn.text = I18n.t("settings_shake") + "   " + (I18n.t("on") if Settings.screenshake_enabled else I18n.t("off"))
	_particle_btn.text = I18n.t("settings_particles") + "   " + (I18n.t("on") if Settings.particles_enabled else I18n.t("off"))
	_shake_btn.disabled = (Settings.quality == 0)
	_particle_btn.disabled = (Settings.quality == 0)
	_forced_low = (Settings.quality == 0)
	for e in _lang_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 0))
		var code := "zh" if v == 0 else "en"
		_set_btn_active(b, code == Settings.language)
	var idx := 0
	for i in FPS_OPTIONS.size():
		if FPS_OPTIONS[i] == Settings.fps_target:
			idx = i
			break
	_fps_option.select(idx)

func _set_btn_active(b: Button, on: bool) -> void:
	if b == null:
		return
	var sb := StyleBoxFlat.new()
	if on:
		sb.bg_color = Color(0.92, 0.42, 0.26, 0.35)
		sb.border_color = Color(1.0, 0.72, 0.42, 1.0)
	else:
		sb.bg_color = Color(0.2, 0.22, 0.28, 0.6)
		sb.border_color = Color(0.4, 0.45, 0.55, 0.8)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(1.0, 0.6, 0.4, 0.5)
	b.add_theme_stylebox_override("pressed", sbp)

func show_menu() -> void:
	_refresh_texts()
	_refresh_from_settings()
	_root.visible = true

func hide_menu() -> void:
	_root.visible = false

func _on_music_vol(v: float) -> void:
	Settings.set_music_volume(int(v))

func _on_sfx_vol(v: float) -> void:
	Settings.set_sfx_volume(int(v))

func _on_quality(v: int) -> void:
	Settings.set_quality(v)
	_refresh_from_settings()
	if v == 0:
		# 低画质：强制关粒子 / 震屏并禁用开关（降级）
		_forced_low = true
		Settings.set_particles(false)
		Settings.set_screenshake(false)
	else:
		if _forced_low:
			# 离开低画质：恢复被强制关的开关为开
			Settings.set_particles(true)
			Settings.set_screenshake(true)
			_forced_low = false
	_refresh_from_settings()

func _on_shake() -> void:
	Settings.set_screenshake(not Settings.screenshake_enabled)
	_refresh_from_settings()

func _on_particle() -> void:
	Settings.set_particles(not Settings.particles_enabled)
	_refresh_from_settings()

func _on_lang(i: int) -> void:
	var code := "zh" if i == 0 else "en"
	I18n.set_locale(code)

func _on_fps(index: int) -> void:
	Settings.set_fps_target(FPS_OPTIONS[index])

func _on_locale_changed(_locale: String = "") -> void:
	_refresh_texts()
	_refresh_from_settings()

func _on_back() -> void:
	Sfx.ui_click()
	hide_menu()
	if back_pressed.is_valid():
		back_pressed.call()
