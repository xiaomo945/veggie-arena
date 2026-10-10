extends RefCounted

# 模拟 AI 的"买什么"决策 —— 纯逻辑（无渲染/无 autoload 依赖，可单测）。
#
# 为什么单独有这个文件：
#   以前 ui/Screens/Main.gd::_auto_shop 是"卡面顺序扫一遍，买得起就买"，而且落武器走
#   Inventory.merge_or_add —— 买一把 5 级能把手里 1 级的【直接跳到 5 级】（跳过 4 次
#   合成、只付一份钱）。结果模拟 AI 的战力虚高，playtest 测出的"死在第几波"偏乐观，
#   拿这条基线去调中期难度 = 把难度调到比实际更狠。
#   现在改成和 scripts/SimCore.gd（power_band 探针）同一套口径：
#     ① 落武器只走 Inventory.buy_weapon 的两态规则（有空槽占槽 / 满槽同档才合成）
#     ② 逐张贪心：每轮挑"每金币涨的 DPS 最高"的那张，买完再重排（买第一把会改变
#        后面每张的收益，一次性排序是错的）
#     ③ 生存/功能类道具（血/甲/移速）DPS 增益是 0，但真人一定会买 —— 按最优输出卡
#        的 SURVIVAL_W 折算，否则 AI 后期"钱花不出去"，金币结余数据也是假的。
#
# ⚠️ 不做无条件合成：2 合 1 只涨 1.398 倍却少一半槽位，总输出是下降的，真人不干
#    （SimCore._shop 里有同样的注释，两边必须保持一致）。

const Inventory := preload("res://core/Inventory.gd")

# 生存/功能类道具相对最优输出卡的性价比
const SURVIVAL_W := 0.6
# 一间店最多刷新几次（与 scripts/SimCore.gd 的 MAX_REROLL 同口径：
# 真人有钱会刷新，但不会无限刷 —— 刷新价越刷越贵，自然收敛）
const MAX_REROLL := 2

# 把 {"key": 份数} 折成属性字典（用真实 Inventory.apply_upgrade，口径和战斗一致）
static func stats_of(upgrades: Dictionary, defs: Dictionary) -> Dictionary:
	var st := {}
	for k in upgrades:
		var d = defs.get(str(k), {})
		for _i in int(upgrades[k]):
			st = Inventory.apply_upgrade(st, d)
	return st

static func dps(weapons: Array, st: Dictionary) -> float:
	return Inventory.total_dps(weapons, float(st.get("dmg_pct", 0.0)),
		float(st.get("rate_pct", 0.0)))

# 买这张卡能涨多少 DPS。买不了返回 -1.0（槽位/合成规则不允许）。
static func gain(weapons: Array, st: Dictionary, o: Dictionary,
		max_slot: int, max_lv: int, ccfg: Dictionary) -> float:
	var base := dps(weapons, st)
	if str(o.get("kind", "")) == "weapon":
		var w2: Array = weapons.duplicate(true)
		if not Inventory.buy_weapon(w2, o, int(o.get("lv", 1)),
				int(o.get("cost", 0)), max_slot, ccfg, max_lv):
			return -1.0
		return dps(w2, st) - base
	var st2 := Inventory.apply_upgrade(st.duplicate(), o)
	return dps(weapons, st2) - base

# 一间店的购买顺序：返回 offers 下标数组（已按"先买哪张"排好，且每张都买得起）。
# weapons 不会被改动（本函数只在副本上推演），真正落袋由调用方按返回值执行。
static func plan(offers: Array, weapons: Array, st: Dictionary, gold: int,
		max_slot: int, max_lv: int, ccfg: Dictionary) -> Array:
	var w2: Array = weapons.duplicate(true)
	var st2: Dictionary = st.duplicate()
	var money := gold
	var out: Array = []
	var pending: Array = []
	for i in offers.size():
		pending.append(i)
	# 本店见过的最高"每金币 DPS" —— 【跨轮保留】，不能每轮重置：
	#   输出卡通常在第 1~2 轮就被买光，之后的轮次里一张输出卡都不剩，若每轮重置
	#   best_pg 就会归零 → 生存卡折算价也归零 → AI 后半场一分钱花不出去，
	#   金币全攒着，测出来的"金币结余"又是假的（真实玩家记得住刚才的行情）。
	var best_pg := 0.0
	# 每轮重新打分：买到第 k 张之后，槽位与合成状态都变了，第 k+1 张的收益随之变。
	while pending.size() > 0:
		var pg_of := {}
		var noncombat := []
		for i in pending:
			var g := gain(w2, st2, offers[i], max_slot, max_lv, ccfg)
			if g <= 0.0:
				# 没涨 DPS：武器类直接弃（g<0 = 买不了），道具类按生存折算
				if g == 0.0 and str((offers[i] as Dictionary).get("kind", "")) != "weapon":
					noncombat.append(i)
				continue
			var pg := g / float(maxi(1, int((offers[i] as Dictionary).get("cost", 0))))
			pg_of[i] = pg
			if pg > best_pg:
				best_pg = pg
		for i in noncombat:
			pg_of[i] = best_pg * SURVIVAL_W
		var pick := -1
		var pick_pg := 0.0
		for i in pg_of:
			if float(pg_of[i]) > pick_pg:
				pick_pg = float(pg_of[i]); pick = int(i)
		if pick < 0:
			break
		var o: Dictionary = offers[pick]
		var cost := int(o.get("cost", 0))
		if money < cost:
			# 这张这辈子都买不起了（价格不会变便宜），本店放弃它，继续看下一张
			pending.erase(pick)
			continue
		if str(o.get("kind", "")) == "weapon":
			if not Inventory.buy_weapon(w2, o, int(o.get("lv", 1)), cost, max_slot, ccfg, max_lv):
				pending.erase(pick)
				continue
		else:
			st2 = Inventory.apply_upgrade(st2, o)
		money -= cost
		out.append(pick)
		pending.erase(pick)
	return out
