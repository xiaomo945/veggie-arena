extends RefCounted

# 移速加成的边际递减（纯逻辑）。
#
# 为什么要有：speed_pct 可以一直堆（道具 + 角色 + 狂暴 + 受击加速还会相乘），
#   线性叠上去会飙到 300px/s 以上 —— 在 540 宽的竖屏上就是"每秒跨半屏多"，
#   画面滚太快，主观感受是"发晃 / 像丢帧"（真机反馈 2026-10-11；同期实测 CPU
#   只占 60fps 预算的 4%，渲染侧没事，问题出在速度本身）。
#
# 为什么是递减而不是压死上限：直接把 cap 砍下来会惩罚已经堆了加速的 build，
#   而"快"本身就是这类游戏的爽点。递减只削掉"飙到晃眼"的那一段 ——
#   前 SOFT（20%）全额生效（从 220 到 264 这一段的手感一点不变），
#   超出的部分只吃 FALL（35%），堆得越多收益越低，但永远不是零。

const SOFT := 0.20
const FALL := 0.35

# 名义加成 → 实际生效的加成倍率增量
static func effective(pct: float) -> float:
	var p := maxf(0.0, pct)
	if p <= SOFT:
		return p
	return SOFT + (p - SOFT) * FALL

# 最终像素/秒：base × (1 + 实际加成) × 设置缩放 × 临时倍率，最后再压硬上限
static func final_speed(base: float, pct: float, scale_mul: float,
		mult: float, cap: float) -> float:
	return minf(base * (1.0 + effective(pct)) * scale_mul * mult, cap)
