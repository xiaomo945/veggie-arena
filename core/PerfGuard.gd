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
