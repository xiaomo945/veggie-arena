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

# ---- 关系树 / 排序：把规则表翻成"谁解开谁"的形状 ----
# 用途有两个：选角页排序（免费在前、锁着的在后），以及关系树那张图。
# 全是纯函数，规则一变图自动跟着变，不需要任何地方维护"路线表"。

# 阶梯深度：free=0；靠别人通关解锁 = 前置角色的深度 +1（取最深的那条）
static func depth_of(unlocks: Dictionary, key: String) -> int:
	return _depth(unlocks, key, [])

# 主线边：parent → [children]，意思是"用 parent 通关过就能玩 child"
static func edges(unlocks: Dictionary, all_keys: Array) -> Dictionary:
	var out: Dictionary = {}
	for k in all_keys:
		var key := str(k)
		for dep in clear_deps(rule_of(unlocks, key)):
			var p := str(dep)
			if not out.has(p):
				out[p] = []
			var arr: Array = out[p]
			if not arr.has(key):
				arr.append(key)
	return out

# 一条条主线（每条都是一个数组，从深度 0 的根拉到最深的后代）。
# DFS 拉直：一个父角色开出多个分支时，分支角色排在父角色后面依次展开。
static func lanes(unlocks: Dictionary, all_keys: Array) -> Array:
	var eg := edges(unlocks, all_keys)
	var roots: Array = []
	for k in all_keys:
		var key := str(k)
		if depth_of(unlocks, key) == 0 and not (eg.get(key, []) as Array).is_empty():
			roots.append(key)
	roots.sort()
	var out: Array = []
	var used: Array = []
	for root in roots:
		var lane: Array = []
		_collect(eg, str(root), lane, used)
		out.append(lane)
	return out

# 不挂在任何主线上的角色：只能靠累计数据解锁（没有 clear_with）
static func standalone(unlocks: Dictionary, all_keys: Array) -> Array:
	var eg := edges(unlocks, all_keys)
	var out: Array = []
	for k in all_keys:
		var key := str(k)
		var has_parent := false
		for p in eg:
			if (eg[p] as Array).has(key):
				has_parent = true
				break
		if not has_parent and (eg.get(key, []) as Array).is_empty():
			out.append(key)
	out.sort()
	return out

# 规则里的主线条件本体（轻视累计支路）：关系树上要画的就是"通关前置"这一条
static func first_clear_with(rule: Dictionary) -> Dictionary:
	if rule.has("any_of"):
		for sub in (rule.get("any_of", []) as Array):
			var hit := first_clear_with(sub as Dictionary)
			if not hit.is_empty():
				return hit
		return {}
	return rule.duplicate(true) if str(rule.get("type", "")) == "clear_with" else {}

# 选角页顺序：**能玩的一律在前**（免费最靠前，其次按阶梯深浅），锁着的一律在后。
# 玩家诉求的原话是"免费角色要放在最前面，需要解锁的放在后面"。
# 组内再按"所属职业线 → 阶梯深浅"聚拢，于是选角页的排布和关系树的排布是同一套顺序：
# 玩家在树上看到的那一列，回头在卡片网格里还能认出来。
static func order(save: Dictionary, unlocks: Dictionary, all_keys: Array) -> Array:
	var lane_of: Dictionary = {}
	var li := 0
	for lane in lanes(unlocks, all_keys):
		for k in lane:
			lane_of[str(k)] = li
		li += 1
	var packed: Array = []
	for k in all_keys:
		var key := str(k)
		packed.append({
			"k": key,
			"d": depth_of(unlocks, key),
			"l": int(lane_of.get(key, li)),
			"open": is_unlocked(save, unlocks, key),
		})
	packed.sort_custom(_cmp_order)
	var out: Array = []
	for e in packed:
		out.append(str((e as Dictionary).get("k", "")))
	return out

static func _cmp_order(a, b) -> bool:
	var A := a as Dictionary
	var B := b as Dictionary
	var ao := bool(A.get("open", false))
	var bo := bool(B.get("open", false))
	if ao != bo:
		return ao
	var al := int(A.get("l", 0))
	var bl := int(B.get("l", 0))
	if al != bl:
		return al < bl
	var ad := int(A.get("d", 0))
	var bd := int(B.get("d", 0))
	if ad != bd:
		return ad < bd
	return str(A.get("k", "")) < str(B.get("k", ""))

static func _depth(unlocks: Dictionary, key: String, seen: Array) -> int:
	if seen.has(key):
		return 0          # 成环时断链（真正的不成环由单测把关，这里只求不崩）
	var deps := clear_deps(rule_of(unlocks, key))
	if deps.is_empty():
		return 0
	var deepest := 0
	var next_seen: Array = seen.duplicate()
	next_seen.append(key)
	for d in deps:
		var dd := _depth(unlocks, str(d), next_seen) + 1
		if dd > deepest:
			deepest = dd
	return deepest

static func _collect(eg: Dictionary, key: String, lane: Array, used: Array) -> void:
	if lane.has(key) or used.has(key):
		return
	lane.append(key)
	used.append(key)
	var kids: Array = (eg.get(key, []) as Array).duplicate()
	kids.sort()
	for c in kids:
		_collect(eg, str(c), lane, used)
