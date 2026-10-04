extends CanvasLayer

# HUD：血条、波次进度、金币、击杀、武器槽、横幅、底部按钮。
#
# 【架构】本文件是"编排器 / orchestrator"，不含任何控件构造细节：
#   - 只做一件事：订阅 Events → 把数据分发给三个子组件 → 驱动它们的 tick。
#   - HudTop（顶部信息）/ HudBanners（横幅）/ HudButtons（底部按钮）各自
#     管自己的控件与安全区平移，互相不认识对方。
#   - 这样单文件不会随功能增长而失控（历史教训：曾经长到 389 行）。
#
# 布局约束：手机竖屏 540x900，顶部 74px 是 HUD 区（竞技场从 y=74 开始），
# 拇指会挡住下半屏，所以所有信息都放顶部。

const HudTopScript := preload("res://ui/HUD/HudTop.gd")
const HudBannersScript := preload("res://ui/HUD/HudBanners.gd")
const HudButtonsScript := preload("res://ui/HUD/HudButtons.gd")
const WaveSkipScript := preload("res://ui/HUD/WaveSkip.gd")
const DebugMode := preload("res://core/DebugMode.gd")
const Weapon := preload("res://core/Weapon.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")

# 竖屏安全区：顶部内容下移避让刘海 / 状态栏，底部按钮上移避让手势条。
const TOP_SHIFT := 34.0
const BOTTOM_SHIFT := 34.0

const COMBO_WINDOW := 2.5   # 连击有效窗口（秒）
const COMBO_MIN := 2        # 连击 >=2 才显示

var _top
var _banners
var _buttons
var _wok_last_tier := 0
var _wok_charges_n := 0     # 当前已存颠勺充能数（按钮常驻显示用）
var _combo := 0             # 连击数（短时间连续击杀累加）
var _combo_t := 0.0         # 连击剩余有效时间
var _run_total := 20        # 总波次（来自 balance.json）

func _ready() -> void:
	layer = 20

	# 顺序即绘制顺序，也决定触摸优先级：按钮最后加 → 永远压在最上面。
	_top = HudTopScript.new()
	add_child(_top)

	_banners = HudBannersScript.new()
	add_child(_banners)

	_buttons = HudButtonsScript.new()
	add_child(_buttons)

	# 调试"跳到第 N 波"：只在测试模式创建节点（core/DebugMode），正式版玩家看不到
	if DebugMode.enabled():
		add_child(WaveSkipScript.new())

	Events.player_hp_changed.connect(_on_hp)
	Events.gold_changed.connect(_on_gold)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_progress.connect(_on_wave_progress)
	Events.weapons_changed.connect(_on_weapons)
	Events.run_started.connect(_on_weapons)
	Events.boss_wave.connect(_on_boss_wave)
	Events.final_boss_wave.connect(_on_final_boss_wave)
	Events.endless_started.connect(_on_endless_started)
	Events.wok_heat_changed.connect(_on_wok_heat)
	Events.wok_ready_changed.connect(_on_wok_ready)
	Events.wok_charges_changed.connect(_on_wok_charges)
	Events.unlocked.connect(_on_unlocked)
	Events.enemy_killed.connect(_on_killed)
	Events.run_started.connect(_show_pause)
	Events.player_died.connect(_hide_pause)
	Events.run_won.connect(_hide_pause)
	Events.run_paused.connect(_on_run_paused)
	# 语言切换时刷新静态文案（颠勺按钮文本等）
	I18n.locale_changed.connect(_on_locale_changed)

	_run_total = int(Data.wave_cfg().get("total", 20))
	_top.set_bar("run_wave", GameState.wave)
	_top.set_bar("run_total", _run_total)
	_on_weapons()
	_refresh()

	# 竖屏安全区：必须在所有子组件建好后统一平移（子组件的矩形会跟着变）
	_apply_safe_area()

# ---- 信号 → 子组件 ----

func _on_hp(hp: int, max_hp: int) -> void:
	_top.set_bar("hp_ratio", float(hp) / maxf(1.0, float(max_hp)))

func _on_gold(gold: int) -> void:
	_top.set_gold_text(I18n.t("hud_gold") % gold)

func _on_wave_started(_wave: int) -> void:
	_refresh()

func _on_wave_progress(elapsed: float, length: float) -> void:
	_top.set_bar("wave_progress", elapsed / maxf(0.001, length))
	# 击杀数每帧跟着刷新（省一个信号，反正波次进度也是每帧发）
	_top.set_kills_text(I18n.t("hud_kills") % GameState.kills)
	_top.set_bar("run_wave", GameState.wave)
	_top.set_wave_text(_wave_text())

