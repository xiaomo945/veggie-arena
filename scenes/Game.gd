extends Node2D

# 战斗协调器：生命周期、暂停、波次推进、金币磁吸、刷怪节奏。
# 敌人移动 / 子弹命中结算 / 颠勺等重逻辑在 scenes/EnemySystem.gd（本节点的子节点）。
#
# 【状态放哪】本节点只留"场景编排"相关的状态（player 引用、_paused、刷怪累计）。
#   敌人池 / 子弹池 / 随机源 / 竞技场 / 每帧暂存数组 / 诊断计数器全部移到
#   scenes/BattleWorld.gd —— 那是 EnemySystem 也要用的一份共享契约。
#   跨模块读写 game._xxx 是本项目曾经的头号耦合源，现已清零。

const BulletScene := preload("res://entities/Bullet/Bullet.tscn")
const EnemyScene := preload("res://entities/Enemy/Enemy.tscn")
const PickupFieldScene := preload("res://entities/Pickup/PickupField.tscn")
const HUDScene := preload("res://ui/HUD/HUD.tscn")
const FxScene := preload("res://ui/Fx/FxLayer.tscn")
const ShopScene := preload("res://ui/Shop/Shop.tscn")
const DeathScene := preload("res://ui/Screens/DeathScreen.tscn")
const VictoryScene := preload("res://ui/Screens/VictoryScreen.tscn")
const PauseScene := preload("res://ui/Screens/PauseScreen.tscn")
const Economy := preload("res://core/Economy.gd")
const Spawner := preload("res://core/Spawner.gd")
const Run := preload("res://core/Run.gd")
const EnemySystem := preload("res://scenes/EnemySystem.gd")
const BattleWorld := preload("res://scenes/BattleWorld.gd")

# 共享战斗状态（池 / rng / 竞技场 / 诊断计数），EnemySystem 拿的是同一个对象
var world := BattleWorld.new()
var player: Node2D = null
var enemy_system: Node = null          # 战斗子系统（刷怪/敌人/子弹/颠勺），_ready 里注入
var _paused := false
var _spawn_acc := 0.0

func _ready() -> void:
	world.rng.randomize()
	var a := Data.arena()
	world.arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	world.pickups = PickupFieldScene.instantiate()
	add_child(world.pickups)
	_build_pools()
	# 战斗子系统：接手刷怪 / 敌人移动 / 子弹命中 / 颠勺（状态通过 world 共享）
	enemy_system = EnemySystem.new()
	enemy_system.world = world
	add_child(enemy_system)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.player_died.connect(_on_player_died)
	Events.run_won.connect(_on_run_won)
	# ⚠️ 不再这里 reset —— 一局由标题页"开始"或死亡页"再来一局"触发 start_run()
	# （reset 会把 running 置 true，若提前调了，标题页还没点就开始刷怪了）
	add_child(HUDScene.instantiate())
	add_child(FxScene.instantiate())
	add_child(ShopScene.instantiate())
	add_child(DeathScene.instantiate())
	add_child(VictoryScene.instantiate())
	add_child(PauseScene.instantiate())
	Events.shop_closed.connect(_on_shop_closed)
	Events.pause_requested.connect(_on_pause_requested)
	Events.resume_requested.connect(_on_resume_requested)
	Events.quit_to_title_requested.connect(_on_quit_to_title)
	Events.wok_toss_requested.connect(_on_wok_toss_requested)

# 注入玩家节点：同时挂到 world 上，让 EnemySystem 也拿得到（只有这一个入口，
# 不会出现"Game.player 换了、EnemySystem 还指着旧的"）
func set_player(p: Node2D) -> void:
	player = p
	world.player = p

func is_paused() -> bool:
	return _paused

# 手动推进一帧物理（模拟 / 调试用；正常游戏由引擎调 _physics_process）
func step(delta: float) -> void:
	_physics_process(delta)

# 由标题页/死亡页的 run_requested 触发。回收场上所有敌人/子弹，重置状态，正式开跑。
func start_run() -> void:
	for e in world.enemies:
		e.recycle()
	for b in world.bullets:
		b.recycle()
	if world.pickups != null:
		world.pickups.clear()
	world.reset_run()
	_spawn_acc = 0.0
	GameState.reset()
	_paused = false
	GameState.paused = false
	set_physics_process(true)
	Events.run_started.emit()

func _build_pools() -> void:
	for i in BattleWorld.MAX_BULLETS:
		var b = BulletScene.instantiate()
		b.recycle()
		add_child(b)
		world.bullets.append(b)
	for i in BattleWorld.MAX_ENEMIES:
		var e = EnemyScene.instantiate()
		e.recycle()
		add_child(e)
		world.enemies.append(e)

func _on_player_died() -> void:
	set_physics_process(false)
	_finish_run(false)

# 通关（撑过最后一波）
func _on_run_won() -> void:
	set_physics_process(false)
	_finish_run(true)

# ---- 暂停（HUD 暂停键触发，复用现有 _paused 机制，不暂停整棵树以免按钮失灵）----
func _on_pause_requested() -> void:
	if not GameState.running or _paused:
		return
	_paused = true
	GameState.paused = true
	Events.run_paused.emit(true)

func _on_resume_requested() -> void:
	_paused = false
	GameState.paused = false
	Events.run_paused.emit(false)

