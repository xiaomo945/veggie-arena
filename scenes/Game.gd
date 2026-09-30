extends Node2D

# 战斗管理器：刷怪、子弹池、命中结算、玩家受击、波次推进。
# 所有对象都走对象池 —— 手机上反复 instantiate 是掉帧主因。

const BulletScene := preload("res://entities/Bullet/Bullet.tscn")
const EnemyScene := preload("res://entities/Enemy/Enemy.tscn")
const PickupFieldScene := preload("res://entities/Pickup/PickupField.tscn")
const HUDScene := preload("res://ui/HUD/HUD.tscn")
const FxScene := preload("res://ui/Fx/FxLayer.tscn")
const ShopScene := preload("res://ui/Shop/Shop.tscn")
const DeathScene := preload("res://ui/Screens/DeathScreen.tscn")
const VictoryScene := preload("res://ui/Screens/VictoryScreen.tscn")
const Economy := preload("res://core/Economy.gd")
const Spawner := preload("res://core/Spawner.gd")
const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")
const Run := preload("res://core/Run.gd")

const MAX_BULLETS := 90
const MAX_ENEMIES := 110
const SEPARATION_FORCE := 90.0

var player: Node2D = null
var _paused := false
# 本局累计捡到的金币（诊断用：与 GameState.gold 的区别是不会被商店花掉）
var gold_picked := 0

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

func _ready() -> void:
	_rng.randomize()
	var a := Data.arena()
	_arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	_pickups = PickupFieldScene.instantiate()
	add_child(_pickups)
	_build_pools()
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.player_died.connect(_on_player_died)
	# ⚠️ 不再这里 reset —— 一局由标题页"开始"或死亡页"再来一局"触发 start_run()
	# （reset 会把 running 置 true，若提前调了，标题页还没点就开始刷怪了）
	add_child(HUDScene.instantiate())
	add_child(FxScene.instantiate())
	add_child(ShopScene.instantiate())
	add_child(DeathScene.instantiate())
	add_child(VictoryScene.instantiate())
	Events.shop_closed.connect(_on_shop_closed)
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

# ---- 刷怪 ----
func _boss_wave() -> bool:
	var every := int(Data.spawn_cfg().get("boss_every", 5))
	return every > 0 and GameState.wave % every == 0

func _spawn_one() -> void:
	var e = _enemies[_enemy_cursor]
	_enemy_cursor = (_enemy_cursor + 1) % MAX_ENEMIES
	var side := _rng.randi_range(0, 3)
	var pos := Spawner.edge_position(side, Data.arena(), _rng.randf(), _rng.randf())
	var type := Spawner.pick_type(GameState.wave, _rng.randf(), Data.spawn_cfg())
	# Boss 波里，普通怪有一定概率是"精英版"（更厚更大更值钱）
	var elite := false
	if _boss_wave() and _rng.randf() < float(Data.spawn_cfg().get("elite_chance", 0.3)):
		elite = true
	var stats := Spawner.stats_for(type, GameState.wave, Data.enemies, elite)
	if stats.is_empty():
		return
	e.spawn(pos, stats, _next_id)
	_next_id += 1

# Boss 波开局额外刷一只首领：慢、大、硬、疼，但金币丰厚
func _spawn_boss() -> void:
	var e = _enemies[_enemy_cursor]
	_enemy_cursor = (_enemy_cursor + 1) % MAX_ENEMIES
	var side := _rng.randi_range(0, 3)
	var pos := Spawner.edge_position(side, Data.arena(), _rng.randf(), _rng.randf())
	var stats := Spawner.stats_for("boss", GameState.wave, Data.enemies)
	if stats.is_empty():
		return
	e.spawn(pos, stats, _next_id)
	_next_id += 1

# 地上还没被捡走的金币面额（诊断/HUD 用）
func ground_gold() -> int:
	return _pickups.ground_value() if _pickups != null else 0

func alive_enemy_count() -> int:
	var n := 0
	for e in _enemies:
		if e.alive:
			n += 1
	return n

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
	if _boss_wave():
		rate *= float(cfg.get("boss_rate_mult", 0.55))
	_spawn_acc += rate * delta
	var cap := int(cfg.get("max_alive", 88))
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive_enemy_count() < cap:
			_spawn_one()

	# 敌人移动 + 互相分离 + 不要贴玩家脸
	_update_enemies(delta)

	# 先收集敌人数组（含本帧位置/速度），供开火与子弹追踪共用
	_collect_enemy_data()

	# 开火（武器自动瞄准最近目标）
	if player.has_method("auto_fire"):
		player.auto_fire(_edata, delta)

	# 子弹追踪：飞行中轻微朝当前最近存活怪转向，
	# 让"朝你走来的怪"被稳稳咬住，多怪时不再平行打空
	_home_bullets(delta)

	# 子弹飞行
	for b in _bullets:
		b.advance(delta)

	# 命中结算
	_resolve_hits()

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
	if _boss_wave():
		Events.boss_wave.emit(GameState.wave)
		_spawn_boss()

