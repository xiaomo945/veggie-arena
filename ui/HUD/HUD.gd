extends CanvasLayer

# HUD：血条、波次进度、金币、击杀、武器槽。
# 只订阅 Events 信号更新自己 —— 不认识 Player、也不认识 Game。
# 布局约束：手机竖屏 540x900，顶部 74px 是 HUD 区（竞技场从 y=74 开始），
# 拇指会挡住下半屏，所以所有信息都放顶部。

const HudBarsScene := preload("res://ui/HUD/HudBars.gd")
const DashButtonScript := preload("res://ui/HUD/DashButton.gd")

# 冲刺按钮位置：右下角，避开中间的颠勺按钮（210..330）与左下拇指区
const DASH_POS := Vector2(398, 748)
const DASH_SIZE := 96.0

var _bars: Node2D
var _dash_btn: Control
var _unlock: Label
var _wave: Label
var _gold: Label
var _kill: Label
var _wave_time := 0.0
var _wave_len := 20.0
var _banner: Label
var _banner_t := 0.0
var _wok_banner: Label
var _wok_banner_t := 0.0
var _wok_last_tier := 0
var _wok_charges_n := 0        # 当前已存颠勺充能数（按钮常驻显示用）
var _toss_btn: Button
var _unlock_queue: Array = []    # 待展示的解锁提示（一次一條，避免刷屏）
var _unlock_t := 0.0
var _pause_btn: Button
var _combo := 0                  # 连击数（短时间连续击杀累加）
var _combo_t := 0.0              # 连击剩余有效时间
var _combo_label: Label
var _run_total := 20             # 总波次（来自 balance.json）

func _ready() -> void:
	layer = 20
	_bars = Node2D.new()
	_bars.set_script(HudBarsScene)
	add_child(_bars)

	# 血条左侧红心图标（代表血量），血条已右移到 x=40 给图标腾出空间
	_mk_icon("heart", Vector2(10, 4), 26)

	_wave = _mk_label(Vector2(40, 44), 16, Color(0.95, 0.95, 0.95))
	_gold = _mk_label(Vector2(40, 62), 14, Color(0.98, 0.84, 0.35))
	_kill = _mk_label(Vector2(180, 62), 12, Color(0.75, 0.75, 0.78))

	# 金币左侧金币图标，金币标签已右移到 x=40 避免遮挡
	_mk_icon("coin", Vector2(12, 58), 22)

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

	# 锅气档位弹窗（顶部偏下，火候上档时弹出"翻炒!"/"爆炒!"）
	_wok_banner = Label.new()
	_wok_banner.position = Vector2(0, 96)
	_wok_banner.custom_minimum_size = Vector2(540, 40)
	_wok_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wok_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wok_banner.add_theme_font_size_override("font_size", 30)
	_wok_banner.text = ""
	add_child(_wok_banner)

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
	_toss_btn.text = I18n.t("hud_toss")
	_toss_btn.visible = false
	_toss_btn.pressed.connect(_on_toss_pressed)
	add_child(_toss_btn)
	# 共享给 Joystick：玩家戳这个区域时只触发颠勺、不移动
	GameState.wok_toss_rect = Rect2(210, 706, 120, 120)

	# 冲刺按钮（常驻右下角，自带冷却扇形）
	_dash_btn = Control.new()
	_dash_btn.set_script(DashButtonScript)
	_dash_btn.position = DASH_POS
	add_child(_dash_btn)
	# 共享给 Joystick：戳这块只冲刺，不当成走位拖拽
	GameState.dash_rect = Rect2(DASH_POS, Vector2(DASH_SIZE, DASH_SIZE))

	Events.player_hp_changed.connect(_on_hp)
	Events.gold_changed.connect(_on_gold)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_progress.connect(_on_wave_progress)
	Events.weapons_changed.connect(_on_weapons)
	Events.run_started.connect(_on_weapons)
	Events.boss_wave.connect(_on_boss_wave)
	Events.wok_heat_changed.connect(_on_wok_heat)
	Events.wok_ready_changed.connect(_on_wok_ready)
	Events.wok_charges_changed.connect(_on_wok_charges)
	Events.unlocked.connect(_on_unlocked)

	# 解锁横幅（复用 Boss 横幅的位置与渐隐逻辑，另开一个 Label）
	_unlock = Label.new()
	_unlock.position = Vector2(0, 340)
	_unlock.custom_minimum_size = Vector2(540, 40)
	_unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unlock.add_theme_font_size_override("font_size", 24)
	_unlock.add_theme_color_override("font_color", Color(1.0, 0.84, 0.36))
	_unlock.text = ""
	add_child(_unlock)

	_wave_len = float(Data.wave_cfg().get("length", 20))
	_run_total = int(Data.wave_cfg().get("total", 20))
	_bars.set("run_wave", GameState.wave)
	_bars.set("run_total", _run_total)
	_on_weapons()
	_refresh()

	# 连击显示（基于击杀信号，短时间内连续击杀累加）
	_combo_label = Label.new()
	_combo_label.position = Vector2(300, 62)
	_combo_label.add_theme_font_size_override("font_size", 12)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_combo_label.text = ""
	add_child(_combo_label)
	Events.enemy_killed.connect(_on_killed)

	# 暂停按钮：右上角，游戏中显示，暂停/结算时隐藏
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
	add_child(_pause_btn)
	_pause_btn.visible = false
	# 共享给 Joystick：戳暂停按钮区域只暂停，不当成走位拖拽
	GameState.pause_rect = Rect2(_pause_btn.position, _pause_btn.size)

	Events.run_started.connect(_show_pause)
	Events.player_died.connect(_hide_pause)
	Events.run_won.connect(_hide_pause)
	Events.run_paused.connect(_on_run_paused)

	# 语言切换时刷新静态文案（颠勺按钮文本等）
	I18n.locale_changed.connect(_on_locale_changed)

	# 竖屏安全区：全部 HUD 元素整体下移，避开刘海 / 状态栏（必须在所有子节点建好后）
	_apply_safe_area()

