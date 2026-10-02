extends Node2D

# 战斗协调器：生命周期、暂停、波次推进、金币磁吸、刷怪节奏。
# 重逻辑（敌人移动/子弹结算/颠勺）在 scenes/EnemySystem.gd；共享状态在 scenes/BattleWorld.gd。

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
# 战斗倍率（快进）：每物理帧多跑一次世界步进，而不是改 time_scale
var _sim_speed := 1

func _ready() -> void:
	world.rng.randomize()
	var a := Data.arena()
	world.arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	# 战场地面 art/ArenaFloor（砧板+钢边+污渍+远景）替换纯黑背景；show_behind_parent 垫最底
	var floor_node := Node2D.new()
	floor_node.set_script(preload("res://art/ArenaFloor.gd"))
	floor_node.show_behind_parent = true
	add_child(floor_node)
	floor_node.setup(world.arena)
	world.pickups = PickupFieldScene.instantiate(); add_child(world.pickups)
	_build_pools()
	# 战斗子系统：接手刷怪 / 敌人移动 / 子弹命中 / 颠勺（状态通过 world 共享）
	enemy_system = EnemySystem.new()
	enemy_system.world = world
	add_child(enemy_system)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.melee_swung.connect(_on_melee_swung)
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
	Events.endless_continue_requested.connect(_on_endless_continue)

# 注入玩家节点：同时挂到 world 上，EnemySystem 才拿得到（只留这一个入口）
func set_player(p: Node2D) -> void:
	player = p
	world.player = p

func is_paused() -> bool:
	return _paused

func step(delta: float) -> void:
	_physics_process(delta)

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
	_sim_speed = 1
	Events.fast_forward_toggled.emit(false)
	set_physics_process(true)
	_spawn_wave_burst()
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
	# 已通关后继续无尽：胜利记过了，这里只刷新最佳波次/分数（一局不算两次）
	if GameState.won:
		SaveMgr.record_endless(GameState.wave, GameState.run_score())
		return
	_finish_run(false)

# 通关页"继续无尽"：恢复战斗并推进到 total+1 波（复用开波流程，场上残敌留着）
func _on_endless_continue() -> void:
	GameState.endless = true
	GameState.running = true
	GameState.paused = false
	set_physics_process(true)
	GameState.next_wave()
	_begin_wave()
	Events.endless_started.emit(GameState.wave)

func _on_run_won() -> void:
	set_physics_process(false)
	_finish_run(true)

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

func _finish_run(won: bool) -> void:
	GameState.won = won
	SaveMgr.record_run(GameState.wave, GameState.kills, GameState.gold,
		GameState.run_score(), won)
	# Steam 统计/成就（未挂载 GodotSteam 时自动 no-op，不影响游戏）
	Steam.record_run(GameState.wave, GameState.kills, GameState.gold, won)

func ground_gold() -> int:
	return world.ground_gold()

func alive_enemy_count() -> int:
	return world.alive_enemy_count()

# 每波开局先撒一批怪（数量 = spawn_burst + 波号，不超 max_alive）
func _spawn_wave_burst() -> void:
	var cfg := Data.spawn_cfg()
	var n := int(cfg.get("spawn_burst", 14)) + GameState.wave
	var cap := int(cfg.get("max_alive", 88))
	for _i in n:
		if world.alive_enemy_count() >= cap:
			break
		enemy_system.spawn_one()

func _physics_process(delta: float) -> void:
	if player == null or not GameState.running or _paused:
		return
	# 快进：每物理帧把世界步进多次（UI/补间/震屏按真实时间，不受影响）
	for _i in _sim_speed:
		_step_world(delta)

func _step_world(delta: float) -> void:
	GameState.tick_wave(delta)
	# 锅气自然衰减：停手不刷怪就凉下来，逼你保持进攻节奏
	GameState.decay_wok(delta)
	GameState.tick_buff(delta)
	# 颠勺冲击波动画推进
	if world.shock_t >= 0.0:
		world.shock_t += delta

	# 刷怪：Boss 波降低普通刷怪速率，把注意力留给首领
	var cfg := Data.spawn_cfg()
	var rate := Spawner.spawn_rate(GameState.wave, cfg,
		Run.endless_over(GameState.wave, Data.wave_cfg()), Data.endless_cfg())
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

	# 开火（武器自动瞄准最近目标；近战在此走 melee_swung 漏斗）
	if player.has_method("auto_fire"):
		player.auto_fire(world.edata, delta)

	# 子弹追踪：飞行中轻微朝当前最近存活怪转向
	enemy_system.home_bullets(delta)

	for b in world.bullets:
		b.advance(delta)

	# 命中结算
	enemy_system.resolve_hits()

	# 金币磁吸：走过去自动收钱，是本作最直接的走位正反馈
	_collect_pickups(delta)

	if GameState.wave_finished():
		_end_wave()

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
	# 波末清场：地上没捡的钱自动入袋，但按 wave_end_loss 扣减（fullauto=0 损耗）
	if world.pickups != null:
		var swept: int = world.pickups.collect_all(player.global_position)
		if swept > 0:
			world.gold_picked += swept
			var kept: int = int(float(swept) * (1.0 - GameState.gold_sweep_loss()))
			if kept > 0:
				GameState.add_gold(kept)
	GameState.add_gold(Economy.wave_bonus(GameState.wave, Data.wave_cfg()))
	GameState.heal_percent(float(Data.wave_cfg().get("heal_percent", 0.12)))
	# 波末回血（wave_heal）：固定值，与上面的百分比回血叠加，是"续航流"的核心
	var wh := int(round(GameState.stat_value("wave_heal")))
	if wh > 0:
		GameState.heal(wh)
	# 过关庆祝（卡通彩纸）：在开补给站之前发，Fx 层画在商店之上所以看得见
	Events.wave_ended.emit(GameState.wave, player.global_position)
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
	_begin_wave()

# 开一波：Boss 波开局刷首领并通知 HUD 弹横幅（终局波发专属信号），再撒一批怪
func _begin_wave() -> void:
	if enemy_system.boss_wave():
		if enemy_system.final_wave():
			Events.final_boss_wave.emit(GameState.wave)
		else:
			Events.boss_wave.emit(GameState.wave)
		enemy_system.spawn_boss()
	_spawn_wave_burst()

func _on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color, key: String) -> void:
	enemy_system.on_weapon_fired(pos, dir, stats, c, key)

func _on_melee_swung(origin: Vector2, dir: Vector2, reach: float, half_arc: float,
		dmg: float, crit: bool, knockback: float, c: Color, key: String, level: int) -> void:
	enemy_system.on_melee_swung(origin, dir, reach, half_arc, dmg, crit, knockback, c, key, level)

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
