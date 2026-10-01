extends Node

# 战斗子系统：刷怪、敌人移动、子弹追踪、命中结算、颠勺。
# 由 Game 持有（game 子节点），共享 Game 的对象池与状态字段。
# GDScript 无真私有，本脚本通过 game._xxx 直接读写 Game 的实例字段。

const Spawner := preload("res://core/Spawner.gd")
const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")
const DamageLabel := preload("res://entities/effects/DamageLabel.gd")
const HitSpark := preload("res://entities/effects/HitSpark.gd")
const Shake := preload("res://entities/effects/Shake.gd")

const MAX_BULLETS := 90
const MAX_ENEMIES := 110
const LIFESTEAL_CHANCE := 0.08
const SEPARATION_FORCE := 90.0
const KB_IMPULSE := 120.0        # 命中击退脉冲（克制，约 14px 位移）
const KB_DECEL := 520.0          # 击退衰减（/s），短促

var game: Node2D = null          # 注入：持有 _enemies / _bullets / _arena / _rng / player / _pickups 等

func _ready() -> void:
	game = get_parent()
	Shake.register(game)

# ---- 刷怪 ----
func boss_wave() -> bool:
	var every := int(Data.spawn_cfg().get("boss_every", 5))
	return every > 0 and GameState.wave % every == 0

func spawn_one() -> void:
	var e = game._enemies[game._enemy_cursor]
	game._enemy_cursor = (game._enemy_cursor + 1) % MAX_ENEMIES
	var side: int = game._rng.randi_range(0, 3)
	var pos := Spawner.edge_position(side, Data.arena(), game._rng.randf(), game._rng.randf())
	var type := Spawner.pick_type(GameState.wave, game._rng.randf(), Data.spawn_cfg())
	# Boss 波里，普通怪有一定概率是"精英版"（更厚更大更值钱）
	var elite := false
	if boss_wave() and game._rng.randf() < float(Data.spawn_cfg().get("elite_chance", 0.3)):
		elite = true
	var stats := Spawner.stats_for(type, GameState.wave, Data.enemies, elite)
	if stats.is_empty():
		return
	e.spawn(pos, stats, game._next_id)
	game._next_id += 1

# Boss 波开局额外刷一只首领：慢、大、硬、疼，但金币丰厚
func spawn_boss() -> void:
	var e = game._enemies[game._enemy_cursor]
	game._enemy_cursor = (game._enemy_cursor + 1) % MAX_ENEMIES
	var side: int = game._rng.randi_range(0, 3)
	var pos := Spawner.edge_position(side, Data.arena(), game._rng.randf(), game._rng.randf())
	var stats := Spawner.stats_for("boss", GameState.wave, Data.enemies)
	if stats.is_empty():
		return
	e.spawn(pos, stats, game._next_id)
	game._next_id += 1
	# Boss 出场轻微震屏
	Shake.kick(9.0, 0.4)

# 地上还没被捡走的金币面额（诊断/HUD 用）
func ground_gold() -> int:
	return game._pickups.ground_value() if game._pickups != null else 0

func alive_enemy_count() -> int:
	var n := 0
	for e in game._enemies:
		if e.alive:
			n += 1
	return n