func _mk_label(pos: Vector2, size: int, c: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	add_child(l)
	return l

# 在 HUD 上放一个小图标（TextureRect）。没图时（Art 兜底）直接跳过，不影响布局。
func _mk_icon(name: String, pos: Vector2, sz: float) -> void:
	if not Art.has_ui_icon(name):
		return
	var tex = TextureRect.new()
	tex.texture = Art.ui_icon(name)
	tex.custom_minimum_size = Vector2(sz, sz)
	tex.size = Vector2(sz, sz)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.position = pos
	add_child(tex)

func _on_hp(hp: int, max_hp: int) -> void:
	_bars.set("hp_ratio", float(hp) / maxf(1.0, float(max_hp)))
	_bars.queue_redraw()

func _on_gold(gold: int) -> void:
	_gold.text = I18n.t("hud_gold") % gold

func _on_wave_started(wave: int) -> void:
	_refresh()

func _on_wave_progress(elapsed: float, length: float) -> void:
	_bars.set("wave_progress", elapsed / maxf(0.001, length))
	_bars.queue_redraw()
	# 击杀数每帧跟着刷新（省一个信号，反正波次进度也是每帧发）
	_kill.text = I18n.t("hud_kills") % GameState.kills
	_bars.set("run_wave", GameState.wave)
	var wtxt := I18n.t("hud_wave") % [GameState.wave, _run_total]
	if GameState.is_last_wave():
		wtxt += I18n.t("hud_final")
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
			"name": I18n.pick(def),
		})
	_bars.set("slots", slots)
	_bars.queue_redraw()

func _refresh() -> void:
	var wtxt := I18n.t("hud_wave") % [GameState.wave, _run_total]
	if GameState.is_last_wave():
		wtxt += I18n.t("hud_final")
	_wave.text = wtxt
	_kill.text = "KILLS %d" % GameState.kills
	_bars.set("run_wave", GameState.wave)
	_bars.set("run_total", _run_total)
	_bars.queue_redraw()

func _on_boss_wave(wave: int) -> void:
	if GameState.is_last_wave():
		_banner.text = I18n.t("hud_final_wave") % wave
	else:
		_banner.text = I18n.t("hud_boss_wave") % wave
	_banner_t = 2.6

func _on_wok_heat(value: float, tier: int) -> void:
	_bars.set("wok_ratio", clampf(value / 100.0, 0.0, 1.0))
	_bars.set("wok_tier", tier)
	_bars.queue_redraw()
	# 跨档弹窗：让玩家明确知道"锅气上档了、火力变了"
	if tier != _wok_last_tier:
		_wok_last_tier = tier
		if tier >= 2:
			_pop_wok(I18n.t("hud_wok_tier2"), Color(1.0, 0.5, 0.3))
		elif tier >= 1:
			_pop_wok(I18n.t("hud_wok_tier1"), Color(1.0, 0.82, 0.42))

func _on_wok_ready(ready: bool) -> void:
	# 就绪仅代表"有充能可放"；按钮常驻可见，文本由充能数决定
	_refresh_toss_btn()

func _on_wok_charges(n: int) -> void:
	_wok_charges_n = n
	_refresh_toss_btn()

