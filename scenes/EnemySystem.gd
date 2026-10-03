extends Node

# 战斗子系统：刷怪、敌人移动、子弹追踪、命中结算、颠勺。
# 由 Game 持有（game 子节点），战斗状态通过 scenes/BattleWorld.gd 共享。
#
# 【依赖边界】world —— 全部战斗状态（池 / rng / 竞技场 / 暂存数组 / 计数器），公开契约。
#   game —— 只用来挂特效节点（add_child）和注册震屏，**不读它的任何状态字段**
#   （以前 game._xxx 读写 64 处是全项目头号耦合源，现已全部搬进 BattleWorld）。

const Spawner := preload("res://core/Spawner.gd")
const Run := preload("res://core/Run.gd")
const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")
const DamageLabel := preload("res://entities/effects/DamageLabel.gd")
const HitSpark := preload("res://entities/effects/HitSpark.gd")
const Shake := preload("res://entities/effects/Shake.gd")
const BattleWorld := preload("res://scenes/BattleWorld.gd")
const WokToss := preload("res://scenes/WokToss.gd")
const BulletSystem := preload("res://scenes/BulletSystem.gd")
const EnemyMind := preload("res://scenes/EnemyMind.gd")

# 同屏击杀特效并发上限（防密集击杀时 Node/Tween 暴涨拖帧）
const MAX_DEATH_FX := 16

const LIFESTEAL_CHANCE := 0.08
const SEPARATION_FORCE := 90.0
const KB_IMPULSE := 120.0        # 命中击退脉冲（克制，约 14px 位移）
const KB_DECEL := 520.0          # 击退衰减（/s），短促

var world: BattleWorld = null    # 注入：战斗状态（池 / rng / arena / 暂存数组）
var _toss: WokToss = null        # 锅气大招（独立部件，见 scenes/WokToss.gd）
var _bullets: BulletSystem = null # 子弹（独立部件，见 scenes/BulletSystem.gd）
var _mind = null                  # 敌人 AI/移动/接触（独立部件，见 scenes/EnemyMind.gd）
var game: Node2D = null          # 仅用于挂特效节点与注册震屏
var _contact := 0.0              # 荆棘伤害（contact_dmg），每帧缓存一次

func _ready() -> void:
	game = get_parent()
	Shake.register(game)

# ---- 刷怪 ----
# 终局 Boss 波（配置里的最后一波）：这一波的 boss 走 final_boss 段的强化属性
func final_wave() -> bool:
	return Run.is_final_wave(GameState.wave, Data.wave_cfg())

# Boss 波：常规每 boss_every 波一只 + 终局波必定有（不依赖 boss_every 的整除）
func boss_wave() -> bool:
	var every := int(Data.spawn_cfg().get("boss_every", 5))
	return final_wave() or (every > 0 and GameState.wave % every == 0)

# 无尽段的属性倍率（越过最终波后每波递增）；未进无尽段时全为 1
func endless_scales() -> Dictionary:
	return Run.endless_scales(GameState.wave, Data.wave_cfg(), Data.endless_cfg())

func spawn_one() -> void:
	_ensure_mind()
	var e = world.enemies[world.enemy_cursor]
	world.enemy_cursor = (world.enemy_cursor + 1) % BattleWorld.MAX_ENEMIES
	# 在玩家视野外一圈刷新（大地图下不再按竞技场边缘，否则怪要跑半天才到玩家身边）
	var pp := world.player.global_position
	var ang := world.rng.randf() * TAU
	# 刷在玩家附近一圈（比屏幕略大一点就到，避免"子弹好久没怪可打"的空窗）
	var pos := pp + Vector2(cos(ang), sin(ang)) * 470.0
	pos = Movement.clamp_to_arena(pos, world.arena, 16.0)
	var type := Spawner.pick_type(GameState.wave, world.rng.randf(), Data.spawn_cfg())
	# 精英节奏：第 elite_from_wave 波起、每 elite_every 波一轮，概率随波缓升
	var elite := world.rng.randf() < Spawner.elite_chance(GameState.wave, Data.spawn_cfg())
	var stats := Spawner.stats_for(type, GameState.wave, Data.enemies, elite, endless_scales())
	if stats.is_empty():
		return
	e.spawn(pos, stats, world.next_id)
	world.next_id += 1
	if _mind != null:
		_mind.register(e, stats)
	# 精英/Boss 出场给一记"光环扩散 + 时间暂缓"（纯表现，FxSpawnHalo 订阅）
	if bool(stats.get("elite", false)) or str(stats.get("type", "")) == "boss":
		Events.enemy_spawned.emit(e)

