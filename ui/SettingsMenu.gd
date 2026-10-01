extends CanvasLayer

# 设置菜单：从暂停菜单进入。改动实时写 Settings 并持久化。
# 竖屏 540x900，内容留安全区内边距（顶部避开刘海，底部避开圆角/手势条）。
# 画质选"低"时自动关粒子 / 震屏（降级）并禁用对应开关。

# 画质档名称，索引即 quality 值（0=低 / 1=中 / 2=高）
const QUALITY_NAMES := ["低", "中", "高"]
# 帧率选项：0 = 引擎默认
const FPS_OPTIONS := [0, 30, 60, 120]
const FPS_LABELS := ["默认 (引擎)", "30 FPS", "60 FPS", "120 FPS"]
# 安全区内边距（设计坐标）
const TOP_INSET := 40.0
const BOTTOM_INSET := 28.0

var _root: Control
var _music_slider: HSlider
var _sfx_slider: HSlider
var _quality_btns: Array = []      # [{btn, val}]
var _shake_btn: Button
var _particle_btn: Button
var _fps_option: OptionButton
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

	var t := Label.new()
	t.text = "SETTINGS"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_position(Vector2(0, TOP_INSET))
	t.set_size(Vector2(540, 48))
	_root.add_child(t)

	# 音乐音量
	_mk_label("音乐音量 MUSIC", TOP_INSET + 70)
	_music_slider = _mk_slider(TOP_INSET + 100)
	_music_slider.value = float(Settings.music_volume)
	_music_slider.value_changed.connect(_on_music_vol)

	# 音效音量
	_mk_label("音效音量 SFX", TOP_INSET + 160)
	_sfx_slider = _mk_slider(TOP_INSET + 190)
	_sfx_slider.value = float(Settings.sfx_volume)
	_sfx_slider.value_changed.connect(_on_sfx_vol)

	# 画质档
	_mk_label("画质 QUALITY", TOP_INSET + 250)
	var qw := 100.0
	var qgap := 10.0
	var qstart := (540.0 - (float(QUALITY_NAMES.size()) * qw + float(QUALITY_NAMES.size() - 1) * qgap)) * 0.5
	for i in QUALITY_NAMES.size():
		var b := Button.new()
		b.set_size(Vector2(qw, 56))
		b.set_position(Vector2(qstart + float(i) * (qw + qgap), TOP_INSET + 280))
		b.add_theme_font_size_override("font_size", 20)
		b.text = QUALITY_NAMES[i]
		b.pressed.connect(_on_quality.bind(i))
		_root.add_child(b)
		_quality_btns.append({"btn": b, "val": i})

	# 震屏开关
	_mk_label("震屏 SCREENSHAKE", TOP_INSET + 360)
	_shake_btn = _mk_toggle(TOP_INSET + 390)
	_shake_btn.pressed.connect(_on_shake)

	# 粒子开关
	_mk_label("粒子 PARTICLES", TOP_INSET + 450)
	_particle_btn = _mk_toggle(TOP_INSET + 480)
	_particle_btn.pressed.connect(_on_particle)

	# 帧率目标
	_mk_label("帧率目标 FPS", TOP_INSET + 540)
	_fps_option = OptionButton.new()
	_fps_option.set_size(Vector2(300, 50))
	_fps_option.set_position(Vector2((540 - 300) * 0.5, TOP_INSET + 570))
	_fps_option.add_theme_font_size_override("font_size", 18)
	for i in FPS_OPTIONS.size():
		_fps_option.add_item(FPS_LABELS[i], FPS_OPTIONS[i])
	_fps_option.item_selected.connect(_on_fps)
	_root.add_child(_fps_option)

	# 返回：回到暂停菜单
	var back := Button.new()
	back.text = "返回 BACK"
	back.set_size(Vector2(300, 60))
	back.set_position(Vector2((540 - 300) * 0.5, 900 - BOTTOM_INSET - 60))
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(_on_back)
	_root.add_child(back)

	_refresh_from_settings()

func _mk_label(text: String, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_position(Vector2(0, y))
	l.set_size(Vector2(540, 26))
	_root.add_child(l)

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
	# 具体回调在 _build 里按用途分别连接（震屏 / 粒子）
	_root.add_child(b)
	return b

# 用当前 Settings 刷新所有控件状态
func _refresh_from_settings() -> void:
	_music_slider.value = float(Settings.music_volume)
	_sfx_slider.value = float(Settings.sfx_volume)
	for e in _quality_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 1))
		var on := (v == Settings.quality)
		_set_btn_active(b, on)
	_shake_btn.text = "震屏   " + ("ON" if Settings.screenshake_enabled else "OFF")
	_particle_btn.text = "粒子   " + ("ON" if Settings.particles_enabled else "OFF")
	_shake_btn.disabled = (Settings.quality == 0)
	_particle_btn.disabled = (Settings.quality == 0)
	_forced_low = (Settings.quality == 0)
	# 帧率选中项
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

func _on_fps(index: int) -> void:
	Settings.set_fps_target(FPS_OPTIONS[index])

func _on_back() -> void:
	Sfx.ui_click()
	hide_menu()
	if back_pressed.is_valid():
		back_pressed.call()
