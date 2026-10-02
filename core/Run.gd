extends RefCounted

# 一局流程的纯逻辑：是否最后一波、终局 Boss 波、无尽段缩放、通关结算分。
# 不依赖任何 autoload / 渲染节点，便于 --script 单测；
# 阈值（total）从 data/balance.json 的 "wave" 段读，数值只改 JSON。

# 是否到了通关波：撑过这一波即胜利
static func is_last_wave(wave: int, cfg: Dictionary) -> bool:
	var total := int(cfg.get("total", 20))
	return total > 0 and wave >= total

# 配置的最终波（终局 Boss 就在这一波）。total<=0 表示纯无尽，没有最终波。
static func final_wave(cfg: Dictionary) -> int:
	return int(cfg.get("total", 20))

static func is_final_wave(wave: int, cfg: Dictionary) -> bool:
	var t := final_wave(cfg)
	return t > 0 and wave == t

# 无尽模式是否开启（wave.endless，默认开）
static func endless_enabled(cfg: Dictionary) -> bool:
	return bool(cfg.get("endless", true))

# 超出最终波多少波（还没进无尽段就是 0）。无尽关闭时恒为 0。
static func endless_over(wave: int, cfg: Dictionary) -> int:
	if not endless_enabled(cfg):
		return 0
	var t := final_wave(cfg)
	if t <= 0:
		return 0
	return maxi(0, wave - t)

# 是否处在无尽段（第 total 波之后的波次）
static func is_endless_wave(wave: int, cfg: Dictionary) -> bool:
	return endless_over(wave, cfg) > 0

# 无尽段某一项的成长倍率：1 + per_wave * 超出波数，超过 cap 则封顶。
# key 取 "hp" / "dmg" / "gold"，读 endless 段的 "<key>_per_wave" 与 "<key>_cap"。
static func endless_mult(over: int, ecfg: Dictionary, key: String) -> float:
	if over <= 0:
		return 1.0
	var per := float(ecfg.get(key + "_per_wave", 0.0))
	var cap := float(ecfg.get(key + "_cap", 0.0))
	var m := 1.0 + per * float(over)
	if cap > 0.0:
		m = minf(m, cap)
	return m

# 无尽段的属性倍率集合（喂给 Spawner.stats_for 的 endless 参数）
static func endless_scales(wave: int, cfg: Dictionary, ecfg: Dictionary) -> Dictionary:
	var over := endless_over(wave, cfg)
	return {
		"hp": endless_mult(over, ecfg, "hp"),
		"dmg": endless_mult(over, ecfg, "dmg"),
		"gold": endless_mult(over, ecfg, "gold"),
	}

# 通关/阵亡的统一结算分：给重开一个可追逐的目标。
# 击杀权重最高（操作奖赏）、波次反映进度（无尽波数直接体现）、金币反映经营。
static func score(kills: int, gold: int, wave: int) -> int:
	return kills * 10 + gold + wave * 50
