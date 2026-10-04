extends SceneTree

# 真渲染截图工具（美术目检专用）
#
# headless 跑不出任何像素，美术问题只能靠真渲染截图看。跑法：
#   xvfb-run -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/shot.gd -- \
#       --t=6 --out=/tmp/shot.png
#
# 参数：--t=秒数(默认6) --out=路径 --boss/--final(Boss演出) --elite(精英出场)
#   --shop(合成高亮) --sets(套装条) --hud[=N](行为符文) --stats(属性页)
#   --pause --wok(颠勺) --series=秒(连拍) --to=x,y(走位) --rise(Boss破土) --no-run
#
# ⚠️ --script 模式不注册 autoload，且它是编译期标识符（运行时 add_child 也救不了，
#    会 Compile Error）。所以统一走 root.get_node("Events") 运行时取节点。

var _out := "/tmp/va_shot.png"
var _secs := 6.0
var _series := 0.0
var _to := Vector2.INF
var _boss_wait := 0.45
var _elite_wait := 0.3
var _rise_wait := 0.42
# 开关旗标一行一个太占行，合并写（都是互不依赖的 bool）
var _boss := false; var _final := false; var _elite := false; var _rise := false
var _shop := false; var _shop_n := 6; var _hud := false; var _hud_n := 6
var _stats := false; var _sets := false; var _pause := false; var _no_run := false
var _wok := false

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
		elif a == "--hud":
			_hud = true
		elif a.begins_with("--hud="):
			_hud = true
			_hud_n = maxi(0, int(a.substr(6)))
		elif a == "--no-run":
			_no_run = true
		elif a == "--sets":
			_sets = true
		elif a == "--stats":
			_stats = true
		elif a == "--pause":
			_pause = true
		elif a == "--wok":
			_wok = true
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
	if _hud:
		_fire_hud()
		await _wait(0.5)
	if _shop:
		_fire_shop()
		await _wait(0.6)
	if _sets:
		_fire_sets()
		await _wait(0.6)
	if _stats:
		_fire_stats()
		await _wait(0.5)
		_dump_labels(_stats_node)
	if _pause:
		_bus("Events").run_paused.emit(true)
		await _wait(0.4)
	_save(_out)
	quit(0)
	if _wok:
		_fire_wok(main)
		await _wait(0.06)
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

# Boss 登场演出：直接发信号（Fx 层订阅的就是这两个）
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

# Boss 升起演出：真刷一只 Boss 拽到玩家旁边（保证在屏幕内），看破土动画
func _fire_rise(main: Node) -> void:
	main.game.enemy_system.spawn_boss()
	var world = main.game.world
	for e in world.enemies:
		if e.alive and e.etype == "boss":
			e.global_position = main.player.global_position + Vector2(150.0, -40.0)
			return

# 武器槽目检：七种打法各来一把、等级错开（1~4），看行为符文与等级点数。
func _fire_hud() -> void:
	var gs := _bus("GameState")
	var plan := [["pistol", 1], ["cleaver", 2], ["microwave", 3], ["pan", 2],
		["staff", 4], ["baking_tray", 1], ["rocket", 3]]
	if _hud_n < plan.size():
		plan = plan.slice(0, _hud_n)
	gs.weapons.clear()
	for p in plan:
		gs.weapons.append({"key": str(p[0]), "lv": int(p[1])})
	_bus("Events").weapons_changed.emit(gs.weapons)

# 补给站：塞"两对同 key 同等级"武器（触发金色可合成高亮）再开店。
func _fire_shop() -> void:
	var defs: Dictionary = _bus("Data").weapons
	var keys := defs.keys()
	if keys.size() < 4:
		return
	var plan := [[0, 1], [0, 1], [1, 2], [2, 3], [2, 3], [3, 1]]
	if _shop_n < plan.size():
		plan = plan.slice(0, _shop_n)
	var pairs: Array = []
	for p in plan:
		pairs.append([keys[p[0]], p[1]])
	_grant_and_open(defs, pairs)

# 套装条目检：刀工 3 件（差 1 到第 2 档）+ 枪械 2 件（已激活），看套装条与卡片竖条。
func _fire_sets() -> void:
	var defs: Dictionary = _bus("Data").weapons
	var want := {"blade": 3, "gun": 2}
	var pairs: Array = []
	for k in defs:
		var tags: Array = (defs[k] as Dictionary).get("tags", []) as Array
		var t := str(tags[0]) if not tags.is_empty() else ""
		if t == "" or not want.has(t) or int(want[t]) <= 0:
			continue
		want[t] = int(want[t]) - 1
		pairs.append([k, 1 + (pairs.size() % 2)])
	_grant_and_open(defs, pairs)

# 把 [key,lv] 塞进背包（补全 dmg/cd/color/buy_cost），发 weapons_changed 并开店
func _grant_and_open(defs: Dictionary, pairs: Array) -> void:
	var gs := _bus("GameState")
	gs.weapons.clear()
	for p in pairs:
		var d: Dictionary = defs[p[0]]
		gs.weapons.append({"key": str(p[0]), "lv": int(p[1]),
			"dmg": int(d.get("dmg", 10)), "cd": float(d.get("cd", 0.5)),
			"color": d.get("color", Color(1, 1, 1)), "buy_cost": 40 * int(p[1])})
	gs.gold = 500
	_bus("Events").weapons_changed.emit(gs.weapons)
	_bus("Events").shop_opened.emit()

# 属性页目检：每个 stat 的第一个升级 key 各买 1 层，看亮/灰样式与滚动区溢出。
func _fire_stats() -> void:
	var gs := _bus("GameState")
	var data: Node = _bus("Data")
	var ups: Dictionary = data.upgrades
	var first_key: Dictionary = {}   # stat -> 第一个提供它的升级 key
	for k in ups:
		var u: Dictionary = ups[k] as Dictionary
		var st: String = str(u.get("stat", ""))
		if st != "" and not first_key.has(st):
			first_key[st] = k
		if u.has("stats"):
			for sk in u["stats"]:
				var s2 := str(sk)
				if not first_key.has(s2):
					first_key[s2] = k
	var ups_set: Dictionary = {}
	for st in first_key:
		ups_set[first_key[st]] = 1
	gs.upgrades = ups_set
	gs.max_hp = 137
	var ss: Node = load("res://ui/Screens/StatsScreen.gd").new()
	root.add_child(ss)
	ss.show_menu()
	_stats_node = ss

# 颠勺爆炸目检：充满锅气真触发一次，看爆炸是否钉在玩家位置。
func _fire_wok(main: Node) -> void:
	var gs := _bus("GameState")
	gs.add_wok(100000.0)
	_bus("Events").wok_toss_requested.emit()

var _stats_node: Node = null

# DEBUG：遍历打印非空 Label 的最终位置（布局排错用）
func _dump_labels(from: Node) -> void:
	if from == null:
		return
	var stack: Array = [from]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label:
			var l := n as Label
			if l.text != "":
				print("LBL '", l.text, "' gpos=", l.global_position, " size=", l.size)

func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT " + path)
