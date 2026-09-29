extends RefCounted

# 经济系统 —— 金币、波次奖励、商店刷新与抽卡
# 纯逻辑，无渲染依赖

# --script 模式下 class_name 不会注册，必须显式 preload
const Inventory := preload("res://core/Inventory.gd")

# 通关一波给的金币奖励
static func wave_bonus(wave: int, cfg: Dictionary) -> int:
	var base := int(cfg.get("bonus_base", 10))
	var per := int(cfg.get("bonus_per_wave", 4))
	return base + wave * per

# 刷新第 n 次的价格（越刷越贵）
static func reroll_cost(times: int, cfg: Dictionary) -> int:
	var base := int(cfg.get("reroll_base", 3))
	var step := int(cfg.get("reroll_step", 2))
	return base + times * step

static func can_buy(gold: int, cost: int) -> bool:
	return gold >= cost

# 从池子里不重复抽 n 个（rng 由调用方传入，保证可复现）
static func roll_offers(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var left := pool.duplicate()
	var out: Array = []
	while out.size() < count and left.size() > 0:
		var i := rng.randi_range(0, left.size() - 1)
		out.append(left[i])
		left.remove_at(i)
	return out

# 构造可用商品池：武器（槽位未满，或可合成）+ 全部强化
# weapons 里每项需含 "key" 与 "lv"
static func build_pool(weapons: Array, weapon_defs: Dictionary, upgrade_defs: Dictionary, max_slot: int, max_lv: int) -> Array:
	var pool: Array = []
	for key in weapon_defs.keys():
		if Inventory.can_accept(weapons, key, max_slot, max_lv):
			var w: Dictionary = weapon_defs[key].duplicate()
			w["key"] = key
			w["kind"] = "weapon"
			pool.append(w)
	for key in upgrade_defs.keys():
		var u: Dictionary = upgrade_defs[key].duplicate()
		u["key"] = key
		u["kind"] = "upgrade"
		pool.append(u)
	return pool

# 一波打完的总收入（击杀掉落 + 通关奖励），用于配平
static func wave_income(wave: int, kills: int, avg_gold: float, cfg: Dictionary) -> int:
	return int(round(float(kills) * avg_gold)) + wave_bonus(wave, cfg)
