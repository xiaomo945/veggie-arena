extends RefCounted

# 补给站节奏 + 单卡可控（docs/07 §5.5 的 Q5 / Q6，纯逻辑、可单测）
#
# Q5 商店节奏：不是每波都开一模一样的店。
#   - 大商店：每 big_every 波（默认 3）一次，卡更多 + 全场打折 —— 让玩家攒钱的那一波
#     有"采购爽感"，也给出"再撑两波就能大买"的节奏预期。
#   - 小商店：其余波次只有 2 张卡，快速选完就回战斗，不打断割草节奏。
# Q6 单卡可控：整店重刷常常把已经想要的卡刷没了，所以给两张"抓手"：
#   - 锁定：锁住的卡在整店刷新时保留（不会被抽走）
#   - 单张刷新：只换这一张，价格约为整店刷新的一半（省钱的取舍）
#
# 为什么单独一个文件：Shop.gd 已经 264 行，再加这些就顶穿 300 行架构红线。

const Economy := preload("res://core/Economy.gd")

# 本波是不是大商店（第 1 波也算大，开局给一次像样的采购）
static func is_big(wave: int, cfg: Dictionary) -> bool:
	var every := maxi(1, int(cfg.get("big_every", 3)))
	return wave <= 1 or wave % every == 0

# 本波开几张卡。
#
# ⚠️ 硬性产品约束（用户 2026-10-06 拍板）：【每一波都必须刷满 6 张，一个空位都不许留】。
#   旧设计"小商店只开 4 张（快速选完回战斗）"翻车了：卡片区是 3 列网格，4 张 = 第 2 行
#   只有 1 张卡 + 2 个空格，玩家看到的就是「商店坏了 / 道具刷不出来了」，还以为是
#   武器等级太高把货架卡住了（其实和等级毫无关系，纯粹是卡数少）。
#   现在大小商店一律 6 张 —— 网格永远铺满；大商店的额外好处改成【全场打折】。
#   ⚠️ small_offer_count 已废弃（从 data/balance.json 里删掉了）：加回来也是死配置。
static func offer_count(_wave: int, cfg: Dictionary) -> int:
	return maxi(1, int(cfg.get("big_offer_count", 6)))

# 本波的额外折扣（大商店才打折，与玩家自己的 shop_discount 叠加）
static func discount(wave: int, cfg: Dictionary) -> float:
	if not is_big(wave, cfg):
		return 0.0
	return clampf(float(cfg.get("big_discount_pct", 0.15)), 0.0, 0.6)

# 单张刷新的价格：整店刷的一半（向上取整，至少 1），避免比整店还贵
static func single_reroll_cost(times: int, cfg: Dictionary) -> int:
	var full := Economy.reroll_cost(times, cfg)
	var ratio := clampf(float(cfg.get("single_reroll_ratio", 0.5)), 0.1, 1.0)
	return maxi(1, int(ceil(float(full) * ratio)))

# 整店刷新但【保留锁定的卡】：先在池子里把锁定项排除，再补足剩下的卡位。
# locked: Array[int] = 被锁定的卡位下标（对应 offers 的下标）
static func reroll_keep(offers: Array, locked: Array, pool: Array, count: int,
		rng: RandomNumberGenerator, gold: int = -1) -> Array:
	var keep: Array = []
	var keep_keys: Array = []
	for i in locked:
		if i < 0 or i >= offers.size():
			continue
		var o = offers[i]
		keep.append(o)
		keep_keys.append(key_of(o))
	# 抽新的：池子里剔除"已保留"的同一件东西，避免重开一店出现两张一模一样的卡
	var rest: Array = []
	for it in pool:
		if keep_keys.has(key_of(it)):
			continue
		rest.append(it)
	var need := maxi(0, count - keep.size())
	var fresh := Economy.roll_offers(rest, need, rng, gold) if need > 0 else []
	var out: Array = []
	out.append_array(keep)
	out.append_array(fresh)
	return out

# 单张刷新：只换 index 这一张（已被锁定的卡不参与刷新）
static func reroll_one(offers: Array, index: int, pool: Array,
		rng: RandomNumberGenerator, gold: int = -1) -> Array:
	if index < 0 or index >= offers.size():
		return offers
	var cur: Variant = offers[index]
	# 排除【当前这张】（不能刷出一样的）+【店里其它卡】（避免同店出现两张一模一样的）
	var skip: Array = [key_of(cur)]
	for i in offers.size():
		if i != index:
			skip.append(key_of(offers[i]))
	var rest: Array = []
	for it in pool:
		if skip.has(key_of(it)):
			continue
		rest.append(it)
	var fresh := Economy.roll_offers(rest, 1, rng, gold)
	if fresh.is_empty():
		return offers
	var out: Array = offers.duplicate()
	out[index] = fresh[0]
	return out

# 一张卡的身份：种类 + key + 等级（同 key 同 lv 视为同一张，不重复上架）
static func key_of(o) -> String:
	if not (o is Dictionary):
		return str(o)
	var d := o as Dictionary
	return "%s|%s|%s" % [str(d.get("kind", "")), str(d.get("key", "")), str(d.get("lv", 0))]
