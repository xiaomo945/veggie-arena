extends Node2D

# 主场景（阶段 2.1：竞技场 + 一个能跑的萝卜 + 摇杆）
# 后面每加一个功能，只在这里加一行 add_child，不改已有逻辑。

const PlayerScene := preload("res://entities/Player/Player.tscn")
const JoystickScene := preload("res://ui/Joystick/Joystick.tscn")
const GameScene := preload("res://scenes/Game.tscn")
const TitleScene := preload("res://ui/Screens/TitleScreen.gd")
const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")

var player: Node2D
var game: Node
var _rng := RandomNumberGenerator.new()
var _shake := 0.0          # 屏幕震动强度，受伤时拉起、每帧衰减
var _cam: Camera2D         # 跟随玩家的相机（大地图滚动用，不碰 HUD/摇杆）
var _prev_hp := 100
var _floor: Node2D = null  # 厨房战场地面（art/ArenaFloor），切无尽段换砧板可从这里重掷

const FloorScene := preload("res://art/ArenaFloor.gd")

func _ready() -> void:
	var a := Data.arena()
	var cx := float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5
	var cy := float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5

	# 厨房主题战场地面（纯代码绘制）：第一个 add_child = 画在最底层
	var floor_node := FloorScene.new()
	_floor = floor_node
	add_child(floor_node)
	floor_node.setup(Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 1080)), float(a.get("h", 1620))))

	player = PlayerScene.instantiate()
	player.position = Vector2(cx, cy)
	# ⚠️ 主角必须画在敌人/子弹之上：game 节点（含 110 个敌人 + 90 发子弹的池）是在
	#    player 之后 add_child 的，默认按树序绘制会把主角整个埋进怪堆里 ——
	#    "主角看不见了，只能靠感觉"就是这么来的。抬 z_index 让主角永远压在战斗层之上
	#    （HUD/Fx 是 CanvasLayer，不受影响，依旧盖在最上层）。
	player.z_index = 6
	add_child(player)

	# 相机：直接挂在玩家身上（最稳的跟随方式，引擎原生支持，不用每帧手动算位置）
	# 不要再写 root.canvas_transform —— 那会和 stretch 模式冲突，导致镜头完全不动
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 9.0
	player.add_child(_cam)
	_cam.make_current()   # 必须在 add_child 之后调用，否则节点还没进树会报 is_inside_tree 错误

	# 战斗管理器（刷怪/子弹/命中/波次）
	game = GameScene.instantiate()
	game.set_player(player)
	add_child(game)

	add_child(JoystickScene.instantiate())

	# 标题页：盖在最上层，点 START 才开跑（run_requested 由 Main 接管）
	var title = TitleScene.new()
	add_child(title)
	Events.run_requested.connect(_begin_run)
	Events.player_hp_changed.connect(_on_hp_shake)

	queue_redraw()

	# headless 自测：godot --headless -- --sim=30 跑 30 秒战斗并打印数字（怪/击杀/掉血）
	# --char=potato 单独扫一遍（不能塞进 _sim_arg：那里遇 --sim= 就 return，会漏掉 --char）
	for ua in OS.get_cmdline_user_args():
		if ua.begins_with("--char="):
			GameState.set_character(ua.substr(7))
	var secs := _sim_arg()
	if OS.get_cmdline_user_args().has("--sim") or secs > 0.0:
		_begin_run()
		_run_simulation(secs if secs > 0.0 else 30.0)

# 标题页"开始" / 死亡页"再来一局" 都走这里：正式开跑一局
func _begin_run() -> void:
	_prev_hp = GameState.max_hp
	_shake = 0.0
	if game != null and game.has_method("start_run"):
		game.start_run()

# 掉血 → 屏幕震动（受伤反馈，比单纯闪白更"中被撞"）
func _on_hp_shake(hp: int, _m: int) -> void:
	if hp < _prev_hp:
		_shake = 9.0
	_prev_hp = hp

func _process(delta: float) -> void:
	# 相机跟随由"挂在玩家身上"自动完成（引擎原生，拉伸/平滑都管好了，不碰 stretch）
	# 这里只管受击震屏：衰减后作为相机 offset 叠加，不影响跟随
	if _cam != null and is_instance_valid(_cam):
		if _shake > 0.1:
			_shake = maxf(0.0, _shake - delta * 42.0)
			_cam.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		else:
			_cam.offset = Vector2.ZERO

