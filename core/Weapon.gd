extends RefCounted

# 武器逻辑 —— 纯函数，不碰 Node。
# 负责：等级合成后的属性、自动选目标、冷却、扇形弹道。
# 真正的"开火特效"在 entities/ 层，这里只算数。

const MAX_PELLETS := 12  # 安全上限，防止数据表填错把手机卡死

# 合成后的属性：Lv1 原样，之后每级 dmg ×1.30、cd ×0.93（系数来自 balance.json）
static func merged_stats(def: Dictionary, level: int, cfg: Dictionary) -> Dictionary:
	var dm := float(cfg.get("merge_dmg_multiplier", 1.30))
	var cm := float(cfg.get("merge_cd_multiplier", 0.93))
	var lv := maxi(1, int(level))
	var out := def.duplicate()
	out["dmg"] = float(def.get("dmg", 0)) * pow(dm, float(lv - 1))
	out["cd"] = float(def.get("cd", 1.0)) * pow(cm, float(lv - 1))
	out["level"] = lv
	return out

# 射程内最近的敌人，返回索引；没有则返回 -1
static func nearest_target(pos: Vector2, enemies: Array, max_range: float) -> int:
	var best := -1
	var best_d := INF
	for i in enemies.size():
		var e = enemies[i]
		if not (e is Dictionary):
			continue
		var p = e.get("pos", null)
		if p == null:
			continue
		var d: float = pos.distance_to(p)
		if d <= max_range and d < best_d:
			best_d = d
			best = int(i)
	return best

# 冷却是否就绪
static func can_fire(timer: float, cd: float) -> bool:
	return cd <= 0.0 or timer >= cd

# 冷却计时：保留余数，掉帧时不会损失射速
static func next_cooldown(timer: float, cd: float) -> float:
	if cd <= 0.0:
		return 0.0
	return maxf(0.0, timer - cd)

# 扇形弹道：pellets 发弹丸均匀分布在 ±spread/2 弧度内
# pellets=1 时永远走正前方（不受 spread 影响），避免单发武器莫名其妙打偏
static func pellet_directions(base: Vector2, pellets: int, spread: float, rng) -> Array:
	var n := clampi(int(pellets), 1, MAX_PELLETS)
	var dirs: Array = []
	if n == 1 or spread <= 0.0:
		dirs.append(base.normalized())
		return dirs
	var half := spread * 0.5
	var step := spread / float(n - 1)
	for i in range(n):
		var a := -half + step * float(i)
		# 加一点随机抖动，多發武器不会形成死板的扇面
		var jitter := 0.0
		if rng != null and rng.has_method("randf_range"):
			jitter = float(rng.randf_range(-step * 0.25, step * 0.25))
		dirs.append(base.normalized().rotated(a + jitter))
	return dirs

# 武器环绕玩家的站位（Brotato 式：武器绕着角色转）
static func mount_position(center: Vector2, index: int, count: int, radius: float) -> Vector2:
	if count <= 0:
		return center
	var a := TAU * float(index) / float(count) - PI * 0.5
	return center + Vector2(cos(a), sin(a)) * radius

# 一把武器在一次射击里的理论总伤害（含多发），用于配平模拟
static func burst_damage(stats: Dictionary) -> float:
	return float(stats.get("dmg", 0)) * float(stats.get("pellets", 1))
