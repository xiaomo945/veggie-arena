extends Node

# 当前这一局的状态。重开时调 reset()，不新建节点。
# 依赖 Data，但不依赖任何渲染节点 —— 便于 headless 测试。

var wave: int = 1
var gold: int = 0
var hp: int = 100
var max_hp: int = 100
var kills: int = 0
var elapsed_in_wave: float = 0.0
var running: bool = false
var paused: bool = false     # 暂停菜单是否打开（Joystick 据此停止接管触摸，避免暂停时还在走位）
var won: bool = false        # 本局是不是打通关了（区分"阵亡"与"通关"，结算页/自测报告都要用）

# 当前选择的角色（data/characters.json 的键）。角色自带属性加成，与强化叠加。
var character: String = "turnip"

# 装备：元素形如 {"key": "pistol", "lv": 1}
# ⚠️ 字段名必须是 "lv"（core/Inventory 里就用这个），写成 "level" 会让合成静默失效
var weapons: Array = []
# 强化：{"key": 数量}
var upgrades: Dictionary = {}

# ---- 锅气 Wok Heat（招牌机制）----
# 0..max 的"火候"值。击杀/命中攒，停手衰减，挨打掉。
# 档位：0 微温 / 1 翻炒(加攻速) / 2 爆炒(加攻速+伤害)。
# 满锅气可"颠勺"：全屏击退+重伤，然后火候回落。
# 纯逻辑在 core/Wok.gd（可单测），这里只持有状态 + 发信号。
const Wok := preload("res://core/Wok.gd")
const Run := preload("res://core/Run.gd")
var wok: Dictionary = {}
var wok_heat: float = 0.0
var _wok_tier: int = 0
var _wok_ready_emitted := false
# 颠勺按钮在屏幕上的可点区域（HUD 写入，Joystick 读取以避让移动）
var wok_toss_rect := Rect2(0, 0, 0, 0)
# 冲刺按钮占的屏幕区域（HUD 写入，Joystick 读取后避让：戳这块只冲刺、不走位）
var dash_rect := Rect2(0, 0, 0, 0)
# 暂停按钮占的屏幕区域（HUD 写入，Joystick 读取后避让：戳这块只暂停、不走位）
var pause_rect := Rect2(0, 0, 0, 0)

func _ready() -> void:
	reset()
	# ⚠️ reset() 会把 running 置 true（那是给"正式开跑"用的）。
	#    启动时必须停下：否则标题页还没点，背后就已经在刷怪开打了。
	running = false

func reset() -> void:
	var p := Data.player_cfg()
	# 角色自带的生命加成在这里并入上限（其它属性走 stat_value）
	max_hp = int(p.get("max_hp", 100)) + int(_char_stat("max_hp"))
	hp = max_hp
	wave = 1
	gold = 0
	kills = 0
	elapsed_in_wave = 0.0
	running = true
	won = false
	weapons = []
	upgrades = {}
	# 锅气参数从 balance.json 读，避免数值写死在代码里
	wok = Wok.make(Data.wok_cfg())
	wok_heat = 0.0
	_wok_tier = 0
	_wok_ready_emitted = false
	# 开局自带手枪 + 冲锋枪：双武器起步，前期清怪有手感、锅气攒得快
	weapons.append({"key": "pistol", "lv": 1})
	weapons.append({"key": "smg", "lv": 1})

# ---- 角色 ----
func set_character(key: String) -> void:
	if key.is_empty() or not Data.characters.has(key):
		return
	character = key
	Events.character_changed.emit(key)
	# 立刻重算一局状态：标题页换角色后，开局的血量上限要跟着变
	var p := Data.player_cfg()
	max_hp = int(p.get("max_hp", 100)) + int(_char_stat("max_hp"))
	hp = max_hp
	Events.player_hp_changed.emit(hp, max_hp)
	Events.weapons_changed.emit(weapons)

# 角色自带的某条属性加成（读 characters.json，缺角色返回 0）
func _char_stat(stat: String) -> float:
	var c := Data.character(character)
	var st: Dictionary = c.get("stats", {}) as Dictionary
	return float(st.get(stat, 0.0))

# ---- 血量 ----
func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
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
	gold += amount
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
	Events.wave_started.emit(wave)

func tick_wave(delta: float) -> void:
	elapsed_in_wave += delta
	Events.wave_progress.emit(elapsed_in_wave, float(Data.wave_cfg().get("length", 20)))

func wave_finished() -> bool:
	return elapsed_in_wave >= float(Data.wave_cfg().get("length", 20))

# 是否到了通关波（撑过这一波即胜利）。波数阈值走 balance.json 的 wave.total。
func is_last_wave() -> bool:
	return Run.is_last_wave(wave, Data.wave_cfg())

# ---- 击杀 ----
func add_kill() -> void:
	kills += 1

# 通关/阵亡的统一结算分（与死亡页同口径）
func run_score() -> int:
	return Run.score(kills, gold, wave)

# ---- 强化（属性加成）----
# 所有加成都由 upgrades.json 的 "stat" 字段驱动，加新强化不用改代码
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
		# ⚠️ stat 名必须和 upgrades.json 一致（是 heal_now 不是 heal），
		#    之前写 "heal" 导致买回血强化时静默不生效
		"heal_now":
			heal(int(val))
		_:
			pass
	# 伤害/攻速等加成通过武器重建生效
	Events.weapons_changed.emit(weapons)

# 某个属性的总加成值（如 dmg_pct、speed_pct）
func stat_value(stat: String) -> float:
	var total := _char_stat(stat)
	for k in upgrades:
		var up := Data.upgrade(k)
		if str(up.get("stat", "")) == stat:
			total += float(up.get("value", 0)) * int(upgrades[k])
	return total

# ---- 锅气 Wok Heat ----
# 下面这些方法都是对 core/Wok.gd 纯逻辑的薄封装：改状态 + 同步公开字段 + 发信号。
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

func toss_wok() -> bool:
	var ok := Wok.toss(wok, Data.wok_cfg())
	if ok:
		_sync_wok()
	return ok
