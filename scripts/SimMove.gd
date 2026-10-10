extends RefCounted

# 模拟 AI 的走位（从 ui/Screens/Main.gd 拆出来：Main 卡在 300 行架构红线上，
# 而这段只在 --sim 自测里用，挪走不影响任何玩法逻辑）。
#
# 逃离"附近所有怪质心"（1/d 加权）+ 往场地中心靠 —— 比只躲最近一只更像真玩家。

# sense = 感知半径；jitter = 方向抖动（避免被逼到死角后反复横跳卡住）
static func dodge_dir(pp: Vector2, enemies: Array, arena: Dictionary,
		sense: float = 220.0, jitter: float = 0.22, rng = null) -> Vector2:
	var center := Vector2(float(arena.get("x", 0)) + float(arena.get("w", 540)) * 0.5,
	                      float(arena.get("y", 0)) + float(arena.get("h", 900)) * 0.5)
	var flee := Vector2.ZERO
	var n := 0
	for e in enemies:
		if not e.alive:
			continue
		var d := pp.distance_to(e.global_position)
		if d < sense:
			# 越近的怪推得越狠（1/d 加权），方向是"远离它"
			flee += (pp - e.global_position).normalized() / maxf(d, 24.0)
			n += 1
	var to_center := (center - pp).normalized()
	var away := to_center
	if n > 0:
		away = flee.normalized().lerp(to_center, 0.2)
	if rng != null:
		away = away.rotated(rng.randf_range(-jitter, jitter))
	return away.limit_length(1.0)

# 有怪进到 dist px 内 = 威胁，模拟 AI 这时才按冲刺
static func threat_close(pp: Vector2, enemies: Array, dist: float = 70.0) -> bool:
	for e in enemies:
		if e.alive and e.global_position.distance_to(pp) < dist:
			return true
	return false
