extends CanvasLayer

# 暂停菜单：游戏中按右上角暂停键弹出。半透明遮罩 + 继续/重开/退出 + 音频开关。
# 自己只负责显示与发声，所有"动作"都通过 Events 信号交给 Game/TitleScreen 处理。
# 退出到标题由 Game 复位本局 + TitleScreen 重新显共同完成（见各自监听）。

var _root: Control
var _sfx_btn: Button
var _music_btn: Button

func _ready() -> void:
	layer = 30
	_build()
	_root.visible = false
	Events.run_paused.connect(_on_paused)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.82)
	_root.add_child(shade)

	var t := Label.new()
	t.text = "PAUSED"
	t.add_theme_font_size_override("font_size", 38)
	t.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_position(Vector2(0, 190))
	t.set_size(Vector2(540, 50))
	_root.add_child(t)

	_mk_btn("RESUME", 260, _on_resume, "play")
	_mk_btn("RESTART", 338, _on_restart)
	_mk_btn("QUIT TO TITLE", 416, _on_quit)

	_sfx_btn = _mk_toggle(484, _on_sfx)
	_music_btn = _mk_toggle(544, _on_music)
	_refresh_toggles()

func _mk_btn(text: String, y: float, cb: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.set_size(Vector2(300, 64))
	b.set_position(Vector2((540 - 300) * 0.5, y))
	b.add_theme_font_size_override("font_size", 22)
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
	b.pressed.connect(cb)
	_root.add_child(b)
	return b

func _refresh_toggles() -> void:
	if _sfx_btn != null:
		_sfx_btn.text = "SFX   " + ("ON" if Settings.sfx_enabled() else "OFF")
		if Art.has_ui_icon("volume_on") and Art.has_ui_icon("volume_off"):
			if Settings.sfx_enabled():
				_sfx_btn.icon = Art.ui_icon("volume_on")
			else:
				_sfx_btn.icon = Art.ui_icon("volume_off")
			_sfx_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _music_btn != null:
		_music_btn.text = "MUSIC " + ("ON" if Settings.music_enabled() else "OFF")
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

func _on_resume() -> void:
	Sfx.ui_click()
	Events.resume_requested.emit()

func _on_restart() -> void:
	Sfx.ui_click()
	_root.visible = false
	Events.run_paused.emit(false)
	Events.run_requested.emit()

func _on_quit() -> void:
	Sfx.ui_click()
	_root.visible = false
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
