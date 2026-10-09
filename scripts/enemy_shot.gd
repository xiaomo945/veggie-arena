extends SceneTree

# 敌人贴图目检：走真实 Main 场景开一局，把每种敌人的贴图/手绘状态逐个验证。
# 有贴图的敌人直接摆到镜头前截真渲染图；输出 /tmp/enemy_ingame.png 拼图由外部 PIL 做。
#
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/enemy_shot.gd

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

# 全部 13 种，缺图的一眼就能从截图里看出来
const KEYS := ["grunt", "fast", "tank", "fly", "boss", "swarm", "brute",
	"shambler", "shooter", "charger", "splitter", "bomber", "splitling"]


func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	var ev: Node = root.get_node("Events")

	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	ev.emit_signal("run_requested")
	for _f in 8:
		await process_frame

	# 隐藏所有 UI 弹层（标题/解锁树/商店/HUD…），只留战场和摆好的敌人
	for c in main.get_children():
		if c is CanvasLayer:
			c.visible = false

	var idx := 0
	for k in KEYS:
		var tex = root.get_node("Art").sprite("enemy_" + str(k))
		if tex == null:
			print("MISS ", k)
			continue
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(0.35, 0.35)
		spr.position = Vector2(70 + (idx % 7) * 70, 90 + int(idx / 7.0) * 110)
		idx += 1
		main.add_child(spr)
	for _f in 10:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/enemy_ingame.png")
	print("SAVED /tmp/enemy_ingame.png  sprites=", idx)
	quit(0)