func _update_enemies(delta: float) -> void:
	var pp := player.global_position
	for i in _enemies.size():
		var e = _enemies[i]
		if not e.alive:
			continue
		var pos: Vector2 = e.global_position
		# 朝玩家
		var to_p := (pp - pos)
		if to_p.length() > 0.001:
			var dir := to_p.normalized()
			# 飞行兵：在朝玩家的方向上叠加左右蛇形摆动，更难被预判/击中
			if e.flight:
				e._phase += delta * 7.0
				var perp := Vector2(-dir.y, dir.x)
				dir = (dir + perp * sin(e._phase) * 0.7).normalized()
			pos += dir * e.speed * delta
		# 分离：只算附近的，避免 O(n^2) 在满怪时拖慢手机
		_neighbors.clear()
		for j in _enemies.size():
			if j == i:
				continue
			var o = _enemies[j]
			if not o.alive:
				continue
			if pos.distance_squared_to(o.global_position) < 3600.0:  # 60px 内才算
				_neighbors.append({"pos": o.global_position, "radius": o.radius})
		pos += Hit.separation(pos, _neighbors, e.radius) * SEPARATION_FORCE * delta
		# 别叠在玩家身上
		pos += Hit.keep_distance(pos, pp, e.radius + float(Data.player_cfg().get("radius", 16)))
		e.global_position = Movement.clamp_to_arena(pos, _arena, e.radius)
		e.tick(delta)
		# 接触玩家 → 造成伤害
		if pos.distance_to(pp) <= e.radius + float(Data.player_cfg().get("radius", 16)) + 2.0:
			if player.has_method("take_hit"):
				player.take_hit(e.dmg)
				# 挨打掉火候（被摸一下 = 锅被泼了冷水）；封顶 8 点，避免首领一巴掌把火候清零
				GameState.cool_wok(minf(e.dmg, 8.0))

func _collect_enemy_data() -> void:
	_edata.clear()
	for e in _enemies:
		if e.alive:
			# 敌人基本朝玩家追，用"朝玩家方向 × 速度"近似速度，给自动瞄准打提前量
			var vel := Vector2.ZERO
			var to_p: Vector2 = player.global_position - e.global_position
			if to_p.length() > 0.001:
				vel = to_p.normalized() * float(e.speed)
			_edata.append({"pos": e.global_position, "radius": e.radius,
				"vel": vel, "alive": true, "ref": e})

