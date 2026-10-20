extends SceneTree

# 冲刺场景级探针（窗口模式，真物理）：造一个真 Player，发 dash_requested，
# 逐帧记录位置/冲刺态/速度，验证"冲刺真的产生位移"。
# 用法：godot --path . --script res://scripts/dash_probe.gd

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

func _initialize() -> void:
	_run()

func _run() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	var ev: Node = root.get_node("Events")
	var p: Node = load("res://entities/Player/Player.tscn").instantiate()
	root.add_child(p)
	await physics_frame
	await physics_frame
	# 场景 A：无方向输入 → 随机冲刺
	var pos0: Vector2 = p.global_position
	print("=== A：无方向 dash_requested（随机向）===")
	ev.emit_signal("dash_requested")
	var moved := 0.0
	var peak := 0.0
	var frames_active := 0
	for i in 30:
		await physics_frame
		var d: Dictionary = p.get("_dash")
		if float(d.get("t", -1.0)) > 0.0:
			frames_active += 1
		var v: Vector2 = p.get("_vx_vy") if p.get("_vx_vy") != null else Vector2(p.get("_vx"), p.get("_vy"))
		peak = maxf(peak, v.length())
		print("  f%02d pos=(%.1f,%.1f) active=%s t=%.3f cd=%.2f" % [i, p.global_position.x, p.global_position.y,
			d.get("t", -1.0) > 0.0, float(d.get("t", -1.0)), float(d.get("cd", 0.0))])
	moved = pos0.distance_to(p.global_position)
	print("  A 结果: 位移 %.1fpx  峰值速度 %.1f  冲刺帧数 %d" % [moved, peak, frames_active])
	# 场景 B：指定方向（模拟键盘蓄方向）
	for _f in 100:
		await physics_frame   # 等冷却走完
	var pos1: Vector2 = p.global_position
	print("=== B：set_move_dir 右下 + dash（指定向）===")
	p.call("set_move_dir", Vector2(1.0, 0.6))
	ev.emit_signal("dash_requested")
	var moved_b := 0.0
	for i in 30:
		await physics_frame
	moved_b = pos1.distance_to(p.global_position)
	var d2: Dictionary = p.get("_dash")
	print("  B 结果: 位移 %.1fpx  dir=%s" % [moved_b, d2.get("dir")])
	# 场景 C：朝正下冲刺（0,1）—— 验证角色不旋转：叶子必须还朝上。
	# 旧代码把萝卜按 dash 方向整体旋转，朝下冲 = "头朝下"。窗口模式截图留证。
	for _f in 100:
		await physics_frame
	print("=== C：朝正下 (0,1) dash + active 中段截图 ===")
	p.call("_fire_dash", Vector2(0.0, 1.0))
	for i in 3:   # 冲到中段（t 0.10 左右）再拍，形变和速度线都在
		await physics_frame
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/windos/AppData/Local/Temp/va_shot/dash_down.png")
	print("  C 截图已存: C:/Users/windos/AppData/Local/Temp/va_shot/dash_down.png")
	quit(0)
