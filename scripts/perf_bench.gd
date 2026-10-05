extends SceneTree

# 性能微基准：直接量"每帧热点函数"的开销，不启动整局游戏。
#
# 为什么不做整局测量：--script + xvfb 起完整 Main 要跑 3 分钟以上且噪声极大
# （真踩过：llvmpipe 软渲染 + 每档重建场景，测出来的帧时间全是渲染底噪，
#  根本盖不住 CPU 侧的差异）。而"怪一多就卡"这件事的 CPU 侧开销是可以
# 精确隔离出来量的 —— 瓶颈就在这几个每帧调用的函数里。
#
# 量的是【真实生产函数】，不是复刻版：
#   Hit.separation / Hit.overlaps / Weapon.nearest_target 直接 preload core/ 下的实现。
#   EnemyMind._collect_neighbors 的 O(n²) 扫描逻辑同构复刻（它本身要 Node 环境，
#   但那 20 行是纯数组遍历，照搬结构不改语义 —— 下面 _bench_scan 注明了对应关系）。
#
# 用法：godot --headless --path . --script res://scripts/perf_bench.gd

const Hit := preload("res://core/Hit.gd")
const Weapon := preload("res://core/Weapon.gd")

# 复刻 EnemyMind._collect_neighbors + Hit.separation 的组合开销。
# 对应真实代码：scenes/EnemyMind.gd 的 _collect_neighbors()（O(n²) 全表扫）
# 与 Hit.separation()（只处理 60px 内的邻居）。
func _bench_separation(n: int, iters: int) -> Dictionary:
	var pos := PackedVector2Array()
	var radius := PackedFloat32Array()
	for i in n:
		# 撒在 700x700 范围内（大致同屏可见范围），半径 22
		pos.append(Vector2(fposmod(float(i) * 97.0, 700.0), fposmod(float(i) * 53.0, 700.0)))
		radius.append(22.0)
	var neighbors: Array = []
	var acc := 0.0
	var t0 := Time.get_ticks_usec()
	for it in iters:
		for i in n:
			# ---- _collect_neighbors：O(n) 扫全表，只收 60px 内的 ----
			_nn = 0
			for j in n:
				if j == i:
					continue
				if pos[i].distance_squared_to(pos[j]) >= 3600.0:
					continue
				if _nn >= neighbors.size():
					neighbors.append({"pos": pos[j], "radius": radius[j]})
				else:
					var d: Dictionary = neighbors[_nn]
					d["pos"] = pos[j]
					d["radius"] = radius[j]
				_nn += 1
			# ---- separation：只遍历收集到的邻居 ----
			acc += Hit.separation(pos[i], neighbors, radius[i], _nn).length()
	var us := float(Time.get_ticks_usec() - t0) / float(iters)
	return {"per_frame_ms": us / 1000.0, "checks": float(n) * float(n), "acc": acc}

var _nn := 0

# 复刻 Weapon.nearest_target：每把武器开火前都全表扫一遍找最近目标。
# 6 把武器 = 每帧 6 次全表扫。
func _bench_nearest(n: int, iters: int, weapons: int) -> float:
	var edata: Array = []
	for i in n:
		edata.append({"pos": Vector2(fposmod(float(i) * 97.0, 700.0),
			fposmod(float(i) * 53.0, 700.0)), "radius": 22.0, "alive": true})
	var origin := Vector2(350.0, 350.0)
	var acc := 0
	var t0 := Time.get_ticks_usec()
	for it in iters:
		for w in weapons:
			acc += Weapon.nearest_target(origin, edata, 400.0)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(iters)

# 复刻 collect_enemy_data：每帧把所有活怪的字典刷新一遍。
func _bench_collect(n: int, iters: int) -> float:
	var edata: Array = []
	var t0 := Time.get_ticks_usec()
	for it in iters:
		var arr: Array = []
		for i in n:
			arr.append({"pos": Vector2(i, i), "radius": 22.0, "vel": Vector2.ZERO,
				"alive": true, "ref": null})
		edata = arr
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(iters)

func _initialize() -> void:
	print("=== 性能微基准（headless，纯 CPU；单位 ms/帧）===")
	print()
	print("【A】敌人分离 = EnemyMind._collect_neighbors(O(n²)) + Hit.separation")
	print("   怪数   ms/帧     距离检查次数/帧   60fps预算占比")
	print("   " + "-".repeat(58))
	# 迭代次数按 n 缩放，保证总工作量恒定（否则 n=88 要跑 88²×1000 次）
	for n in [10, 20, 30, 40, 60, 88]:
		var iters := maxi(4, int(40000.0 / float(n)))
		var r := _bench_separation(n, iters)
		var ms: float = r["per_frame_ms"]
		var budget := ms / 16.67 * 100.0
		print("   %4d   %7.3f   %14.0f   %13.1f%%"
			% [n, ms, r["checks"], budget])
	print()
	print("【B】自动瞄准 = Weapon.nearest_target × 6 把武器（每把扫一遍全表）")
	print("   怪数   ms/帧     60fps预算占比")
	print("   " + "-".repeat(58))
	for n in [10, 20, 30, 40, 60, 88]:
		var iters := maxi(20, int(20000.0 / float(n)))
		var ms := _bench_nearest(n, iters, 6)
		print("   %4d   %7.3f   %13.1f%%" % [n, ms, ms / 16.67 * 100.0])
	print()
	print("【C】敌人数组收集 = collect_enemy_data（每帧刷新全部活怪字典）")
	print("   怪数   ms/帧     60fps预算占比")
	print("   " + "-".repeat(58))
	for n in [10, 20, 40, 60, 88]:
		var iters := maxi(20, int(20000.0 / float(n)))
		var ms := _bench_collect(n, iters)
		print("   %4d   %7.3f   %13.1f%%" % [n, ms, ms / 16.67 * 100.0])
	print()
	print("=== 读数说明 ===")
	print("  60fps 预算 = 16.67ms/帧。占比 >100% 就是必掉帧，>50% 已经很危险。")
	print("  A 是 O(n²)：怪数翻倍 → 开销 4 倍。这是'怪一多就卡'最可能的主因。")
	quit(0)