# Boss 波开局额外刷一只首领：慢、大、硬、疼，但金币丰厚
func spawn_boss() -> void:
	_ensure_mind()
	var e = world.enemies[world.enemy_cursor]
	world.enemy_cursor = (world.enemy_cursor + 1) % BattleWorld.MAX_ENEMIES
	# Boss 也在玩家附近出场（大地图下不再按竞技场边缘）
	var pp := world.player.global_position
	var ang := world.rng.randf() * TAU
	var pos := pp + Vector2(cos(ang), sin(ang)) * 480.0
	pos = Movement.clamp_to_arena(pos, world.arena, 16.0)
	var stats: Dictionary
	if final_wave():
		stats = Spawner.final_boss_stats(GameState.wave, Data.enemies,
			Data.final_boss_cfg(), endless_scales())
	else:
		stats = Spawner.stats_for("boss", GameState.wave, Data.enemies, false, endless_scales())
	if stats.is_empty():
		return
	e.spawn(pos, stats, world.next_id)
	world.next_id += 1
	if _mind != null:
		_mind.register(e, stats)
	# Boss 出场轻微震屏（终局 Boss 更重，出场就有压迫感）
	if bool(stats.get("final", false)):
		Shake.kick(16.0, 0.6)
	else:
		Shake.kick(9.0, 0.4)

# 分裂怪死亡时由 EnemyMind.on_kill 回调：在死亡位置生成两只子代（行为为空，不会无限分裂）。
# 复用同一个环形对象池，受 MAX_ENEMIES 硬封顶；行为登记交给 _mind.register。
func spawn_child(pos: Vector2, type: String) -> void:
	if world.alive_enemy_count() >= BattleWorld.MAX_ENEMIES:
		return
	var e = world.enemies[world.enemy_cursor]
	world.enemy_cursor = (world.enemy_cursor + 1) % BattleWorld.MAX_ENEMIES
	var stats := Spawner.stats_for(type, GameState.wave, Data.enemies, false, endless_scales())
	if stats.is_empty():
		return
	e.spawn(pos, stats, world.next_id)
	world.next_id += 1
	if _mind != null:
		_mind.register(e, stats)

# 敌人移动/分离/接触结算（含炮手远程、猛冲兵相位猛冲、自爆、分裂等行为）
# 全交给 EnemyMind —— 这样不断加新行为也不会把本文件顶过 300 行红线。
# EnemyMind 懒构造：world 由 Game 在 _ready 之后才注入，这里不能在 _ready 里 new。
func update_enemies(delta: float) -> void:
	_ensure_mind()
	_mind.update(delta)

# 懒构造 EnemyMind（world 注入后才可用）；顺手把子弹部件也准备好，炮手要借它开火。
# spawn_child 作为回调传进去，分裂怪死亡时由 EnemyMind 回调本系统生成子代。
func _ensure_mind() -> void:
	if _mind != null:
		return
	if _bullets == null:
		_bullets = BulletSystem.new()
		_bullets.world = world
		_bullets.damage_fn = damage_enemy
	_mind = EnemyMind.new()
	_mind.setup(world, damage_enemy, _bullets, spawn_child)

# 先收集敌人数组（含本帧位置/速度），供开火与子弹追踪共用
func collect_enemy_data() -> void:
	world.edata.clear()
	for e in world.enemies:
		if e.alive:
			# 敌人基本朝玩家追，用"朝玩家方向 × 速度"近似速度，给自动瞄准打提前量
			var vel := Vector2.ZERO
			var to_p: Vector2 = world.player.global_position - e.global_position
			if to_p.length() > 0.001:
				vel = to_p.normalized() * float(e.speed)
			world.edata.append({"pos": e.global_position, "radius": e.radius,
				"vel": vel, "alive": true, "ref": e})

# ---- 子弹：追踪 / 弹墙 / 命中结算全在 scenes/BulletSystem.gd ----
# 这里只做转发，并把伤害结算（damage_enemy）注入进去 —— 子弹自己不知道
# 什么叫"击杀"，只有 EnemySystem 知道（击杀计数 / 掉金币 / 涨锅气都在那）。
func home_bullets(delta: float) -> void:
	_bind_bullets()
	_bullets.home(delta)
	_bullets.bounce()

func resolve_hits() -> void:
	_bind_bullets()
	_bullets.resolve()

# 懒构造 + 每次重新注入：world 可能在重开一局后被换掉，缓存会指向旧状态
func _bind_bullets() -> void:
	if _bullets == null:
		_bullets = BulletSystem.new()
	_bullets.world = world
	_bullets.damage_fn = damage_enemy

