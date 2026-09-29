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

# 装备：元素形如 {"key": "pistol", "lv": 1}
# ⚠️ 字段名必须是 "lv"（core/Inventory 里就用这个），写成 "level" 会让合成静默失效
var weapons: Array = []
# 强化：{"key": 数量}
var upgrades: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	var p := Data.player_cfg()
	max_hp = int(p.get("max_hp", 100))
	hp = max_hp
	wave = 1
	gold = 0
	kills = 0
	elapsed_in_wave = 0.0
	running = true
	weapons = []
	upgrades = {}
	# 开局自带一把手枪（否则一进场没武器，玩家会以为坏了）
	weapons.append({"key": "pistol", "lv": 1})

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

# ---- 击杀 ----
func add_kill() -> void:
	kills += 1

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
		"heal":
			heal(int(val))
		_:
			pass
	# 伤害/攻速等加成通过武器重建生效
	Events.weapons_changed.emit(weapons)

# 某个属性的总加成值（如 dmg_pct、speed_pct）
func stat_value(stat: String) -> float:
	var total := 0.0
	for k in upgrades:
		var up := Data.upgrade(k)
		if str(up.get("stat", "")) == stat:
			total += float(up.get("value", 0)) * int(upgrades[k])
	return total
