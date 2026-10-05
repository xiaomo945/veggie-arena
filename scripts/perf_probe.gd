extends SceneTree

# 真渲染性能测量（不是 headless —— headless 没有帧时间，量不出卡顿）。
#
# 为什么要有这个：用户报"怪一多就卡顿"。但"卡"有三个完全不同的成因，治法也完全不同：
#   ① 每帧 CPU 开销随敌人数非线性暴涨（典型：O(n²) 的分离/邻居查询）
#   ② 绘制调用过多（每个怪一个 Node2D + 若干 _draw，Godot 每帧都要遍历）
#   ③ 特效/粒子/飘字这类短命对象引发的 GC 风暴
# 不测就分不清是哪个 —— 而三者修法完全不同，猜错等于白改几天。
#
# 这个脚本按怪数梯度跑，每档统计中位帧时间 / p95 / 最坏帧。
# ⚠️ 看的是 p95 不是平均：玩家感知到的"卡"由最坏的那批帧决定，
#    平均帧时间好看但 p95 爆炸的情况很常见（GC 尖峰、批量 spawn）。
#
# 两个测量上的关键决定：
#   1) 冻结自动降级（Perf.debug_freeze）。不冻结的话测到的是"降级后"的性能，
#      看不出瓶颈在哪一层 —— 降级本身正是要掩盖瓶颈的东西。
#   2) 怪数靠连续调 enemy_system.spawn_one() 堆到目标值，而不是等自然刷怪。
#      自然刷怪要等几十秒且数量不稳，测出来的曲线没法比较。
#
# 用法：
#   xvfb-run -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path . --script res://scripts/perf_probe.gd -- --counts=10,20,40,60,88 --sec=3

# ⚠️ --script 模式不注册 autoload，而 Art/Data/Events 这些是编译期标识符，
#    preload 任何用到它们的场景都会 Compile Error（不是运行时能救的）。
#    所以照 scripts/shot.gd 的既有做法：手动 new 出每个 autoload 挂到 root 上。
#    ⚠️ 名单必须与 project.godot 完全一致，漏一个就会 Compile Error。
const AUTOLOADS := {
	"Art": "res://autoload/Art.gd",
	"Data": "res://autoload/Data.gd",
	"Events": "res://autoload/Events.gd",
	"GameState": "res://autoload/GameState.gd",
	"Settings": "res://autoload/Settings.gd",
	"Steam": "res://autoload/Steam.gd",
	"SaveMgr": "res://autoload/SaveMgr.gd",
	"Sfx": "res://autoload/Sfx.gd",
	"Bgm": "res://autoload/Bgm.gd",
	"Gamepad": "res://autoload/Gamepad.gd",
	"I18n": "res://autoload/I18n.gd",
	"Perf": "res://autoload/Perf.gd",
	"HudLayout": "res://ui/HUD/HudLayout.gd",
	"ScreenMode": "res://ui/Screens/ScreenMode.gd",
}

var _counts: Array = []
var _sec := 3.0
var _game = null
var _main = null

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--counts="):
			for s in (a.substr(9) as String).split(","):
				_counts.append(int(s))
		elif a.begins_with("--sec="):
			_sec = float(a.substr(6))
	if _counts.is_empty():
		_counts = [10, 20, 40, 60, 88]

func _initialize_async() -> void:
	_run()

func _run() -> void:
	await _idle()
	print("=== 真渲染性能测量（每档 %.1f 秒，已冻结自动降级）===" % _sec)
	print("  怪数   存活   中位ms   p95ms   最差ms   中位FPS  p95FPS  评级")
	print("  " + "-".repeat(68))
	var first_bad := -1
	for n in _counts:
		var r: Dictionary = await _measure(int(n))
		var med: float = r["median"]
		var p95: float = r["p95"]
		var grade := "OK"
		if p95 > 33.0:
			grade = "卡(<30)"
		elif p95 > 22.0:
			grade = "抖"
		elif p95 > 18.0:
			grade = "偏低"
		if first_bad < 0 and p95 > 33.0:
			first_bad = int(r["n"])
		print("  %4d  %4d   %6.2f  %6.2f  %6.2f   %6.1f  %6.1f  %s"
			% [n, int(r["alive"]), med, p95, r["worst"],
				1000.0 / maxf(med, 0.001), 1000.0 / maxf(p95, 0.001), grade])
	print("  " + "-".repeat(68))
	if first_bad > 0:
		print("  ⚠️ 拐点：%d 只怪时 p95 已超 30fps 预算(33ms)" % first_bad)
	else:
		print("  ✅ 全部档位 p95 < 33ms（30fps 预算内）")
	quit(0)

func _measure(n: int) -> Dictionary:
	await _boot()
	# ⚠️ Perf 是 autoload 标识符，编译期注入；--script 模式下它不存在，
	#    直接写 Perf.xxx 会 Compile Error（不是运行时能救的）。走 root 取节点。
	var perf: Node = root.get_node_or_null("Perf")
	if perf != null and perf.has_method("debug_freeze"):
		perf.debug_freeze(true)
	# 堆怪：直接调公开的 spawn_one，绕开自然刷怪的速率限制
	var guard := 0
	while _alive() < n and guard < n * 20:
		_game.enemy_system.spawn_one()
		guard += 1
	await _idle()
	# 让子弹/特效进入稳态（第一帧有加载尖峰，量进来会污染最坏帧）
	for i in 30:
		await process_frame

	var times: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(_sec * 1000.0):
		var f0 := Time.get_ticks_usec()
		await process_frame
		times.append(float(Time.get_ticks_usec() - f0) / 1000.0)
	times.sort()
	var alive := _alive()
	await _cleanup()
	var med: float = times[times.size() / 2] if times.size() > 0 else 0.0
	var p95: float = times[mini(times.size() - 1, int(times.size() * 0.95))] if times.size() > 0 else 0.0
	return {"n": n, "alive": alive, "median": med, "p95": p95,
		"worst": times[times.size() - 1] if times.size() > 0 else 0.0,
		"frames": times.size()}

func _boot() -> void:
	await _cleanup()
	_ensure_autoloads()
	_main = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	_bus("Events").run_requested.emit()
	await process_frame
	await process_frame
	# Main 用成员变量持有 Game（不是固定节点名），所以从实例上取
	_game = _main.get("game")
	if _game == null or not is_instance_valid(_game):
		# 结构变了就明确报错，绝不静默量 0 怪 —— 那样会得出"性能很好"的假结论
		print("  ❌ Main 上取不到 game（Main.gd 结构变了？）")
		quit(1)

# --script 模式没有 autoload，手动补齐。只做一次。
var _al_done := false
func _ensure_autoloads() -> void:
	if _al_done:
		return
	_al_done = true
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)

func _bus(name: String) -> Node:
	return root.get_node_or_null(name)

# ⚠️ 必须真的把上一局 Main 从树上摘掉。之前只置空引用，结果每一档都在 root 上
#    叠一个完整的 Main（还在跑 _process 继续刷怪渲染），五档叠五个游戏，
#    帧时间被抬到几百 ms，测出来全是噪声还会卡死。autoload 不受影响（留在 root）。
func _cleanup() -> void:
	if _main != null and is_instance_valid(_main):
		root.remove_child(_main)
		_main.free()
	_main = null
	_game = null
	await process_frame

func _alive() -> int:
	if _game == null or not is_instance_valid(_game):
		return 0
	return int(_game.alive_enemy_count())

func _idle() -> void:
	for i in 4:
		await process_frame
