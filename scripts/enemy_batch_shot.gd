extends SceneTree

# 敌人合批②的真实渲染 A/B 探针（对照基准）。
# 确定性铺一屏敌人：13 型全带 + 精英描边 + 残血血条 + 终局 Boss 装饰，速度置 0 冻结移动，
# 的位置固定，可复现。改前(每只一个 Node2D 各画 _draw)与改后(单节点合批)用它对照。
#
#   # headless 无像素，必须窗口模式跑(真 GL 上下文)：
#   godot --path . --script res://scripts/enemy_batch_shot.gd -- --out=C:/.../baseline.png
#
# ⚠️ 与其它 _shot.gd 一致：--script 模式不注册 autoload，手工 new 挂 root。

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

const TYPES := ["grunt", "fast", "tank", "fly", "boss", "swarm", "brute",
	"shambler", "shooter", "charger", "splitter", "bomber", "splitling"]

var _out := "C:/Users/windos/AppData/Local/Temp/va_shot/enemy_baseline.png"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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
	# 确定性 A/B 的前提：world.rng 未播种（波次撒怪位置逐 run 随机，还会推挤网格怪）。
	# 必须在 run_requested 之前固定 —— 之后 spawn_wave_burst 立即撒 15 只。
	var w0 = main.game.world
	if w0 != null:
		w0.rng.seed = 20260418
	ev.emit_signal("run_requested")
	for _f in 12:
		await physics_frame
	# 冻结自动降档：量的是未降级前的真实绘制路径
	var perf: Node = root.get_node_or_null("Perf")
	if perf != null and perf.has_method("debug_freeze"):
		perf.debug_freeze(true)
	# 清空武器停 auto-fire：玩家武器是 _rebuild_weapons 缓存，须重发 weapons_changed 才生效
	var gs0: Node = root.get_node_or_null("GameState")
	if gs0 != null and (gs0.get("weapons") is Array):
		(gs0.get("weapons") as Array).clear()
		ev.emit_signal("weapons_changed", [])
	# 递归隐藏所有 UI 弹层(HUD/触控不在 main 直接子节点)，只留战场与摆好的敌人
	var ui_stack: Array[Node] = [root]
	while not ui_stack.is_empty():
		var n: Node = ui_stack.pop_back()
		if n is CanvasLayer:
			n.visible = false
			continue
		for c in n.get_children():
			ui_stack.append(c)
	var world = main.game.world
	var player = world.player
	# A/B 确定性：关掉两台时间驱动的浮动源（渲染 delta 累积，逐 run 漂移）——
	#   玩家受击无敌期的闪烁 alpha（PlayerVisual._process）
	#   环境尘埃（AmbientKitchen._process）
	# 敌人 tick/动画相位走物理步(固定 1/60)，帧确定；地面用固定 seed，静态。
	player.visible = false
	for c in main.game.get_children():
		var p: String = c.get_script().resource_path if c.get_script() != null else ""
		if p.contains("AmbientKitchen"):
			c.visible = false
	var data: Node = root.get_node("Data")
	var enemies: Dictionary = data.get("enemies")
	var origin: Vector2 = player.global_position
	# 网格铺开：5 列，行随 i 增；spacing>60px 避免触发分离、speed=0 冻结追踪
	var idx := 0
	var boss_elite_used := false
	for ty in TYPES:
		var base = enemies.get(ty)
		if base == null:
			print("MISS ", ty); continue
		var stats: Dictionary = (base as Dictionary).duplicate(true)
		stats["type"] = ty
		stats["speed"] = 0.0
		stats["elite"] = false
		stats["final"] = false
		var col := idx % 5
		var row := int(idx / 5.0)
		var pos: Vector2 = origin + Vector2(-180.0 + col * 90.0, -140.0 + row * 92.0)
		if ty == "tank":
			stats["elite"] = true                    # 精英描边
		if ty == "boss":
			stats["final"] = true                    # 终局 Boss 金色装饰
		if ty == "brute":
			stats["radius"] = float((base as Dictionary).get("radius", 16)) * 1.4  # 大只一点，撞 ViewStretch
		var e = world.enemies[world.enemy_cursor]
		world.enemy_cursor = (world.enemy_cursor + 1) % world.enemies.size()
		e.spawn(pos, stats, world.next_id)
		world.next_id += 1
		if ty == "swarm":
			e.hp = e.max_hp * 0.5                     # 残血 → 血条显示
		idx += 1
	# 等 Boss"破土"升起动画播完(_rise 播完才会画终局装饰)，再定影
	for _f in 75:
		await physics_frame
	# 定影：get_texture() 取的是"最近已完成的那一渲染帧"，渲染调度抖动会让它
	# 落在 ±1 个物理 tick 上（Boss 终局装饰的相位差一点，尖刺环就转角）。
	# time_scale=0 后所有 tick 的 delta=0、状态冻结，任意一帧都是同一张图。
	Engine.time_scale = 0.0
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(_out)
	print("SAVED ", _out, "  enemies=", idx)
	quit(0)
