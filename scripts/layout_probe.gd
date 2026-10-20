extends SceneTree

# 布局探针（窗口模式）：打印触控按钮簇的真实屏上坐标与布局常量。
# 用法：godot --path . --script res://scripts/layout_probe.gd

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
	var hl: Node = root.get_node("HudLayout")
	var data: Node = root.get_node("Data")
	print("=== 布局常量 ===")
	print("  is_landscape=", data.is_landscape(), " design=", hl.design_size())
	print("  pivot=", hl.buttons_pivot(), " dash=", hl.buttons_dash_center(),
		" arc_r=", hl.buttons_arc_r())
	print("  joy_base=", hl.joy_fixed_base(), " bottom_shift=", hl.bottom_shift())
	print("  window=", DisplayServer.window_get_size(), " canvas=", get_root().get_visible_rect().size)
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	ev.emit_signal("run_requested")
	for _f in 10:
		await physics_frame
	await process_frame
	await process_frame
	print("=== 真实按钮坐标（run 后）===")
	var hb: Node = _find(main, "HudButtons")
	if hb == null:
		print("  HudButtons 未找到！")
		quit(0)
		return
	for b: Dictionary in hb.get("_btns"):
		var nd: Node = b["node"]
		print("  %-6s center=screen(%.0f,%.0f) size=%.0f" % [
			b["type"], nd.global_position.x + nd.size.x * 0.5,
			nd.global_position.y + nd.size.y * 0.5, nd.size.x])
	for b: Node in hb.get("_skill_btns"):
		print("  skill  node screen=(%.0f,%.0f)" % [b.global_position.x + b.size.x * 0.5,
			b.global_position.y + b.size.y * 0.5])
	var joy: Node = _find(main, "Joystick")
	if joy != null:
		print("  Joy    screen=(%.0f,%.0f)" % [joy.global_position.x, joy.global_position.y])
	# 左下橙色 x3 充能键是谁
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Resource = n.get_script()
		if s != null and ("Charge" in str(s.resource_path) or "Ult" in str(s.resource_path)
				or "Qte" in str(s.resource_path)):
			var r: Rect2 = n.get_global_rect()
			print("  特殊节点 %s screen=(%.0f,%.0f)" % [s.resource_path.get_file(),
				r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5])
		for c in n.get_children():
			stack.append(c)
	quit(0)

func _find(n: Node, cls: String) -> Node:
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		var s: Resource = x.get_script()
		if s != null and s.resource_path.get_basename().get_file() == cls:
			return x
		for c in x.get_children():
			stack.append(c)
	return null
