extends RefCounted

# 移动手感层 —— 全部纯函数，不碰任何 Node，因此可被 headless 测试覆盖。
#
# 三件事决定"跟不跟手"：
#   1. 死区 deadzone   —— 手指微动不该被忽略，太大就有"起不来"的粘滞感
#   2. 浮点摇杆        —— 手指推出边界后摇杆原点跟着走，变向不必回中
#   3. 速度插值 k      —— 变大不是瞬移（会飘），变小就是延迟
# 参考值来自 HTML 原型实测：变向响应 83ms（固定原点）→ 33ms（浮点摇杆）。

const DEFAULT_RADIUS := 52.0
const DEFAULT_DEADZONE := 3.0
const DEFAULT_K_FWD := 90.0
const DEFAULT_K_REV := 110.0

# 把 balance.json 的 feel 段读成统一结构，缺键用默认值兜底。
static func feel(cfg: Dictionary) -> Dictionary:
	return {
		"radius": float(cfg.get("joystick_radius", DEFAULT_RADIUS)),
		"deadzone": float(cfg.get("joystick_deadzone", DEFAULT_DEADZONE)),
		"k_forward": float(cfg.get("accel_forward", DEFAULT_K_FWD)),
		"k_reverse": float(cfg.get("accel_reverse", DEFAULT_K_REV)),
	}

# 指数插值系数：dt 越大、k 越大，越接近 1（瞬间到位）。
static func accel(k: float, dt: float) -> float:
	return 1.0 - exp(-k * dt)

# 手指偏移 -> 方向单位向量。死区内返回零向量。
static func stick_direction(dx: float, dy: float, deadzone: float) -> Vector2:
	var l := sqrt(dx * dx + dy * dy)
	if l <= deadzone or l == 0.0:
		return Vector2.ZERO
	return Vector2(dx / l, dy / l)

# 浮点摇杆：手指超出半径时，原点被"拖"着走，使偏移始终 <= radius。
# 这是变向延迟从 83ms 降到 33ms 的关键。
static func follow_origin(ox: float, oy: float, px: float, py: float, radius: float) -> Vector2:
	var dx := px - ox
	var dy := py - oy
	var l := sqrt(dx * dx + dy * dy)
	if l <= radius or l == 0.0:
		return Vector2(ox, oy)
	return Vector2(px - dx / l * radius, py - dy / l * radius)

# 朝目标速度插值一步。反向（点积 < 0）用更大的 k —— 急转要更跟手。
static func step(vx: float, vy: float, dir_x: float, dir_y: float,
		speed: float, dt: float, k_forward: float, k_reverse: float) -> Vector2:
	var tx := dir_x * speed
	var ty := dir_y * speed
	var dot := vx * tx + vy * ty
	var k := k_reverse if dot < 0.0 else k_forward
	var a := accel(k, dt)
	return Vector2(vx + (tx - vx) * a, vy + (ty - vy) * a)

static func speed_of(vx: float, vy: float) -> float:
	return sqrt(vx * vx + vy * vy)

# 把角色限制在竞技场内（按半径留边）。
static func clamp_to_arena(pos: Vector2, arena: Rect2, radius: float) -> Vector2:
	return Vector2(
		clampf(pos.x, arena.position.x + radius, arena.position.x + arena.size.x - radius),
		clampf(pos.y, arena.position.y + radius, arena.position.y + arena.size.y - radius)
	)

# 理论时间（秒）：从静止加速到 pct × 满速。
#   pct=0.9 -> t = 2.303 / k
static func time_to_percent(k: float, pct: float) -> float:
	if k <= 0.0:
		return INF
	return -log(1.0 - clampf(pct, 0.0, 0.999)) / k

# 理论时间（秒）：从"反向满速"拉回到 pct × 正向满速（最苛刻的变向）。
#   pct=0.9 -> t = 2.996 / k
static func time_to_percent_reverse(k: float, pct: float) -> float:
	if k <= 0.0:
		return INF
	return -log((1.0 - clampf(pct, 0.0, 0.999)) * 0.5) / k

# 实测模拟：按固定帧率跑，数第几帧速度达到 pct × 满速。
# 这才是玩家真正感觉到的延迟（含帧量化），比理论值更真实。
static func frames_to_percent(k: float, pct: float, fps: float,
		from_reverse: bool = false, max_frames: int = 600) -> int:
	var dt := 1.0 / fps
	var speed := 1.0
	var v := -speed if from_reverse else 0.0
	for i in range(1, max_frames + 1):
		v += (speed - v) * accel(k, dt)
		if v >= pct * speed:
			return i
	return max_frames
