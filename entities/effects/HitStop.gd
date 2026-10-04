extends RefCounted

# 命中定帧（hitstop）：打击瞬间把 time_scale 压到接近 0，几十毫秒后恢复。
# 这是打击感最便宜也最有效的手段 —— 画面"卡"了一下，玩家读成"这一下真沉"。
#
# 为什么用真实时钟而不是节点 _process：time_scale 会同时缩放 _process 的 delta，
# 拿缩放过的 delta 计时永远等不到恢复。所以统一用 Time.get_ticks_usec()。
#
# 为什么不是 autoload：纯静态状态 + FxLayer._process 每帧 tick() 一次即可，
# 不需要在场景树里占一个节点。
#
# ⚠️ 整局模拟（--sim）是手动 step() 的，不走引擎 delta，所以模拟跑分不受影响。

static var _until_usec := 0
static var _armed := false

# 单帧内大量命中（如颠勺清屏瞬间触发几十次 kill/damage）时，定帧总时长封顶，
# 避免把几十次"顺延"累加成 1~2 秒的 0.05 倍速（玩家感知就是"开了慢镜头"）。
const MAX_HITSTOP := 0.10

# 触发一次定帧。连击时顺延（不叠加倍速，只延长到点），但总时长不超过 MAX_HITSTOP。
static func hit(sec: float, scale := 0.05) -> void:
	if sec <= 0.0:
		return
	var now := Time.get_ticks_usec()
	var dur_us := int(sec * 1000000.0)
	var cap_us := int(MAX_HITSTOP * 1000000.0)
	if _armed and now < _until_usec:
		_until_usec = mini(_until_usec + dur_us, now + cap_us)
		return
	Engine.time_scale = scale
	_until_usec = mini(now + dur_us, now + cap_us)
	_armed = true

# ---- 普通命中的顿帧必须节流 ----
# 连射武器一秒十几次命中，每次都顿到 0.05 倍速，画面就成了幻灯片（比不顿还难受）。
# 所以轻顿帧走"每 gap 秒最多一次"；重击（大伤害 / 击杀）不节流 ——
# 那是"这一下真沉"的读法，每次都该停。
const THROTTLE_GAP := 0.12

static var _last_hit_sec := -10.0

# 返回是否真的顿了（false = 被节流吃掉，调用方无需处理）
static func hit_throttled(sec: float, scale: float, gap: float = THROTTLE_GAP) -> bool:
	var now := float(Time.get_ticks_usec()) / 1000000.0
	if _armed:
		# 还没到点 = 真的在顿帧里，别再叠；已过点但 tick() 还没跑（暂停/切后台
		# 回来）就按"已恢复"处理，否则一次漏 tick 会把顿帧永久卡住。
		if Time.get_ticks_usec() < _until_usec:
			return false
		_armed = false
	if now - _last_hit_sec < gap:
		return false
	_last_hit_sec = now
	hit(sec, scale)
	return true

# 每帧调用（放在不会暂停的 _process 里）：到点恢复 1.0
static func tick() -> void:
	if _armed and Time.get_ticks_usec() >= _until_usec:
		_armed = false
		Engine.time_scale = 1.0

# 场景切换 / 结算时兜底，避免把 0.05 倍速带到别的界面
static func reset() -> void:
	_armed = false
	_last_hit_sec = -10.0     # 节流窗口也要清：否则换场景第一发会被上局的窗口吃掉
	Engine.time_scale = 1.0
