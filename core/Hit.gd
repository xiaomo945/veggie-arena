extends RefCounted

# 命中与挤压 —— 纯函数。
# 分离逻辑（separation）是手感关键：没有它，敌人会全部叠在同一个像素上，
# 看起来像"只有一只怪"，玩家会以为游戏出 bug 了。

# 两个圆是否相交
static func overlaps(a_pos: Vector2, a_r: float, b_pos: Vector2, b_r: float) -> bool:
	var r := a_r + b_r
	return a_pos.distance_squared_to(b_pos) <= r * r

# 遍历所有子弹 × 敌人，返回命中对 [{bullet: int, enemy: int}]
# 子弹需含 pos/radius；敌人需含 pos/radius/alive
static func find_hits(bullets: Array, enemies: Array) -> Array:
	var out: Array = []
	for bi in bullets.size():
		var b = bullets[bi]
		if not (b is Dictionary):
			continue
		if not bool(b.get("active", false)):
			continue
		var bpos: Vector2 = b.get("pos", Vector2.ZERO)
		var br: float = float(b.get("radius", 4))
		for ei in enemies.size():
			var e = enemies[ei]
			if not (e is Dictionary):
				continue
			if not bool(e.get("alive", false)):
				continue
			var epos: Vector2 = e.get("pos", Vector2.ZERO)
			var er: float = float(e.get("radius", 12))
			if overlaps(bpos, br, epos, er):
				out.append({"bullet": int(bi), "enemy": int(ei)})
	return out

# 敌人之间的分离力：把重叠的单位推开，让怪群看起来是一"群"而不是一"坨"
# 返回本帧应该叠加到自身速度上的位移
# limit：只取前 limit 个邻居。调用方用"复用字典池 + 有效个数"的方式避免每帧 new
# 上万个 Dictionary（旧写法是卡顿主因之一），池数组比实际个数长，靠这个参数截断。
static func separation(self_pos: Vector2, others: Array, self_radius: float, limit := -1) -> Vector2:
	var n: int = others.size() if limit < 0 else mini(limit, others.size())
	var push := Vector2.ZERO
	var count := 0
	for i in n:
		var o = others[i]
		if not (o is Dictionary):
			continue
		var p: Vector2 = o.get("pos", Vector2.ZERO)
		var r: float = float(o.get("radius", 12))
		var d := self_pos.distance_to(p)
		var min_d := self_radius + r
		if d > 0.0001 and d < min_d:
			# 越近推得越狠
			push += (self_pos - p).normalized() * (min_d - d) / min_d
			count += 1
	if count == 0:
		return Vector2.ZERO
	return push / float(count)

# 敌人不要挤到玩家身体里（否则贴脸瞬间掉血，看不出发生了什么）
static func keep_distance(self_pos: Vector2, target_pos: Vector2, min_dist: float) -> Vector2:
	var d := self_pos.distance_to(target_pos)
	if d <= 0.0001 or d >= min_dist:
		return Vector2.ZERO
	return (self_pos - target_pos).normalized() * (min_dist - d)