# 颠勺按钮常驻：只要有充能就一直可见（不再"攒满闪一下又消失"）。
# 充能 >1 时显示 "颠勺 x{n}"，提示玩家手里存了好几个，危险时连放。
func _refresh_toss_btn() -> void:
	_toss_btn.visible = _wok_charges_n > 0
	if _wok_charges_n > 1:
		_toss_btn.text = "%s x%d" % [I18n.t("hud_toss"), _wok_charges_n]
	else:
		_toss_btn.text = I18n.t("hud_toss")

func _on_toss_pressed() -> void:
	Events.wok_toss_requested.emit()

func _on_locale_changed(_l: String = "") -> void:
	_refresh_toss_btn()

func _pop_wok(text: String, c: Color) -> void:
	_wok_banner.text = text
	_wok_banner.add_theme_color_override("font_color", c)
	_wok_banner.modulate.a = 1.0
	_wok_banner_t = 1.6

func _on_unlocked(key: String) -> void:
	_unlock_queue.append(key)

# 解锁提示：一次显示一条，2.2 秒后换下一条（多条时排队，不叠在一起）
func _tick_unlock(delta: float) -> void:
	if _unlock_t > 0.0:
		_unlock_t -= delta
		var a := clampf(_unlock_t / 0.5, 0.0, 1.0)
		_unlock.modulate.a = a
		if _unlock_t <= 0.0:
			_unlock.text = ""
		return
	if _unlock_queue.is_empty():
		return
	var key := str(_unlock_queue.pop_front())
	var def := Data.weapon(key)
	var name := I18n.pick(def)
	_unlock.text = I18n.t("hud_unlocked") % name.to_upper()
	_unlock_t = 2.2

func _on_pause_pressed() -> void:
	Events.pause_requested.emit()

func _show_pause() -> void:
	_pause_btn.visible = true

func _hide_pause() -> void:
	_pause_btn.visible = false

func _on_run_paused(paused: bool) -> void:
	_pause_btn.visible = !paused and GameState.running

func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		# 最后 0.6s 渐隐
		var a := clampf(_banner_t / 0.6, 0.0, 1.0)
		_banner.modulate.a = a
		if _banner_t <= 0.0:
			_banner.text = ""
	if _wok_banner_t > 0.0:
		_wok_banner_t -= delta
		var a := clampf(_wok_banner_t / 0.6, 0.0, 1.0)
		_wok_banner.modulate.a = a
		if _wok_banner_t <= 0.0:
			_wok_banner.text = ""
	# 颠勺按钮满气时呼吸闪烁，提示玩家"戳这里放颠勺"
	if _toss_btn.visible:
		_toss_btn.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 110.0)
	_tick_unlock(delta)
	# 连击：超时归零，>=2 才显示
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0
	if _combo >= 2:
		_combo_label.text = I18n.t("hud_combo") % _combo
	else:
		_combo_label.text = ""

# 击杀信号：累加连击并刷新有效计时
func _on_killed(_type: String, _pos: Vector2) -> void:
	_combo += 1
	_combo_t = 2.5

# 竖屏安全区 / 异屏适配：
# - 顶部内容（血条 / 图标 / 波次）整体下移 TOP，避开刘海 / 状态栏；
# - 底部按钮（颠勺、冲刺）上移 BOTTOM，避开全面屏手势条 / Home Indicator；
# - 底部按钮上移后，同步更新共享给 Joystick 的避让区，避免"按钮挪走了摇杆还守旧坐标"。
func _apply_safe_area() -> void:
	const TOP := 34.0
	const BOTTOM := 34.0
	for c in get_children():
		# 底部控制（颠勺 / 冲刺）：只上移 BOTTOM 避让手势条，不随顶部一起下移
		if c == _toss_btn or c == _dash_btn:
			var bc := c as Control
			if bc != null:
				bc.position -= Vector2(0.0, BOTTOM)
			else:
				var bn := c as Node2D
				if bn != null:
					bn.position -= Vector2(0.0, BOTTOM)
			if c == _toss_btn:
				GameState.wok_toss_rect = Rect2(_toss_btn.position, _toss_btn.size)
			elif c == _dash_btn:
				GameState.dash_rect = Rect2(_dash_btn.position, Vector2(DASH_SIZE, DASH_SIZE))
		else:
			# 其余（顶部 HUD / 横幅等）：下移 TOP 避让刘海 / 状态栏
			var n2d := c as Node2D
			if n2d != null:
				n2d.position += Vector2(0.0, TOP)
			else:
				var ctrl := c as Control
				if ctrl != null:
					ctrl.position += Vector2(0.0, TOP)
	# 暂停按钮也被下移了，用移位后的坐标重算 Joystick 避让区
	GameState.pause_rect = Rect2(_pause_btn.position, _pause_btn.size)
