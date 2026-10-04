extends RefCounted

# 武器逻辑 —— 纯函数，不碰 Node。
# 负责：等级合成后的属性、自动选目标、冷却、扇形弹道。
# 真正的"开火特效"在 entities/ 层，这里只算数。

const MAX_PELLETS := 12  # 安全上限，防止数据表填错把手机卡死

# 近战扇形：以玩家为圆心、range 为半径、约 120° 的挥砍弧（半角 60°）。
# 100~140° 的区间都算合理，取 120° 居中。
const MELEE_ARC_DEG := 120.0

# 这把武器是不是近战（缺省 "ranged"，保持对 18 把老武器的兼容）
static func is_melee(def: Dictionary) -> bool:
	return str(def.get("type", "ranged")) == "melee"

# 近战挥砍的半角（弧度）。data 里可加 "arc" 字段覆盖（单位：度）。
static func melee_half_arc(def: Dictionary) -> float:
	var deg := float(def.get("arc", MELEE_ARC_DEG))
	return deg_to_rad(deg) * 0.5

# ---- 行为分支 ----
# 32 把武器曾经只差在数字上（dmg/cd/pellets…），换武器只换数值不换手感。
# 现在 data/weapons.json 里加一个 "behavior" 字段就能换一整套打法：
#   projectile（缺省）—— 普通子弹，兼容全部老武器
#   melee      —— 近战扇形挥砍（无子弹）
#   beam       —— 瞬发光束：极细的一条直线，穿到底
#   pulse      —— 以自己为圆心的脉冲，360° 全打
#   chain      —— 链式跳弹：命中后跳向附近另一只怪，每跳衰减
#   boomerang  —— 回旋：飞出去再飞回来，来回各能命中一次
#   homing     —— 制导：强追踪，自己会拐弯咬住目标
# 前三种共用同一套"扇形结算"（区别只在半径与张角），后三种是子弹修饰符。
const BEAM_ARC_DEG := 7.0   # 光束张角：7° 才读起来是"一条线"而不是"一片扇"

static func behavior_of(def: Dictionary) -> String:
	var b := str(def.get("behavior", ""))
	if b != "":
		return b
	return "melee" if is_melee(def) else "projectile"

# 行为中文短名（商店卡展示用）：让玩家"买之前"就知道这把怎么打。
# 局内武器槽已经有几何符文，这里补文字版，两者对照看。
static func behavior_zh(def: Dictionary) -> String:
	match behavior_of(def):
		"melee": return "近战"
		"beam": return "光束"
		"pulse": return "脉冲"
		"chain": return "连锁"
		"boomerang": return "回旋"
		"homing": return "追踪"
		_: return "弹丸"

# 是不是"以自己为圆心的扇形"结算（近战 / 光束 / 脉冲）
static func is_sector(def: Dictionary) -> bool:
	match behavior_of(def):
		"melee", "beam", "pulse":
			return true
		_:
			return false

# 扇形半角（弧度）：近战 120°、光束 7°、脉冲整圈（半角 PI）
static func sector_half_arc(def: Dictionary) -> float:
	match behavior_of(def):
		"beam":
			return deg_to_rad(BEAM_ARC_DEG) * 0.5
		"pulse":
			return PI
		_:
			return melee_half_arc(def)

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