func _on_weapons(_ignored: Array = []) -> void:
	var slots: Array = []
	# Q1 套装：武器槽的描边按套装上色，凑够件数的那套会亮起来
	var act := WeaponSets.active_sets(GameState.weapons, Data.weapons, Data.weapon_sets)
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
			# 打法分支（光束/脉冲/链式/回旋/制导…）：武器槽要画对应符文
			"behavior": Weapon.behavior_of(def),
			"tag": _set_tag(def),
			"set_on": act.has(_set_tag(def)),
			"set_color": Color(str(Data.weapon_set(_set_tag(def)).get("color", "#8a7a5a"))),
		})
	_top.set_bar("slots", slots)

# 一把武器的主套装（取第一个 tag；没有 tag 的老数据返回空串）
func _set_tag(def: Dictionary) -> String:
	var tags: Array = def.get("tags", [])
	return str(tags[0]) if tags.size() > 0 else ""

func _refresh() -> void:
	_top.set_wave_text(_wave_text())
	_top.set_kills_text(I18n.t("hud_kills") % GameState.kills)
	_top.set_bar("run_wave", GameState.wave)
	_top.set_bar("run_total", _run_total)

func _wave_text() -> String:
	if GameState.endless:
		return I18n.t("hud_endless") % GameState.wave
	var t := I18n.t("hud_wave") % [GameState.wave, _run_total]
	if GameState.is_last_wave():
		t += I18n.t("hud_final")
	return t

func _on_boss_wave(wave: int) -> void:
	if GameState.is_last_wave():
		_banners.pop_boss(I18n.t("hud_final_wave") % wave)
	else:
		_banners.pop_boss(I18n.t("hud_boss_wave") % wave)

func _on_final_boss_wave(_wave: int) -> void:
	_banners.pop_final_boss(I18n.t("hud_final_boss"))

func _on_endless_started(wave: int) -> void:
	_banners.pop_boss(I18n.t("hud_endless") % wave)

func _on_wok_heat(value: float, tier: int) -> void:
	_top.set_bar("wok_ratio", clampf(value / 100.0, 0.0, 1.0))
	_top.set_bar("wok_tier", tier)
	# 跨档弹窗：让玩家明确知道"锅气上档了、火力变了"
	if tier != _wok_last_tier:
		_wok_last_tier = tier
		if tier >= 2:
			_banners.pop_wok(I18n.t("hud_wok_tier2"), Color(1.0, 0.5, 0.3))
		elif tier >= 1:
			_banners.pop_wok(I18n.t("hud_wok_tier1"), Color(1.0, 0.82, 0.42))

func _on_wok_ready(_ready: bool) -> void:
	# 就绪仅代表"有充能可放"；按钮常驻可见，文本由充能数决定
	_buttons.set_charges(_wok_charges_n)

func _on_wok_charges(n: int) -> void:
	_wok_charges_n = n
	_buttons.set_charges(n)

func _on_locale_changed(_l: String = "") -> void:
	_buttons.set_charges(_wok_charges_n)

func _on_unlocked(key: String) -> void:
	_banners.queue_unlock(key)

func _show_pause() -> void:
	_top.set_pause_visible(true)

func _hide_pause() -> void:
	_top.set_pause_visible(false)

func _on_run_paused(paused: bool) -> void:
	_top.set_pause_visible(not paused and GameState.running)

func _process(delta: float) -> void:
	_banners.tick(delta)
	_buttons.tick(delta)
	# 连击：超时归零，>=2 才显示
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0
	if _combo >= COMBO_MIN:
		_top.set_combo_text(I18n.t("hud_combo") % _combo)
	else:
		_top.set_combo_text("")

# 击杀信号：累加连击并刷新有效计时
func _on_killed(_type: String, _pos: Vector2) -> void:
	_combo += 1
	_combo_t = COMBO_WINDOW

# 竖屏安全区 / 异屏适配：
# - 顶部内容（血条 / 图标 / 波次 / 横幅）整体下移 TOP，避开刘海 / 状态栏；
# - 底部按钮（颠勺、冲刺）上移 BOTTOM，避开全面屏手势条 / Home Indicator；
# - 平移后同步更新共享给 Joystick 的避让区，避免"按钮挪走了摇杆还守旧坐标"。
func _apply_safe_area() -> void:
	_top.apply_safe_area(TOP_SHIFT)
	_banners.apply_safe_area(TOP_SHIFT)
	_buttons.apply_safe_area(BOTTOM_SHIFT)
	GameState.wok_toss_rect = _buttons.toss_rect()
	GameState.dash_rect = _buttons.dash_rect()
	GameState.pause_rect = _top.pause_rect()
