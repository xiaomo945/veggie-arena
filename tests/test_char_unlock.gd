extends RefCounted

# 角色解锁阶梯（E1/E2/E3）的守门测试。
# 这里盯的是"以后加角色时最容易踩的坑"：
#   1) 免费起点没了 → 新玩家开局没得选
#   2) clear_with 指向不存在的角色 → 那个角色永远解不开，且没人会报错
#   3) clear_with 成环（A 要 B、B 又要 A）→ 整条线死锁
#   4) 某个角色只有主线条件 → 这一局打不赢就被彻底卡死（Brotato 的解法是留旁路）
#   5) 角色解锁了但它的本命武器不在解锁表里 → 拿到人却配不齐 build
# 另外顺手把所有没写解锁规则的武器拦下来 —— 没规则 = 永远不会进商店 = 死内容。

const Save := preload("res://core/Save.gd")
const Unlocks := preload("res://core/Unlocks.gd")

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)

func run(data) -> Dictionary:
	var unlocks: Dictionary = data.unlocks_cfg()
	var rules: Dictionary = unlocks.get("characters", {}) as Dictionary
	var keys: Array = data.characters.keys()
	var save0 := Save.defaults()

	# ---- 1) 免费起点：至少 3 个（三条职业线各一个）----
	var free_list := Unlocks.unlocked_keys(save0, unlocks, keys)
	chk(free_list.size() >= 3, "新档可玩角色 = %d（至少 3，三条线各一个）：%s" % [
		free_list.size(), ", ".join(free_list)])

	# ---- 2) 每个角色都得有规则：没规则等于在选角页消失 ----
	for k in keys:
		chk(rules.has(str(k)), "%s 配了解锁规则" % k)

	# ---- 3) clear_with 目标必须存在 ----
	for k in keys:
		for dep in Unlocks.clear_deps(Unlocks.rule_of(unlocks, str(k))):
			chk(data.characters.has(dep), "%s 的前置角色 %s 真实存在" % [k, dep])

	# ---- 4) 不能成环：从每个角色的依赖链往下走，遇不到自己 ----
	for k in keys:
		chk(not _cycle_hit(unlocks, str(k), str(k), []), "%s 的依赖链没有闭环" % k)

	# ---- 5) 每个非免费角色都必须有一条不依赖通关的支路（防卡死）----
	for k in keys:
		var rule := Unlocks.rule_of(unlocks, str(k))
		if str(rule.get("type", "")) == "free":
			continue
		chk(Unlocks.has_side_branch(rule), "%s 有旁路条件（打不赢也能攒出来）" % k)

	# ---- 6) 可达性：从免费角色出发 BFS，所有角色最终都能解锁 ----
	var reach := _reachable(unlocks, keys)
	for k in keys:
		chk(reach.has(str(k)), "%s 从免费起点可达" % k)

	# ---- 7) 判定逻辑本身 ----
	var s := Save.defaults()
	chk(not Unlocks.is_unlocked(s, unlocks, "martial"), "新档下 martial 是锁着的")
	s["total_kills"] = 800
	chk(Unlocks.is_unlocked(s, unlocks, "martial"), "累计 800 击杀解锁 martial（旁路生效）")
	var s2 := Save.defaults()
	Save.record_run(s2, {"wave": 11, "kills": 900, "gold": 500, "score": 7000,
		"won": true, "character": "turnip"})
	chk(int((s2.get("clears", {}) as Dictionary).get("turnip", 0)) == 1,
		"用 turnip 通关 → clears[turnip] = 1")
	chk(Unlocks.is_unlocked(s2, unlocks, "martial"), "turnip 通关解锁 martial（主线生效）")
	var s3 := Save.defaults()
	Save.record_run(s3, {"wave": 3, "kills": 100, "gold": 50, "score": 900,
		"won": false, "character": "turnip"})
	chk((s3.get("clears", {}) as Dictionary).is_empty(), "阵亡不记 clears（只有通关推进阶梯）")
	chk(not Unlocks.is_unlocked(s3, unlocks, "martial"), "阵亡不推进解锁阶梯")

	# ---- 8) remaining / next_character 给 UI 的进度要准 ----
	var rem := Unlocks.remaining(s2, Unlocks.rule_of(unlocks, "bruiser"))
	chk(int(rem.get("left", -1)) >= 0, "bruiser 的解锁进度可算：%s" % str(rem))
	var nx := Unlocks.next_character(s2, unlocks, keys)
	chk(nx.has("key"), "还有下一个可解锁目标：%s（还差 %s）" % [
		str(nx.get("key", "")), str(nx.get("left", ""))])
	var full := Save.defaults()
	full["total_kills"] = 99999
	full["total_gold"] = 99999
	full["best_wave"] = 999
	full["wins"] = 99
	chk(Unlocks.unlocked_keys(full, unlocks, keys).size() == keys.size(),
		"统计拉满后全部 %d 个角色解锁" % keys.size())
	chk(Unlocks.next_character(full, unlocks, keys).is_empty(),
		"全解锁后没有下一个目标（UI 不再显示）")

	# ---- 9) 武器侧：每把武器必须"能被拿到"（初始清单 or 有解锁规则）----
	var start: Array = unlocks.get("start_weapons", []) as Array
	var wkeys: Array = data.weapons.keys()
	var wrules: Dictionary = unlocks.get("weapons", {}) as Dictionary
	var orphan := []
	for w in wkeys:
		if not start.has(str(w)) and not wrules.has(str(w)):
			orphan.append(str(w))
	chk(orphan.is_empty(), "没有永远拿不到的武器（死内容 %d 把：%s）" % [
		orphan.size(), ", ".join(orphan)])
	var all_w := Save.unlocked_weapons(full, unlocks)
	chk(all_w.size() == wkeys.size(), "统计拉满后 %d 把武器全部可用" % wkeys.size())

	# ---- 10) 本命武器不能晚于它的角色太多：角色解锁时本命就该买得到 ----
	for k in keys:
		var sig: Dictionary = data.character(str(k)).get("signature", {}) as Dictionary
		var wk := str(sig.get("key", ""))
		if wk.is_empty():
			continue
		chk(all_w.has(wk), "%s 的本命武器 %s 最终可解锁" % [k, wk])

	return {"pass": _p, "fail": _f, "failures": _failures}

