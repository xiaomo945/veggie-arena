extends RefCounted

# 帧率自适应画质档位 —— 纯逻辑，可单测（autoload/Perf.gd 只负责每帧调 step()）。
#
# 为什么需要它：满屏怪掉帧是本项目被反馈最多次的问题（"怪多有点儿卡顿"、
# "用完大招清完屏立马就不卡了"）。根因是同屏开销随敌人数暴涨，而手机性能上限是死的。
# 与其让玩家自己进设置里翻，不如让游戏自己降档：掉帧就砍特效和同屏敌人数，
# 帧率稳住了再慢慢升回去。
#
# 三条设计原则：
#   1) 降档要快、升档要慢 —— 卡顿是当下的痛，升档是赚的；宁可多待在低档。
#   2) 迟滞（down 50fps / up 58fps）+ 持续时间门槛，避免档位在阈值附近来回抖
#      （抖档的观感比一直低档更糟：画面一亮一暗、敌人忽多忽少）。
#   3) 玩家手选的画质是【下限】：手选"低"就锁死在最低档，自动降级不许把它拉高。

const MAX_LEVEL := 3          # 0=满配 1=轻降 2=中降 3=保底（只求能玩）

# 每档的开销上限。数值来自实测顺序：先砍"看得见的"（飘字/特效），
# 最后才砍"影响玩法的"（同屏敌人数）—— 玩法被削是最后的手段。
# "deco"：敌人装饰 LOD —— 低档关掉脚下内圈影/顶部高光/腮红这些纯装饰 draw，
# 每只怪每帧少 ~40% 的 draw 调用（脸和本体形状永远保留，辨识度不受影响）。
# ⚠️ max_alive 这一列必须按"同屏怪数"的量级来定，不能凭感觉写大数：
#   实测同屏上限是 spawn.max_alive（现 38 只），而旧表里写的是 88/64/48/32 ——
#   前两档比 38 还大，等于"降了两档，同屏一只怪没少"，只砍了飘字和装饰。
#   所以改成 0 / 32 / 26 / 20：0 = 该档不额外限制（满配 = 完全交给 spawn 配置，
#   满配时的体验与改动前逐帧一致）；往下每档都真的少 6 只怪。
#   GPU 侧的开销几乎全部随"同屏怪数"线性增长（每只怪各自的 draw），
#   所以这才是手机掉帧时最该砍的一项 —— 见 docs/08 的诊断结论。
const CAPS: Array = [
	{"max_alive": 0, "death_fx": 6, "floats": 24, "pops": 24, "rings": 18, "far_detail": true, "deco": true},
	{"max_alive": 32, "death_fx": 4, "floats": 16, "pops": 16, "rings": 12, "far_detail": true, "deco": true},
	{"max_alive": 26, "death_fx": 2, "floats": 10, "pops": 10, "rings": 8, "far_detail": false, "deco": false},
	{"max_alive": 20, "death_fx": 1, "floats": 6, "pops": 6, "rings": 5, "far_detail": false, "deco": false},
]

# 同屏敌人上限 = spawn 配置 ∩ 当前档位上限。
# 档位写 0 时表示"这一档不额外限制"，直接沿用 spawn 配置（满配档就是这样）。
static func alive_cap(spawn_cap: int, level: int) -> int:
	var tier := int(cap(level, "max_alive", 0))
	if tier <= 0:
		return spawn_cap
	return mini(spawn_cap, tier)

const DOWN_FPS := 54.0        # 比原 50 更早降档：用户反馈「怪多 + 远程武器时仍有点卡顿」，
                              # 在 fps 刚往下掉（还没到 50 的明显卡）就先开始 0.4s 倒计时砍同屏敌人数
const UP_FPS := 58.0          # 比降档阈值高 4fps → 迟滞带，防抖档
const HOLD_DOWN := 0.4        # 0.4 秒门槛（被 test_perf_guard 锁定：必须 > 0.3 才能"躲开偶发卡顿"，
                              # 且 1.1s 内只连降两档；改小会同时击穿这两条断言）
