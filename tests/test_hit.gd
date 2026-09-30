extends RefCounted

# 命中与分离测试

const Hit := preload("res://core/Hit.gd")

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
	# 1) 圆相交判定
	chk(Hit.overlaps(Vector2(0, 0), 5, Vector2(8, 0), 5), "两个半径 5 相距 8 → 相交")
	chk(not Hit.overlaps(Vector2(0, 0), 5, Vector2(11, 0), 5), "相距 11 → 不相交")
	chk(Hit.overlaps(Vector2(0, 0), 5, Vector2(10, 0), 5), "正好相切 → 算命中（边界含）")

	# 2) 命中对
	var bullets := [{"pos": Vector2(0, 0), "radius": 4, "active": true}]
	var enemies := [
		{"pos": Vector2(10, 0), "radius": 12, "alive": true},
		{"pos": Vector2(300, 0), "radius": 12, "alive": true},
	]
	var hits := Hit.find_hits(bullets, enemies)
	chk(hits.size() == 1, "只命中近的那个（%d 对）" % hits.size())
	chk(int(hits[0]["enemy"]) == 0, "命中的是 0 号敌人")

	# 3) 不活跃的子弹/死掉的敌人不参与
	bullets = [{"pos": Vector2(0, 0), "radius": 4, "active": false}]
	chk(Hit.find_hits(bullets, enemies).size() == 0, "未激活的子弹不参与判定")
	enemies[0]["alive"] = false
	chk(Hit.find_hits([{"pos": Vector2(0, 0), "radius": 4, "active": true}], enemies).size() == 0,
		"已死的敌人不再被命中")

	# 4) 空输入不崩
	chk(Hit.find_hits([], []).size() == 0, "空列表不崩")

	# 5) 一发子弹可以同时判定多个敌人（穿透武器用得上）
	var many := [
		{"pos": Vector2(0, 0), "radius": 12, "alive": true},
		{"pos": Vector2(8, 0), "radius": 12, "alive": true},
	]
	chk(Hit.find_hits([{"pos": Vector2(0, 0), "radius": 6, "active": true}], many).size() == 2,
		"大子弹可同时判定多个敌人")

	# 6) 分离力：重叠时要被推开
	var others := [{"pos": Vector2(10, 0), "radius": 14}]
	var push := Hit.separation(Vector2(0, 0), others, 14)
	chk(push.length() > 0.0, "重叠时产生推力（%.2f）" % push.length())
	chk(push.x < 0.0, "推力方向是远离对方（x=%.2f）" % push.x)

	# 7) 不重叠时没有推力（否则怪群会莫名抖动）
	chk(Hit.separation(Vector2(0, 0), [{"pos": Vector2(100, 0), "radius": 14}], 14).length() == 0.0,
		"距离足够时不产生推力")

	# 8) 完全重合时也要能分开（除零保护）
	var same := Hit.separation(Vector2(5, 5), [{"pos": Vector2(5, 5), "radius": 14}], 14)
	chk(is_finite(same.x) and is_finite(same.y), "完全重合时不产生 NaN（%.2f, %.2f）" % [same.x, same.y])

	# 9) 保持距离：贴太近会被顶开
	var kd := Hit.keep_distance(Vector2(0, 0), Vector2(5, 0), 20)
	chk(kd.length() > 0.0, "贴脸时被顶开（%.1f）" % kd.length())
	chk(Hit.keep_distance(Vector2(0, 0), Vector2(50, 0), 20).length() == 0.0,
		"距离够时不干预")

	# 10) 一整群怪互相分离后应该散开（模拟 60 帧）
	var group := []
	for i in range(8):
		group.append({"pos": Vector2(100 + randf() * 0.5, 100 + randf() * 0.5), "radius": 14})
	var spread_before := _spread(group)
	for frame in range(60):
		for i in group.size():
			var rest := []
			for j in group.size():
				if j != i:
					rest.append(group[j])
			var s: Vector2 = Hit.separation(group[i]["pos"], rest, 14)
			group[i]["pos"] = group[i]["pos"] + s * 0.35
	var spread_after := _spread(group)
	chk(spread_after > spread_before * 2.0,
		"60 帧后怪群散开：%.1f → %.1f px" % [spread_before, spread_after])

	return {"pass": _p, "fail": _f, "failures": _failures}

# 群体离散度：所有成员到质心的平均距离
func _spread(g: Array) -> float:
	if g.is_empty():
		return 0.0
	var c := Vector2.ZERO
	for m in g:
		c += m["pos"]
	c /= float(g.size())
	var total := 0.0
	for m in g:
		total += m["pos"].distance_to(c)
	return total / float(g.size())
