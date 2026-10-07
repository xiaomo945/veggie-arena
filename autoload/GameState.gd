extends Node

# 当前这一局的状态：重开时调 reset()，不新建节点；只依赖 Data，不依赖渲染节点（便于 headless 测试）。

var wave: int = 1
var gold: int = 0
var hp: int = 100
var max_hp: int = 100
var kills: int = 0
var xp: int = 0            # 累计经验（core/Level 换算成等级）
var elapsed_in_wave: float = 0.0
var running: bool = false
var paused: bool = false     # 暂停菜单是否打开（Joystick 据此停止接管触摸，避免暂停时还在走位）
var won: bool = false        # 本局是不是打通关了（区分"阵亡"与"通关"，结算页/自测报告都要用）
var endless: bool = false    # 是否已进入无尽段（通关后选了"继续"，波次越过 wave.total）

# 当前选择的角色（data/characters.json 的键）。角色自带属性加成，与强化叠加。
var character: String = "turnip"

# 开局自选的初始武器（data/weapons.json 的键），在标题页"选武器页"落地。
# 空串 = 未选，reset() 退回 pistol+smg 双武器起步；选了则"所选 1 把 + 手枪保底"，
# 手枪永远在，避免新手只拿一把近战被围死。
var start_weapon: String = ""

# 装备：元素形如 {"key": "pistol", "lv": 1}
# ⚠️ 字段名必须是 "lv"（core/Inventory 里就用这个），写成 "level" 会让合成静默失效
var weapons: Array = []
# 强化：{"key": 数量}
var upgrades: Dictionary = {}

# ---- 锅气 Wok Heat（招牌机制）---- 0 微温/1 翻炒/2 爆炒，满锅气可颠勺（全屏击退+重伤）
const Wok := preload("res://core/Wok.gd")
const Character := preload("res://core/Character.gd")
const Run := preload("res://core/Run.gd")
const Inventory := preload("res://core/Inventory.gd")
const Pickup := preload("res://core/Pickup.gd")
const Level := preload("res://core/Level.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")
const StatBonus := preload("res://core/StatBonus.gd")
const WaveStats := preload("res://core/WaveStats.gd")
var wave_stats := WaveStats.new()   # 每波统计（D3-3 结算页用），纯逻辑见 core/WaveStats.gd
var wok: Dictionary = {}
var wok_heat: float = 0.0
var _wok_tier: int = 0
var _wok_ready_emitted := false
# 以下三块屏幕矩形由 HUD 写入、Joystick 读取后避让：戳这块只做对应操作，不走位
var wok_toss_rect := Rect2(0, 0, 0, 0)
var dash_rect := Rect2(0, 0, 0, 0)
var pause_rect := Rect2(0, 0, 0, 0)

func _ready() -> void:
	reset()
	# reset() 把 running 置 true；启动时必须停下，否则标题页没点背后就开打了
	running = false

func reset() -> void:
	var p := Data.player_cfg()
	# 角色自带的生命加成并入上限（其它属性走 stat_value）
	max_hp = int(p.get("max_hp", 100)) + int(_char_stat("max_hp"))
	hp = max_hp
	wave = 1
	gold = 0
	kills = 0
	wave_stats.snapshot(0, 0)
	xp = 0
	elapsed_in_wave = 0.0
	running = true
	won = false
	endless = false
	weapons = []
	upgrades = {}
	wok = Wok.make(Data.wok_cfg())
	# 角色自带开局充能：爆炒萝卜一进局就能颠一勺，不用先读懂火候条
	Wok.grant(wok, Character.start_wok_charges(Data.character(character)))
	wok_heat = 0.0
	_wok_tier = 0
	_wok_ready_emitted = false
	shield = 0
	frenzy_left = 0.0
	Events.shield_changed.emit(shield)
	# 开局武器：标题页选的 1 把 + 手枪保底（没选则 pistol+smg 双武器起步）
	weapons = []
	if start_weapon != "" and start_weapon != "pistol":
		weapons.append({"key": start_weapon, "lv": 1})
	weapons.append({"key": "pistol", "lv": 1})
	if start_weapon == "":
		weapons.append({"key": "smg", "lv": 1})

