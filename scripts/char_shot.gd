extends SceneTree

# 主角贴图目检：逐个切 10 个萝卜职业，各截一张真渲染图。
#
# 走真实 Main 场景（视口 540×900 竖屏），每切一个角色等几帧让
# PlayerVisual._process 的 queue_redraw + _class_tint 重算走完，抓全屏存盘。
# 拼图交给外部 PIL 做 —— GDScript 里做像素格式转换踩过坑。
#
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/char_shot.gd
#
# 与 shot.gd 同样的坑：--script 模式不注册 autoload，一律 root.get_node("Events") 取。

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
	"HudLayout": "res://ui/HUD/HudLayout.gd",
	"ScreenMode": "res://ui/Screens/ScreenMode.gd",
	"Perf": "res://autoload/Perf.gd",
}

const KEYS := ["turnip", "archer", "bruiser", "mage", "skirmisher",
	"hoarder", "hedgehog", "commando", "martial", "magnet"]


func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")

	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	ev.emit_signal("run_requested")
	await process_frame

	for i in KEYS.size():
		gs.character = KEYS[i]
		ev.emit_signal("character_changed", KEYS[i])
		# 等视觉层重画 + 站定
		for _f in 24:
			await process_frame
		root.get_texture().get_image().save_png("user://charcell_%d.png" % i)
		print("shot ", KEYS[i])

	print("SHOT done")
	quit(0)
