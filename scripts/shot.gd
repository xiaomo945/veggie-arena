extends SceneTree

# 真渲染截图工具（美术目检专用）
#
# headless 跑不出任何像素，美术问题（背景糊成一团、描边看不见、层级盖错）
# 只能靠真渲染截图看。跑法：
#   xvfb-run -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/shot.gd -- \
#       --t=6 --out=/tmp/shot.png
#
# 参数：
#   --t=秒数        开跑后渲染多少秒再截图（默认 6）
#   --out=路径      PNG 输出路径（默认 /tmp/va_shot.png）
#   --boss          截图前发一次 boss_wave（看 Boss 登场演出）
#   --final         截图前发一次 final_boss_wave
#   --elite         截图前把场上第一只怪标成精英并重发出场信号（看精英出场）
#   --shop          截图前塞一组"有两对可合成"的武器并打开补给站（看 6 格物品栏 / 合成高亮）
#   --series=秒     连拍：每 1 秒一张（文件名自动加序号）
#   --to=x,y        玩家一直朝这个世界坐标走（看地图边缘 / 围栏用）
#
# ⚠️ --script 模式不注册 autoload，且 autoload 是**编译期**标识符，
#    运行时 add_child 也救不了（会 Compile Error: Identifier not found）。
#    所以这里统一走 root.get_node("Events") 这种运行时取节点的方式。

var _out := "/tmp/va_shot.png"
var _secs := 6.0
var _boss := false
var _final := false
var _elite := false
var _series := 0.0
var _to := Vector2.INF
var _boss_wait := 0.45
var _elite_wait := 0.3
var _rise := false
var _rise_wait := 0.42
var _shop := false
var _shop_n := 6
var _no_run := false

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
}

func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--t="):
			_secs = float(a.substr(4))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--boss":
			_boss = true
		elif a == "--final":
			_final = true
		elif a == "--elite":
			_elite = true
		elif a == "--shop":
			_shop = true
		elif a.begins_with("--shop="):
			_shop = true
			_shop_n = maxi(0, int(a.substr(7)))
		elif a == "--no-run":
			_no_run = true
		elif a.begins_with("--series="):
			_series = float(a.substr(9))
		elif a == "--rise":
			_rise = true
		elif a.begins_with("--rw="):
			_rise_wait = float(a.substr(5))
		elif a.begins_with("--ew="):
			_elite_wait = float(a.substr(5))
		elif a.begins_with("--bw="):
			_boss_wait = float(a.substr(5))
		elif a.begins_with("--to="):
			var parts := a.substr(5).split(",")
			_to = Vector2(float(parts[0]), float(parts[1]))
	var main: Node = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if not _no_run:
		_bus("Events").run_requested.emit()
	await process_frame
	if _series > 0.0:
		for i in int(_series):
			if _to != Vector2.INF:
				_walk_towards(main)
			await _wait(1.0)
			_save(_out.replace(".png", "_%d.png" % (i + 1)))
		quit(0)
		return
	# 走到目标点（每帧纠偏），走到 8px 内就停下
	var guard := 0
	while _to != Vector2.INF and guard < 1800:
		guard += 1
		if _walk_towards(main):
			break
		await _wait(1.0 / 60.0)
	await _wait(_secs)
	if _boss or _final:
		_fire_boss()
		await _wait(_boss_wait)
	if _elite:
		_fire_elite(main)
		await _wait(_elite_wait)
	if _rise:
		_fire_rise(main)
		await _wait(_rise_wait)
	if _shop:
		_fire_shop()
		await _wait(0.6)
	_save(_out)
	quit(0)

func _bus(name: String) -> Node:
	return root.get_node(name)

func _wait(secs: float) -> void:
	var frames := maxi(1, int(secs * 60.0))
	for _i in frames:
		await process_frame

# 朝 --to 的目标点走；到了返回 true
func _walk_towards(main: Node) -> bool:
	var p: Vector2 = main.player.global_position
	var d := _to - p
	if d.length() < 10.0:
		main.player.set_move_dir(Vector2.ZERO)
		return true
	main.player.set_move_dir(d.normalized())
	return false

# Boss 登场演出：直接发信号（Fx 层订阅的就是这两个信号）
func _fire_boss() -> void:
	var ev := _bus("Events")
	var w := int(_bus("GameState").wave)
	if _final:
		ev.final_boss_wave.emit(w)
	else:
		ev.boss_wave.emit(w)

# 精英出场：把场上第一只活怪临时标成精英，再发 enemy_spawned
func _fire_elite(main: Node) -> void:
	for e in main.game.world.enemies:
		if e.alive and e.etype != "boss":
			e.elite = true
			_bus("Events").enemy_spawned.emit(e)
			return

# Boss 升起演出：真刷一只 Boss 并把它拽到玩家旁边（保证在屏幕内），看破土动画
func _fire_rise(main: Node) -> void:
	main.game.enemy_system.spawn_boss()
	var world = main.game.world
	for e in world.enemies:
		if e.alive and e.etype == "boss":
			e.global_position = main.player.global_position + Vector2(150.0, -40.0)
			return

# 补给站：塞一组"两对同 key 同等级"的武器（触发金色可合成高亮），再开店。
# 6 格全满 + 2 对可合，正好把"满槽样式 / 空槽样式 / 合成高亮"三种状态里前两种都照到。
func _fire_shop() -> void:
	var gs := _bus("GameState")
	var defs: Dictionary = _bus("Data").weapons
	var keys := defs.keys()
	if keys.size() < 4:
		return
	var plan := [[0, 1], [0, 1], [1, 2], [2, 3], [2, 3], [3, 1]]
	if _shop_n < plan.size():
		plan = plan.slice(0, _shop_n)
	gs.weapons.clear()
	for p in plan:
		var d: Dictionary = defs[keys[p[0]]]
		gs.weapons.append({
			"key": str(keys[p[0]]), "lv": p[1],
			"dmg": int(d.get("dmg", 10)), "cd": float(d.get("cd", 0.5)),
			"color": d.get("color", Color(1, 1, 1)), "buy_cost": 40 * int(p[1]),
		})
	gs.gold = 500
	_bus("Events").weapons_changed.emit(gs.weapons)
	_bus("Events").shop_opened.emit()

func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT " + path)