# 逐个敌人报告有没有贴图（缺图会退回手绘几何图形，画面看着"少了点什么"但不崩）
func _enemy_art_report() -> String:
	var parts := []
	for k in Data.enemies.keys():
		var ok := Art.sprite("enemy_" + str(k)) != null
		parts.append("%s=%s" % [str(k), "贴图" if ok else "手绘"])
	return " ".join(parts)

func _sim_arg() -> float:
	# get_cmdline_args() 拿不到（踩过坑，别改回去）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			return float(a.substr(6))
	return 0.0

# 模拟 AI：逃离"附近所有怪的质心"（按距离反比加权）+ 往场地中心靠。
# 只躲最近一只会一头扎进怪群，这版更像真玩家的走位，也能在更密的怪海里活下来。
func _dodge_dir(sense: float = 220.0, jitter: float = 0.22) -> Vector2:
	var a := Data.arena()
	var center := Vector2(float(a.get("x", 0)) + float(a.get("w", 540)) * 0.5,
	                      float(a.get("y", 0)) + float(a.get("h", 900)) * 0.5)
	var pp := player.global_position
	var flee := Vector2.ZERO
	var n := 0
	for e in game.world.enemies:
		if not e.alive:
			continue
		var d := pp.distance_to(e.global_position)
		if d < sense:
			# 越近的怪推得越狠（1/d 加权），方向是"远离它"
			flee += (pp - e.global_position).normalized() / maxf(d, 24.0)
			n += 1
	var to_center := (center - pp).normalized()
	var away := to_center
	if n > 0:
		away = flee.normalized().lerp(to_center, 0.2)
	# 抖动避免被逼到死角后反复横跳卡住
	away = away.rotated(_rng.randf_range(-jitter, jitter))
	return away.limit_length(1.0)

# 自动逛补给站：把"买得起的全买"跑一遍，等于把商店的购买运行期路径也测了。
# 真实游戏里这一步由玩家手指完成，模拟只是代替点击。
func _auto_shop() -> void:
	var cfg := Data.shop_cfg()
	var max_slot := int(cfg.get("max_slot", 6))
	var max_lv := int(cfg.get("max_lv", 4))
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades, max_slot, max_lv,
		[], 0.0, GameState.wave, float(cfg.get("price_inflation", 0.0)))
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

# 有怪进到 70px 内 = 威胁，模拟 AI 这时才按冲刺
var _threats := 0

func _threat_close(dist: float = 70.0) -> bool:
	var pp := player.global_position
	for e in game.world.enemies:
		if e.alive and e.global_position.distance_to(pp) < dist:
			return true
	return false

