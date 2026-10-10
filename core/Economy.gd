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
static func roll_offers(pool: Array, count: int, rng: RandomNumberGenerator, gold: int = -1) -> Array:
	var weapons := []
	var others := []
	var partners := []   # 合成搭档：买下去能直接跟已持有武器凑成对（同 key 同等级）
	var spares := []     # 备用道具：主池抽干时兜底补位（见下方"绝不留空位"）
	for it in pool:
		if it is Dictionary and bool(it.get("spare", false)):
			spares.append(it)
			continue
		if it is Dictionary and str(it.get("kind", "")) == "weapon":
			weapons.append(it)
			if it.get("merge_partner", false):
				partners.append(it)
		else:
			others.append(it)
	var out: Array = []
	# 保底武器数：offer_count=4 时给 1~2 把，且不超过当前可买的武器数
	var w_quota := 0
	if weapons.size() > 0:
		w_quota = clampi(int(ceil(float(count) * 0.5)), 1, mini(2, weapons.size()))
	# 先强制塞 1 把"合成搭档"：玩家持有 L 级，商店就必须 reliably 给得出 L 级去合 L+1。
	# 否则高级武器权重极低（5 级 0.28 vs 1 级 7），随机抽几乎永远抽不到那把关键的搭档，
	# "持有 5 级却合不出 6 级"。
	#
	# ⚠️ 保底选哪把 = user-facing 的经济阀门（2026-10-05 实测）：
	#   旧行为是无脑给"等级最高"的搭档。`max_lv` 提到 10 之后，最高档搭档到后期能标价几万
	#   （等级 ×2 复利 × 波次通胀），一张卡吃掉玩家两三波的全部收入 —— 结果是每间店有
	#   整整一个卡位永远买不动，金币就这么攒下来花不出去。
	#   现在改成给"买得起的最高那一档"；谁都买不起时退而求其次给"最便宜"的那张。
	#   保底位因此永远是一张玩家真能下单的卡，而不是一张纯观赏的贵卡。
	#   （`gold < 0` = 调用方没传钱包，退回旧的"最高级优先"，保持向后兼容。）
	var took_partner := 0
	if partners.size() > 0 and w_quota >= 1:
		var best: Variant = partners[0]
		for pp in partners:
			if partner_score(pp, gold) > partner_score(best, gold):
				best = pp
		out.append(best)
		weapons.erase(best)
		took_partner = 1
	# 覆盖位：第 2 张武器固定给【等级最低的持有武器】的搭档。
	#   为什么必须有：保底位永远给最高档（主力升级路径），随机位又在几十个候选里加权抽
	#   —— 玩家手里落在后面的低级武器（比如开局送的几把 Lv1）整局都等不到自己的搭档，
	#   "主力 10 级、还有 3 把 Lv1 合不上去"就是这么来的（真机反馈 2026-10-11）。
	#   有了覆盖位，每一波必刷一张"最落后武器"的搭档：买两张合成升一级，
	#   落后的武器就能一级一级追上来。并列最低时随机挑一把（多把 Lv1 轮着来）。
	if w_quota >= 2 and partners.size() > 0:
		var cover: Variant = null
		var cover_lv := 1 << 30
		var ties: Array = []
		for pp in partners:
			if not weapons.has(pp):
				continue   # 已被保底位选走
			var pl := int(pp.get("lv", 1))
			if pl < cover_lv:
				cover_lv = pl
				ties = [pp]
			elif pl == cover_lv:
				ties.append(pp)
		if ties.size() > 0:
			cover = ties[rng.randi() % ties.size()]
			out.append(cover)
			weapons.erase(cover)
			took_partner += 1
	for _i in (w_quota - took_partner):
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
	# 绝不留空位（用户硬要求：每一波必须刷满 6 个，一个空格都不许有）：
	#   旧代码到这里就 return 了 —— 池子抽干时返回 count 以内的任意个数，
	#   Shop.gd 却照着 _card_count 去铺卡片，于是货架上出现空卡片（玩家反馈
	#   "刷出来只有 4 个道具，剩下两个是空白"，一度被误以为是武器等级太高）。
	#   补位顺序：① 备用道具（data/upgrades.json 里 spare:true 的那几条，
	#   刻意做得"有用但不强"，不会变成必买卡）→ ② 连备用道具都不够时重复已有的卡
	#   （理论上到不了这一步：真实池子含 60+ 件道具，备用道具有 4 条）。
	for sp in spares:
		if out.size() >= count:
			break
		out.append(sp)
	while out.size() < count and out.size() > 0:
		out.append(out[rng.randi() % out.size()])
	return out