# 子弹追踪：每帧把每颗激活子弹的方向，朝"当前最近的存活怪"最多转 homing_turn*delta 弧度。
# 幅度克制（约 4 rad/s），只修正发射后怪的绕走/多怪时的误判，不会瞬转成"导航弹"。
func _home_bullets(delta: float) -> void:
	var cfg := Data.bullet_cfg()
	var turn := float(cfg.get("homing_turn", 0.0))
	if turn <= 0.0:
		return
	var hr := float(cfg.get("homing_range", 360))
	var max_turn := turn * delta
	for b in _bullets:
		if not b.active:
			continue
		var best := -1
		var best_d := INF
		for k in _edata.size():
			var e: Dictionary = _edata[k]
			if not bool(e.get("alive", false)):
				continue
			var d: float = b.global_position.distance_to(e.get("pos", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = int(k)
		if best < 0 or best_d > hr:
			continue
		var ep: Vector2 = _edata[best].get("pos", Vector2.ZERO)
		var desired: Vector2 = (ep - b.global_position).normalized()
		var cur: Vector2 = b.dir.normalized()
		var ang := cur.angle_to(desired)
		ang = clampf(ang, -max_turn, max_turn)
		b.dir = cur.rotated(ang)
		b.rotation = b.dir.angle()

func _resolve_hits() -> void:
	_bdata.clear()
	for b in _bullets:
		if b.active:
			_bdata.append({"pos": b.global_position, "radius": b.radius, "active": true, "ref": b})
	if _bdata.is_empty() or _edata.is_empty():
		return
	for h in Hit.find_hits(_bdata, _edata):
		var b = _bdata[int(h["bullet"])]["ref"]
		var e = _edata[int(h["enemy"])]["ref"]
		if not b.active or not e.alive:
			continue
		if b.hit_ids.has(e.eid):
			continue          # 同一发子弹不重复打同一个敌人
		b.hit_ids[e.eid] = true
		hits_landed += 1
		# 命中微量攒锅气（主要靠击杀，命中只是让"没空档"也能维持火候）
		GameState.add_wok(float(Data.wok_cfg().get("hit_heat", 0.5)))
		_damage_enemy(e, b.dmg)
		if b.aoe_radius > 0.0:
			_explode(b, e)
		if b.pierce_left > 0:
			b.pierce_left -= 1
		else:
			b.recycle()

func _explode(b, center_enemy) -> void:
	var c: Vector2 = center_enemy.global_position
	for d in _edata:
		var e = d["ref"]
		if not e.alive or e == center_enemy:
			continue
		if (e.global_position as Vector2).distance_to(c) <= b.aoe_radius:
			_damage_enemy(e, b.dmg * 0.6)   # 溅射伤害打 6 折

func _damage_enemy(e, amount: float) -> void:
	# 先取位置：hurt() 触发死亡后会 recycle，之后再取坐标就不稳了
	var epos: Vector2 = e.global_position
	# 飘伤害数字（特效层订阅，纯表现）
	Events.damage_dealt.emit(int(amount), epos, false)
	if e.hurt(amount):
		GameState.add_kill()
		# 钱掉在地上（不是直接入账）：玩家要走进磁吸圈才收得到
		# drop 的返回值 = 池满时被直接结算的金额（钱不会凭空蒸发）
		if _pickups != null:
			var ov: int = int(_pickups.drop(epos, e.gold))
			if ov > 0:
				gold_picked += ov
				GameState.add_gold(ov)
		# 击杀爆环（Boss 的环更大）
		Events.enemy_killed.emit(str(e.etype), epos)
		# 击杀回血（lifesteal 强化：续航流玩法）
		var ls: float = GameState.stat_value("lifesteal")
		if ls > 0.0:
			GameState.heal(int(ls))
		# 击杀按金币攒锅气：普通怪一点点，Boss 一大口，火候涨得有节奏
		# 再乘上 wok_pct 强化（锅气获取 +X%）
		var heat: float = float(Data.wok_cfg().get("kill_heat", 9)) * (1.0 + 0.2 * float(e.gold))
		heat *= 1.0 + GameState.stat_value("wok_pct")
		GameState.add_wok(heat)

var shots_fired := 0
var hits_landed := 0

func _on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color) -> void:
	shots_fired += 1
	for attempt in MAX_BULLETS:
		var b = _bullets[_bullet_cursor]
		_bullet_cursor = (_bullet_cursor + 1) % MAX_BULLETS
		if not b.active:
			b.launch(pos, dir, stats, c)
			return

# ---- 颠勺（满锅气终极）----
# 由 HUD 颠勺按钮 / Joystick 避让区点按触发：全屏击退+重伤，火候回落。
func _on_wok_toss_requested() -> void:
	if not GameState.wok_ready():
		return
	var pp := player.global_position
	var w := Data.wok_cfg()
	var dmg_mult := float(w.get("toss_dmg_mult", 0.6))
	var knock := float(w.get("toss_knock", 130))
	for e in _enemies:
		if not e.alive:
			continue
		var dir: Vector2 = e.global_position - pp
		if dir.length() < 0.001:
			dir = Vector2(0, 1)
		# 重伤：按敌人当前最大血量比例结算，Boss 也削一大块
		_damage_enemy(e, e.max_hp * dmg_mult + 25.0)
		# 甩飞：沿远离玩家方向推开，营造"颠勺"的爆开感
		var np: Vector2 = e.global_position + dir.normalized() * knock
		e.global_position = Movement.clamp_to_arena(np, _arena, e.radius)
	# 冲击波视觉
	_shock_pos = pp
	_shock_t = 0.0
	GameState.toss_wok()
	Events.wok_tossed.emit()

func _draw() -> void:
	if _shock_t < 0.0 or _shock_t > _shock_dur:
		return
	var k := clampf(_shock_t / _shock_dur, 0.0, 1.0)
	var r := _shock_max * k
	var a := 1.0 - k
	draw_arc(_shock_pos, r, 0.0, TAU, 36, Color(1.0, 0.78, 0.42, a), 7.0, true)
	draw_arc(_shock_pos, r * 0.7, 0.0, TAU, 36, Color(1.0, 0.92, 0.7, a * 0.7), 4.0, true)
