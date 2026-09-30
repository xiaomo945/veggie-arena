extends Node

# 只读数据表访问层
# 所有平衡数值都来自 data/*.json —— 改数值只改 JSON，永远不改代码。
# 注意：--headless --script 模式下 autoload 不会自动实例化，
#       测试里需要 Data.new() 后显式调用 load_all()。

var balance: Dictionary = {}
var weapons: Dictionary = {}
var enemies: Dictionary = {}
var upgrades: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	balance = _read("res://data/balance.json")
	weapons = _read("res://data/weapons.json")
	enemies = _read("res://data/enemies.json")
	upgrades = _read("res://data/upgrades.json")

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Data: 读不到 " + path)
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_error("Data: JSON 解析失败 " + path + " -> " + j.get_error_message())
		return {}
	if j.data is Dictionary:
		return j.data
	push_error("Data: 顶层不是对象 " + path)
	return {}

# ---- 便捷取值（缺键时给默认值，避免崩溃） ----
func arena() -> Dictionary:
	return balance.get("arena", {})

func player_cfg() -> Dictionary:
	return balance.get("player", {})

func wave_cfg() -> Dictionary:
	return balance.get("wave", {})

func spawn_cfg() -> Dictionary:
	return balance.get("spawn", {})

func shop_cfg() -> Dictionary:
	return balance.get("shop", {})

func combat_cfg() -> Dictionary:
	return balance.get("combat", {})

func feel_cfg() -> Dictionary:
	return balance.get("feel", {})

func wok_cfg() -> Dictionary:
	return balance.get("wok", {})

func bullet_cfg() -> Dictionary:
	return balance.get("bullet", {})

func dash_cfg() -> Dictionary:
	return balance.get("dash", {})

func pickup_cfg() -> Dictionary:
	return balance.get("pickup", {})

func weapon(key: String) -> Dictionary:
	return weapons.get(key, {})

func enemy(key: String) -> Dictionary:
	return enemies.get(key, {})

func upgrade(key: String) -> Dictionary:
	return upgrades.get(key, {})

func weapon_keys() -> Array:
	return weapons.keys()

func upgrade_keys() -> Array:
	return upgrades.keys()
