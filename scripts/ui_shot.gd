extends SceneTree

# UI 目检截图：真渲染抓"标题页 / 选武器页 / 武器详情页"三张图。
# 这三个页面是容器布局 + 手算坐标混着搭的，headless 单测抓不到"字被压住、卡在被车外面"
# 这类问题，只能真渲染截图看。
#
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/ui_shot.gd
#
# 与 shot.gd / char_shot.gd 同样的坑：--script 模式不注册 autoload，
# 必须手动 new 出来挂到 root 下（名字要对，否则 TitleScreen 里编译期标识符全报错）。

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

const OUT := "/tmp"


func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)

	# ---- 1) 标题页（真实 Main 场景，开局就是它）----
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	for _f in 20:
		await process_frame
	_save("ui_title")
	# ---- 2) 解锁关系树（真实 Main 场景里 TitleScreen 建好的那颗，layer 54）----
	var tree: Control = null
	var tree_layer: CanvasLayer = null
	for layer in root.find_children("*", "CanvasLayer", true, false):
		for c in layer.get_children():
			if c.get_script() == load("res://ui/Screens/UnlockTree.gd"):
				tree = c as Control
				tree_layer = layer as CanvasLayer
	if tree == null:
		print("!! 没找到 UnlockTree（TitleScreen 没建出来？）")
	else:
		# 先用当前存档截一张（通常是"全都解锁"的状态），再换新档截一张锁着的样式。
		# 锁着的样式才是新玩家第一眼看到的画面，必须目检。
		var real: Dictionary = root.get_node("SaveMgr").data
		tree.call("show_page")
		tree_layer.visible = true
		for _f in 6:
			await process_frame
		_save("ui_unlock_tree")
		root.get_node("SaveMgr").data = load("res://core/Save.gd").defaults()
		tree.call("show_page")
		for _f in 6:
			await process_frame
		_save("ui_unlock_tree_fresh")
		root.get_node("SaveMgr").data = real

	main.queue_free()
	await process_frame

	# ---- 2) 选武器页 + 武器详情页（自己搭一个画布来挂，省得模拟点击）----
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var picker: Control = load("res://ui/Screens/WeaponPicker.gd").new()
	canvas.add_child(picker)
	for _f in 8:
		await process_frame
	_save("ui_weapon_picker")

	# 详情页 = 选武器页的最后一个子节点（见 WeaponPicker._build_detail）
	var detail: Control = picker.get_child(picker.get_child_count() - 1) as Control
	detail.call("show_for", "bow")
	for _f in 12:
		await process_frame
	# 背景层若没画出来，多半是几何问题：把详情页各子节点的几何抖出来看
	print("[detail] size=", detail.size, " visible=", detail.visible,
		" modulate=", detail.modulate)
	for c in detail.get_children():
		print("  child ", c.get_class(), " pos=", c.position, " size=", c.size,
			" visible=", c.visible)
		for cc in c.get_children():
			print("    sub ", cc.get_class(), " pos=", cc.position, " size=", cc.size,
				" visible=", cc.visible)
	_save("ui_weapon_detail")

	print("UI SHOT done -> " + OUT)
	quit(0)


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("shot " + name)
