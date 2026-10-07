extends CanvasLayer

# 设置菜单：从暂停菜单进入。改动实时写 Settings 并持久化。
# 竖屏 540x900，内容留安全区内边距（顶部避开刘海，底部避开圆角/手势条）。
# 画质选"低"时自动关粒子 / 震屏（降级）并禁用对应开关。
# 多语言：所有文案经 I18n.t；底部"语言"切换（中文 / English）实时生效并持久化。
#
# ⚠️ 布局用 _y 游标而不是手写 "TOP_INSET + N"：以前在中间插一行就得把后面
# 十几个坐标全部加一遍，改一次错一次。现在插/删一行只影响它自己。

# 帧率选项：0 = 引擎默认
const FPS_OPTIONS := [0, 30, 60, 120]
# 控件工厂（纯造控件，不含文案/业务）：拆出去才能守住 300 行红线
const Widgets := preload("res://ui/SettingsWidgets.gd")
# 安全区内边距（设计坐标）
const TOP_INSET := 40.0
const BOTTOM_INSET := 28.0

var _root: Control
var _title_lbl: Label
# 各行标题按名字存，避免为每个标签声明一个成员变量（新增一行 = 加一个 key）
var _labels: Dictionary = {}
var _music_slider: HSlider
var _sfx_slider: HSlider
var _move_slider: HSlider
var _quality_btns: Array = []      # [{btn, val}]
var _perf_lbl: Label
var _shake_btn: Button
var _particle_btn: Button
var _mute_btn: Button
var _fps_option: OptionButton
var _show_fps_btn: Button
var _lang_btns: Array = []          # [{btn, val}] 0=中文 1=English
var _back_btn: Button
# 低画质强制降级标记：离开低画质时把被强制关的开关恢复为开
var _forced_low := false
# 纵向布局游标（见文件头说明）
var _y := 0.0

# 返回暂停菜单的回调（由 PauseScreen 注入）
var back_pressed: Callable = Callable()

func _ready() -> void:
	layer = 35
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)   # 横屏下把竖屏菜单缩放到 960x540 视口内、居中

# 游标往下推 gap 像素，返回新的 y
func _advance(gap: float) -> float:
	_y += gap
	return _y

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.92)
	_root.add_child(shade)

	_y = TOP_INSET
	_title_lbl = Widgets.label(_root, _y, 34, Color(0.98, 0.86, 0.32))

	# 音乐音量
	_labels["music"] = Widgets.label(_root, _advance(52.0), 16, Color(0.85, 0.88, 0.92))
	_music_slider = Widgets.slider(_root, _advance(28.0))
	_music_slider.value = float(Settings.music_volume)
	_music_slider.value_changed.connect(_on_music_vol)

	# 音效音量
	_labels["sfx"] = Widgets.label(_root, _advance(40.0), 16, Color(0.85, 0.88, 0.92))
	_sfx_slider = Widgets.slider(_root, _advance(28.0))
	_sfx_slider.value = float(Settings.sfx_volume)
	_sfx_slider.value_changed.connect(_on_sfx_vol)

	# 一键静音（音乐+音效一起静）：连 Settings.toggle_muted（已修复切换当帧生效）
	_labels["mute"] = Widgets.label(_root, _advance(40.0), 16, Color(0.85, 0.88, 0.92))
	_mute_btn = Widgets.toggle(_root, _advance(30.0))
	_mute_btn.pressed.connect(_on_mute)

	# 移动速度手感（70%~150%）：手感是主观的，与其反复改数值重新出包，
	# 不如让玩家自己拧到舒服为止 —— 上限收到 150%，配合 player.speed_cap 防"跑太快拖影"
	_labels["move"] = Widgets.label(_root, _advance(40.0), 16, Color(0.85, 0.88, 0.92))
	_move_slider = Widgets.slider(_root, _advance(28.0))
	_move_slider.min_value = 70.0
	_move_slider.max_value = 150.0
	_move_slider.step = 5.0
	_move_slider.value = float(Settings.move_scale)
	_move_slider.value_changed.connect(_on_move_scale)

	# 画质档 / 语言：三选一、二选一的按钮行
	_labels["quality"] = Widgets.label(_root, _advance(44.0), 16, Color(0.85, 0.88, 0.92))
	_quality_btns = Widgets.button_row(_root, 3, _advance(30.0), _on_quality)
	# 自动降级档位：掉帧会自己往下降，必须让玩家看得见，否则只会以为游戏偷偷变糊
	_perf_lbl = Widgets.label(_root, _advance(24.0), 13, Color(0.62, 0.90, 0.63))
	Perf.level_changed.connect(_on_perf_level)

	# 震屏开关
	_labels["shake"] = Widgets.label(_root, _advance(80.0), 16, Color(0.85, 0.88, 0.92))
	_shake_btn = Widgets.toggle(_root, _advance(30.0))
	_shake_btn.pressed.connect(_on_shake)

	# 粒子开关
	_labels["particles"] = Widgets.label(_root, _advance(60.0), 16, Color(0.85, 0.88, 0.92))
	_particle_btn = Widgets.toggle(_root, _advance(28.0))
	_particle_btn.pressed.connect(_on_particle)

	# 帧率目标
	_labels["fps"] = Widgets.label(_root, _advance(82.0), 16, Color(0.85, 0.88, 0.92))
	_fps_option = OptionButton.new()
	_fps_option.set_size(Vector2(300, 50))
	_fps_option.set_position(Vector2((540 - 300) * 0.5, _advance(30.0)))
	_fps_option.add_theme_font_size_override("font_size", 18)
	_fps_option.item_selected.connect(_on_fps)
	_root.add_child(_fps_option)

	# 显示 FPS 计数器（排查卡顿用：打开后左上角显示 FPS + 同屏怪数）
	_labels["show_fps"] = Widgets.label(_root, _advance(76.0), 16, Color(0.85, 0.88, 0.92))
	_show_fps_btn = Widgets.toggle(_root, _advance(30.0))
	_show_fps_btn.pressed.connect(_on_show_fps)

	# 语言切换（中文 / English）
	_labels["lang"] = Widgets.label(_root, _advance(60.0), 16, Color(0.85, 0.88, 0.92))
	_lang_btns = Widgets.button_row(_root, 2, _advance(30.0), _on_lang)

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

