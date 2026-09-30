extends RefCounted

# 金币掉落物：掉落散开 + 磁吸飞行 + 拾取判定。
#
# 纯函数层：不认识 Player、不认识 Game、不 emit 信号。
# 调用方（entities/Pickup）负责把结果写回节点并发信号。
#
# 为什么要有金币实体（而不是击杀直接入账）：
#   1) 走位有正反馈 —— 冲进怪堆杀完，回身一圈把钱收了，是这类游戏的核心爽点
#   2) 让"拾取范围"强化真正有意义（upgrades.json 的 pick）
#   3) 看得见的钱 = 玩家能感知难度（该不该冒险去捡）

const DEFAULTS := {
	"magnet": 92.0,        # 基础磁吸半径（px）：进圈才飞过来
	"pull_speed": 430.0,   # 吸附飞行速度（px/s）：必须明显快于玩家速度(240)，否则追不上
	"collect_radius": 18.0,# 判定吃到玩家的距离（px）
	"spread": 26.0,        # 掉落散开半径：多枚金币不会叠成一坨
	"life": 0.0,           # 存活秒数，0 = 不消失（波末由 Game 全收）
}

static func cfg(raw: Dictionary) -> Dictionary:
	var c := DEFAULTS.duplicate()
	for k in c.keys():
		if raw.has(k):
			c[k] = float(raw[k])
	return c

# 吸附半径 = 基础 × (1 + pickup_pct 强化)
static func magnet_range(base: float, pickup_pct: float) -> float:
	return base * (1.0 + maxf(0.0, pickup_pct))

# 掉落散开：给一个随机偏移，让爆开的一堆金币看得清是一堆
# rand_a/rand_b 是两个 [0,1) 的随机数，由调用方提供（保持纯函数，便于测试复现）
static func drop_position(pos: Vector2, rand_a: float, rand_b: float, spread: float) -> Vector2:
	if spread <= 0.0:
		return pos
	var ang := rand_a * TAU
	var dist := sqrt(maxf(0.0, rand_b)) * spread   # sqrt 让分布偏外圈，视觉更散
	return pos + Vector2(cos(ang), sin(ang)) * dist

# 一帧的位移与拾取判定。
# 返回 {"pos": Vector2, "collected": bool, "pulled": bool}
#   pulled 用于表现层（被吸中的金币可以加个拖尾/放大）
static func step(pos: Vector2, player_pos: Vector2, magnet: float,
		pull_speed: float, collect_radius: float, delta: float) -> Dictionary:
	var d := pos.distance_to(player_pos)
	if d <= collect_radius:
		return {"pos": pos, "collected": true, "pulled": true}
	if magnet <= 0.0 or d > magnet:
		return {"pos": pos, "collected": false, "pulled": false}
	# 越近吸得越快（0.45 → 1.5 倍），营造"啪一下被吸走"的手感
	var k := 1.0 - clampf(d / magnet, 0.0, 1.0)
	var sp := pull_speed * (0.45 + 1.05 * k)
	var np := pos + (player_pos - pos).normalized() * sp * delta
	# 别冲过头：这一步若跨过了玩家（方向反转），直接判定吃到，
	# 否则高速时会在玩家两侧来回抖动
	if np.distance_to(player_pos) <= collect_radius:
		return {"pos": np, "collected": true, "pulled": true}
	if (np - player_pos).dot(pos - player_pos) <= 0.0:
		return {"pos": player_pos, "collected": true, "pulled": true}
	return {"pos": np, "collected": false, "pulled": true}

# 一坨金币该拆成几枚（避免一枚金币显示 "+7" 也避免刷 7 个节点）
# 返回枚数：1~max_pieces，价值大的多拆几枚
static func split_count(value: int, max_pieces: int) -> int:
	if value <= 1 or max_pieces <= 1:
		return 1
	return clampi(int(round(float(value) / 2.0)), 1, max_pieces)

# 把总价值拆成若干份（尽量均分，余数塞进第一枚）
static func split_values(value: int, pieces: int) -> Array:
	var out: Array = []
	if pieces <= 1:
		out.append(value)
		return out
	var base := int(floor(float(value) / float(pieces)))
	var rest := value - base * pieces
	for i in pieces:
		var v := base
		if rest > 0:
			v += 1
			rest -= 1
		out.append(v)
	return out
