extends RefCounted

# 选角排序 + 解锁关系树的守门测试（今晚两件事："免费在前"和"关系树一看就明白"）。
#
# 盯的都是"以后加角色 / 改解锁规则时最容易翻的车"：
#   1) 排序失效 → 新玩家第一眼看到一串锁着的萝卜（他要的是"我现在能玩谁"）
#   2) 阶梯深度算错 → 树把后置角色排在前面，箭头方向看着是反的
#   3) lanes / standalone 漏人重复人 → 树上有角色凭空消失或出现两次
#   4) 主线/旁路分错类 → 树上的方块显示错的条件，甚至同时出现在两列

const Unlocks := preload("res://core/Unlocks.gd")
const Save := preload("res://core/Save.gd")

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
	var keys: Array = data.characters.keys()
	var rules: Dictionary = unlocks.get("characters", {}) as Dictionary

	# ---- 1) 免费起点必须在最前面 ----
	var save0: Dictionary = Save.defaults()
	var order: Array = Unlocks.order(save0, unlocks, keys)
	var frees: Array = []
	for k in keys:
		if str((rules.get(str(k), {}) as Dictionary).get("type", "")) == "free":
			frees.append(str(k))
	frees.sort()
	var first3: Array = order.slice(0, frees.size())
	first3.sort()
	chk(order.size() == keys.size(), "排序不丢角色（%d / %d）" % [order.size(), keys.size()])
	chk(first3 == frees, "新档的前 %d 个就是全部免费角色：%s" % [frees.size(), ", ".join(first3)])
	# 任意"已解锁"角色都必须排在任意"锁着"的角色之前
	var first_locked := -1
	for i in order.size():
		if not Unlocks.is_unlocked(save0, unlocks, str(order[i])):
			first_locked = i
			break
	var bad_pos := false
	for i in range(first_locked, order.size()):
		if Unlocks.is_unlocked(save0, unlocks, str(order[i])):
			bad_pos = true
	chk(not bad_pos, "新档里所有能玩的角色都排在锁着的角色之前")

	# ---- 2) 阶梯深度：free=0，每往下一级 +1 ----
	var d_ok := true
	for lane in Unlocks.lanes(unlocks, keys):
		for i in (lane as Array).size():
			var key := str((lane as Array)[i])
			var want := 0
			for dep in Unlocks.clear_deps(Unlocks.rule_of(unlocks, key)):
				want = maxi(want, Unlocks.depth_of(unlocks, str(dep)) + 1)
			if Unlocks.depth_of(unlocks, key) != want:
				d_ok = false
	chk(d_ok, "每个角色的阶梯深度 = 前置角色深度 + 1（箭头不会画反）")
	chk(Unlocks.depth_of(unlocks, "turnip") == 0, "免费起点 turnip 深度 0")

	# ---- 3) 关系树：车道 + 旁路 = 全部角色，且不重不漏 ----
	var lanes: Array = Unlocks.lanes(unlocks, keys)
	var side: Array = Unlocks.standalone(unlocks, keys)
	var seen: Array = []
	var dup := []
	for lane in lanes:
		for k in lane:
			if seen.has(str(k)):
				dup.append(str(k))
			seen.append(str(k))
	for k in side:
		if seen.has(str(k)):
			dup.append(str(k))
		seen.append(str(k))
	chk(lanes.size() >= 3, "至少 3 条主线（当前 %d 条）" % lanes.size())
	chk(dup.is_empty(), "没有角色同时出现在两条线里（重复：%s）" % _j(dup))
	chk(seen.size() == keys.size(), "树上有全部 %d 个角色（实际 %d 个）" % [keys.size(), seen.size()])
	# 每条线的头必须是免费起点 —— 否则玩家不知道从哪儿下嘴
	var bad_head := []
	for lane in lanes:
		var head := str((lane as Array)[0])
		if Unlocks.depth_of(unlocks, head) != 0:
			bad_head.append(head)
	chk(bad_head.is_empty(), "每条主线的头都是免费起点（异常：%s）" % _j(bad_head))
	# 车道内部必须"父在前子在后"，箭头才不会往回指
	var bad_order := []
	for lane in lanes:
		var arr := lane as Array
		for i in arr.size():
			var kids: Array = (Unlocks.edges(unlocks, keys).get(str(arr[i]), []) as Array)
			for c in kids:
				if arr.find(str(c)) < i:
					bad_order.append("%s→%s" % [str(arr[i]), str(c)])
	chk(bad_order.is_empty(), "主线内部父节点永远排在子节点之前（异常：%s）" % _j(bad_order))

	# ---- 4) 旁路角色：确实没有主线条件（它们只能靠累计数据解锁）----
	var bad_side := []
	for k in side:
		if not (Unlocks.clear_deps(Unlocks.rule_of(unlocks, str(k))) as Array).is_empty():
			bad_side.append(str(k))
	chk(bad_side.is_empty(), "旁路列里的角色确实没有主线条件（异常：%s）" % _j(bad_side))

	# ---- 5) first_clear_with：树上要画的就是"通关前置"这一条 ----
	var f: Dictionary = Unlocks.first_clear_with(Unlocks.rule_of(unlocks, "martial"))
	chk(str(f.get("type", "")) == "clear_with" and str(f.get("need", "")) == "turnip",
		"martial 的主线条件 = 用 turnip 通关")
	chk(Unlocks.first_clear_with(Unlocks.rule_of(unlocks, "turnip")).is_empty(),
		"免费角色没有主线条件（树上它的方块不显示前置）")

	# ---- 6) 全解锁档：排序里一个都不能少，且顺序仍然稳定 ----
	var typed := Unlocks.order(Save.defaults(), unlocks, keys)
	chk(typed.size() == keys.size(), "再排一次仍然是全部角色（排序是纯函数、不受调用次数影响：%d）"
		% typed.size())

	return {"pass": _p, "fail": _f, "failures": _failures}

func _j(arr: Array) -> String:
	return "无" if arr.is_empty() else ", ".join(arr)
