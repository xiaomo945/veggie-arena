extends SceneTree

# 投稿素材探针：一次出齐"评审会看到的几个页面"。
#   01 标题页（竖屏）  02 角色详情  03 解锁路线  04 选武器页
# 用法：godot --path . --script res://scripts/gallery_shot.gd
# 输出到 OUT（投稿用图目录，随后由人工挑图）。

const OUT := "C:/Users/windos/WorkBuddy AI/2026-10-15-04-26-28/veggie-arena/submission/"
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

var _main: Node
var _title: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_size(Vector2i(540, 900))
	_main = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(_main)
	for _i in 12:
		await process_frame
	_title = _find_title(root)
	await _snap("01_标题页")

	# 角色详情（点角色卡后的独立页，layer 55）
	_title.call("_on_char_detail_requested", "turnip")
	for _i in 10:
		await process_frame
	await _snap("02_角色详情")
	var cd: Node = _title.get("_char_detail")
	if cd != null:
		if cd.has_method("_on_close"):
			cd.call("_on_close")
		(cd as CanvasLayer).visible = false
	for _i in 6:
		await process_frame

	# 解锁路线（右上角入口）
	_title.call("_on_route")
	for _i in 10:
		await process_frame
	await _snap("03_解锁路线")
	_title.call("_on_tree_close")
	for _i in 6:
		await process_frame

	# 选武器页（START 之后）
	_title.call("_on_start")
	for _i in 12:
		await process_frame
	await _snap("04_选武器页")

	# 局内战斗：run_requested 会同时开跑（Main._begin_run）并收起标题/选武器页
	# （TitleScreen._on_run_requested）。等怪刷出来再拍，画面才有内容。
	root.get_node("Events").emit_signal("run_requested")
	for _i in 200:
		await process_frame
	await _snap("05_局内战斗")
	for _i in 420:
		await process_frame
	await _snap("06_局内战斗_后期")
	quit(0)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	print("%s.png %s err=%d" % [name, img.get_size(), err])

func _find_title(n: Node) -> Node:
	for c in n.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 50:
			return c
		var r := _find_title(c)
		if r != null:
			return r
	return null
