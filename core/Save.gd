extends RefCounted

# 存档的纯逻辑层：默认值 / 清洗 / 记录一局 / 解锁判定。
#
# 这一层不碰文件系统（读写由 autoload/SaveMgr.gd 负责），所以可以单测。
#
# 存档设计的三条原则：
#   1) **永不信任磁盘**：sanitize() 必须能把手改坏/旧版本的存档修回可用状态，
#      宁可丢进度也不能让游戏起不来（网页版尤其致命，玩家只会关掉页面）
#   2) 只存"统计"不存"局内状态":死了就是死了，不做中途续关，避免存档变大变脆
#   3) 解锁条件写在 data/unlocks.json，加新武器不用改代码

const VERSION := 1

# 存档字段与其默认值（sanitize 按这张表补齐/修正类型）
const FIELDS := {
	"version": 0,
	"best_score": 0,
	"best_wave": 0,
	"total_kills": 0,
	"total_gold": 0,
	"runs": 0,
	"wins": 0,
	"character": "",
	"run_mode": "short",
}

# 单局时长三档（与 balance.json 的 wave.run_modes 对齐）。
# 存档里存的档位名若不在名单里（手改过 / 老档），sanitize 会退回 short。
const RUN_MODES := ["short", "classic", "endless"]

const UNLOCK_TYPES := ["total_kills", "total_gold", "best_wave", "wins"]

static func defaults() -> Dictionary:
	var s: Dictionary = FIELDS.duplicate()
	s["version"] = VERSION
	return s

# 清洗：缺字段补默认、类型不对修正、版本号不一致直接回默认（旧档不兼容就重开）
static func sanitize(raw) -> Dictionary:
	var s := defaults()
	if not (raw is Dictionary):
		return s
	var d: Dictionary = raw
	if int(d.get("version", 0)) != VERSION:
		return s
	for k in FIELDS:
		if not d.has(k):
			continue
		var v = d[k]
		if FIELDS[k] is int:
			# 统计值不允许为负：手改过的存档里出现 -5 会让"最佳分数"显示成负数，
			# 也会让解锁判定永远达不成。一律钳到 >= 0
			s[k] = maxi(0, int(v))
		elif FIELDS[k] is String:
			s[k] = str(v)
	if not RUN_MODES.has(str(s.get("run_mode", "short"))):
		s["run_mode"] = "short"
	return s

# 某个统计值（给解锁判定用）
static func stat_of(save: Dictionary, stat: String) -> int:
	if stat == "wins":
		return int(save.get("wins", 0))
	if stat == "runs":
		return int(save.get("runs", 0))
	if stat == "best_wave":
		return int(save.get("best_wave", 0))
	if stat == "total_kills":
		return int(save.get("total_kills", 0))
	if stat == "total_gold":
		return int(save.get("total_gold", 0))
	return 0

# 记录一局的结果（就地修改并返回同一字典）
# result: {wave, kills, gold, score, won}
# 只累加统计 + 刷新最佳，不做任何"局内"状态的保存
static func record_run(save: Dictionary, result: Dictionary) -> Dictionary:
	save["runs"] = int(save.get("runs", 0)) + 1
	save["total_kills"] = int(save.get("total_kills", 0)) + int(result.get("kills", 0))
	save["total_gold"] = int(save.get("total_gold", 0)) + int(result.get("gold", 0))
	var wave := int(result.get("wave", 0))
	if wave > int(save.get("best_wave", 0)):
		save["best_wave"] = wave
	var score := int(result.get("score", 0))
	if score > int(save.get("best_score", 0)):
		save["best_score"] = score
	if bool(result.get("won", false)):
		save["wins"] = int(save.get("wins", 0)) + 1
	# 记住上次用的角色，标题页默认选中它
	var c := str(result.get("character", ""))
	if not c.is_empty():
		save["character"] = c
	return save

# 无尽段续命（通关后继续、最终死在更高波次）：只刷新"最佳"统计 —— 波次与分数。
# 不再累加 runs/击杀/金币，也不再重复加 wins：那些在第 total 波通关时已经记过了，
# 否则一局会被算成两局。
static func record_endless(save: Dictionary, result: Dictionary) -> Dictionary:
	var wave := int(result.get("wave", 0))
	if wave > int(save.get("best_wave", 0)):
		save["best_wave"] = wave
	var score := int(result.get("score", 0))
	if score > int(save.get("best_score", 0)):
		save["best_score"] = score
	return save

# 当前已解锁的武器列表 = 初始武器 + 达成条件的武器
# unlocks 来自 data/unlocks.json
static func unlocked_weapons(save: Dictionary, unlocks: Dictionary) -> Array:
	var out: Array = []
	var start: Array = unlocks.get("start_weapons", []) as Array
	for k in start:
		if not out.has(str(k)):
			out.append(str(k))
	var rules: Dictionary = unlocks.get("weapons", {}) as Dictionary
	for key in rules:
		var rule: Dictionary = rules[key] as Dictionary
		var t := str(rule.get("type", ""))
		var need := int(rule.get("need", 0))
		if stat_of(save, t) >= need:
			if not out.has(str(key)):
				out.append(str(key))
	return out

# 新增解锁（用于弹提示）：比较两次解锁列表的差集
static func newly_unlocked(before: Array, after: Array) -> Array:
	var out: Array = []
	for k in after:
		if not before.has(k):
			out.append(k)
	return out

# 下一条还没达成的解锁（标题页显示"再杀 42 只解锁菜刀"，给玩家目标）
# 返回 {"key":.., "type":.., "need":.., "have":.., "left":..} 或空
static func next_unlock(save: Dictionary, unlocks: Dictionary) -> Dictionary:
	var rules: Dictionary = unlocks.get("weapons", {}) as Dictionary
	var have := unlocked_weapons(save, unlocks)
	var best: Dictionary = {}
	var best_left := 0
	for key in rules:
		if have.has(str(key)):
			continue
		var rule: Dictionary = rules[key] as Dictionary
		var t := str(rule.get("type", ""))
		var need := int(rule.get("need", 0))
		var cur := stat_of(save, t)
		var left := maxi(0, need - cur)
		# 挑"最接近达成"的那条，玩家看了最想再来一局
		if best.is_empty() or left < best_left:
			best_left = left
			best = {"key": str(key), "type": t, "need": need,
				"have": cur, "left": left,
				"en": str(rule.get("en", ""))}
	return best

# 解锁条件文案用的统计名（出海用英文）
static func stat_label_for(t: String) -> String:
	return stat_label(t)

static func stat_label(t: String) -> String:
	match t:
		"total_kills": return "kills"
		"total_gold": return "gold"
		"best_wave": return "wave"
		"wins": return "wins"
	return t
