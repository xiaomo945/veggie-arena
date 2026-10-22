extends SceneTree

# 纯键盘冲刺探针：全程**不产生任何鼠标事件**，验证"按移动方向的角度直接冲刺"。
#   A 稳定按 W 30 帧 → 冲：dir 必须精确朝上
#   B 从 W 转向 W+A 后 1 帧立刻冲：dir 必须落在 90°~135° 之间（中间角度，不是跳档）
#   C 稳定按 W+A 30 帧 → 冲：dir 必须精确朝左上（平滑收敛，不会一直歪着）
# 用法：godot --headless --path . --script res://scripts/kb_dash_probe.gd

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

const UP := Vector2(0, -1)
const UP_LEFT := Vector2(-1, -1)

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
	for _i in 3:
		await physics_frame
	print("=== 全程零鼠标事件：_has_mouse=%s（false 才说明测的是纯键盘路径）===" % p.get("_has_mouse"))

	ev.emit_signal("stick_dir_changed", UP)
	for _i in 30:
		await physics_frame
	await _dash(p, ev, "A 稳定按 W", -90.0, -90.0)

	await _cooldown(p)

	ev.emit_signal("stick_dir_changed", UP)
	for _i in 20:
		await physics_frame
	ev.emit_signal("stick_dir_changed", UP_LEFT.normalized())
	await physics_frame
	await _dash(p, ev, "B 转向后 1 帧冲", -135.0, -90.0)

	await _cooldown(p)

	# B2：转向后 4 帧（约 67ms）再冲 —— 这是玩家真正能稳定操作的"中间角度"
	ev.emit_signal("stick_dir_changed", UP)
	for _i in 20:
		await physics_frame
	ev.emit_signal("stick_dir_changed", UP_LEFT.normalized())
	for _i in 4:
		await physics_frame
	await _dash(p, ev, "B2 转向后 4 帧冲", -122.0, -104.0)

	await _cooldown(p)

	ev.emit_signal("stick_dir_changed", UP_LEFT.normalized())
	for _i in 30:
		await physics_frame
	await _dash(p, ev, "C 稳定按 W+A", -135.0, -135.0)

	quit(0)

func _cooldown(p: Node) -> void:
	for _i in 140:
		await physics_frame

# lo/hi 为期望角度区间（度）；hi 给同一个值表示"精确等于"
func _dash(p: Node, ev: Node, tag: String, lo: float, hi: float) -> void:
	# 每次冲前回场地中心：否则连续朝同一侧冲刺会被 clamp_to_arena 卡在墙上，位移读成 0
	var arena: Rect2 = p.get("_arena")
	p.global_position = arena.get_center()
	p.set("_vx", 0.0)
	p.set("_vy", 0.0)
	await physics_frame
	var pos0: Vector2 = p.global_position
	ev.emit_signal("dash_requested")
	await physics_frame
	var d: Dictionary = p.get("_dash")
	var dir: Vector2 = d.get("dir", Vector2.ZERO)
	var deg := rad_to_deg(dir.angle())
	var ok := deg >= minf(lo, hi) - 0.6 and deg <= maxf(lo, hi) + 0.6
	if lo == hi:
		ok = absf(deg - lo) <= 0.6
	for _i in 20:
		await physics_frame
	print("  %s: dir=(%.3f,%.3f) 角度 %.1f°  期望[%.1f,%.1f]  %s  位移 %.1fpx"
		% [tag, dir.x, dir.y, deg, lo, hi, "OK" if ok else "FAIL", pos0.distance_to(p.global_position)])
