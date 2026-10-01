extends Node2D

# 战斗协调器：生命周期、暂停、波次推进、金币磁吸、刷怪节奏。
# 敌人移动 / 子弹命中结算 / 颠勺等重逻辑已抽到 scenes/EnemySystem.gd（本节点的子节点）。

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

const MAX_BULLETS := 90
const MAX_ENEMIES := 110

var player: Node2D = null
var _paused := false
# 本局累计捡到的金币（诊断用：与 GameState.gold 的区别是不会被商店花掉）
var gold_picked := 0
var enemy_system: Node = null          # 战斗子系统（刷怪/敌人/子弹/颠勺），_ready 里注入

var _pickups: Node2D = null       # 金币场地（自建池，Game 只调三个方法）
var _bullets: Array = []
var _enemies: Array = []
var _rng := RandomNumberGenerator.new()
var _arena := Rect2()
var _spawn_acc := 0.0
var _next_id := 1
var _bullet_cursor := 0
var _enemy_cursor := 0
# 复用数组，避免每帧新建对象产生 GC 压力
var _bdata: Array = []
var _edata: Array = []
var _neighbors: Array = []
# 颠勺冲击波动画：_shock_t<0 表示不在播放；>=0 表示从触发起经过的秒数
var _shock_t := -1.0
var _shock_pos := Vector2.ZERO
var _shock_max := 280.0
var _shock_dur := 0.38

# 诊断计数器（Main 调试面板读取）
var shots_fired := 0
var hits_landed := 0

func _ready() -> void:
	_rng.randomize()
	var a := Data.arena()
	_arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	_pickups = PickupFieldScene.instantiate()
	add_child(_pickups)
	_build_pools()
	# 战斗子系统：接手刷怪 / 敌人移动 / 子弹命中 / 颠勺
	enemy_system = EnemySystem.new()
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

# 由标题页/死亡页的 run_requested 触发。回收场上所有敌人/子弹，重置状态，正式开跑。
func start_run() -> void:
	for e in _enemies:
		e.recycle()
	for b in _bullets:
		b.recycle()
	if _pickups != null:
		_pickups.clear()
	_spawn_acc = 0.0
	_next_id = 1
	GameState.reset()
	_paused = false
	GameState.paused = false
	set_physics_process(true)
	Events.run_started.emit()

func _build_pools() -> void:
	for i in MAX_BULLETS:
		var b = BulletScene.instantiate()
		b.recycle()
		add_child(b)
		_bullets.append(b)
	for i in MAX_ENEMIES:
		var e = EnemyScene.instantiate()
		e.recycle()
		add_child(e)
		_enemies.append(e)

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
	for e in _enemies:
		e.recycle()
	for b in _bullets:
		b.recycle()
	if _pickups != null:
		_pickups.clear()
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
	return enemy_system.ground_gold()

func alive_enemy_count() -> int:
	return enemy_system.alive_enemy_count()

# ---- 主循环 ----
func _physics_process(delta: float) -> void:
	if player == null or not GameState.running or _paused:
		return
	GameState.tick_wave(delta)
	# 锅气自然衰减：停手不刷怪就凉下来，逼你保持进攻节奏
	GameState.decay_wok(delta)
	# 颠勺冲击波动画推进
	if _shock_t >= 0.0:
		_shock_t += delta

	# 刷怪：Boss 波降低普通刷怪速率，把注意力留给首领
	var cfg := Data.spawn_cfg()
	var rate := Spawner.spawn_rate(GameState.wave, cfg)
	if enemy_system.boss_wave():
		rate *= float(cfg.get("boss_rate_mult", 0.55))
	_spawn_acc += rate * delta
	var cap := int(cfg.get("max_alive", 88))
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if enemy_system.alive_enemy_count() < cap:
			enemy_system.spawn_one()

	# 敌人移动 + 互相分离 + 不要贴玩家脸
	enemy_system.update_enemies(delta)

	# 先收集敌人数组（含本帧位置/速度），供开火与子弹追踪共用
	enemy_system.collect_enemy_data()

	# 开火（武器自动瞄准最近目标）
	if player.has_method("auto_fire"):
		player.auto_fire(_edata, delta)

	# 子弹追踪：飞行中轻微朝当前最近存活怪转向
	enemy_system.home_bullets(delta)

	# 子弹飞行
	for b in _bullets:
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
	if _pickups == null:
		return
	var got: int = _pickups.update(delta, player.global_position,
		GameState.stat_value("pickup_pct"), false)
	if got > 0:
		gold_picked += got
		GameState.add_gold(got)

func _end_wave() -> void:
	# 波末清场：地上没捡的钱一次性收回，不惩罚玩家"打太散"
	if _pickups != null:
		var swept: int = _pickups.collect_all(player.global_position)
		if swept > 0:
			gold_picked += swept
			GameState.add_gold(swept)
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
	if _shock_t < 0.0 or _shock_t > _shock_dur:
		return
	var k := clampf(_shock_t / _shock_dur, 0.0, 1.0)
	var r := _shock_max * k
	var a := 1.0 - k
	draw_arc(_shock_pos, r, 0.0, TAU, 36, Color(1.0, 0.78, 0.42, a), 7.0, true)
	draw_arc(_shock_pos, r * 0.7, 0.0, TAU, 36, Color(1.0, 0.92, 0.7, a * 0.7), 4.0, true)
