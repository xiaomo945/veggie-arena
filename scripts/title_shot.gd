extends SceneTree

# 标题页/首屏体检探针（窗口模式）：竖屏 540x900 与横屏 960x540 各截一张，
# 用来确认评审第一次打开时看到的布局（19 张角色卡会不会把 START 挤出屏幕）。
# 用法：godot --path . --script res://scripts/title_shot.gd

const OUT := "C:/Users/windos/AppData/Local/Temp/va_shot/"
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
	"Keyboard": "res://autoload/Keyboard.gd",
	"Gamepad": "res://autoload/Gamepad.gd",
	"I18n": "res://autoload/I18n.gd",
	"HudLayout": "res://ui/HUD/HudLayout.gd",
	"ScreenMode": "res://ui/Screens/ScreenMode.gd",
	"Perf": "res://autoload/Perf.gd",
}

func _initialize() -> void:
	_run()

func _run() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame

	await _shot("title_portrait.png", Vector2i(540, 900))
	await _shot("title_landscape.png", Vector2i(960, 540))
	await _shot_hint("hint_portrait.png", Vector2i(540, 900))
	await _shot_hint("hint_landscape.png", Vector2i(960, 540))
	quit(0)

# 局内开局提示（ui/HUD/HintLine.gd）：发 run_started 让它亮，等 0.5s 拍一张，
# 再等到 7s 之后确认它已经淡到看不见。
func _shot_hint(name: String, win: Vector2i) -> void:
	DisplayServer.window_set_size(win)
	# 模拟"点过 START"：标题页 _root 隐藏（真实流程在 TitleScreen._on_start 里做），
	# 否则标题页 layer=50 会盖住 HUD（layer=20），拍到的提示被角色卡挡住。
	var ts := _find_title(root)
	if ts != null:
		(ts.get("_root") as Control).visible = false
	root.get_node("Events").emit_signal("run_started")
	for _i in 20:
		await process_frame
	var hint := _find_hint(root)
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	if hint == null:
		print("%s 未找到 HintLine" % name)
		return
	var r := (hint as Control).get_global_rect()
	var lbl := hint as Label
	print("%s alpha=%.2f rect=x%.0f..%.0f y%.0f..%.0f 视口=%.0f 文字宽=%.0f mouse_filter=%d text=%s"
		% [name, lbl.modulate.a, r.position.x, r.end.x, r.position.y, r.end.y,
			root.get_visible_rect().size.x, lbl.get_minimum_size().x, lbl.mouse_filter, lbl.text])

func _find_hint(n: Node) -> Node:
	for c in n.get_children():
		if c is Label and ((c as Label).text.contains("WASD") or (c as Label).text.contains("摇杆移动")):
			return c
		var r := _find_hint(c)
		if r != null:
			return r
	return null

func _shot(name: String, win: Vector2i) -> void:
	DisplayServer.window_set_size(win)
	for _i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT + name)
	print("%s 窗口=%s 纹理=%s err=%d" % [name, win, img.get_size(), err])
	_dump_layout()

# 打印标题页纵向布局：VBox 总高、各子节点占位、START 按钮是否出屏。
# 判断"内容超过设计高度 900"靠这里的数字，不靠目测截图。
func _dump_layout() -> void:
	var ts := _find_title(root)
	if ts == null:
		print("  [layout] 未找到标题页")
		return
	var box: Control = ts.get("_box")
	if box == null:
		print("  [layout] 未找到 _box")
		return
	var vp := root.get_visible_rect().size
	print("  [layout] 视口=%.0fx%.0f  VBox rect=%s 最小高=%.0f"
		% [vp.x, vp.y, box.get_global_rect(), box.get_combined_minimum_size().y])
	for nm in ["_start_btn", "_pick_lbl", "_how_lbl", "_best_lbl"]:
		var c := ts.get(nm) as Control
		if c != null:
			var r := c.get_global_rect()
			print("  [layout] %-10s y=%.0f..%.0f (h=%.0f) %s" % [nm, r.position.y, r.end.y, r.size.y,
				"← 出屏" if r.end.y > vp.y + 0.5 else ""])

func _find_title(n: Node) -> Node:
	for c in n.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 50:
			return c
		var r := _find_title(c)
		if r != null:
			return r
	return null
