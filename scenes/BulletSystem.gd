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

var world = null                     # BattleWorld
var damage_fn: Callable = Callable() # (enemy, amount) -> bool 是否被这一击打死

const KB_IMPULSE := 120.0            # 命中击退脉冲（克制，约 14px 位移）

# ---- 每帧推进 ----
# 顺序很重要：先转向（追踪）、再撞墙反弹、最后判命中。
func tick(delta: float) -> void:
	home(delta)
	bounce()
	resolve()

# 追踪：每帧把每颗激活子弹的方向，朝"当前最近的存活怪"最多转 homing_turn*delta 弧度。
# 幅度克制（约 4 rad/s），只修正发射后怪的绕走/多怪时的误判，不会瞬转成"导航弹"。
# homing_pct 道具在此基础上再乘一档（"制导萝卜"）。
func home(delta: float) -> void:
	var cfg := Data.bullet_cfg()
	var turn := float(cfg.get("homing_turn", 0.0))
	if turn <= 0.0:
		return
	turn *= 1.0 + GameState.stat_value("homing_pct")
	var hr := float(cfg.get("homing_range", 360))
	var max_turn := turn * delta
	for b in world.bullets:
		if not b.active:
			continue
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

# 弹墙（ricochet）：撞到竞技场边就反射一次，直到次数用完。
# 反射用 Movement 的边界判定，保证和大怪/玩家的夹取规则一致。
func bounce() -> void:
	for b in world.bullets:
		if not b.active or b.bounce_left <= 0:
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
	world.bdata.clear()
	for b in world.bullets:
		if b.active:
			world.bdata.append({"pos": b.global_position, "radius": b.radius, "active": true, "ref": b})
	if world.bdata.is_empty() or world.edata.is_empty():
		return
	# 击退强度：子弹类道具 knock_pct 让"打断敌人贴脸"成为一种构筑方向
	var kb := KB_IMPULSE * (1.0 + GameState.stat_value("knock_pct"))
	for h: Dictionary in Hit.find_hits(world.bdata, world.edata):
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
		# 命中小幅击退：沿子弹方向把敌人推开一瞬
		if e.alive:
			e.apply_knockback(b.dir.normalized(), kb)
		if b.aoe_radius > 0.0:
			_explode(b, e)
		if b.pierce_left > 0:
			b.pierce_left -= 1
		else:
			b.recycle()

func _explode(b, center_enemy) -> void:
	var c: Vector2 = center_enemy.global_position
	for d in world.edata:
		var e = d["ref"]
		if not e.alive or e == center_enemy:
			continue
		if (e.global_position as Vector2).distance_to(c) <= b.aoe_radius:
			damage_fn.call(e, b.dmg * 0.6)   # 溅射伤害打 6 折
