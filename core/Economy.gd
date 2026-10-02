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

# 从池子里不重复抽 n 个。
#
# ⚠️ 武器保底（道具从 48 涨到 1150 后必须加）：等权重抽会让武器（权重 4）被 1150 个
# 道具（权重 6/3/1）稀释到 ~1%，玩家几乎刷不到武器、只能买到道具。这里把池子拆成
# "武器 / 非武器"两堆，先保底抽 1~2 把武器，再用原加权逻辑补齐其余，保证每间商店
# 都能看到武器（像 Brotato 那样武器和道具混着出）。
static func roll_offers(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var weapons := []
	var others := []
	for it in pool:
		if it is Dictionary and str(it.get("kind", "")) == "weapon":
			weapons.append(it)
		else:
			others.append(it)
	var out: Array = []
	# 保底武器数：offer_count=4 时给 1~2 把，且不超过当前可买的武器数
	var w_quota := 0
	if weapons.size() > 0:
		w_quota = clampi(int(ceil(float(count) * 0.5)), 1, mini(2, weapons.size()))
	for _i in w_quota:
		if weapons.is_empty():
			break
		var pick: Variant = _weighted_pick(weapons, rng)
		out.append(pick)
		weapons.erase(pick)
	# 其余名额：从"剩下的武器 + 全部非武器"里按原加权抽（不重复）
	var rest := weapons.duplicate()
	for o in others:
		rest.append(o)
	while out.size() < count and rest.size() > 0:
		var pick: Variant = _weighted_pick(rest, rng)
		out.append(pick)
		rest.erase(pick)
	return out

# 加权抽一个（从 items 里移除被抽中的，保证不重复）
static func _weighted_pick(items: Array, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for it in items:
		total += weight_of(it)
	var r := rng.randf() * total
	var pick := 0
	for i in items.size():
		r -= weight_of(items[i])
		if r <= 0.0:
			pick = i
			break
	return items[pick]

# 构造可用商品池：武器（槽位未满，或可合成）+ 全部强化
# weapons 里每项需含 "key" 与 "lv"
# unlocked_weapons: 已解锁的武器 key 列表。传空数组表示"全部可买"（默认，向后兼容）。
# rarity -> 抽取权重。稀有度越高越难出现，出现时才是"要不要为它改 build"的抉择。
const RARITY_WEIGHT := {1: 6.0, 2: 3.0, 3: 1.0}
# 武器与道具的相对权重：武器要凑满 6 个槽位，不能让 48 个道具把它淹掉
const WEAPON_WEIGHT := 4.0

# 打折 + 波次通胀后的价格。
# wave<=1 表示首店（刚结束第 1 波，还没经历通胀），不涨价；之后每过一关价格按
# inflation_pct 线性上涨：第 N 家店 multiplier = 1 + (N-1)*inflation_pct。
# 目的：让金币有处可花，避免"金币花不完、无限买买买"（用户核心诉求）。
static func price_of(base_cost: int, discount_pct: float, wave: int = 0, inflation_pct: float = 0.0) -> int:
	var p := float(base_cost)
	if inflation_pct > 0.0 and wave > 1:
		p *= (1.0 + float(wave - 1) * inflation_pct)
	if discount_pct > 0.0:
		p *= (1.0 - clampf(discount_pct, 0.0, 0.9))
	return maxi(1, int(round(p)))

static func build_pool(weapons: Array, weapon_defs: Dictionary, upgrade_defs: Dictionary, max_slot: int, max_lv: int, unlocked_weapons: Array = [], discount_pct: float = 0.0, wave: int = 0, inflation_pct: float = 0.0) -> Array:
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
			w["cost"] = price_of(int(w.get("cost", 0)), discount_pct, wave, inflation_pct)
			pool.append(w)
	for key in upgrade_defs.keys():
		var u: Dictionary = upgrade_defs[key].duplicate()
		u["key"] = key
		u["kind"] = "upgrade"
		u["weight"] = RARITY_WEIGHT.get(int(u.get("rarity", 2)), 3.0)
		u["cost"] = price_of(int(u.get("cost", 0)), discount_pct, wave, inflation_pct)
		pool.append(u)
	return pool

# 一波打完的总收入（击杀掉落 + 通关奖励），用于配平
static func wave_income(wave: int, kills: int, avg_gold: float, cfg: Dictionary) -> int:
	return int(round(float(kills) * avg_gold)) + wave_bonus(wave, cfg)
