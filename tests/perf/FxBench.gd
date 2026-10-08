extends Node2D

# 击杀特效【尖峰】基准：模拟"一波清场 30 只怪同时死"的瞬时开销。
#
# 为什么要单开一个基准：
#   稳态帧率（A 类）由 scripts/perf_regression.py 守（每帧热点 ms/帧），
#   但用户报告的"怪一多就卡"多半是【B 类尖峰】—— 每次击杀 new 一堆节点 +
#   Tween 再 queue_free。稳态均值完全看不出尖峰：平均 60fps、但清场那一帧
#   花 30ms，玩家感觉到的就是"卡"。只有这种"连杀 30 次"的基准抓得住。
#
# 判据（- 见 scripts/fx_band.py）：
#   30 连杀特效的 CPU 开销必须与"每次击杀只做属性赋值"同量级；
#   节点数增量必须≈0（池化后不应再产生任何临时节点）。

const N := 30

var _root: Node2D = null
var _pool: Node = null

func _ready() -> void:
	_root = Node2D.new()
	add_child(_root)
	# 池的预建不计入计时（真实游戏里是开局一次性成本）
	var sp := preload("res://entities/effects/SparkPool.gd").new()
	_root.add_child(sp)
	sp.build()
	_pool = sp
	await get_tree().process_frame
	_bench()
	get_tree().quit(0)

func _bench() -> void:
	var n0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o0 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	for i in N:
		_spawn(float(i) * 17.0, float(i) * 29.0, false)
	var us := Time.get_ticks_usec() - t0
	var n1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("FXBENCH kills=%d us=%d ms=%.3f per_kill_us=%d node_delta=%d obj_delta=%d" % [
		N, us, float(us) / 1000.0, us / N, n1 - n0, o1 - o0])

# ⚠️ 这一行是基准的"被测对象"：走池还是走 new，由 SparkPool 是否存在决定。
# 池化改造前后跑的是同一条路径，所以前后数字可直接对比。
func _spawn(x: float, y: float, big: bool) -> void:
	_pool.pop(Vector2(x, y), big)
