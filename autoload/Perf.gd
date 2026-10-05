extends Node

# 运行时画质档位（autoload）：每帧采样帧率 → 交给 core/PerfGuard.gd 的纯逻辑定档。
#
# 为什么做成 autoload：Game / EnemySystem / FxLayer / ArenaFloor 都要读同一个档位，
# 而 core/ 层按架构守卫不许碰 autoload —— 所以纯逻辑在 core/PerfGuard.gd（可单测），
# 这里只做"采样 + 广播"，是薄薄一层。
#
# 玩家手选的 Settings.quality 是【下限】：手选"低画质"就锁死保底档，
# 自动降级只会往下走、不会把它拉高。

signal level_changed(level: int)

const PerfGuard := preload("res://core/PerfGuard.gd")

const WARMUP := 2.0      # 开局/换场景的头 2 秒不算：加载尖峰会被误判成"卡"
const SMOOTH := 0.05     # 帧率指数平滑：单帧抖动不该影响档位

var level := 0
var _hold := 0.0
var _ema := 60.0
var _warm := 0.0
# 性能测量用：true 时冻结档位（不自动降级）。
# 为什么需要：scripts/perf_probe.gd 要测"未降级时的真实开销"才能定位瓶颈 ——
# 不冻结的话测到的是"降级后"的性能，看不出到底哪一层是原凶。
var _frozen := false

func _process(delta: float) -> void:
	if delta <= 0.0 or _frozen:
		return
	_warm += delta
	if _warm < WARMUP:
		return
	_ema += (1.0 / delta - _ema) * SMOOTH
	var lo := PerfGuard.floor_from_quality(Settings.quality)
	var r := PerfGuard.step(level, _ema, _hold, delta, lo)
	_hold = float(r[1])
	var lv := int(r[0])
	if lv != level:
		level = lv
		_hold = 0.0
		level_changed.emit(level)

# 各表现层读这里：Perf.int_cap("floats", 24) / Perf.bool_cap("far_detail", true)
func cap(key: String, fallback: Variant = 0) -> Variant:
	return PerfGuard.cap(level, key, fallback)

func int_cap(key: String, fallback: int = 0) -> int:
	return int(cap(key, fallback))

func bool_cap(key: String, fallback: bool = true) -> bool:
	return bool(cap(key, fallback))

# 同屏敌人上限：spawn 配置 ∩ 当前档位上限（掉帧时真正生效的那一个数）。
# 刷怪的两处（持续刷 + 开局撒一批）都走这里，否则会出现
# "档位已经降到保底，但开局那一批照旧撒 38 只"的漏网。
func alive_cap(spawn_cap: int) -> int:
	return PerfGuard.alive_cap(spawn_cap, level)

# 玩家在设置里改了画质：下限提高时立刻对齐（手选低画质 → 当场降到保底档）
func sync_quality() -> void:
	var lo := PerfGuard.floor_from_quality(Settings.quality)
	if level < lo:
		level = lo
		_hold = 0.0
		level_changed.emit(level)

# 供设置面板显示当前档位（自动降级的档位对玩家可见，才不会以为游戏偷偷变糊）
func label() -> String:
	return I18n.t("perf_level_%d" % level)

# 冻结/解冻自动降级。只给性能测量脚本用，正常游戏路径不该调。
func debug_freeze(v: bool) -> void:
	_frozen = v