func update_enemies(delta: float) -> void:
	var pp: Vector2 = game.player.global_position
	for i in game._enemies.size():
		var e = game._enemies[i]
		if not e.alive:
			continue
		var pos: Vector2 = e.global_position
		# 朝玩家
		var to_p: Vector2 = (pp - pos)
		if to_p.length() > 0.001:
			var dir: Vector2 = to_p.normalized()
			# 飞行兵：在朝玩家的方向上叠加左右蛇形摆动，更难被预判/击中
			if e.flight:
				e._phase += delta * 7.0
				var perp := Vector2(-dir.y, dir.x)
				dir = (dir + perp * sin(e._phase) * 0.7).normalized()
			pos += dir * e.speed * delta
		# 分离：只算附近的，避免 O(n^2) 在满怪时拖慢手机
		game._neighbors.clear()
		for j in game._enemies.size():
			if j == i:
				continue
			var o = game._enemies[j]
			if not o.alive:
				continue
			if pos.distance_squared_to(o.global_position) < 3600.0:  # 60px 内才算
				game._neighbors.append({"pos": o.global_position, "radius": o.radius})
		pos += Hit.separation(pos, game._neighbors, e.radius) * SEPARATION_FORCE * delta
		# 别叠在玩家身上
		pos += Hit.keep_distance(pos, pp, e.radius + float(Data.player_cfg().get("radius", 16)))
		# 受击击退脉冲：随帧快速衰减，位移克制不影响手感
		var kb: Vector2 = e._kb
		if kb.length_squared() > 0.01:
			pos += kb * delta
			e._kb = kb.move_toward(Vector2.ZERO, KB_DECEL * delta)
		e.global_position = Movement.clamp_to_arena(pos, game._arena, e.radius)
		e.tick(delta)
		# 接触玩家 → 造成伤害
		if pos.distance_to(pp) <= e.radius + float(Data.player_cfg().get("radius", 16)) + 2.0:
			if game.player.has_method("take_hit"):
				game.player.take_hit(e.dmg)
				# 挨打掉火候（被摸一下 = 锅被泼了冷水）；封顶 8 点，避免首领一巴掌把火候清零
				GameState.cool_wok(minf(e.dmg, 8.0))

# 先收集敌人数组（含本帧位置/速度），供开火与子弹追踪共用
func collect_enemy_data() -> void:
	game._edata.clear()
	for e in game._enemies:
		if e.alive:
			# 敌人基本朝玩家追，用"朝玩家方向 × 速度"近似速度，给自动瞄准打提前量
			var vel := Vector2.ZERO
			var to_p: Vector2 = game.player.global_position - e.global_position
			if to_p.length() > 0.001:
				vel = to_p.normalized() * float(e.speed)
			game._edata.append({"pos": e.global_position, "radius": e.radius,
				"vel": vel, "alive": true, "ref": e})