# 帧率选项文本（首个为"默认"，其余 N FPS）
func _fps_label(i: int) -> String:
	if i == 0:
		return I18n.t("fps_default")
	return "%d FPS" % FPS_OPTIONS[i]

# 写入所有随语言变化的文案
func _refresh_texts() -> void:
	_title_lbl.text = I18n.t("settings_title")
	_labels["music"].text = I18n.t("settings_music")
	_labels["sfx"].text = I18n.t("settings_sfx")
	_labels["mute"].text = I18n.t("mute")
	_labels["quality"].text = I18n.t("settings_quality")
	_labels["shake"].text = I18n.t("settings_shake")
	_labels["particles"].text = I18n.t("settings_particles")
	_labels["fps"].text = I18n.t("settings_fps")
	_labels["show_fps"].text = I18n.t("settings_show_fps")
	_labels["lang"].text = I18n.t("settings_language")
	_refresh_perf_label()
	_refresh_move_label()
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

# 自动画质档位（每帧可能变，档位变化时也要刷新）
func _refresh_perf_label() -> void:
	_perf_lbl.text = "%s：%s" % [I18n.t("settings_perf"), Perf.label()]

func _on_perf_level(_lv: int) -> void:
	_refresh_perf_label()

# 移动速度标题带实时百分比（滑块拖动时要跟着变）
func _refresh_move_label() -> void:
	_labels["move"].text = "%s  %d%%" % [I18n.t("settings_move"), Settings.move_scale]

# 用当前 Settings 刷新所有控件状态（含随状态变化的开关文案 / 选中高亮）
func _refresh_from_settings() -> void:
	_music_slider.value = float(Settings.music_volume)
	_sfx_slider.value = float(Settings.sfx_volume)
	_move_slider.value = float(Settings.move_scale)
	_refresh_move_label()
	for e in _quality_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 1))
		Widgets.set_active(b, v == Settings.quality)
	_shake_btn.text = I18n.t("settings_shake") + "   " + (I18n.t("on") if Settings.screenshake_enabled else I18n.t("off"))
	_particle_btn.text = I18n.t("settings_particles") + "   " + (I18n.t("on") if Settings.particles_enabled else I18n.t("off"))
	_shake_btn.disabled = (Settings.quality == 0)
	_particle_btn.disabled = (Settings.quality == 0)
	_mute_btn.text = I18n.t("mute") + "   " + (I18n.t("on") if Settings.muted else I18n.t("off"))
	Widgets.set_active(_mute_btn, Settings.muted)
	_forced_low = (Settings.quality == 0)
	for e in _lang_btns:
		var d := e as Dictionary
		var b := d.get("btn") as Button
		var v := int(d.get("val", 0))
		var code := "zh" if v == 0 else "en"
		Widgets.set_active(b, code == Settings.language)
	var idx := 0
	for i in FPS_OPTIONS.size():
		if FPS_OPTIONS[i] == Settings.fps_target:
			idx = i
			break
	_fps_option.select(idx)
	if _show_fps_btn != null:
		var on := bool(Settings.get_setting("show_fps", false))
		_show_fps_btn.text = I18n.t("on") if on else I18n.t("off")
		Widgets.set_active(_show_fps_btn, on)

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

func _on_mute() -> void:
	Settings.toggle_muted()
	_refresh_from_settings()

# 移动速度手感：写设置 + 立刻刷新百分比。实际速度由 Player 每帧读 Settings 重算，
# 所以不用重建角色 —— 拧一下滑块马上就能感觉到。
func _on_move_scale(v: float) -> void:
	Settings.set_move_scale(int(v))
	_refresh_move_label()

func _on_quality(v: int) -> void:
	Settings.set_quality(v)
	Perf.sync_quality()      # 手选"低画质"要当场降到保底档，不能等自动
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

func _on_show_fps() -> void:
	Settings.set_show_fps(not bool(Settings.get_setting("show_fps", false)))
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
