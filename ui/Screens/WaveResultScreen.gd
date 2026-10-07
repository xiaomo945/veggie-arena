extends CanvasLayer

# 每波结算页（D3-3）：波次结束弹出，显示本波金币 / 击杀 / 最高连击 / 当前生命，
# 给玩家一个缓冲（世界已在 WaveDirector.end_wave 里暂停）。点"继续"开补给站。
# 仅通过 Events 与外界通信，不读任何私有字段（R3）。
# I18n / Sfx / ScreenMode / Art / Events / GameState 均为 autoload，直接用全局名。

var _root: Control
var _open := false
var _title_lbl: Label
var _gold_lbl: Label
var _kill_lbl: Label
var _combo_lbl: Label
var _hp_lbl: Label
var _cont_btn: Button

func _ready() -> void:
	layer = 31
	add_to_group("wave_result")
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)
	Events.wave_result_ready.connect(_on_ready)
	Events.wave_result_closed.connect(_on_closed)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.05, 0.09, 0.78)
	_root.add_child(shade)
	var panel := Panel.new()
	panel.set_size(Vector2(440, 380))
	panel.position = Vector2((540 - 440) * 0.5, (900 - 380) * 0.5)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(24, 22)
	vb.size = Vector2(392, 336)
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 30)
	_title_lbl.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	vb.add_child(_title_lbl)
	_gold_lbl = _mk_row(vb)
	_kill_lbl = _mk_row(vb)
	_combo_lbl = _mk_row(vb)
	_hp_lbl = _mk_row(vb)
	_cont_btn = Button.new()
	_cont_btn.text = I18n.t("wave_result_continue")
	_cont_btn.set_size(Vector2(360, 56))
	_cont_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cont_btn.add_theme_font_size_override("font_size", 22)
	Art.style_button(_cont_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_cont_btn.pressed.connect(_on_continue)
	vb.add_child(_cont_btn)

func _mk_row(vb: VBoxContainer) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	vb.add_child(l)
	return l

func _on_ready(wave: int) -> void:
	_refresh(wave)
	_open = true
	_root.visible = true
	# 模拟自测打印一行，供 run_sim.py 断言"结算页显示过"（见 scripts/run_sim.py）
	if OS.has_environment("SIM_SEED"):
		var ws := GameState.wave_stats
		print("  波次结算: 第 %d 波 金币+%d 击杀%d 连击%d 生命%d/%d" % [
			wave, ws.gold_earned(GameState.gold), ws.kills_this_wave(GameState.kills),
			ws.best_combo, GameState.hp, GameState.max_hp])

func _on_closed() -> void:
	_open = false
	_root.visible = false

func _on_continue() -> void:
	Sfx.ui_click()
	_open = false
	_root.visible = false
	Events.wave_result_closed.emit()

func _on_locale_changed(_l: String = "") -> void:
	if _open:
		_refresh(GameState.wave)

func _refresh(wave: int) -> void:
	var ws := GameState.wave_stats
	_title_lbl.text = I18n.t("wave_result_title") % wave
	_gold_lbl.text = I18n.t("wave_result_gold") % ws.gold_earned(GameState.gold)
	_kill_lbl.text = I18n.t("wave_result_kills") % ws.kills_this_wave(GameState.kills)
	_combo_lbl.text = I18n.t("wave_result_combo") % ws.best_combo
	_hp_lbl.text = I18n.t("wave_result_hp") % [GameState.hp, GameState.max_hp]

func is_open() -> bool:
	return _open
