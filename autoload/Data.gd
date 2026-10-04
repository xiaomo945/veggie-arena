extends Node

# 只读数据表访问层
# 所有平衡数值都来自 data/*.json —— 改数值只改 JSON，永远不改代码。
# 注意：--headless --script 模式下 autoload 不会自动实例化，
#       测试里需要 Data.new() 后显式调用 load_all()。

var balance: Dictionary = {}
var weapons: Dictionary = {}
var enemies: Dictionary = {}
var upgrades: Dictionary = {}
var characters: Dictionary = {}
var unlocks: Dictionary = {}
var skills: Dictionary = {}
var _landscape := false     # 横屏标志：宽屏窗口下由 ScreenMode.apply() 置 true（竖屏默认 false）

func _ready() -> void:
	load_all()

func load_all() -> void:
	balance = _read("res://data/balance.json")
	weapons = _read("res://data/weapons.json")
	enemies = _read("res://data/enemies.json")
	upgrades = _read("res://data/upgrades.json")
	characters = _read("res://data/characters.json")
	unlocks = _read("res://data/unlocks.json")
	skills = _read("res://data/skills.json")

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

# 横屏标志读写（由 Orientation 在启动时设定，全局只读查询）
func set_landscape(v: bool) -> void:
	_landscape = v

func is_landscape() -> bool:
	return _landscape

func arena() -> Dictionary:
	var a: Dictionary = balance.get("arena", {})
	# 横屏：用 arena.landscape 覆盖尺寸 / 中心（竞技场 1620x1080，居中于原点），
	# 让相机在更宽的视口里仍有多余空间平移；竖屏走原值，零改动。
	if _landscape and a.has("landscape"):
		var l: Dictionary = a["landscape"]
		return {
			"x": float(l.get("x", a.get("x", 0))),
			"y": float(l.get("y", a.get("y", 0))),
			"w": float(l.get("w", a.get("w", 540))),
			"h": float(l.get("h", a.get("h", 900))),
		}
	return {
		"x": float(a.get("x", 0)),
		"y": float(a.get("y", 0)),
		"w": float(a.get("w", 540)),
		"h": float(a.get("h", 900)),
	}

func player_cfg() -> Dictionary:
	return balance.get("player", {})

func wave_cfg() -> Dictionary:
	return balance.get("wave", {})

func spawn_cfg() -> Dictionary:
	return balance.get("spawn", {})

# 终局 Boss（第 total 波专属）的属性倍率
func final_boss_cfg() -> Dictionary:
	return balance.get("final_boss", {})

# 无尽段（通关后继续）的成长参数
func endless_cfg() -> Dictionary:
	return balance.get("endless", {})

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

func unlocks_cfg() -> Dictionary:
	return unlocks

func character(key: String) -> Dictionary:
	return characters.get(key, {})

func enemy(key: String) -> Dictionary:
	return enemies.get(key, {})

func upgrade(key: String) -> Dictionary:
	return upgrades.get(key, {})

func weapon_keys() -> Array:
	return weapons.keys()

func upgrade_keys() -> Array:
	return upgrades.keys()

# 主动技能表：返回 data/skills.json 里的 "skills" 数组（每项含 id/cooldown/radius/效果）
func skills_cfg() -> Array:
	return skills.get("skills", [])

# 手动攻击键（右下角大按钮）释放哪个技能 —— "最常用的那一个"。
# 读 skills.json 的 "primary"；没配就退回第一个技能，永远有值。
func skills_primary() -> String:
	var p := str(skills.get("primary", ""))
	if p != "":
		return p
	var arr := skills_cfg()
	if arr.size() > 0:
		return str((arr[0] as Dictionary).get("id", ""))
	return ""