# 退出到标题：放弃本局（不写存档），回收场上实体，交还控制权给 TitleScreen
func _on_quit_to_title() -> void:
	set_physics_process(false)
	_paused = false
	GameState.paused = false
	GameState.running = false
	for e in world.enemies:
		e.recycle()
	for b in world.bullets:
		b.recycle()
	if world.pickups != null:
		world.pickups.clear()
	Events.run_paused.emit(false)

# 一局结束的统一收尾：把成绩写进存档（解锁判定也在这里触发）
func _finish_run(won: bool) -> void:
	GameState.won = won
	SaveMgr.record_run(GameState.wave, GameState.kills, GameState.gold,
		GameState.run_score(), won)
	# Steam 统计/成就（未挂载 GodotSteam 时自动 no-op，不影响游戏）
	Steam.record_run(GameState.wave, GameState.kills, GameState.gold, won)

# 地上还没被捡走的金币面额（诊断/HUD 用）
func ground_gold() -> int:
	return world.ground_gold()

func alive_enemy_count() -> int:
	return world.alive_enemy_count()

# ---- 主循环 ----
func _physics_process(delta: float) -> void:
	if player == null or not GameState.running or _paused:
		return
	GameState.tick_wave(delta)
	# 锅气自然衰减：停手不刷怪就凉下来，逼你保持进攻节奏
	GameState.decay_wok(delta)
	# 颠勺冲击波动画推进
	if world.shock_t >= 0.0:
		world.shock_t += delta

	# 刷怪：Boss 波降低普通刷怪速率，把注意力留给首领
	var cfg := Data.spawn_cfg()
	var rate := Spawner.spawn_rate(GameState.wave, cfg)
	if enemy_system.boss_wave():
		rate *= float(cfg.get("boss_rate_mult", 0.55))
	_spawn_acc += rate * delta
	var cap := int(cfg.get("max_alive", 88))
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if world.alive_enemy_count() < cap:
			enemy_system.spawn_one()

	# 敌人移动 + 互相分离 + 不要贴玩家脸
	enemy_system.update_enemies(delta)

	# 先收集敌人数组（含本帧位置/速度），供开火与子弹追踪共用
	enemy_system.collect_enemy_data()

	# 开火（武器自动瞄准最近目标）
	if player.has_method("auto_fire"):
		player.auto_fire(world.edata, delta)

	# 子弹追踪：飞行中轻微朝当前最近存活怪转向
	enemy_system.home_bullets(delta)

	# 子弹飞行
	for b in world.bullets:
		b.advance(delta)

	# 命中结算
	enemy_system.resolve_hits()

	# 金币磁吸：走过去自动收钱，是本作最直接的走位正反馈
	_collect_pickups(delta)

	# 波次推进：暂停 → 开补给站 → 玩家买完再继续
	if GameState.wave_finished():
		_end_wave()

# 每帧推进金币磁吸，把吃到的钱记进 GameState
func _collect_pickups(delta: float) -> void:
	if world.pickups == null:
		return
	# 磁吸半径用真实值（含自动拾取/拾取范围强化），不再把 pickup_pct 当半径传（旧 bug：半径≈0）
	var got: int = world.pickups.update(delta, player.global_position,
		GameState.pickup_magnet(), false)
	if got > 0:
		world.gold_picked += got
		GameState.add_gold(got)

func _end_wave() -> void:
	# 波末清场：地上没捡的钱自动入袋，但按损耗比例扣减（"部分损耗落袋"）。
	# 全屏自动拾取(fullauto)=0 损耗，自动拾取减半，其余按 wave_end_loss。
	if world.pickups != null:
		var swept: int = world.pickups.collect_all(player.global_position)
		if swept > 0:
			world.gold_picked += swept
			var kept: int = int(float(swept) * (1.0 - GameState.gold_sweep_loss()))
			if kept > 0:
				GameState.add_gold(kept)
	GameState.add_gold(Economy.wave_bonus(GameState.wave, Data.wave_cfg()))
	GameState.heal_percent(float(Data.wave_cfg().get("heal_percent", 0.12)))
	# 最后一波结束 = 通关：停跑并弹胜利页，不再开补给站
	if GameState.is_last_wave():
		GameState.running = false
		Events.run_won.emit()
		return
	_paused = true
	Events.shop_opened.emit()

func _on_shop_closed() -> void:
	_paused = false
	GameState.next_wave()
	# 新的波次若是 Boss 波，开局刷一只首领并通知 HUD 弹横幅
	if enemy_system.boss_wave():
		Events.boss_wave.emit(GameState.wave)
		enemy_system.spawn_boss()

func _on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color) -> void:
	enemy_system.on_weapon_fired(pos, dir, stats, c)

# ---- 颠勺（满锅气终极）----
func _on_wok_toss_requested() -> void:
	enemy_system.on_wok_toss()

func _draw() -> void:
	if world.shock_t < 0.0 or world.shock_t > world.shock_dur:
		return
	var k := clampf(world.shock_t / world.shock_dur, 0.0, 1.0)
	var r := world.shock_max * k
	var a := 1.0 - k
	draw_arc(world.shock_pos, r, 0.0, TAU, 36, Color(1.0, 0.78, 0.42, a), 7.0, true)
	draw_arc(world.shock_pos, r * 0.7, 0.0, TAU, 36, Color(1.0, 0.92, 0.7, a * 0.7), 4.0, true)
