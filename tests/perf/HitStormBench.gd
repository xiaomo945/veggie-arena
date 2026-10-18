extends Node2D

# 命中风暴【分配 churn】基准（③ 特效/GC 池化的守门人）。
#
# 已有的两个闸门各自看一类问题：
#   perf_regression.py —— 稳态每帧热点（均值）
#   fx_band.py         —— 击杀清场那一帧的尖峰
# 但都看不见【每次命中】这条最高频路径的分配：6 把武器每秒十几次命中，
# per-hit 的新建/销毁累积成 GC 压力，均值照样漂亮。这个基准模拟一轮真实
# 命中风暴（飘字/枪口火光/爆环/爆点/掉钱/近战扇形全部走 Events 真信号路径 +
# 真 SparkPool / 真 PickupField），跑两轮 + 老化，量分配与复用。
#
# 判据（见 scripts/hit_storm_band.py）：
#   1. 两轮风暴 + 全部老化后 node_delta == 0 —— 池化后特效路径不允许新增
#      任何常驻节点；谁把飘字改回 Label.new()，这条立刻红
#   2. obj_delta <= OBJ_MAX —— 同上。实测 5~9：headless dummy 音频服务的
#      播放 transient（真机播放完即释放），本路径自身零分配
#   3. per_event_us <= PE_MAX —— 每次事件的表现开销有界（防止有人把
#      O(n) 的东西塞进 per-hit 路径）
#   4. 第二轮与第一轮 us2 ≈ us1 —— Label 池真的在复用（否则第二轮会慢一截）

const FX_SCENE := preload("res://ui/Fx/FxLayer.tscn")
const SPARK := preload("res://entities/effects/SparkPool.gd")
const FIELD := preload("res://entities/Pickup/PickupField.tscn")

const N_HIT := 2400    # 命中：飘字 + 迸溅（Feel.hit → 顿帧节流）
const N_SHOT := 1200   # 开火：枪口火光
const N_KILL := 300    # 击杀：爆环 + 爆点池 + 掉钱
const N_MELEE := 300   # 近战：扇形 + 地面裂痕
const AGE_FRAMES := 70 # 老化帧数（band 以 --fixed-fps 60 跑 → ≈1.17s，
                       # 盖过最长寿命：裂痕/彩纸 0.85s + 顿帧缩放窗口 + 余量）
const KEYS := ["pistol", "smg", "rocket", "shotgun"]

var _fx: CanvasLayer = null
var _sparks: Node = null
var _field: Node = null

func _ready() -> void:
	var fx: CanvasLayer = FX_SCENE.instantiate()
	add_child(fx)
	_fx = fx
	var sp := SPARK.new()
	add_child(sp)
	sp.build()
	_sparks = sp
	var f: Node = FIELD.instantiate()
	add_child(f)
	_field = f
	await get_tree().process_frame
	# ⚠️ _bench() 内含 await，必须 await 它再 quit —— 直接调会立刻拿到协程
	# 句柄就退出，测量一行都打不出来（踩过）。
	await _bench()
	get_tree().quit(0)

func _bench() -> void:
	# 预热：灌满 Label 池与各视图首批数组（一次性成本，不进测量窗口）
	for i in 80:
		Events.damage_dealt.emit(5 + (i % 30), Vector2(float(i), 40.0), i % 9 == 0)
	await _age()
	var n0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o0 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	_storm()
	var us1 := Time.get_ticks_usec() - t0
	await _age()
	# 第二轮：证明第一轮新建的 Label 被复用（node_delta 应仍为 0、us2≈us1）
	t0 = Time.get_ticks_usec()
	_storm()
	var us2 := Time.get_ticks_usec() - t0
	await _age()
	var n1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var ev := N_HIT + N_SHOT + N_KILL + N_MELEE
	print("HITSTORM events=%d us1=%d us2=%d per_event_us=%d node_delta=%d obj_delta=%d" % [
		ev, us1, us2, us1 / ev, n1 - n0, o1 - o0])

# 一轮命中风暴：与真实战斗同频同路径（信号名、参数形状都一致）
func _storm() -> void:
	var color := Color(0.9, 0.9, 0.9)
	var stats := {"bullet_speed": 560.0, "dmg": 3.0, "range": 300.0}
	for i in N_HIT:
		Events.damage_dealt.emit(5 + (i % 40), Vector2(float(i % 400), 120.0), i % 7 == 0)
	for i in N_SHOT:
		Events.weapon_fired.emit(Vector2(float(i % 300), 60.0), Vector2.RIGHT,
			stats, color, KEYS[i % KEYS.size()])
	for i in N_KILL:
		var p := Vector2(80.0 + float(i % 260), 90.0 + float(i % 7) * 13.0)
		Events.enemy_killed.emit("grunt", p)
		_sparks.pop(p, i % 40 == 0)
		_field.drop(p, 13)
	for i in N_MELEE:
		Events.melee_visual.emit(Vector2(120.0, 150.0), Vector2.RIGHT,
			90.0, 0.6, color, KEYS[i % KEYS.size()], 1 + (i % 3))

# 老化：等所有特效寿命自然走完（飘字/爆环/迸溅/裂痕/爆点），池化 Label 全部归还
func _age() -> void:
	for _k in AGE_FRAMES:
		await get_tree().process_frame
