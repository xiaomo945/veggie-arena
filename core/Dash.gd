extends RefCounted

# 冲刺闪避状态机（纯函数）：冷却 → 触发 → 冲刺中 → 结束 → 再冷却。
#
# 为什么要有冲刺：本作是"自动开火 + 手动走位"，走位就是唯一的主动技巧。
# 光靠匀速移动躲不开后期成群的怪，必须给玩家一个"应急按钮"：
# 短距高速位移 + 短暂无敌 —— 用得好能穿出包围圈，用不好就是白给一次冷却。
#
# 冲刺期间直接覆盖速度（不走 Movement 的加速度），这样才有"窜出去"的爆发感。

const DEFAULTS := {
	"cooldown": 1.8,      # 冷却秒数
	"duration": 0.16,     # 冲刺持续秒数（短才有爆发感，长了就变成加速跑）
	"speed_mult": 3.4,    # 冲刺速度 = 基础速度 × 这个倍数
	"ifr": 0.30,          # 冲刺带来的无敌时长（略长于冲刺本身，穿过怪堆不会立刻挨打）
	"distance": 96.0,     # 参考冲刺距离（px），用于自检：duration × speed × mult
}

static func cfg(raw: Dictionary) -> Dictionary:
	var c := DEFAULTS.duplicate()
	for k in c.keys():
		if raw.has(k):
			c[k] = float(raw[k])
	return c

# 状态：
#   cd  = 剩余冷却
#   t   = 冲刺剩余时间（<0 表示没在冲刺）
#   dir = 冲刺方向
#   ifr = 本次冲刺带来的剩余无敌时间（独立于 t，可以比冲刺本身更长）
static func make() -> Dictionary:
	return {"cd": 0.0, "t": -1.0, "dir": Vector2.ZERO, "ifr": 0.0}

static func active(s: Dictionary) -> bool:
	return float(s.get("t", -1.0)) > 0.0

static func can_start(s: Dictionary, c: Dictionary) -> bool:
	return float(s.get("cd", 0.0)) <= 0.0 and not active(s)

# 触发冲刺。dir 为零向量时返回 false（没方向没法冲）。
static func start(s: Dictionary, dir: Vector2, c: Dictionary) -> bool:
	if not can_start(s, c):
		return false
	if dir.length_squared() < 0.0001:
		return false
	s["dir"] = dir.normalized()
	s["t"] = float(c.get("duration", 0.16))
	s["cd"] = float(c.get("cooldown", 1.8))
	s["ifr"] = float(c.get("ifr", 0.30))
	return true

# 每帧推进：冲刺计时、无敌计时、冷却各走各的。返回本帧是否"刚结束冲刺"。
static func step(s: Dictionary, delta: float) -> bool:
	var just_ended := false
	if active(s):
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			s["t"] = -1.0
			just_ended = true
	var ifr := float(s.get("ifr", 0.0))
	if ifr > 0.0:
		s["ifr"] = maxf(0.0, ifr - delta)
	var cd := float(s.get("cd", 0.0))
	if cd > 0.0:
		s["cd"] = maxf(0.0, cd - delta)
	return just_ended

# 冲刺中的实际速度
static func speed(s: Dictionary, base_speed: float, c: Dictionary) -> float:
	if not active(s):
		return base_speed
	return base_speed * float(c.get("speed_mult", 3.4))

# 本次冲刺带来的剩余无敌时间（独立于冲刺位移，通常比冲刺长一点）
static func ifr_left(s: Dictionary, _c: Dictionary = {}) -> float:
	return maxf(0.0, float(s.get("ifr", 0.0)))

# 冷却进度 0..1（1 = 冷却完成可用），给 HUD 画冷却扇形
static func cooldown_ratio(s: Dictionary, c: Dictionary) -> float:
	var cd := float(c.get("cooldown", 1.8))
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - float(s.get("cd", 0.0)) / cd, 0.0, 1.0)

# 参考冲刺距离（用于配平自检：太短没手感，太长会冲进怪堆送死）
static func distance(base_speed: float, c: Dictionary) -> float:
	return base_speed * float(c.get("speed_mult", 3.4)) * float(c.get("duration", 0.16))