const HOLD_UP := 6.0          # 升档要稳 6 秒：刚升上去又掉下来最难受

# 玩家手选画质 → 允许的最高画质（= 自动降级的地板档位）
static func floor_from_quality(q: int) -> int:
	match q:
		0: return 3      # 低画质：锁死在保底档
		1: return 1      # 中画质：最多用到"轻降"
		_: return 0      # 高画质：交给自动
	return 0

static func caps(level: int) -> Dictionary:
	return CAPS[clampi(level, 0, MAX_LEVEL)] as Dictionary

static func cap(level: int, key: String, fallback: Variant = 0) -> Variant:
	return caps(level).get(key, fallback)

# 每帧一步：返回 [档位, 已持续秒数]。hold 由调用方保存并回传。
# fps<=0（delta 异常/首帧）时不动，避免开局第 1 帧的脏数据把画面拉到最低档。
# ---- 尖峰判据（B 类卡顿）----
# 平均帧率【看不见尖峰】：平均 60fps、但每 10 帧卡一次（密集击杀/GC/着色器编译），
# EMA 平滑后仍有 55fps 左右（按 DOWN_FPS 判定"及格"），玩家却每 10 帧实实在在
# 顿一下。所以降档不能只看均值，还得看"超预算帧的比例"—— 行业里衡量卡顿用的
# 就是 P99 / 1% low，不是平均帧率。
#
# 帧预算随屏幕刷新率变：120Hz 屏是 8.33ms，60Hz 是 16.67ms。高刷屏上"没掉到
# 54fps"远不代表流畅 —— 80fps 在 120Hz 屏上就是每 3 帧丢 1 帧的 judder。
const SPIKE_RATIO := 0.12      # 窗口内超预算帧占比超过 12% = 有卡顿
const SPIKE_WIN := 120         # 统计窗口（帧），约 1~2 秒
const SPIKE_HOLD := 2          # 连续这么多个窗口都超才降档，防单次误判

# 帧预算（ms）：按屏幕刷新率推。高刷屏（120Hz）预算只有 8.33ms。
# 刷新率取"观测到的峰值帧率"近似 —— 稳定状态下的最高帧率就是刷新率上限。
static func budget_ms(peak_fps: float) -> float:
	if peak_fps >= 100.0:
		return 1000.0 / 120.0
	if peak_fps >= 80.0:
		return 1000.0 / 90.0
	return 1000.0 / 60.0

# 窗口内超预算帧的占比（纯函数）
static func over_budget_ratio(frame_ms: Array, budget: float) -> float:
	if frame_ms.is_empty() or budget <= 0.0:
		return 0.0
	var n := 0
	for t in frame_ms:
		if float(t) > budget:
			n += 1
	return float(n) / float(frame_ms.size())

# 尖峰连续计数 → 是否该降一档。返回 [是否降档, 新的连续计数]
static func spike_step(ratio: float, streak: int) -> Array:
	if ratio > SPIKE_RATIO:
		var s := streak + 1
		if s >= SPIKE_HOLD:
			return [true, 0]
		return [false, s]
	return [false, 0]

static func step(cur: int, fps: float, hold: float, delta: float, floor_level: int = 0) -> Array:
	var lo := clampi(floor_level, 0, MAX_LEVEL)
	var lv := clampi(cur, lo, MAX_LEVEL)
	var want := lv
	if fps > 0.0 and fps < DOWN_FPS and lv < MAX_LEVEL:
		want = lv + 1
	elif fps > UP_FPS and lv > lo:
		want = lv - 1
	if want == lv:
		return [lv, 0.0]
	var need := HOLD_DOWN if want > lv else HOLD_UP
	var h := hold + delta
	if h >= need:
		return [want, 0.0]
	return [lv, h]