# ---- 角色 ----
func set_character(key: String) -> void:
	if key.is_empty() or not Data.characters.has(key):
		return
	character = key
	Events.character_changed.emit(key)
	var p := Data.player_cfg()   # 换角色后立刻重算血量上限
	max_hp = int(p.get("max_hp", 100)) + int(_char_stat("max_hp"))
	hp = max_hp
	Events.player_hp_changed.emit(hp, max_hp)
	Events.weapons_changed.emit(weapons)

# 角色自带的某条属性加成（读 characters.json，缺角色返回 0）
func _char_stat(stat: String) -> float:
	var st := (Data.character(character).get("stats", {})) as Dictionary
	return float(st.get(stat, 0.0))

# ---- 血量 ----
func take_damage(amount: int) -> void:
	# 护甲在所有伤害源的统一入口做扁平减免，强化不只是商店里的数字
	hp = maxi(0, hp - maxi(0, int(amount) - int(stat_value("armor"))))
	Events.player_hp_changed.emit(hp, max_hp)
	if hp <= 0:
		running = false
		Events.player_died.emit()

func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	Events.player_hp_changed.emit(hp, max_hp)

func heal_percent(pct: float) -> int:
	var before := hp
	heal(int(round(float(max_hp) * pct)))
	return hp - before

# ---- 金币 ----
func add_gold(amount: int) -> void:
	# gold_pct 在这里统一结算：所有进账都吃（波末奖励、爆金币）
	gold += int(round(float(amount) * (1.0 + stat_value("gold_pct"))))
	Events.gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	Events.gold_changed.emit(gold)
	return true

# ---- 波次 ----
func next_wave() -> void:
	wave += 1
	elapsed_in_wave = 0.0
	# 结算页用的"本波"计数在每波开局快照一次（shop 内的购买/花费不影响本波金币统计）
	wave_stats.snapshot(gold, kills)
	Events.wave_started.emit(wave)

func tick_wave(delta: float) -> void:
	elapsed_in_wave += delta
	wave_stats.tick(delta)
	Events.wave_progress.emit(elapsed_in_wave, float(Data.wave_cfg().get("length", 20)))

func wave_finished() -> bool:
	return elapsed_in_wave >= float(Data.wave_cfg().get("length", 20))

# 是否到了通关波。无尽段（越过最终波）不再算 —— 否则又会弹一次胜利页。
func is_last_wave() -> bool:
	var cfg := Data.wave_cfg()
	return Run.is_last_wave(wave, cfg) and not Run.is_endless_wave(wave, cfg)

# ---- 击杀 ----
func add_kill() -> void:
	kills += 1
	wave_stats.add_kill()

# ---- 经验 / 等级（击杀掉经验；升级奖励也在这里结算，爽点集中一处）----
func add_xp(amount: int) -> void:
	var cfg := Data.level_cfg()
	var r := Level.add(xp, amount, cfg)
	xp = int(r["xp"])
	var lv := int(r["level"])
	var bd := Level.breakdown(xp, cfg)
	Events.xp_changed.emit(lv, int(bd["into"]), int(bd["need"]), float(bd["pct"]))
	var gained := int(r["gained"])
	if gained > 0:
		_heal_on_level_up(gained)
		Events.level_up.emit(lv, gained)
# 升级奖励：回血 + 短暂狂暴（数值算法在 core/Level）
func _heal_on_level_up(gained: int) -> void:
	var r := Level.level_up_reward(gained, max_hp, Data.level_cfg())
	if int(r["heal"]) > 0:
		heal(int(r["heal"]))
	if float(r["frenzy"]) > 0.0:
		start_frenzy(float(r["frenzy"]))

# 当前等级明细 {level, into, need, pct}。要等级号直接读 ["level"]，不要另开一个方法。
func level_info() -> Dictionary:
	return Level.breakdown(xp, Data.level_cfg())

func run_score() -> int:
	return Run.score(kills, gold, wave)

# ---- 强化（属性加成）---- 加成都由 upgrades.json 的 "stat" 驱动，加新强化不用改代码
func buy_upgrade(key: String) -> void:
	if key.is_empty():
		return
	upgrades[key] = int(upgrades.get(key, 0)) + 1
	var up := Data.upgrade(key)
	var stat := str(up.get("stat", ""))
	var val := float(up.get("value", 0))
	match stat:
		"max_hp":
			max_hp += int(val)
			hp += int(val)
			Events.player_hp_changed.emit(hp, max_hp)
		"heal_now":   # ⚠️ stat 名必须与 upgrades.json 一致，写错会静默不生效
			heal(int(val))
		"wok_charges":   # 抬高颠勺充能上限，不影响已存数，但要同步展示
			wok["max_charges"] = int(wok.get("max_charges", 3)) + int(val)
			Events.wok_charges_changed.emit(Wok.charges_of(wok))
		_:
			pass
	Events.weapons_changed.emit(weapons)   # 伤害/攻速等加成靠武器重建生效

