extends SceneTree

# 键盘行为探针（窗口模式，真渲染 + 真输入分发）：
# 复现"每次按 J / U 都弹出遮挡"——按真实 InputEventKey，
# 记录按键前后哪些节点从不可见变可见 / 从可见变不可见。
# 用法：godot --path . --script res://scripts/key_smoke_shot.gd

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
	var sm: Node = root.get_node("SaveMgr")
	# 首局引导只在"从未玩过"时挂载：伪造空存档，防止真实 user:// 存档把它顶掉（复现用户现场）
	if sm.has_method("load_save"):
		sm.load_save()
	sm.set("data", {})
	sm.set("_loaded_path", "user://nonexistent_probe.json")
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var w0 = main.game.world
	if w0 != null:
		w0.rng.seed = 20260419
	ev.emit_signal("run_requested")
	for _f in 20:
		await physics_frame
	await process_frame
	print("=== 基线快照（开局后）===")
	var before: Dictionary = _snap()
	print("可见覆盖层: ", _overlays(before))
	# 依次按 J / U / K / L（每键等 4 物理帧 + 2 渲染帧）
	for kc in [KEY_J, KEY_U, KEY_K, KEY_L]:
		_press(kc)
		for _f in 4:
			await physics_frame
		await process_frame
		await process_frame
		var after: Dictionary = _snap()
		var diff: Array = _diff(before, after)
		print("按键 %s -> 变化节点: %s" % [OS.get_keycode_string(kc), diff])
		for p in after:
			if bool(after[p]) and not bool(before.get(p, false)) and str(p).begins_with("/root/Main/@CanvasLayer"):
				_identify(str(p))
	quit(0)

func _snap() -> Dictionary:
	var d := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer or n is Control:
			d[n.get_path()] = n.visible
		for c in n.get_children():
			stack.append(c)
	return d

func _overlays(d: Dictionary) -> Array:
	var r := []
	for p in d:
		if bool(d[p]) and ("Screens" in str(p) or "Onboarding" in str(p) or "HUD" in str(p) or "Shop" in str(p) or "Result" in str(p)):
			r.append(p)
	return r

func _diff(a: Dictionary, b: Dictionary) -> Array:
	var r := []
	for p in b:
		if bool(a.get(p, false)) != bool(b[p]):
			r.append("%s %s->%s" % [p, "1" if bool(a.get(p, false)) else "0", "1" if bool(b[p]) else "0"])
	return r

func _press(kc: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = kc
	e.physical_keycode = kc
	e.pressed = true
	Input.parse_input_event(e)
	var e2 := InputEventKey.new()
	e2.keycode = kc
	e2.physical_keycode = kc
	e2.pressed = false
	Input.parse_input_event(e2)

func _identify(p: String) -> void:
	var n: Node = root.get_node_or_null(NodePath(p))
	if n == null:
		print("  [identify] 找不到 ", p)
		return
	var sc: Resource = n.get_script()
	print("  [identify] ", p)
	print("    name=", n.name, " class=", n.get_class())
	print("    script=", sc.resource_path if sc != null else "null")
	var par: Node = n.get_parent()
	print("    parent=", par.name, " parent_script=", (par.get_script().resource_path if par.get_script() != null else "null"))
	if n.get_child_count() > 0:
		var c: Node = n.get_child(0)
		print("    child0=", c.name, " child0_script=", (c.get_script().resource_path if c.get_script() != null else "null"))
