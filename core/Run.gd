extends RefCounted

# 一局流程的纯逻辑：是否最后一波、通关结算分。
# 不依赖任何 autoload / 渲染节点，便于 --script 单测；
# 阈值（total）从 data/balance.json 的 "wave" 段读，数值只改 JSON。

# 是否到了通关波：撑过这一波即胜利
static func is_last_wave(wave: int, cfg: Dictionary) -> bool:
	var total := int(cfg.get("total", 20))
	return total > 0 and wave >= total

# 通关/阵亡的统一结算分：给重开一个可追逐的目标。
# 击杀权重最高（操作奖赏）、波次反映进度、金币反映经营。
static func score(kills: int, gold: int, wave: int) -> int:
	return kills * 10 + gold + wave * 50
