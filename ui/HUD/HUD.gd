extends CanvasLayer

# HUD：血条、波次进度、金币、击杀、武器槽、横幅、底部按钮。竖屏 540x900。
# 【架构】编排器：订阅 Events → 分发子组件 → 驱动 tick；HudTop/HudBanners/HudButtons/HudSynergy 各自管控件与安全区平移，互不认识。

const HudTopScript := preload("res://ui/HUD/HudTop.gd")
const HudBannersScript := preload("res://ui/HUD/HudBanners.gd")
const HudButtonsScript := preload("res://ui/HUD/HudButtons.gd")
const HudSynergyScript := preload("res://ui/HUD/HudSynergy.gd")
const WaveSkipScript := preload("res://ui/HUD/WaveSkip.gd")
const FpsMeterScript := preload("res://ui/HUD/FpsMeter.gd")
const HintLineScript := preload("res://ui/HUD/HintLine.gd")
const DebugMode := preload("res://core/DebugMode.gd")
const Weapon := preload("res://core/Weapon.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")
const Stats := preload("res://core/Stats.gd")

# 竖屏安全区：顶部下移避让刘海/状态栏，底部上移避让手势条（值都在 HudLayout，相机也按它让位，两处各写一份必然漂移）。
# ⚠️ 底部平移由 HudButtons.relayout() 自重放并自刷共享矩形，攻击键与摇杆底盘才永远同一水平线。
const COMBO_WINDOW := 2.5   # 连击有效窗口（秒）
const COMBO_MIN := 2        # 连击 >=2 才显示

var _top
var _banners
var _syn              # 羁绊进度条（自己拉数据、自己画，跨档时给本文件发 tier_up）
var _buttons
var _wok_last_tier := 0
var _wok_charges_n := 0     # 当前已存颠勺充能数（按钮常驻显示用）
var _combo := 0             # 连击数（短时间连续击杀累加）
var _combo_t := 0.0         # 连击剩余有效时间
var _run_total := 20        # 总波次（来自 balance.json）
var _set_tiers := {}        # 上一帧各套装的档位（用于侦测"刚跨档"）
var _fps                   # FPS 计数器（默认隐藏）

func _ready() -> void:
	layer = 20
	visible = false   # 标题页期间整层隐藏，run_started（_show_pause）再亮，回标题再灭

	# 顺序即绘制顺序，也决定触摸优先级：按钮最后加 → 永远压在最上面。
	_top = HudTopScript.new()
	add_child(_top)

	# 羁绊进度条：常驻"本命 3/6 还差几件"，自己每 0.25s 拉数据；本文件只转发跨档通知
	_syn = HudSynergyScript.new()
	add_child(_syn)
	_syn.tier_up.connect(_on_syn_tier_up)

	_banners = HudBannersScript.new()
	add_child(_banners)
	add_to_group("hud")   # 供 Shop 等 UI 层通过 get_first_node_in_group 拿到 HUD，再取横幅组件

	add_child(HintLineScript.new())   # 开局一行操作提示，6 秒淡出（IGNORE 鼠标，不挡点击）
	_buttons = HudButtonsScript.new()
	add_child(_buttons)

	# 调试"跳到第 N 波"：只在测试模式创建（core/DebugMode），正式版玩家看不到
	if DebugMode.enabled():
		add_child(WaveSkipScript.new())

	# FPS 计数器：默认隐藏，Settings 打开才显示（排查卡顿要玩家报 FPS + 同屏怪数）
	_fps = FpsMeterScript.new()
	_fps.set_position(HudLayout.fps_pos())
	add_child(_fps)

	Events.player_hp_changed.connect(_on_hp)
	Events.gold_changed.connect(_on_gold)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_progress.connect(_on_wave_progress)
	Events.weapons_changed.connect(_on_weapons)
	Events.run_started.connect(_on_run_started)
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
	Events.quit_to_title_requested.connect(_hide_pause)
	Events.run_paused.connect(_on_run_paused)
	Events.xp_changed.connect(_on_xp)
	Events.level_up.connect(_on_level_up)
	I18n.locale_changed.connect(_on_locale_changed)   # 切语言刷新静态文案（颠勺按钮文本等）

	_run_total = int(Data.wave_cfg().get("total", 20))
	_top.set_bar("run_wave", GameState.wave)
	_top.set_bar("run_total", _run_total)
	_on_weapons()
	_refresh()

	# 子组件全建好后统一平移一次（矩形会跟着变）
	_apply_safe_area()
	# 横竖屏翻转 / 窗口缩放：ScreenMode 广播后各子组件按新模式自排
	ScreenMode.layout_changed.connect(_on_layout_changed)

# 布局模式翻转（横↔竖）：各子组件 relayout 内部已自 reset + 自重放安全区 + 自刷共享矩形，HUD 只补挪 FPS 位。
func _on_layout_changed(_land: bool) -> void:
	if _top != null and _top.has_method("relayout"):
		_top.relayout()
	if _syn != null and _syn.has_method("relayout"):
		_syn.relayout()
	if _buttons != null and _buttons.has_method("relayout"):
		_buttons.relayout()
	if _fps != null:
		_fps.set_position(HudLayout.fps_pos())
# ---- 信号 → 子组件 ----

