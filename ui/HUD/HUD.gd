extends CanvasLayer

# HUD：血条、波次进度、金币、击杀、武器槽。
# 只订阅 Events 信号更新自己 —— 不认识 Player、也不认识 Game。
# 布局约束：手机竖屏 540x900，顶部 74px 是 HUD 区（竞技场从 y=74 开始），
# 拇指会挡住下半屏，所以所有信息都放顶部。

const HudBarsScene := preload("res://ui/HUD/HudBars.gd")

var _bars: Node2D
var _wave: Label
var _gold: Label
var _kill: Label
var _wave_time := 0.0
var _wave_len := 20.0
var _banner: Label
var _banner_t := 0.0
var _wok_label: Label
var _toss_btn: Button

func _ready() -> void:
	layer = 20
	_bars = Node2D.new()
	_bars.set_script(HudBarsScene)
	add_child(_bars)

	_wave = _mk_label(Vector2(14, 34), 17, Color(0.95, 0.95, 0.95))
	_gold = _mk_label(Vector2(14, 54), 15, Color(0.98, 0.84, 0.35))
	_kill = _mk_label(Vector2(150, 54), 13, Color(0.75, 0.75, 0.78))

	# Boss 波居中横幅
	_banner = Label.new()
	_banner.position = Vector2(0, 288)
	_banner.custom_minimum_size = Vector2(540, 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_color", Color(0.96, 0.34, 0.46))
	_banner.text = ""
	add_child(_banner)

	# 锅气标签（底部，火候条左侧）
	_wok_label = _mk_label(Vector2(120, 828), 14, Color(0.95, 0.85, 0.6))
	_wok_label.text = "WOK 锅气 · 微温"

	# 颠勺按钮：满锅气才出现，点一下全屏甩飞。屏幕坐标共享给 Joystick 用于避让移动。
	_toss_btn = Button.new()
	_toss_btn.custom_minimum_size = Vector2(120, 120)
	_toss_btn.size = Vector2(120, 120)
	_toss_btn.position = Vector2(210, 706)   # 中心 (270, 766)，在火候条上方
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.42, 0.26, 0.28)
	sb.border_color = Color(1.0, 0.72, 0.42, 0.95)
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 60
	sb.corner_radius_top_right = 60
	sb.corner_radius_bottom_left = 60
	sb.corner_radius_bottom_right = 60
	_toss_btn.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(1.0, 0.6, 0.4, 0.5)
	_toss_btn.add_theme_stylebox_override("pressed", sbp)
	_toss_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_toss_btn.add_theme_font_size_override("font_size", 22)
	_toss_btn.text = "颠勺\nWOK"
	_toss_btn.visible = false
	_toss_btn.pressed.connect(_on_toss_pressed)
	add_child(_toss_btn)
	# 共享给 Joystick：玩家戳这个区域时只触发颠勺、不移动
	GameState.wok_toss_rect = Rect2(210, 706, 120, 120)

	Events.player_hp_changed.connect(_on_hp)
	Events.gold_changed.connect(_on_gold)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_progress.connect(_on_wave_progress)
	Events.weapons_changed.connect(_on_weapons)
	Events.run_started.connect(_on_weapons)
	Events.boss_wave.connect(_on_boss_wave)
	Events.wok_heat_changed.connect(_on_wok_heat)
	Events.wok_ready_changed.connect(_on_wok_ready)

	_wave_len = float(Data.wave_cfg().get("length", 20))
	_on_weapons()
	_refresh()

func _mk_label(pos: Vector2, size: int, c: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	add_child(l)
	return l

func _on_hp(hp: int, max_hp: int) -> void:
	_bars.set("hp_ratio", float(hp) / maxf(1.0, float(max_hp)))
	_bars.queue_redraw()

func _on_gold(gold: int) -> void:
	_gold.text = "GOLD %d" % gold

func _on_wave_started(wave: int) -> void:
	_refresh()

func _on_wave_progress(elapsed: float, length: float) -> void:
	_bars.set("wave_progress", elapsed / maxf(0.001, length))
	_bars.queue_redraw()
	# 击杀数每帧跟着刷新（省一个信号，反正波次进度也是每帧发）
	_kill.text = "KILLS %d" % GameState.kills
	var wtxt := "WAVE %d" % GameState.wave
	if GameState.is_last_wave():
		wtxt += " · FINAL"
	_wave.text = wtxt

func _on_weapons(_ignored: Array = []) -> void:
	var slots: Array = []
	for w in GameState.weapons:
		if not (w is Dictionary):
			continue
		var def := Data.weapon(str(w.get("key", "")))
		if def.is_empty():
			continue
		slots.append({
			"key": str(w.get("key", "")),
			"lv": int(w.get("lv", 1)),
			"color": Color(str(def.get("color", "#ffffff"))),
			"zh": str(def.get("en", def.get("zh", ""))),
		})
	_bars.set("slots", slots)
	_bars.queue_redraw()

func _refresh() -> void:
	var wtxt := "WAVE %d" % GameState.wave
	if GameState.is_last_wave():
		wtxt += " · FINAL"
	_wave.text = wtxt
	_kill.text = "KILLS %d" % GameState.kills

func _on_boss_wave(wave: int) -> void:
	if GameState.is_last_wave():
		_banner.text = "FINAL WAVE %d" % wave
	else:
		_banner.text = "BOSS WAVE %d" % wave
	_banner_t = 2.6

func _on_wok_heat(value: float, tier: int) -> void:
	_bars.set("wok_ratio", clampf(value / 100.0, 0.0, 1.0))
	_bars.set("wok_tier", tier)
	_bars.queue_redraw()
	var name := "微温"
	if tier >= 2:
		name = "爆炒"
	elif tier >= 1:
		name = "翻炒"
	_wok_label.text = "WOK 锅气 · %s" % name

func _on_wok_ready(ready: bool) -> void:
	_toss_btn.visible = ready

func _on_toss_pressed() -> void:
	Events.wok_toss_requested.emit()

func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		# 最后 0.6s 渐隐
		var a := clampf(_banner_t / 0.6, 0.0, 1.0)
		_banner.modulate.a = a
		if _banner_t <= 0.0:
			_banner.text = ""