func _run_simulation(seconds: float) -> void:
	var steps := int(seconds * 60.0)
	var peak_alive := 0
	var survived := 0
	var _trace := OS.get_cmdline_user_args().has("--trace")
	# 模拟 AI 默认"贴脸就冲刺"脱离（和真玩家一样）；--no-dash 关掉看 worst case
	var use_dash := not OS.get_cmdline_user_args().has("--no-dash")
	# --human：模拟"普通玩家"（每 0.2s 才重新判断、视野更窄、12% 失误）；调难度以此档为准
	var human := OS.get_cmdline_user_args().has("--human")
	# --endless：通关后自动点"继续无尽"，把 21 波之后的那段也跑一遍（只续一次）
	var auto_endless := OS.get_cmdline_user_args().has("--endless")
	var dodge := Vector2.ZERO
	var dodge_age := 0
	_threats = 0
	# ⚠️ 模拟只让手动 step 推世界：start_run() 会打开引擎的 _physics_process，
	#    它按真实时间再推一遍，推几帧取决于机器快慢 —— 同一个种子能跑出不同结局
	#    （门禁"一会儿第 2 波、一会儿第 1 波阵亡"就是这么来的）。模拟期间关掉它。
	player.set_physics_process(false)
	game.set_physics_process(false)
	for i in steps:
		# 站着不动（--still）是最坏情况；否则让玩家自动躲，才能看出"会玩能撑多久"
		if OS.get_cmdline_user_args().has("--still"):
			player.set_move_dir(Vector2.ZERO)
		elif human:
			dodge_age -= 1
			if dodge_age <= 0:
				dodge = _dodge_dir(120.0, 0.6)
				if _rng.randf() < 0.12:
					dodge = dodge.rotated(_rng.randf_range(1.2, 2.4))   # 判断失误
				dodge_age = 12
			player.set_move_dir(dodge)
		else:
			player.set_move_dir(_dodge_dir(280.0, 0.12))
		# --dash：怪贴脸时冲刺脱离，验证冲刺实战路径与收益
		if use_dash and (i % 90 == 0 or _threat_close(150.0)):
			_threats += 1
			Events.dash_requested.emit()
		# 模拟 AI 也会用主动技能（冰镇减速 + 毒雾持续伤害）：既验证技能运行期路径，
		# 也贴近"会玩的玩家会放技能"的真实情况——纯走位 AI 在更密的怪海里会被磨死，
		# 而真玩家会靠技能控场。这样网关才代表真实可玩性，而不是逼着把怪量调到"无聊"。
		if _threat_close(170.0) and i % 60 == 0:
			Events.wok_toss_requested.emit()   # 被围时放颠勺清场（有充能才生效）
		if _threat_close(150.0) and i % 30 == 0:
			Events.skill_requested.emit("frost")
		if i % 180 == 0:
			Events.skill_requested.emit("poison")
		player.step(1.0 / 60.0)
		game.step(1.0 / 60.0)
		# 波次结束：自动逛补给站（买得起的全买，验证购买运行期路径不崩），再开下一波
		if game.is_paused():
			_auto_shop()
			Events.shop_closed.emit()
		var n := int(game.alive_enemy_count())
		if n > peak_alive:
			peak_alive = n
		survived = i + 1
		if _trace and i >= 200 and i < 215:
			var tb = null
			for b in game.world.bullets:
				if b.active and b.life < 0.05:
					tb = b
					break
			if tb == null:
				continue
			var ne := Vector2.ZERO
			var nd := 99999.0
			for e in game.world.enemies:
				if e.alive:
					var dd: float = tb.global_position.distance_to(e.global_position)
					if dd < nd:
						nd = dd
						ne = e.global_position
			print("   弹 %s dir=%s r=%.0f life=%.2f | 最近敌 %s d=%.1f" % [
				tb.global_position, tb.dir, tb.radius, tb.life, ne, nd])
		if (i + 1) % 60 == 0 and OS.get_cmdline_user_args().has("--verbose"):
			var nb := 0
			for b in game.world.bullets:
				if b.active:
					nb += 1
			print("  [%.0fs] 敌%d 弹%d 射%d 中%d 血%d" % [
				float(i + 1) / 60.0, int(game.alive_enemy_count()), nb,
				game.world.shots_fired, game.world.hits_landed, GameState.hp])
		if not GameState.running:
			if auto_endless and GameState.won and not GameState.endless:
				Events.endless_continue_requested.emit()
				continue
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
		game.world.shots_fired, game.world.hits_landed,
		100.0 * float(game.world.hits_landed) / maxf(1.0, float(game.world.shots_fired))])
	print("  金币        : 持有 %d / 累计捡到 %d / 地上待捡 %d" % [
		GameState.gold, game.world.gold_picked, game.ground_gold()])
	print("  玩家血量    : %d / %d" % [GameState.hp, GameState.max_hp])
	print("  挨打        : %d 次 / 累计 %d 伤害（净掉血看上一条）" % [
		int(player.hits_taken), int(player.damage_taken)])
	var ending := "时间到，仍存活"
	if GameState.won:
		ending = "通关（打满 %d 波）" % int(Data.wave_cfg().get("total", 20))
	elif not GameState.running:
		ending = "阵亡（第 %d 波）" % GameState.wave
	print("  结局        : %s" % ending)
	print("  冲刺次数    : %d（威胁帧 %d）" % [int(player.dash_count), _threats])
	print("  角色        : %s（贴图 %s）" % [
		GameState.character,
		"已装载" if Art.sprite("char_" + GameState.character) != null else "缺图兜底"])
	print("  美术装载    : 玩家=%s 武器图标=%s" % [
		"贴图" if Art.sprite("player") != null else "手绘兜底",
		"贴图" if Art.icon("weapon_pistol") != null else "色点兜底"])
	# 逐个敌人点名：任何一种缺图，这里会显示"手绘"，一眼看出漏了哪张
	print("  敌人贴图    : %s" % _enemy_art_report())
	# 模拟结束写一次存档（真实游戏里由阵亡/通关触发），用来验证存档链路可写
	SaveMgr.record_run(GameState.wave, GameState.kills, GameState.gold,
		GameState.run_score(), false)
	print("  存档        : runs=%d best=%d wave=%d 解锁武器=%d/12 角色=%s" % [
		SaveMgr.total_runs(), SaveMgr.best_score(), SaveMgr.best_wave(),
		SaveMgr.unlocked_weapons().size(), SaveMgr.last_character()])
	get_tree().quit(0)
