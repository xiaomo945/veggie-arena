extends CanvasLayer

# 暂停菜单：游戏中按右上角暂停键弹出。半透明遮罩 + 继续/设置/重开/退出 + 音频开关。
# 自己只负责显示与发声，所有"动作"都通过 Events 信号交给 Game/TitleScreen 处理。
# 退出到标题由 Game 复位本局 + TitleScreen 重新显共同完成（见各自监听）。
# 设置入口：从本菜单进入 SettingsMenu（独立 CanvasLayer，layer 更高）。

const SettingsMenuScript := preload("res://ui/SettingsMenu.gd")
const StatsScreenScript := preload("res://ui/Screens/StatsScreen.gd")

var _root: Control
var _title_lbl: Label
var _sfx_btn: Button
var _music_btn: Button
var _resume_btn: Button
var _stats_btn: Button
var _settings_btn: Button
var _restart_btn: Button
var _quit_btn: Button
var _settings: CanvasLayer
var _stats: CanvasLayer

func _ready() -> void:
	layer = 30
	_build()
	_root.visible = false
	Events.run_paused.connect(_on_paused)
	# 设置菜单 / 属性页作为同级 CanvasLayer 挂到 Game 下（layer 35/36 > 本菜单 30）
	var p := get_parent()
	if p == null:
		p = self
	_settings = SettingsMenuScript.new()
	p.add_child(_settings)
	_settings.back_pressed = _on_settings_back
	_settings.hide_menu()
	_stats = StatsScreenScript.new()
	p.add_child(_stats)
	_stats.back_pressed = _on_stats_back
	_stats.hide_menu()
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.82)
	_root.add_child(shade)

	var t := Label.new()
	t.text = I18n.t("pause_title")
	t.add_theme_font_size_override("font_size", 38)
	t.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_position(Vector2(0, 170))
	t.set_size(Vector2(540, 50))
	_title_lbl = t
	_root.add_child(t)

	_resume_btn = _mk_btn(I18n.t("pause_resume"), 230, _on_resume, "play")
	_stats_btn = _mk_btn(I18n.t("pause_stats"), 308, _on_open_stats, "star")
	_settings_btn = _mk_btn(I18n.t("pause_settings"), 386, _on_open_settings, "settings")
	_restart_btn = _mk_btn(I18n.t("pause_restart"), 464, _on_restart)
	_quit_btn = _mk_btn(I18n.t("pause_quit"), 542, _on_quit)

	_sfx_btn = _mk_toggle(620, _on_sfx)
	_music_btn = _mk_toggle(698, _on_music)
	_refresh_toggles()

func _mk_btn(text: String, y: float, cb: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.set_size(Vector2(300, 64))
	b.set_position(Vector2((540 - 300) * 0.5, y))
	b.add_theme_font_size_override("font_size", 22)
	Art.style_button(b, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	if icon_name != "":
		if Art.has_ui_icon(icon_name):
			b.icon = Art.ui_icon(icon_name)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_root.add_child(b)
	return b

func _mk_toggle(y: float, cb: Callable) -> Button:
	var b := Button.new()
	b.set_size(Vector2(300, 52))
	b.set_position(Vector2((540 - 300) * 0.5, y))
	b.add_theme_font_size_override("font_size", 18)
	Art.style_button(b, Color(0.86, 0.55, 0.20), Color(0.30, 0.18, 0.05), Color(0.80, 0.56, 0.22))
	b.pressed.connect(cb)
	_root.add_child(b)
	return b

func _refresh_toggles() -> void:
	if _sfx_btn != null:
		_sfx_btn.text = I18n.t("pause_sfx") + (I18n.t("on") if Settings.sfx_enabled() else I18n.t("off"))
		if Art.has_ui_icon("volume_on") and Art.has_ui_icon("volume_off"):
			if Settings.sfx_enabled():
				_sfx_btn.icon = Art.ui_icon("volume_on")
			else:
				_sfx_btn.icon = Art.ui_icon("volume_off")
			_sfx_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _music_btn != null:
		_music_btn.text = I18n.t("pause_music") + (I18n.t("on") if Settings.music_enabled() else I18n.t("off"))
		if Art.has_ui_icon("music_on") and Art.has_ui_icon("music_off"):
			if Settings.music_enabled():
				_music_btn.icon = Art.ui_icon("music_on")
			else:
				_music_btn.icon = Art.ui_icon("music_off")
			_music_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

func _on_paused(p: bool) -> void:
	_root.visible = p
	if p:
		_refresh_toggles()
	else:
		# 取消暂停（恢复 / 重开 / 退出）时把叠在上层的设置与属性页一并收掉
		if _settings != null:
			_settings.hide_menu()
		if _stats != null:
			_stats.hide_menu()

func _on_locale_changed(_l: String = "") -> void:
	if _title_lbl != null:
		_title_lbl.text = I18n.t("pause_title")
	if _resume_btn != null:
		_resume_btn.text = I18n.t("pause_resume")
	if _stats_btn != null:
		_stats_btn.text = I18n.t("pause_stats")
	if _settings_btn != null:
		_settings_btn.text = I18n.t("pause_settings")
	if _restart_btn != null:
		_restart_btn.text = I18n.t("pause_restart")
	if _quit_btn != null:
		_quit_btn.text = I18n.t("pause_quit")
	_refresh_toggles()

func _on_resume() -> void:
	Sfx.ui_click()
	_stats.hide_menu()
	Events.resume_requested.emit()

func _on_restart() -> void:
	Sfx.ui_click()
	_root.visible = false
	_stats.hide_menu()
	Events.run_paused.emit(false)
	Events.run_requested.emit()

func _on_quit() -> void:
	Sfx.ui_click()
	_root.visible = false
	_stats.hide_menu()
	Events.run_paused.emit(false)
	Events.quit_to_title_requested.emit()

func _on_sfx() -> void:
	Settings.toggle_sfx()
	Sfx.apply_volume()
	_refresh_toggles()

func _on_music() -> void:
	Settings.toggle_music()
	Bgm.refresh()
	_refresh_toggles()

# 进入设置菜单：隐藏本菜单，打开 SettingsMenu
func _on_open_settings() -> void:
	Sfx.ui_click()
	_root.visible = false
	_settings.show_menu()

# 从设置菜单返回：重新显示本菜单并刷新开关
func _on_settings_back() -> void:
	_root.visible = true
	_refresh_toggles()

# 进入属性页：隐藏本菜单，打开 StatsScreen（游戏仍保持暂停，属性页叠在上层）
func _on_open_stats() -> void:
	Sfx.ui_click()
	_root.visible = false
	_stats.show_menu()

# 从属性页返回：重新显示本菜单
func _on_stats_back() -> void:
	_root.visible = true
	_refresh_toggles()