func stat_value(stat: String) -> float:
	var total := _char_stat(stat)
	for k in upgrades:
		var n := int(upgrades[k])
		for en in Inventory.stat_entries(Data.upgrade(k)):
			if str(en.get("stat", "")) == stat:
				total += float(en.get("value", 0)) * n
	# 套装 + 角色×武器羁绊：不并进来就只是 UI 上一行字（详见 core/StatBonus.gd）
	total += StatBonus.extra(weapons, Data.character(character), Data.weapons, Data.weapon_sets, stat)
	return total

# ---- 颠勺附带的护盾 / 狂暴 ---- 限时状态而非属性，挂 GameState 供 Player/PlayerWeapons 共读
var shield: int = 0              # 护盾：挨打先扣它，扣完才掉血
var frenzy_left: float = 0.0     # 狂暴剩余秒数（攻速 + 移速）

func tick_buff(delta: float) -> void:
	if frenzy_left > 0.0:
		frenzy_left = maxf(0.0, frenzy_left - delta)

func add_shield(amount: int) -> void:
	if amount <= 0:
		return
	shield += amount
	Events.shield_changed.emit(shield)

func start_frenzy(seconds: float) -> void:
	if seconds <= 0.0:
		return
	frenzy_left = maxf(frenzy_left, seconds)

func frenzy_mult() -> float:
	return float(Data.wok_cfg().get("frenzy_mult", 1.6)) if frenzy_left > 0.0 else 1.0
# ---- 锅气 Wok Heat（对 core/Wok.gd 的薄封装：改状态 + 同步公开字段 + 发信号）----
func _sync_wok() -> void:
	wok_heat = Wok.heat_of(wok)
	var t := Wok.tier(wok)
	if t != _wok_tier:
		_wok_tier = t
		Events.wok_tier_changed.emit(_wok_tier)
	var rd := Wok.ready(wok)
	if rd != _wok_ready_emitted:
		_wok_ready_emitted = rd
		Events.wok_ready_changed.emit(rd)
	# 充能数变化（银行/释放/上限提升）都通知 HUD：按钮常驻 + 显示 x{n}
	Events.wok_charges_changed.emit(Wok.charges_of(wok))
	Events.wok_heat_changed.emit(wok_heat, _wok_tier)

func add_wok(amount: float) -> void:
	Wok.add(wok, Data.wok_cfg(), amount)
	_sync_wok()

func decay_wok(delta: float) -> void:
	Wok.decay(wok, Data.wok_cfg(), delta)
	_sync_wok()

func cool_wok(amount: float) -> void:
	Wok.cool(wok, Data.wok_cfg(), amount)
	_sync_wok()

func wok_tier() -> int:
	return _wok_tier

func wok_ready() -> bool:
	return Wok.ready(wok)

func wok_fire_mult() -> float:
	return Wok.fire_mult(wok, Data.wok_cfg())

func wok_dmg_mult() -> float:
	return Wok.dmg_mult(wok, Data.wok_cfg())

func wok_charges() -> int:
	return Wok.charges_of(wok)

func toss_wok() -> bool:
	var ok := Wok.toss(wok, Data.wok_cfg())
	if ok:
		_sync_wok()
	return ok

# ---- 金币拾取（策略函数在 core/Pickup，这里只做"读属性 → 转发"）----
func pickup_magnet() -> float:
	return Pickup.player_magnet(Data.balance.get("pickup", {}) as Dictionary,
		stat_value("pickup_pct"), stat_value("fullauto") > 0.0, stat_value("autopick") > 0.0)

# 波末散落金币未手动拾取时，自动入袋但"丢失"的比例。
func gold_sweep_loss() -> float:
	return Pickup.sweep_loss(Data.balance.get("pickup", {}) as Dictionary,
		stat_value("pickup_pct"), stat_value("fullauto") > 0.0, stat_value("autopick") > 0.0)