func _on_hp(hp: int, max_hp: int) -> void:
	_top.set_bar("hp_ratio", float(hp) / maxf(1.0, float(max_hp)))

func _on_gold(gold: int) -> void:
	_top.set_gold_text(I18n.t("hud_gold") % gold)

func _on_wave_started(_wave: int) -> void:
	_refresh()

func _on_wave_progress(elapsed: float, length: float) -> void:
	_top.set_bar("wave_progress", elapsed / maxf(0.001, length))
	# 击杀数每帧跟着刷新（省一个信号，波次进度本来就每帧发）
	_top.set_kills_text(I18n.t("hud_kills") % GameState.kills)
	_top.set_bar("run_wave", GameState.wave)
	_top.set_wave_text(_wave_text())

# 经验条刷新：每次掉经验都来一次，直接把四个值塞给 HudBars
func _on_xp(level: int, into: int, need: int, pct: float) -> void:
	_top.set_bar("xp_level", level)
	_top.set_bar("xp_into", into)
	_top.set_bar("xp_need", need)
	_top.set_bar("xp_pct", pct)

# 升级：横幅（爽点的主入口）+ 经验条闪一下
func _on_level_up(level: int, gained: int) -> void:
	_top.set_bar("xp_flash", 1.0)
	# 连升多级时横幅停久一点（信息量更大，值得多看一秒）
	if gained > 1:
		_banners.pop_effect(I18n.t("level_up_multi") % [gained, level], Color(0.85, 0.70, 1.0))
	else:
		_banners.pop_effect(I18n.t("level_up") % level, Color(0.85, 0.70, 1.0))

# 新局的套装档位从零算起，别把上一局残留的档位带进来（否则开局不会弹提示）
func _on_run_started() -> void:
	_set_tiers = {}

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
	_check_set_tier_up()

# 套装档位刚跨过去时弹一条横幅：不弹的话，"我凑齐了一套"这件大事只在属性面板里变个数字
func _check_set_tier_up() -> void:
	var now := WeaponSets.active_sets(GameState.weapons, Data.weapons, Data.weapon_sets)
	var tiers: Dictionary = {}    # 只存档位：存整个 active_sets 会拿 Dictionary 去 int() 崩掉
	for tag in now:
		var d := now[tag] as Dictionary
		var tier := int(d.get("tier", 0))
		tiers[tag] = tier
		if tier <= int(_set_tiers.get(tag, 0)):
			continue
		var sd := Data.weapon_set(str(tag))
		_banners.pop_set(I18n.t("set_tier_up") % [I18n.t("set_" + str(tag)),
			int(d.get("count", 0))] + _set_gain(sd, tier),
			Color(str(sd.get("color", "#ffd08a"))))
	_set_tiers = tiers

# 羁绊跨档（本命/武器类多凑够一件）：与套装跨档走同一条横幅通道，不弹就只变成面板里的一行数字
func _on_syn_tier_up(text: String, color: Color) -> void:
	_banners.pop_set(text, color)

# 这一档给了什么（取第一条加成写进横幅，全写会太长）
func _set_gain(sd: Dictionary, tier: int) -> String:
	var st := WeaponSets.tier_stats(sd, tier)
	for k in st:
		var e := Stats.entry(str(k))
		return "  " + I18n.t(str(e.get("name", ""))) + " " + Stats.fmt_value(str(e.get("fmt", "")), float(st[k]))
	return ""

# 一把武器的主套装（取第一个 tag；没有 tag 的老数据返回空串）
func _set_tag(def: Dictionary) -> String:
	var tags: Array = def.get("tags", [])
	return str(tags[0]) if tags.size() > 0 else ""

func _refresh() -> void:
	_top.set_wave_text(_wave_text())
	_top.set_kills_text(I18n.t("hud_kills") % GameState.kills)
	_top.set_bar("run_wave", GameState.wave)
	_top.set_bar("run_total", _run_total)

# 对外：返回横幅组件（HudBanners），供 Shop 等 UI 层弹出强化反馈（R3：走公开访问器，不读私有字段）
func banners() -> Node:
	return _banners

func set_stats_screen(s: CanvasLayer) -> void:
	if _top != null:
		_top.set_stats_screen(s)

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
	_refresh()   # 波次文本模板走 I18n；gold/kills/xp 归 HudTop 自己刷，技能按钮自己重画

func _on_unlocked(key: String) -> void:
	_banners.queue_unlock(key)

func _show_pause() -> void:
	visible = true          # 开跑才亮：标题页/选武器页期间 HUD 整层隐藏（透底事故）
	_top.set_pause_visible(true)

func _hide_pause() -> void:
	visible = false
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

# 竖屏安全区 / 异屏适配：顶部内容整体下移 TOP 避让刘海。
# ⚠️ _buttons 不在这里平移：HudButtons._ready→relayout() 已自重放 bottom_shift，
# 并自刷 wok_toss_rect/dash_rect。这里再放 = 双重平移（攻击键/技能环整体上移
# 34px，轮盘与攻击键不再同一水平线）—— kb_shot 布局断言抓到过这个回归。
func _apply_safe_area() -> void:
	_top.apply_safe_area(HudLayout.safe_top())
	_banners.apply_safe_area(HudLayout.safe_top())
	GameState.pause_rect = _top.pause_rect()
