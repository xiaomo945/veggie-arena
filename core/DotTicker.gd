extends RefCounted

# 持续伤害（毒/灼烧）节流累加器 —— 纯逻辑，不引用任何 autoload，可在 --script 单测里直接实例化。
# 抽出来是为了能在单元测试里验证节流行为（Enemy.gd 因类内引用 Art 自动加载，
# 无法在 --script 单测模式编译，不能直接 .new()）。
#
# 为什么需要节流：一片怪同时中毒时，若每帧都走完整 damage_enemy（发飘字 + 挤压 + 结算），
# 会瞬间上千次调用，手机上直接卡死。这里把每帧微小 dot 累加进 _acc，
# 每 DOT_TICK 秒才一次性返回累积值给上层结算。总伤害 = 逐帧 dot 之和，完全等价，
# 但结算频率从 ~60 次/秒/怪 降到 2 次/秒/怪。

const DOT_TICK := 0.5      # 持续伤害结算间隔（秒）

var _acc := 0.0            # 累计中、尚未结算的 dot
var _timer := 0.0          # 距上次结算已经过的秒数

# 推进 fx 计时并累加毒/灼烧伤害，每 DOT_TICK 秒返回一次累积值，否则返回 0.0。
# fx 是 Enemy 的效果表（引用传递），这里会就地剔除已到期的效果。
# 调用方（EnemySystem）再拿返回值走 damage_enemy 统一结算击杀/掉金/锅气。
func accumulate(fx: Dictionary, delta: float) -> float:
	if fx.is_empty():
		_acc = 0.0
		_timer = 0.0
		return 0.0
	var dot := 0.0
	for k in fx.keys():
		var d: Dictionary = fx[k]
		var t := float(d.get("t", 0.0)) - delta
		if t <= 0.0:
			fx.erase(k)
			continue
		d["t"] = t
		if k == "poison" or k == "burn":
			dot += float(d.get("v", 0.0)) * delta
	_acc += dot
	_timer += delta
	if _timer < DOT_TICK:
		return 0.0
	var out := _acc
	_acc = 0.0
	_timer -= DOT_TICK      # 进位：消除帧对齐漂移，保证总伤害 = 逐帧积分值
	return out

# 对象池复用 / 重生时清掉残留累加，否则上一只怪的 dot 会误结算到新怪身上。
func reset() -> void:
	_acc = 0.0
	_timer = 0.0
