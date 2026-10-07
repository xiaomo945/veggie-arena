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
var weapon_sets: Dictionary = {}   # Q1 武器套装：data/weapon_sets.json
var _landscape := false     # 横屏标志：宽屏窗口下由 ScreenMode.apply() 置 true（竖屏默认 false）

func _ready() -> void:
	load_all()

func load_all() -> void:
	balance = _read("res://data/balance.json")
	run_mode = str(balance.get("wave", {}).get("default_run_mode", "short"))
	_wave_eff = {}
	weapons = _read("res://data/weapons.json")
	enemies = _read("res://data/enemies.json")
	upgrades = _read("res://data/upgrades.json")
	characters = _read("res://data/characters.json")
	_tag_characters()
	unlocks = _read("res://data/unlocks.json")
	skills = _read("res://data/skills.json")
	weapon_sets = _read("res://data/weapon_sets.json")

# 给每个角色条目写回它自己的 key（_key）。
# ⚠️ 真踩过的坑：SkillDef.active_skill 靠 char_entry._key 判断"这是哪个角色"，
#    而 characters.json 的 key 是字典的【键】、不在条目内部 —— 于是 _key 永远是空串，
#    技能变体（角色 + 凑够武器件数 → 技能变强）在实战里一次都没触发过。
#    单元测试绕过这条路径（直接调 resolve 传字符串 key），所以全绿也没人发现。
#    在这里一次性写回，调用方不用每个都记着传 key。
func _tag_characters() -> void:
	for k in characters:
		var e = characters[k]
		if e is Dictionary:
			(e as Dictionary)["_key"] = str(k)

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

# ---------------------------------------------------------------------
# 单局时长三档（短局 12 波 / 经典 20 波 / 无尽）
#
# 为什么把模式放在 Data 而不是 GameState：全项目读"总波数"的地方只有
# `wave_cfg()["total"]` 这一个入口（HUD 进度条、WaveDirector 波次钳位、
# Run.is_last_wave 通关判定、WaveSkip 调试滑杆）。在这里把 total 换成当前档的值，
# 上面那些调用点一行都不用改 —— 改一处，全链路跟着走。
#
# 缓存的原因：wave_cfg() 每帧都被调（GameState 算波次进度），不能每次 duplicate。
var run_mode := "short"
var _wave_eff: Dictionary = {}

func run_modes() -> Dictionary:
	return balance.get("wave", {}).get("run_modes", {})

func set_run_mode(mode: String) -> void:
	if not run_modes().has(mode):
		return
	run_mode = mode
	_wave_eff = {}

# 当前档的总波数（0 = 永不通关）；配表里没这个档时退回 wave.total
func run_total() -> int:
	var m: Dictionary = run_modes().get(run_mode, {})
	if m.is_empty():
		return int(balance.get("wave", {}).get("total", 20))
	return int(m.get("total", 20))

func wave_cfg() -> Dictionary:
	if _wave_eff.is_empty():
		_wave_eff = balance.get("wave", {}).duplicate()
		_wave_eff["total"] = run_total()
	return _wave_eff

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

func level_cfg() -> Dictionary:
	return balance.get("level", {})

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

# 武器套装表（Q1）。键 "_doc" 是说明，取用时跳过。
func weapon_sets_cfg() -> Dictionary:
	return weapon_sets

func weapon_set(tag: String) -> Dictionary:
	return weapon_sets.get(tag, {})

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