# 子弹追踪：每帧把每颗激活子弹的方向，朝"当前最近的存活怪"最多转 homing_turn*delta 弧度。
# 幅度克制（约 4 rad/s），只修正发射后怪的绕走/多怪时的误判，不会瞬转成"导航弹"。
func home_bullets(delta: float) -> void:
	var cfg := Data.bullet_cfg()
	var turn := float(cfg.get("homing_turn", 0.0))
	if turn <= 0.0:
		return
	var hr := float(cfg.get("homing_range", 360))
	var max_turn := turn * delta
	for b in game._bullets:
		if not b.active:
			continue
		var best := -1
		var best_d := INF
		for k in game._edata.size():
			var e: Dictionary = game._edata[k]
			if not bool(e.get("alive", false)):
				continue
			var d: float = b.global_position.distance_to(e.get("pos", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = int(k)
		if best < 0 or best_d > hr:
			continue
		var ep: Vector2 = game._edata[best].get("pos", Vector2.ZERO)
		var desired: Vector2 = (ep - b.global_position).normalized()
		var cur: Vector2 = b.dir.normalized()
		var ang := cur.angle_to(desired)
		ang = clampf(ang, -max_turn, max_turn)
		b.dir = cur.rotated(ang)
		b.rotation = b.dir.angle()

func resolve_hits() -> void:
	game._bdata.clear()
	for b in game._bullets:
		if b.active:
			game._bdata.append({"pos": b.global_position, "radius": b.radius, "active": true, "ref": b})
	if game._bdata.is_empty() or game._edata.is_empty():
		return
	for h: Dictionary in Hit.find_hits(game._bdata, game._edata):
		var b = game._bdata[int(h["bullet"])]["ref"]
		var e = game._edata[int(h["enemy"])]["ref"]
		if not b.active or not e.alive:
			continue
		if b.hit_ids.has(e.eid):
			continue          # 同一发子弹不重复打同一个敌人
		b.hit_ids[e.eid] = true
		game.hits_landed += 1
		# 命中微量攒锅气（主要靠击杀，命中只是让"没空档"也能维持火候）
		GameState.add_wok(float(Data.wok_cfg().get("hit_heat", 0.5)))
		damage_enemy(e, b.dmg)
		# 命中小幅击退：沿子弹方向把敌人推开一瞬
		if e.alive:
			e.apply_knockback(b.dir.normalized(), KB_IMPULSE)
		if b.aoe_radius > 0.0:
			_explode(b, e)
		if b.pierce_left > 0:
			b.pierce_left -= 1
		else:
			b.recycle()

func _explode(b, center_enemy) -> void:
	var c: Vector2 = center_enemy.global_position
	for d in game._edata:
		var e = d["ref"]
		if not e.alive or e == center_enemy:
			continue
		if (e.global_position as Vector2).distance_to(c) <= b.aoe_radius:
			damage_enemy(e, b.dmg * 0.6)   # 溅射伤害打 6 折

func damage_enemy(e, amount: float) -> void:
	# 先取位置：hurt() 触发死亡后会 recycle，之后再取坐标就不稳了
	var epos: Vector2 = e.global_position
	# 伤害飘字（纯表现，受粒子开关控制）
	if Settings.get_setting("particles_enabled", true):
		var dl = DamageLabel.new()
		game.add_child(dl)
		dl.init(int(amount), false, epos)
	# 单次大伤害轻微震屏
	if amount >= 35.0:
		Shake.kick(4.0, 0.16)
	# 飘伤害数字（特效层订阅，纯表现）
	Events.damage_dealt.emit(int(amount), epos, false)
	if e.hurt(amount):
		GameState.add_kill()
		# 击杀碎屑 + 冲击波环（Boss 更大），粒子开关控制
		if Settings.get_setting("particles_enabled", true):
			var spark = HitSpark.new()
			game.add_child(spark)
			spark.init(epos, e.etype == "boss")
		# 钱掉在地上（不是直接入账）：玩家要走进磁吸圈才收得到
		# drop 的返回值 = 池满时被直接结算的金额（钱不会凭空蒸发）
		if game._pickups != null:
			var ov: int = int(game._pickups.drop(epos, e.gold))
			if ov > 0:
				game.gold_picked += ov
				GameState.add_gold(ov)
		# 击杀爆环（Boss 的环更大）
		Events.enemy_killed.emit(str(e.etype), epos)
		# 击杀回血（lifesteal 强化：续航流玩法）
		# ⚠️ 必须概率触发：按击杀固定回血时，一局 1300+ 杀能回几千血，
		#    实测"站着不动"都能满血通关，难度被彻底抵消
		var ls: float = GameState.stat_value("lifesteal")
		if ls > 0.0 and game._rng.randf() < LIFESTEAL_CHANCE:
			GameState.heal(int(ls))
		# 击杀按金币攒锅气：普通怪一点点，Boss 一大口，火候涨得有节奏
		# 再乘上 wok_pct 强化（锅气获取 +X%）
		var heat: float = float(Data.wok_cfg().get("kill_heat", 9)) * (1.0 + 0.2 * float(e.gold))
		heat *= 1.0 + GameState.stat_value("wok_pct")
		GameState.add_wok(heat)

func on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color) -> void:
	game.shots_fired += 1
	for attempt in MAX_BULLETS:
		var b = game._bullets[game._bullet_cursor]
		game._bullet_cursor = (game._bullet_cursor + 1) % MAX_BULLETS
		if not b.active:
			b.launch(pos, dir, stats, c)
			return

# ---- 颠勺（满锅气终极）----
# 由 HUD 颠勺按钮 / Joystick 避让区点按触发：全屏击退+重伤，火候回落。
func on_wok_toss() -> void:
	if not GameState.wok_ready():
		return
	var pp: Vector2 = game.player.global_position
	var w := Data.wok_cfg()
	var dmg_mult := float(w.get("toss_dmg_mult", 0.6))
	var knock := float(w.get("toss_knock", 130))
	for e in game._enemies:
		if not e.alive:
			continue
		var dir: Vector2 = e.global_position - pp
		if dir.length() < 0.001:
			dir = Vector2(0, 1)
		# 重伤：按敌人当前最大血量比例结算，Boss 也削一大块
		damage_enemy(e, e.max_hp * dmg_mult + 25.0)
		# 甩飞：沿远离玩家方向推开，营造"颠勺"的爆开感
		var np: Vector2 = e.global_position + dir.normalized() * knock
		e.global_position = Movement.clamp_to_arena(np, game._arena, e.radius)
	# 冲击波视觉
	game._shock_pos = pp
	game._shock_t = 0.0
	GameState.toss_wok()
	Events.wok_tossed.emit()
