extends RefCounted

# 角色解锁的纯逻辑层（不碰文件，方便单测）。
# 规则写在 data/unlocks.json 的 characters 段 —— 调阶梯不用改一行战斗代码。
#
# 叶子条件：
#   {"type": "free"}                        开局就能玩（三条职业线各自的起点）
#   {"type": "clear_with", "need": "turnip"}  用某个角色通关过（用户要的主线）
#   {"type": "total_kills", "need": 800}    复用 core/Save.stat_of 的累计统计
#   {"any_of": [条件A, 条件B]}              满足任意一条即解锁（主线 OR 旁路）
#
# 旁路为什么必须有：调研里 Brotato 的解锁也是"主线给目标、累计给兜底"。
# 只有主线的话，玩家某一局怎么打都赢不了就被彻底卡死，只能删档重来。
#
# R2：本文件不得引用任何 autoload，判定要用的一切都从参数进来。

const SaveScript := preload("res://core/Save.gd")

# 某个角色的解锁规则（没配规则 = 不出现在选角页）
static func rule_of(unlocks: Dictionary, key: String) -> Dictionary:
	var rules: Dictionary = unlocks.get("characters", {}) as Dictionary
	return (rules.get(key, {}) as Dictionary).duplicate(true)

# 用 key 这个角色通关过几次（记在存档的 clears 字典里，由 Save.record_run 累加）
static func clears_of(save: Dictionary, key: String) -> int:
	var c: Dictionary = save.get("clears", {}) as Dictionary
	return maxi(0, int(c.get(key, 0)))

# 规则是否满足
static func meets(save: Dictionary, rule: Dictionary) -> bool:
	if rule.is_empty():
		return false
	if rule.has("any_of"):
		for sub in (rule.get("any_of", []) as Array):
			if meets(save, sub as Dictionary):
				return true
		return false
	var t := str(rule.get("type", ""))
	if t == "free":
		return true
	if t == "clear_with":
		return clears_of(save, str(rule.get("need", ""))) > 0
	return SaveScript.stat_of(save, t) >= int(rule.get("need", 0))

static func is_unlocked(save: Dictionary, unlocks: Dictionary, key: String) -> bool:
	return meets(save, rule_of(unlocks, key))

# 所有已解锁的角色（按传入顺序返回，方便 UI 保持固定顺序）
static func unlocked_keys(save: Dictionary, unlocks: Dictionary, all_keys: Array) -> Array:
	var out: Array = []
	for k in all_keys:
		if is_unlocked(save, unlocks, str(k)):
			out.append(str(k))
	return out

# 规则里用到的所有 clear_with 目标（给"指向不存在的角色 / 成环"做守门）
static func clear_deps(rule: Dictionary) -> Array:
	var out: Array = []
	if rule.has("any_of"):
		for sub in (rule.get("any_of", []) as Array):
			for d in clear_deps(sub as Dictionary):
				if not out.has(d):
					out.append(d)
		return out
	if str(rule.get("type", "")) == "clear_with":
		var n := str(rule.get("need", ""))
		if not n.is_empty():
			out.append(n)
	return out

# 是否至少有一条"不依赖通关"的支路（防卡死：靠累计也能解锁）
static func has_side_branch(rule: Dictionary) -> bool:
	if rule.has("any_of"):
		for sub in (rule.get("any_of", []) as Array):
			if has_side_branch(sub as Dictionary):
				return true
		return false
	var t := str(rule.get("type", ""))
	return t != "clear_with"

# 还差多少：挑最接近达成的那条支路给 UI 显示
# 返回 {type, need, have, left, char}；left=0 即已达成。无规则返回 {}
static func remaining(save: Dictionary, rule: Dictionary) -> Dictionary:
	if rule.is_empty():
		return {}
	if rule.has("any_of"):
		var best: Dictionary = {}
		for sub in (rule.get("any_of", []) as Array):
			var s := remaining(save, sub as Dictionary)
			if best.is_empty() or int(s.get("left", 0)) < int(best.get("left", 0)):
				best = s
		return best
	var t := str(rule.get("type", ""))
	if t == "free":
		return {"type": t, "need": 0, "have": 0, "left": 0, "char": ""}
	if t == "clear_with":
		var key := str(rule.get("need", ""))
		var c := mini(clears_of(save, key), 1)
		return {"type": t, "need": 1, "have": c, "left": 1 - c, "char": key}
	var need := int(rule.get("need", 0))
	var have := SaveScript.stat_of(save, t)
	return {"type": t, "need": need, "have": have, "left": maxi(0, need - have), "char": ""}

# 下一个"最接近解锁"的角色（标题页给玩家一个具体目标）
# 返回 {key, type, need, have, left, char} 或空
static func next_character(save: Dictionary, unlocks: Dictionary, all_keys: Array) -> Dictionary:
	var rules: Dictionary = unlocks.get("characters", {}) as Dictionary
	var best: Dictionary = {}
	var best_left := 0
	for k in all_keys:
		var key := str(k)
		if not rules.has(key) or is_unlocked(save, unlocks, key):
			continue
		var rem := remaining(save, rule_of(unlocks, key))
		if rem.is_empty():
			continue
		var left := int(rem.get("left", 0))
		if best.is_empty() or left < best_left:
			best_left = left
			best = rem.duplicate()
			best["key"] = key
	return best