# 依赖链里能不能绕回自己（成环检测）
func _cycle_hit(unlocks: Dictionary, target: String, cur: String, seen: Array) -> bool:
	if seen.has(cur):
		return cur == target
	var next: Array = seen.duplicate()
	next.append(cur)
	for dep in Unlocks.clear_deps(Unlocks.rule_of(unlocks, cur)):
		if _cycle_hit(unlocks, target, dep, next):
			return true
	return false

# 从免费角色出发做 BFS：能通关的角色可以再往下解锁它的接班人
func _reachable(unlocks: Dictionary, keys: Array) -> Array:
	var done: Array = []
	for k in keys:
		if str(Unlocks.rule_of(unlocks, str(k)).get("type", "")) == "free":
			done.append(str(k))
	# 每条边的旁路都不依赖通关，所以只看 clear_with 依赖：前置到手 → 接班人必到手
	var grew := true
	while grew:
		grew = false
		for k in keys:
			var key := str(k)
			if done.has(key):
				continue
			var deps: Array = Unlocks.clear_deps(Unlocks.rule_of(unlocks, key))
			var ok := deps.is_empty()
			for d in deps:
				if done.has(str(d)):
					ok = true
			if not ok and Unlocks.has_side_branch(Unlocks.rule_of(unlocks, key)):
				ok = true   # 有旁路 = 迟早能攒出来
			if ok:
				done.append(key)
				grew = true
	return done
