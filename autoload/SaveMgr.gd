extends Node

# 存档管理（autoload）：把 core/Save.gd 的纯逻辑落到 user:// 上。
#
# ⚠️ 网页版（Web export）里 user:// 走 IndexedDB，写入是异步且可能失败
#    （无痕模式/存储被禁）。所以所有读写都包在 try 里：存不了就当没存档，
#    游戏照常能玩 —— 绝不因为存档问题让游戏起不来。
#
# 解锁提示在这里发：一局结束后统计刷新，新达成的解锁逐个 emit Events.unlocked。

const Save := preload("res://core/Save.gd")
const Unlocks := preload("res://core/Unlocks.gd")

const PATH := "user://turnip_save.json"

var data: Dictionary = {}
var _last_unlocked: Array = []

func _ready() -> void:
	load_save()

func load_save() -> void:
	data = Save.sanitize(_read())
	_last_unlocked = unlocked_weapons()
	print("SaveMgr: 载入存档 runs=%d best=%d 解锁武器=%d" % [
		int(data.get("runs", 0)), int(data.get("best_score", 0)), _last_unlocked.size()])

func _read():
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_warning("SaveMgr: 存档解析失败，按新档处理")
		return {}
	return j.get_data()

func flush() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveMgr: 存档写不了（无痕模式或存储被禁），本次进度不保存")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

# 一局结束（阵亡或通关）时调用
func record_run(wave: int, kills: int, gold: int, score: int, won: bool) -> void:
	var before := unlocked_weapons()
	var before_chars := unlocked_characters()
	Save.record_run(data, {
		"wave": wave, "kills": kills, "gold": gold,
		"score": score, "won": won, "character": GameState.character,
	})
	var after := unlocked_weapons()
	var after_chars := unlocked_characters()
	flush()
	# 新解锁的逐个通知（HUD/标题页弹提示）
	for k in Save.newly_unlocked(before, after):
		Events.unlocked.emit(str(k))
	for c in Save.newly_unlocked(before_chars, after_chars):
		# 新角色 = 新的玩法路线开了，比一把新武器更值得单独提示
		Events.character_unlocked.emit(str(c))
	_last_unlocked = after

# 无尽段续命后的收尾：只刷新最佳波次/分数（不重复计入 runs / 击杀 / 金币）
func record_endless(wave: int, score: int) -> void:
	Save.record_endless(data, {"wave": wave, "score": score})
	flush()

func unlocked_weapons() -> Array:
	return Save.unlocked_weapons(data, Data.unlocks_cfg())

# ---- 角色解锁（E2/E3）：阶梯写在 data/unlocks.json 的 characters 段 ----
# 判定本身在 core/Unlocks.gd（纯函数），这里只负责喂数据 + 发信号
func unlocked_characters() -> Array:
	return Unlocks.unlocked_keys(data, Data.unlocks_cfg(), Data.characters.keys())

func is_character_unlocked(key: String) -> bool:
	return Unlocks.is_unlocked(data, Data.unlocks_cfg(), key)

# 还差多少（UI 显示"还差 3 次击杀"这类）—— left=0 表示已达成
func character_remaining(key: String) -> Dictionary:
	return Unlocks.remaining(data, Unlocks.rule_of(Data.unlocks_cfg(), key))

# 标题页的目标钩子："下一个能解锁的角色是谁、还差多少"
func next_character_unlock() -> Dictionary:
	return Unlocks.next_character(data, Data.unlocks_cfg(), Data.characters.keys())

# 选角页的角色顺序：**能玩的一律在前**（免费最靠前），锁着的一律在后。
# 玩家诉求：免费角色放最前面、需要解锁的放后面。
func character_order() -> Array:
	return Unlocks.order(data, Data.unlocks_cfg(), Data.characters.keys())

func is_weapon_unlocked(key: String) -> bool:
	return unlocked_weapons().has(key)

func next_unlock() -> Dictionary:
	return Save.next_unlock(data, Data.unlocks_cfg())

func best_score() -> int:
	return int(data.get("best_score", 0))

func best_wave() -> int:
	return int(data.get("best_wave", 0))

func total_runs() -> int:
	return int(data.get("runs", 0))

func last_character() -> String:
	return str(data.get("character", ""))

# 上次选的单局时长档（short / classic / endless）。玩过一次之后默认沿用，
# 免得每次进游戏都要重新选 —— 但新档默认 short（一局约 11 分钟）。
func run_mode() -> String:
	return str(data.get("run_mode", "short"))

func set_run_mode(mode: String) -> void:
	if not Save.RUN_MODES.has(mode):
		return
	data["run_mode"] = mode
	flush()

# 清档（调试/隐私用）
func wipe() -> void:
	data = Save.defaults()
	_last_unlocked = unlocked_weapons()
	flush()
