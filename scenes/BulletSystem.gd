extends RefCounted

# 子弹的推进 / 追踪 / 撞墙反弹 / 命中结算 —— 从 EnemySystem 拆出来的独立部件。
#
# 为什么拆：EnemySystem 要同时管刷怪、移动、DoT、颠勺，已经贴着 300 行红线；
# 而"弹墙""追踪"这类子弹道具每加一条都要再占十几行。子弹是"一堆有自己位置和
# 方向的东西"，天然该有自己的部件。
#
# ⚠️ 伤害必须回调用 EnemySystem.damage_enemy：只有那里才知道击杀计数、掉金币、
#    涨锅气。绕过它自己扣血会导致"打死的怪不算击杀、不掉钱、不涨火候"。

const Hit := preload("res://core/Hit.gd")
const Movement := preload("res://core/Movement.gd")
const BattleWorld := preload("res://scenes/BattleWorld.gd")
const InnateDot := preload("res://scenes/InnateDot.gd")

var world = null                     # BattleWorld
var damage_fn: Callable = Callable() # (enemy, amount) -> bool 是否被这一击打死

const KB_IMPULSE := 120.0            # 命中击退脉冲（克制，约 14px 位移）

# 命中配对结果的持久数组：每帧复用，避免 find_hits 为命中对 new 一堆 Dictionary
var _hit_out: Array = []

# 武器行为（见 core/Weapon.gd 的 behavior 注释）相关的常量
const CHAIN_RANGE := 190.0           # 链式跳跃的最大跨度
const CHAIN_FALLOFF := 0.72          # 每跳一次伤害衰减（跳得越远越弱）
const BOOMERANG_RETURN_AT := 0.42    # 飞到寿命 42% 时掉头
const BOOMERANG_BACK := 1.9          # 掉头后追加的寿命倍率（够飞回玩家身边）

# ---- 每帧推进 ----
# 顺序很重要：先转向（追踪）、再回旋掉头、再撞墙反弹、最后判命中。
# 回旋必须排在追踪之后：追踪把方向拧向敌人，回旋再拧回玩家，回旋说了算。
func tick(delta: float) -> void:
	home(delta)
	boomerang()
	bounce()
	resolve()