# 保底搭档的排序键：买得起的优先（其中等级越高越好）；全都买不起时给最便宜的那张。
static func partner_score(it: Dictionary, gold: int) -> int:
	var cost := int(it.get("cost", 0))
	if gold < 0 or cost <= gold:
		return 1000000 + int(it.get("lv", 1)) * 1000
	return -cost

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
# 备用道具（spare）的权重：只在主池抽干时兜底补位，正常抽卡几乎抽不到它
const SPARE_WEIGHT := 0.01

const ShopTiers := preload("res://core/ShopTiers.gd")

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
	var tiers := ShopTiers.new()
	var top_tier := tiers.max_tier_for_wave(wave, max_lv)
	for key in weapon_defs.keys():
		# 未解锁的武器根本不进池子（商店里看不到，也不会被抽到）
		if not unlocked_weapons.is_empty() and not unlocked_weapons.has(str(key)):
			continue
		# 按"玩家已持有等级"刷出可买的档位（未持有只刷1级；已持有L级刷[L-1,L]），
		# 再与波次上限取交集。可买性走两态规则：有空槽就能买；满槽则必须"场上有
		# 同等级可合"才刷出来（买下去直接合成升级），满槽且合成不了就不刷。
		var owned := Inventory.owned_max_lv(weapons, str(key))
		for lv in tiers.offer_tiers(owned, top_tier, max_lv):
			if not Inventory.can_accept_tier(weapons, str(key), lv, max_slot, max_lv):
				continue
			var w: Dictionary = weapon_defs[key].duplicate()
			w["key"] = key
			w["kind"] = "weapon"
			w["lv"] = lv
			w["weight"] = WEAPON_WEIGHT * tiers.tier_weight(lv)
			# 合成搭档：买下去能和已持有的"同 key 同等级"凑成对（满级除外）。
			# 这条标记让 roll_offers 保底给一把，否则高级武器权重极低，
			# "持有 5 级却永远刷不到第 2 把 5 级" → 5→6 永远合不出来。
			w["merge_partner"] = Inventory.find_tier(weapons, str(key), lv) >= 0 and lv < max_lv
			# 档位底价走 ShopTiers.price_for_tier（保证高级绝不便宜），再叠打折/通胀
			var base := int(w.get("cost", 0))
			var tier_base := tiers.price_for_tier(base, lv)
			w["base_cost"] = tier_base
			w["cost"] = price_of(tier_base, discount_pct, wave, inflation_pct)
			pool.append(w)
	for key in upgrade_defs.keys():
		var u: Dictionary = upgrade_defs[key].duplicate()
		var rar := int(u.get("rarity", 1))
		# 难度门禁：前几波不出现高阶道具（避免一上来就拿到厉害东西）
		if rar > tiers.max_rarity_for_wave(wave):
			continue
		u["key"] = key
		u["kind"] = "upgrade"
		# 备用道具不参与正常抽卡（roll_offers 会单独挑出来兜底），权重压到接近 0：
		# 万一哪天被并进主池，也不会污染正常出货率。
		u["weight"] = SPARE_WEIGHT if bool(u.get("spare", false)) else RARITY_WEIGHT.get(rar, 3.0)
		u["cost"] = price_of(int(u.get("cost", 0)), discount_pct, wave, inflation_pct)
		pool.append(u)
	return pool

# 一波打完的总收入（击杀掉落 + 通关奖励），用于配平
static func wave_income(wave: int, kills: int, avg_gold: float, cfg: Dictionary) -> int:
	return int(round(float(kills) * avg_gold)) + wave_bonus(wave, cfg)