func damage_enemy(e, amount: float) -> bool:
	# 破甲：受伤加深。放在这里而不是各伤害来源里 —— 所有伤害都吃这个加成，
	# 以后加新伤害类型也不用记着乘一遍
	amount *= 1.0 + e.fx("shred")
	# 先取位置：hurt() 触发死亡后会 recycle，之后再取坐标就不稳了
	var epos: Vector2 = e.global_position
	# 伤害飘字（纯表现，受粒子开关控制）
	if Settings.get_setting("particles_enabled", true):
		var dl = DamageLabel.new()
		game.add_child(dl)
		dl.init(int(amount), false, epos)
	# 受击挤压回弹（squash & stretch）：沿"玩家→敌人"的打击方向压扁
	e.squash(epos - world.player.global_position)
	# 单次大伤害轻微震屏
	if amount >= 35.0:
		Shake.kick(4.0, 0.16)
	# 飘伤害数字（特效层订阅，纯表现）
	Events.damage_dealt.emit(int(amount), epos, false)
	if e.hurt(amount):
		GameState.add_kill()
		if _mind != null:
			_mind.on_kill(e, epos)
	# 击杀碎屑 + 冲击波环（Boss 更大）。并发上限：密集击杀时宁可少画几团，
	# 也不让 Node/Tween 爆炸拖垮手机帧率
	if Settings.get_setting("particles_enabled", true) and _death_fx_count() < MAX_DEATH_FX:
		var spark = HitSpark.new()
		game.add_child(spark)
		spark.init(epos, e.etype == "boss")
		# 钱掉在地上（不是直接入账）：玩家要走进磁吸圈才收得到
		# drop 的返回值 = 池满时被直接结算的金额（钱不会凭空蒸发）
		var ov: int = world.pickups.drop(epos, e.gold)
		if ov > 0:
			world.gold_picked += ov
			GameState.add_gold(ov)
		# 击杀爆环（Boss 的环更大）
		Events.enemy_killed.emit(str(e.etype), epos)
		# 终局 Boss（第 20 波）被击杀 = 直接通关，不必再熬计时
		if e.etype == "boss" and GameState.is_last_wave() and GameState.running:
			Events.run_won.emit()
		# 击杀回血（lifesteal 强化：续航流玩法）
		# ⚠️ 必须概率触发：按击杀固定回血时，一局 1300+ 杀能回几千血，
		#    实测"站着不动"都能满血通关，难度被彻底抵消
		var ls: float = GameState.stat_value("lifesteal")
		if ls > 0.0 and world.rng.randf() < LIFESTEAL_CHANCE:
			GameState.heal(int(ls))
		# 击杀按金币攒锅气：普通怪一点点，Boss 一大口，火候涨得有节奏
		# 再乘上 wok_pct 强化（锅气获取 +X%）
		var heat: float = float(Data.wok_cfg().get("kill_heat", 9)) * (1.0 + 0.2 * float(e.gold))
		heat *= 1.0 + GameState.stat_value("wok_pct")
		GameState.add_wok(heat)
		return true
	return false

# key = 武器 key，透传给子弹画这把武器专属造型（默认参数保证老调用点不用改）
func on_weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, c: Color, key := "") -> void:
	world.shots_fired += 1
	for attempt in BattleWorld.MAX_BULLETS:
		var b = world.bullets[world.bullet_cursor]
		world.bullet_cursor = (world.bullet_cursor + 1) % BattleWorld.MAX_BULLETS
		if not b.active:
			b.launch(pos, dir, stats, c, key)
			return

# 近战扇形挥砍：命中"以 origin 为圆心、reach 为半径、朝向 dir 半角 half_arc 内"
# 的全部存活敌人，伤害统一走 damage_enemy 漏斗（击杀/掉金/锅气/破甲都生效）。
# knockback>0 时对存活敌人施加朝向其外侧的击退脉冲。视觉交给 melee_visual 信号。
func on_melee_swung(origin: Vector2, dir_in: Vector2, reach: float, half_arc: float,
		dmg: float, crit: bool, knockback: float, c: Color, key: String, level: int) -> void:
	world.shots_fired += 1
	var base := dir_in.normalized()
	for e in world.edata:
		if not bool(e.get("alive", false)):
			continue
		var epos: Vector2 = e.get("pos", Vector2.ZERO)
		var d: Vector2 = epos - origin
		var dist: float = d.length()
		if dist > reach:
			continue
		var ang: float = 0.0
		if dist > 0.001:
			ang = abs(base.angle_to(d.normalized()))
		if ang > half_arc:
			continue
		var en = e.get("ref")
		if en == null or not en.alive:
			continue
		# 命中走漏斗：击杀计数 / 掉金币 / 涨锅气 / 破甲全在 damage_enemy 里
		damage_enemy(en, dmg)
		world.hits_landed += 1
		# 命中微量攒锅气（与子弹一致：主要靠击杀，命中只维持火候）
		GameState.add_wok(float(Data.wok_cfg().get("hit_heat", 0.5)))
		if knockback > 0.0 and en.alive:
			var kdir: Vector2 = (d.normalized() if dist > 0.001 else base)
			en.apply_knockback(kdir, knockback)
	# 视觉：短命扇形（纯表现，删掉也不影响伤害）
	Events.melee_visual.emit(origin, base, reach, half_arc, c, key, level)

# ---- 颠勺（满锅气终极）----
# HUD 颠勺按钮触发：全屏重伤 + 击退；附加效果由已买道具决定。
# 施放细节全在 scenes/WokToss.gd —— 这里只把它接上伤害结算与战斗状态。
func on_wok_toss() -> void:
	# 懒构造：world / damage_fn 必须每次重新注入，避免拿到过期的战斗状态
	if _toss == null:
		_toss = WokToss.new()
	_toss.world = world
	_toss.damage_fn = damage_enemy
	_toss.execute()

# 统计当前还活着的击杀特效节点数（配合 MAX_DEATH_FX 限制并发）
func _death_fx_count() -> int:
	var n := 0
	for c in game.get_children():
		if c.get_script() == HitSpark:
			n += 1
	return n