# 追踪：每帧把每颗激活子弹的方向，朝"当前最近的存活怪"最多转 turn*delta 弧度。
# 幅度克制（全局约 4 rad/s），只修正发射后怪的绕走/多怪时的误判，不会瞬转成"导航弹"。
# behavior=homing 的武器用自己的 homing_turn（默认 9 rad/s，真的会咬人）。
# homing_pct 道具在此基础上再乘一档（"制导萝卜"）。
func home(delta: float) -> void:
	var cfg := Data.bullet_cfg()
	var hp := 1.0 + GameState.stat_value("homing_pct")
	var base_turn := float(cfg.get("homing_turn", 0.0)) * hp
	if base_turn <= 0.0:
		return
	var hr := float(cfg.get("homing_range", 360))
	for b in world.bullets:
		if not b.active or b.enemy:
			continue
		var turn := base_turn
		if b.homing_turn > 0.0:
			turn = b.homing_turn * hp
		var max_turn := turn * delta
		var best := -1
		var best_d := INF
		for k in world.edata.size():
			var e: Dictionary = world.edata[k]
			if not bool(e.get("alive", false)):
				continue
			var d: float = b.global_position.distance_to(e.get("pos", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = int(k)
		if best < 0 or best_d > hr:
			continue
		var ep: Vector2 = world.edata[best].get("pos", Vector2.ZERO)
		var desired: Vector2 = (ep - b.global_position).normalized()
		var cur: Vector2 = b.dir.normalized()
		var ang := cur.angle_to(desired)
		ang = clampf(ang, -max_turn, max_turn)
		b.dir = cur.rotated(ang)
		b.rotation = b.dir.angle()

# 回旋（boomerang）：飞到寿命 BOOMERANG_RETURN_AT 时掉头飞回玩家。
# 掉头瞬间清空命中记录 —— 于是同一只怪"去一趟、回一趟"各挨一次，
# 手感上就是飞盘/回旋镖：贴脸围着你的怪会被扫两遍。
func boomerang() -> void:
	if world.player == null:
		return
	var pp: Vector2 = world.player.global_position
	for b in world.bullets:
		if not b.active or b.enemy or b.mode != "boomerang":
			continue
		if b.returning:
			if b.global_position.distance_to(pp) <= 28.0:
				b.recycle()
				continue
			b.dir = (pp - b.global_position).normalized()
			b.rotation = b.dir.angle()
			continue
		if b.life >= b.max_life * BOOMERANG_RETURN_AT:
			b.returning = true
			b.hit_ids.clear()
			b.life = 0.0
			b.max_life *= BOOMERANG_BACK

# 弹墙（ricochet）：撞到竞技场边就反射一次，直到次数用完。
# 反射用 Movement 的边界判定，保证和大怪/玩家的夹取规则一致。
func bounce() -> void:
	for b in world.bullets:
		if not b.active or b.bounce_left <= 0 or b.enemy:
			continue
		var p: Vector2 = b.global_position
		var r: float = b.radius
		var hit_x: bool = p.x <= world.arena.position.x + r or p.x >= world.arena.end.x - r
		var hit_y: bool = p.y <= world.arena.position.y + r or p.y >= world.arena.end.y - r
		if hit_x or hit_y:
			if hit_x:
				b.dir = Vector2(-b.dir.x, b.dir.y)
			if hit_y:
				b.dir = Vector2(b.dir.x, -b.dir.y)
			b.dir = b.dir.normalized()
			b.rotation = b.dir.angle()
			b.bounce_left -= 1
			# 反弹后允许再打同一个敌人（不然弹回来就没伤害了）
			b.hit_ids.clear()
			b.global_position = Movement.clamp_to_arena(p, world.arena, r)

func resolve() -> void:
	# 敌弹：命中玩家（纯表现之外的唯一伤害去向是 Player.take_hit，受无敌帧保护）
	if world.player != null:
		var pr := float(Data.player_cfg().get("radius", 16))
		for b in world.bullets:
			if not b.active or not b.enemy:
				continue
			if b.global_position.distance_to(world.player.global_position) <= b.radius + pr:
				world.player.take_hit(b.dmg)
				b.recycle()
	# 玩家子弹：只参与"打敌人"的碰撞配对（敌弹已被上面单独处理）
	# ⚠️ 之前每帧给每颗激活子弹 new 一个 Dictionary 装快照（满屏 90 颗 = 一帧 90 个 dict），
	#    和邻居/敌人数组是同源 GC 风暴。现在复用字典池 + 末尾 resize 截断，稳态零分配。
	var n := 0
	for b in world.bullets:
		if b.active and not b.enemy:
			var d: Dictionary
			if n < world.bdata.size():
				d = world.bdata[n]
			else:
				d = {}
				world.bdata.append(d)
			d["pos"] = b.global_position
			d["radius"] = b.radius
			d["active"] = true
			d["ref"] = b
			n += 1
	world.bdata.resize(n)
	if world.bdata.is_empty() or world.edata.is_empty():
		return
	# 击退强度：子弹类道具 knock_pct 让"打断敌人贴脸"成为一种构筑方向
	var kb := KB_IMPULSE * (1.0 + GameState.stat_value("knock_pct"))
	# 角色自带的命中效果（scorch 的"打中就着火"），每帧取一次，命中循环里复用
	var dot := InnateDot.of(GameState.character)
	var dot_on := not dot.is_empty()
	for h: Dictionary in Hit.find_hits(world.bdata, world.edata, _hit_out):
		var b = world.bdata[int(h["bullet"])]["ref"]
		var e = world.edata[int(h["enemy"])]["ref"]
		if not b.active or not e.alive:
			continue
		if b.hit_ids.has(e.eid):
			continue          # 同一发子弹不重复打同一个敌人
		b.hit_ids[e.eid] = true
		world.hits_landed += 1
		# 命中微量攒锅气（主要靠击杀，命中只是让"没空档"也能维持火候）
		GameState.add_wok(float(Data.wok_cfg().get("hit_heat", 0.5)))
		damage_fn.call(e, b.dmg)
		if dot_on:
			InnateDot.apply(e, dot)
		# 命中小幅击退：沿子弹方向把敌人推开一瞬
		if e.alive:
			e.apply_knockback(b.dir.normalized(), kb)
		if b.aoe_radius > 0.0:
			_explode(b, e)
		# 链式：命中后跳向另一只怪，跳成功就不消耗穿透也不回收
		if b.chain_left > 0 and _chain_step(b, e):
			continue
		if b.pierce_left > 0:
			b.pierce_left -= 1
		else:
			b.recycle()

# 链式（chain）：命中后瞬移到命中点、掉头咬住附近另一只没打过的怪。
# 每跳一次伤害 ×CHAIN_FALLOFF，跳完衰减完就当普通弹结束 —— 视觉上是一道链闪电。
# 返回 true 表示"跳成功了"（调用方不再回收这颗弹）。
func _chain_step(b, from_enemy) -> bool:
	var best = null
	var best_d := INF
	for d in world.edata:
		if not bool(d.get("alive", false)):
			continue
		var e = d.get("ref")
		if e == null or not e.alive or e == from_enemy:
			continue
		if b.hit_ids.has(e.eid):
			continue
		var dist: float = b.global_position.distance_to(e.global_position)
		if dist < best_d:
			best_d = dist
			best = e
	if best == null or best_d > CHAIN_RANGE:
		return false
	b.chain_left -= 1
	b.dmg *= CHAIN_FALLOFF
	b.global_position = from_enemy.global_position
	b.dir = (best.global_position as Vector2 - b.global_position).normalized()
	b.rotation = b.dir.angle()
	b.life = 0.0
	return true

# 炮手开火：从共享子弹池借一颗空闲弹，标记为敌弹并朝玩家射出。
# 与玩家子弹共用池，但 enemy=true 让 home/bounce/resolve 把它当"打玩家"处理。
func launch_enemy(pos: Vector2, dir: Vector2, dmg: float, color: Color) -> void:
	var b = _free_bullet()
	if b == null:
		return
	b.launch(pos, dir, {"bullet_speed": 300.0, "dmg": dmg, "range": 460.0}, color, "enemybolt")
	b.enemy = true

# 从环形池里找一颗空闲弹（和 on_weapon_fired 共用同一条游标，互不冲突）
func _free_bullet():
	var start: int = world.bullet_cursor
	for i in BattleWorld.MAX_BULLETS:
		var idx: int = (start + i) % BattleWorld.MAX_BULLETS
		var b = world.bullets[idx]
		if not b.active:
			world.bullet_cursor = (idx + 1) % BattleWorld.MAX_BULLETS
			return b
	return null

func _explode(b, center_enemy) -> void:
	var c: Vector2 = center_enemy.global_position
	for d in world.edata:
		var e = d["ref"]
		if not e.alive or e == center_enemy:
			continue
		if (e.global_position as Vector2).distance_to(c) <= b.aoe_radius:
			damage_fn.call(e, b.dmg * 0.6)   # 溅射伤害打 6 折
