extends Node2D

# 战斗管理器：刷怪、子弹池、命中结算、玩家受击、波次推进。
# 所有对象都走对象池 —— 手机上反复 instantiate 是掉帧主因。

const BulletScene := preload("res://entities/Bullet/Bullet.tscn")
const EnemyScene := preload("res://entities/Enemy/Enemy.tscn")
const HUDScene := preload("res://ui/HUD/HUD.tscn")
const ShopScene := preload("res://ui/Shop/Shop.tscn")
const DeathScene := preload("res://ui/Screens/DeathScreen.tscn")
const Economy := preload("res://core/Economy.gd")
const Spawner := preload("res://core/Spawner.gd")
const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")

const MAX_BULLETS := 90
const MAX_ENEMIES := 110
const SEPARATION_FORCE := 90.0

var player: Node2D = null
var _paused := false

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

func _ready() -> void:
	_rng.randomize()
	var a := Data.arena()
	_arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	_build_pools()
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.player_died.connect(_on_player_died)
	GameState.reset()
	add_child(HUDScene.instantiate())
	add_child(ShopScene.instantiate())
	add_child(DeathScene.instantiate())
	Events.shop_closed.connect(_on_shop_closed)

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
func _spawn_one() -> void:
	var e = _enemies[_enemy_cursor]
	_enemy_cursor = (_enemy_cursor + 1) % MAX_ENEMIES
	var side := _rng.randi_range(0, 3)
	var pos := Spawner.edge_position(side, Data.arena(), _rng.randf(), _rng.randf())
	var type := Spawner.pick_type(GameState.wave, _rng.randf(), Data.spawn_cfg())
	var stats := Spawner.stats_for(type, GameState.wave, Data.enemies)
	if stats.is_empty():
		return
	e.spawn(pos, stats, _next_id)
	_next_id += 1

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

	# 刷怪
	var cfg := Data.spawn_cfg()
	_spawn_acc += Spawner.spawn_rate(GameState.wave, cfg) * delta
	var cap := int(cfg.get("max_alive", 88))
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive_enemy_count() < cap:
			_spawn_one()

	# 敌人移动 + 互相分离 + 不要贴玩家脸
	_update_enemies(delta)

	# 子弹飞行
	for b in _bullets:
		b.advance(delta)

	# 开火（武器需要敌人列表来自动瞄准）
	_collect_enemy_data()
	if player.has_method("auto_fire"):
		player.auto_fire(_edata, delta)

	# 命中结算
	_resolve_hits()

	# 波次推进：暂停 → 开补给站 → 玩家买完再继续
	if GameState.wave_finished():
		_end_wave()

func _end_wave() -> void:
	_paused = true
	GameState.add_gold(Economy.wave_bonus(GameState.wave, Data.wave_cfg()))
	GameState.heal_percent(float(Data.wave_cfg().get("heal_percent", 0.12)))
	Events.shop_opened.emit()

func _on_shop_closed() -> void:
	_paused = false
	GameState.next_wave()

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
			pos += to_p.normalized() * e.speed * delta
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

func _collect_enemy_data() -> void:
	_edata.clear()
	for e in _enemies:
		if e.alive:
			_edata.append({"pos": e.global_position, "radius": e.radius, "alive": true, "ref": e})

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
	if e.hurt(amount):
		GameState.add_kill()
		GameState.add_gold(e.gold)

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
