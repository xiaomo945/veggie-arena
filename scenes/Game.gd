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
const WaveDirector := preload("res://scenes/WaveDirector.gd")
const SkillSystem := preload("res://scenes/SkillSystem.gd")
const StatsFlowScript := preload("res://scenes/StatsFlow.gd")

# 共享战斗状态（池 / rng / 竞技场 / 诊断计数），EnemySystem 拿的是同一个对象
var world := BattleWorld.new()
var player: Node2D = null
var enemy_system: Node = null          # 战斗子系统（刷怪/敌人/子弹/颠勺），_ready 里注入
var wave_dir: Node = null              # 波次流程子协调器（见 scenes/WaveDirector.gd）
var skill_sys = null                    # 主动技能系统（冰镇/毒雾…，见 scenes/SkillSystem.gd）
var _stats_flow: Node = null             # 属性页流程协调器（D3-2，见 scenes/StatsFlow.gd）
var _paused := false
var _spawn_acc := 0.0
# 战斗倍率（快进）：每物理帧多跑一次世界步进，而不是改 time_scale
var _sim_speed := 1

func _ready() -> void:
	if OS.has_environment("SIM_SEED"):
		world.rng.seed = int(OS.get_environment("SIM_SEED"))
	else:
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
	# 厨房氛围粒子（蒸汽/火星/油星）垫在地面之上、战斗之下，给满屏割草一点"活气"
	var ambient := Node2D.new()
	ambient.set_script(preload("res://art/AmbientKitchen.gd"))
	ambient.show_behind_parent = true
	add_child(ambient)
	ambient.setup(world.arena)
	world.pickups = PickupFieldScene.instantiate(); add_child(world.pickups)
	_build_pools()
	# 战斗子系统：接手刷怪 / 敌人移动 / 子弹命中 / 颠勺（状态通过 world 共享）
	enemy_system = EnemySystem.new()
	enemy_system.world = world
	add_child(enemy_system)
	# 波次流程子协调器（撒怪/开波/结算/下一波），拆出避免 Game 超 300 行红线
	wave_dir = WaveDirector.new()
	wave_dir.setup(self, world, enemy_system)
	add_child(wave_dir)
	# 主动技能系统（冰镇/毒雾…）：挂在 Game 下，与 WaveDirector 同级
	skill_sys = SkillSystem.new()
	skill_sys.setup(Data.skills_cfg(), world)
	# 伤害型技能（震地/穿透/尖刺…）必须走 EnemySystem 的漏斗，否则击杀不计、不掉钱
	skill_sys.damage_fn = enemy_system.damage_enemy
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.melee_swung.connect(_on_melee_swung)
	Events.player_died.connect(_on_player_died)
	Events.run_won.connect(_on_run_won)
	# ⚠️ 不在这里 reset：一局由标题页"开始"/死亡页"再来一局"触发 start_run()
	var hud := HUDScene.instantiate()
	add_child(hud)
	add_child(FxScene.instantiate())
	add_child(ShopScene.instantiate())
	add_child(DeathScene.instantiate())
	add_child(VictoryScene.instantiate())
	var pause := PauseScene.instantiate()
	add_child(pause)
	# D3-2：属性页单例（layer=36）由 StatsFlow 持有，HUD 与主界面「属性」键、暂停菜单共用
	_stats_flow = StatsFlowScript.new()
	_stats_flow.setup(self)
	add_child(_stats_flow)
	hud.set_stats_screen(_stats_flow.screen())
	pause.set_stats_screen(_stats_flow.screen())
	Events.shop_closed.connect(wave_dir.on_shop_closed)
	Events.pause_requested.connect(_on_pause_requested)
	Events.resume_requested.connect(_on_resume_requested)
	Events.quit_to_title_requested.connect(_on_quit_to_title)
	Events.wok_toss_requested.connect(_on_wok_toss_requested)
	Events.skill_requested.connect(_on_skill_requested)
	Events.endless_continue_requested.connect(_on_endless_continue)

# 注入玩家节点：同时挂到 world 上，EnemySystem 才拿得到（只留这一个入口）
func set_player(p: Node2D) -> void:
	player = p
	world.player = p

func is_paused() -> bool:
	return _paused

# 给 WaveDirector 用的公开暂停入口（架构守卫 R3 禁止跨模块读私有字段，故走公开方法）
func set_paused(v: bool) -> void:
	_paused = v

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
	skill_sys.reset_cooldowns()
	_paused = false
	GameState.paused = false
	_sim_speed = 1
	Events.fast_forward_toggled.emit(false)
	set_physics_process(true)
	wave_dir.spawn_wave_burst()
	Events.run_started.emit()

func _build_pools() -> void:
	for i in BattleWorld.MAX_BULLETS:
		var b = BulletScene.instantiate()
		b.recycle()
		add_child(b)
		world.bullets.append(b)
	# "enemies" 组：整个池子一次性挂上（对象池里的节点常驻，靠 alive 标记区分死活），
	# 这样别处想数"场上有几只怪"只要一次 group 查询，不必每帧同步一个计数器。
	# 现在唯一的用处是设置里打开 FPS 计数器时把同屏怪数一起显示出来。
	for i in BattleWorld.MAX_ENEMIES:
		var e = EnemyScene.instantiate()
		e.recycle()
		add_child(e)
		e.add_to_group("enemies")
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
	wave_dir.begin_wave()
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
	# 主动技能冷却推进（暂停/非运行态时本函数不进，CD 自然冻结）
	if skill_sys != null:
		skill_sys.tick(delta)
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
	# 同屏敌人上限 = 配置值 ∩ 当前画质档位的上限（掉帧时自动砍，见 core/PerfGuard.gd）
	var cap := Perf.alive_cap(int(cfg.get("max_alive", 88)))
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
		wave_dir.end_wave()

func _collect_pickups(delta: float) -> void:
	if world.pickups == null:
		return
	# 磁吸半径用真实值（含自动拾取/拾取范围强化），不再把 pickup_pct 当半径传（旧 bug：半径≈0）
	var got: int = world.pickups.update(delta, player.global_position,
		GameState.pickup_magnet(), false)
	if got > 0:
		world.gold_picked += got
		GameState.add_gold(got)

# 波末结算 / 商店关闭进下一波 / 开波 的逻辑已拆到 scenes/WaveDirector.gd
#（Game 曾长到 306 行超 300 行架构红线；拆出后由 wave_dir 代理，见 _ready）
func _on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color, key: String) -> void:
	enemy_system.on_weapon_fired(pos, dir, stats, c, key)

func _on_melee_swung(origin: Vector2, dir: Vector2, reach: float, half_arc: float,
		dmg: float, crit: bool, knockback: float, c: Color, key: String, level: int) -> void:
	enemy_system.on_melee_swung(origin, dir, reach, half_arc, dmg, crit, knockback, c, key, level)

# ---- 颠勺（满锅气终极）----
func _on_wok_toss_requested() -> void:
	enemy_system.on_wok_toss()

# ---- 主动技能（冰镇/毒雾…）：右手按钮按下 → 这里真正施放 ----
func _on_skill_requested(id: String) -> void:
	if skill_sys != null:
		# 施放前按【当前角色 + 武器 + 属性道具】重算技能：买了把枪、堆够 4 件本命，
		# 下一次按键的伤害/半径/时长立刻跟着变 —— 四元素联动就落在这一行上。
		skill_sys.refresh(Data.character(GameState.character), GameState.weapons,
			Data.weapons, GameState.stat_value)
		skill_sys.cast(id)

# 颠勺冲击波环已并入 FxBlast：整发爆炸统一画在玩家当前位置，不在 Game 里另画一圈。
