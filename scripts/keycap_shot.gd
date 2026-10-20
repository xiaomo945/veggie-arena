extends SceneTree

# 键位角标截图探针（窗口模式）：开局后截右下按钮簇，检查每个按钮的键帽。
# 用法：godot --path . --script res://scripts/keycap_shot.gd

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
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	ev.emit_signal("run_requested")
	for _f in 40:
		await physics_frame
	await process_frame
	await process_frame
	var err: int = root.get_texture().get_image().save_png("C:/Users/windos/AppData/Local/Temp/va_shot/keycaps.png")
	print("save err=", err)
	# 顺带打印每个按钮的键位角标文本（走 SkillButton._key_label）
	var hb: Node = _find(main, "HudButtons")
	if hb != null:
		for b: Dictionary in hb.get("_btns"):
			var nd: Node = b["node"]
			var si: int = nd.get("slot_index")
			var bt: String = nd.get("btn_type")
			print("  %-6s btn_type=%s slot=%d keycap=%s" % [b["type"], bt, si,
				load("res://ui/HUD/KeyCap.gd").label(bt, si)])
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
