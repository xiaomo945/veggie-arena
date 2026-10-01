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

# 单项的抽取权重（没有 weight 字段的老数据按 1 算，保证向后兼容）
static func weight_of(item) -> float:
	if item is Dictionary:
		return maxf(1.0, float((item as Dictionary).get("weight", 1.0)))
	return 1.0

# 从池子里不重复抽 n 个，按 weight 加权（rng 由调用方传入，保证可复现）。
#
# ⚠️ 为什么不能等概率抽：道具从 18 个涨到 48 个之后，等概率会让"稀有道具"和
# "基础道具"一样常见 —— 开局就送猛火/连环爆，build 就没有成长感了；同时武器
# 被稀释到几乎抽不到，六把武器凑不齐。加权后：常见道具常出现，稀有道具偶尔
# 出现（出现时是个真正的抉择时刻）。
static func roll_offers(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var left := pool.duplicate()
	var out: Array = []
	while out.size() < count and left.size() > 0:
		var total := 0.0
		for it in left:
			total += weight_of(it)
		var r := rng.randf() * total
		var pick := 0
		for i in left.size():
			r -= weight_of(left[i])
			if r <= 0.0:
				pick = i
				break
		out.append(left[pick])
		left.remove_at(pick)
	return out

# 构造可用商品池：武器（槽位未满，或可合成）+ 全部强化
# weapons 里每项需含 "key" 与 "lv"
# unlocked_weapons: 已解锁的武器 key 列表。传空数组表示"全部可买"（默认，向后兼容）。
# rarity -> 抽取权重。稀有度越高越难出现，出现时才是"要不要为它改 build"的抉择。
const RARITY_WEIGHT := {1: 6.0, 2: 3.0, 3: 1.0}
# 武器与道具的相对权重：武器要凑满 6 个槽位，不能让 48 个道具把它淹掉
const WEAPON_WEIGHT := 4.0

# 打折后的价格（"讲价"道具 shop_discount）。夹在 1 折以上，避免刷到 0 金币白嫖。
static func price_of(base_cost: int, discount_pct: float) -> int:
	if discount_pct <= 0.0:
		return base_cost
	return maxi(1, int(round(float(base_cost) * (1.0 - clampf(discount_pct, 0.0, 0.9)))))

static func build_pool(weapons: Array, weapon_defs: Dictionary, upgrade_defs: Dictionary, max_slot: int, max_lv: int, unlocked_weapons: Array = [], discount_pct: float = 0.0) -> Array:
	var pool: Array = []
	for key in weapon_defs.keys():
		# 未解锁的武器根本不进池子（商店里看不到，也不会被抽到）
		if not unlocked_weapons.is_empty() and not unlocked_weapons.has(str(key)):
			continue
		if Inventory.can_accept(weapons, key, max_slot, max_lv):
			var w: Dictionary = weapon_defs[key].duplicate()
			w["key"] = key
			w["kind"] = "weapon"
			w["weight"] = WEAPON_WEIGHT
			w["cost"] = price_of(int(w.get("cost", 0)), discount_pct)
			pool.append(w)
	for key in upgrade_defs.keys():
		var u: Dictionary = upgrade_defs[key].duplicate()
		u["key"] = key
		u["kind"] = "upgrade"
		u["weight"] = RARITY_WEIGHT.get(int(u.get("rarity", 2)), 3.0)
		u["cost"] = price_of(int(u.get("cost", 0)), discount_pct)
		pool.append(u)
	return pool

# 一波打完的总收入（击杀掉落 + 通关奖励），用于配平
static func wave_income(wave: int, kills: int, avg_gold: float, cfg: Dictionary) -> int:
	return int(round(float(kills) * avg_gold)) + wave_bonus(wave, cfg)
