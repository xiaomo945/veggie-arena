extends Node2D

# 主场景（阶段 2.1：竞技场 + 一个能跑的萝卜 + 摇杆）
# 后面每加一个功能，只在这里加一行 add_child，不改已有逻辑。

const PlayerScene := preload("res://entities/Player/Player.tscn")
const JoystickScene := preload("res://ui/Joystick/Joystick.tscn")
const GameScene := preload("res://scenes/Game.tscn")
const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")

var player: Node2D
var game: Node
var _rng := RandomNumberGenerator.new()

const BG := Color(0.06, 0.07, 0.10)
const FLOOR := Color(0.11, 0.13, 0.17)
const GRID := Color(1.0, 1.0, 1.0, 0.035)
const BORDER := Color(0.45, 0.75, 0.40, 0.55)

func _ready() -> void:
	var a := Data.arena()
	var cx := float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5
	var cy := float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5

	player = PlayerScene.instantiate()
	player.position = Vector2(cx, cy)
	add_child(player)

	# 战斗管理器（刷怪/子弹/命中/波次）
	game = GameScene.instantiate()
	game.player = player
	add_child(game)

	add_child(JoystickScene.instantiate())
	queue_redraw()

	# headless 自测：godot --headless -- --sim=30 会跑 30 秒战斗并打印结果
	# 画面看不到，就用数字确认"怪刷出来了、被打死了、玩家会掉血"
	var secs := _sim_arg()
	if OS.get_cmdline_user_args().has("--sim") or secs > 0.0:
		_run_simulation(secs if secs > 0.0 else 30.0)

func _sim_arg() -> float:
	# 注意：Godot 4 里 "--" 之后的参数只在 get_cmdline_user_args() 里，
	# get_cmdline_args() 拿不到（踩过坑，别改回去）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			return float(a.substr(6))
	return 0.0

# 模拟用 AI：远离最近的敌人，同时往场地中心靠，避免被逼到墙角定死。
# 真实游戏里这由玩家手指完成，模拟只能用算法代替。
func _dodge_dir() -> Vector2:
	var a := Data.arena()
	var center := Vector2(float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5,
	                      float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5)
	var pp := player.global_position
	var nearest: Node2D = null
	var nd := 99999.0
	for e in game._enemies:
		if not e.alive:
			continue
		var d := pp.distance_to(e.global_position)
		if d < nd:
			nd = d
			nearest = e
	var to_center := (center - pp).normalized()
	var away := to_center
	if nearest != null and nd < 160.0:
		away = (pp - nearest.global_position).normalized().lerp(to_center, 0.25)
	# 抖动避免被逼到死角后反复横跳卡住
	away = away.rotated(randf_range(-0.35, 0.35))
	return away.limit_length(1.0)

# 自动逛补给站：把"买得起的全买"跑一遍，等于把商店的购买运行期路径也测了。
# 真实游戏里这一步由玩家手指完成，模拟只是代替点击。
func _auto_shop() -> void:
	var cfg := Data.shop_cfg()
	var max_slot := int(cfg.get("max_slot", 6))
	var max_lv := int(cfg.get("max_lv", 4))
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades, max_slot, max_lv)
	var offers := Economy.roll_offers(pool, int(cfg.get("offer_count", 4)), _rng)
	for o in offers:
		var cost := int(o.get("cost", 999))
		if not Economy.can_buy(GameState.gold, cost):
			continue
		if str(o.get("kind", "")) == "weapon":
			var ok := Inventory.merge_or_add(GameState.weapons, o, max_slot, max_lv, Data.combat_cfg())
			if ok:
				Events.weapons_changed.emit(GameState.weapons)
			else:
				continue
		else:
			GameState.buy_upgrade(str(o.get("key", "")))
		GameState.spend_gold(cost)

func _run_simulation(seconds: float) -> void:
	var steps := int(seconds * 60.0)
	var peak_alive := 0
	var survived := 0
	var _trace := OS.get_cmdline_user_args().has("--trace")
	for i in steps:
		# 站着不动是最坏情况；模拟里让玩家自动躲，才能看出"会玩的话能撑多久"
		player.set_move_dir(_dodge_dir())
		player._physics_process(1.0 / 60.0)
		game._physics_process(1.0 / 60.0)
		# 波次结束：自动逛补给站（买得起的全买，验证购买运行期路径不崩），再开下一波
		if game._paused:
			_auto_shop()
			Events.shop_closed.emit()
		var n := int(game.alive_enemy_count())
		if n > peak_alive:
			peak_alive = n
		survived = i + 1
		if _trace and i >= 200 and i < 215:
			var tb = null
			for b in game._bullets:
				if b.active and b.life < 0.05:
					tb = b
					break
			if tb == null:
				continue
			var ne := Vector2.ZERO
			var nd := 99999.0
			for e in game._enemies:
				if e.alive:
					var dd: float = tb.global_position.distance_to(e.global_position)
					if dd < nd:
						nd = dd
						ne = e.global_position
			print("   弹 %s dir=%s r=%.0f life=%.2f | 最近敌 %s d=%.1f" % [
				tb.global_position, tb.dir, tb.radius, tb.life, ne, nd])
		if (i + 1) % 60 == 0 and OS.get_cmdline_user_args().has("--verbose"):
			var nb := 0
			for b in game._bullets:
				if b.active:
					nb += 1
			print("  [%.0fs] 敌%d 弹%d 射%d 中%d 血%d" % [
				float(i + 1) / 60.0, int(game.alive_enemy_count()), nb,
				game.shots_fired, game.hits_landed, GameState.hp])
		if not GameState.running:
			break
	print("")
	print("=== 战斗模拟 %.0f 秒（模拟 AI 自动跑位躲怪）===" % seconds)
	print("  存活时长    : %.1f 秒" % (float(survived) / 60.0))
	print("  波次        : %d（波内 %.1f / %.0f 秒）" % [
		GameState.wave, GameState.elapsed_in_wave,
		float(Data.wave_cfg().get("length", 20))])
	print("  场上敌人峰值: %d" % peak_alive)
	print("  累计击杀    : %d" % GameState.kills)
	print("  开火/命中   : %d / %d（命中率 %.0f%%）" % [
		game.shots_fired, game.hits_landed,
		100.0 * float(game.hits_landed) / maxf(1.0, float(game.shots_fired))])
	print("  金币        : %d" % GameState.gold)
	print("  玩家血量    : %d / %d" % [GameState.hp, GameState.max_hp])
	print("  玩家状态    : %s" % ("存活" if GameState.running else "已死亡"))
	print("  美术装载    : 玩家=%s 敌人=%s" % [
		"贴图" if Art.sprite("player") != null else "手绘兜底",
		"贴图" if Art.sprite("enemy_grunt") != null else "手绘兜底"])
	get_tree().quit(0)

func _draw() -> void:
	var a := Data.arena()
	var r := Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	draw_rect(Rect2(0, 0, 540, 900), BG)
	draw_rect(r, FLOOR)
	# 地砖网格：给移动一个参照物，否则看不出自己在动
	var step := 60.0
	var x := r.position.x
	while x <= r.position.x + r.size.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y), GRID, 1.0)
		x += step
	var y := r.position.y
	while y <= r.position.y + r.size.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), GRID, 1.0)
		y += step
	draw_rect(r, BORDER, false, 2.0)
