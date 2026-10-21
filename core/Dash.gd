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

# 随机冲刺方向（只在"没有任何方向输入"时兜底）。两种调用口径共用这一个函数：
#   random_dir()      —— 无参：连续随机角（randf 全局种子），单位长、非零，
#                       test_dash 11 抽 64 次方向互不相同。
#   random_dir(rng)   —— 带种子 RNG：量化到 8 个离散方向（0/45/…/315°），模拟器用，
#                       test_dash 12 断言：全部单位长、400 次抽样覆盖 8 向、均值无偏向。
# 为什么离散向要单位长：本项目方向口径统一归一化（Movement.stick_direction 除长度、
#   StickInput.stick_vector 用 limit_length(1.0)），键盘斜向移动也是单位长。早期写法给
#   对角乘 0.7071 想"归一化"，但 45° 的 cos/sin 本来就是 0.7071 —— 再乘一次等于把斜冲刺
#   砍到 70% 速度，"随机"就成了"替你挑最慢的方向"。这 8 个方向也正是键盘 WASD 能产生的
#   全部 8 个方向（4 正向 + 4 斜向），随机冲刺和手动冲刺的手感因此完全一致。
static func random_dir(rng: RandomNumberGenerator = null) -> Vector2:
	if rng == null:
		var a := randf() * TAU
		return Vector2(cos(a), sin(a))
	var step := rng.randi_range(0, 7)
	return Vector2(cos(float(step) * (PI / 4.0)), sin(float(step) * (PI / 4.0)))

# 冲刺方向裁决（纯函数，便于单测）：桌面端鼠标瞄准优先，摇杆/键盘方向兜底。
#   move      = 摇杆/键盘给出的方向（单位向量，或零向量）
#   to_mouse  = 玩家→鼠标的世界向量（未归一化；长度过小视为没瞄准）
#   has_mouse = 本局收到过【真实】鼠标移动（触屏模拟出来的鼠标事件不算）
#   over_ui   = 鼠标正压在 HUD 按钮/面板上（此时"瞄准"没有意义）
#
# 为什么需要它：键盘 WASD 是 4 个二值键，天生只能产生 8 个方向，"上和左上之间"
# 那个角度按不出来 —— 玩家反馈"冲刺只有 8 个方向、手感生硬"。鼠标瞄准给桌面端
# 连续 360° 的角度，"往哪儿冲"由准星决定，冲刺方向才像自己的操作。
# 压在 UI 上时退回 move：否则"点屏幕右下的冲刺键 → 朝右下冲"会完全反直觉。
static func aim(move: Vector2, to_mouse: Vector2, has_mouse: bool, over_ui: bool) -> Vector2:
	if has_mouse and not over_ui and to_mouse.length_squared() > 4.0:
		return to_mouse.normalized()
	return move

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
