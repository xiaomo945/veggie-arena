extends RefCounted

# 武器槽与合成升级 —— 纯逻辑
# 规则（用户最终拍板）：同类武器"两把相同的→合成升一级"（2合1）；商店购买不再自动合成，
# 而是落一把独立成品占一个槽位，玩家在补给站点"合成"手动把两把相同的合上去。
# 另外支持"售出"：回收价 ≤ 买入价（默认 80%）。

const Combat := preload("res://core/Combat.gd")
const Weapon := preload("res://core/Weapon.gd")
const Stats := preload("res://core/Stats.gd")

# 还有没有空槽（任何"新买一把"都需要一个空槽，因为不再自动合成）
static func can_accept_slot(weapons: Array, max_slot: int) -> bool:
	return weapons.size() < max_slot

# 某档位武器能不能买（用户拍板的两态规则）：
#   - 有空槽 → 能买：单独占一格，不自动合
#   - 没空槽 → 只有当场上已有一把"同 key 同等级、且还没满级"的武器时才能买，
#               这一把会被直接合成进去（升一级）。否则买了没地方放，不能买。
static func can_accept_tier(weapons: Array, key: String, lv: int, max_slot: int, max_lv: int) -> bool:
	if can_accept_slot(weapons, max_slot):
		return true
	if lv >= max_lv:
		return false
	return find_tier(weapons, key, lv) >= 0

# 找"恰好等于某档位"的武器，返回索引；没有返回 -1
static func find_tier(weapons: Array, key: String, lv: int) -> int:
	for i in weapons.size():
		var w = weapons[i]
		if not (w is Dictionary):
			continue
		if str(w.get("key", "")) == key and int(w.get("lv", 1)) == lv:
			return i
	return -1

# 某 key 当前持有的最高等级（没持有返回 0）
static func owned_max_lv(weapons: Array, key: String) -> int:
	var top := 0
	for w in weapons:
		if w is Dictionary and str(w.get("key", "")) == key:
			top = maxi(top, int(w.get("lv", 1)))
	return top

# 把一把武器升到 new_lv（重算 dmg/cd），原地改 weapons[idx]
static func _upgrade_to(weapons: Array, idx: int, new_lv: int, combat_cfg: Dictionary) -> void:
	var w: Dictionary = weapons[idx]
	var dmg_mul := float(combat_cfg.get("merge_dmg_multiplier", 1.30))
	var cd_mul := float(combat_cfg.get("merge_cd_multiplier", 0.93))
	w["lv"] = new_lv
	w["dmg"] = int(round(float(w.get("dmg", 1)) * dmg_mul))
	w["cd"] = float(w.get("cd", 1.0)) * cd_mul
	weapons[idx] = w

# 买一把武器（用户拍板的两态落法）：
#   - 没满槽 → 单独占一个新格，不自动合（按 tier 重算 dmg/cd，记 buy_cost 供售出退款）
#   - 满  槽 → 找同 key 同等级的那一把，直接合成升一级；本次花费累加进它的 buy_cost，
#               保证"售出回收价 ≤ 总投入"。找不到搭档 / 该档已满级 → 买不了，返回 false。
# def 需含 key/dmg/cd（1级基准值）。返回 false 时钱不会被扣（由调用方负责退款）。
static func buy_weapon(weapons: Array, def: Dictionary, tier: int, cost: int, max_slot: int,
		combat_cfg: Dictionary = {}, max_lv: int = 99) -> bool:
	if weapons.size() < max_slot:
		var st: Dictionary = Weapon.merged_stats(def, maxi(1, tier), combat_cfg)
		var nw: Dictionary = {
			"key": str(def.get("key", "")),
			"lv": maxi(1, tier),
			"dmg": int(round(float(st.get("dmg", def.get("dmg", 1))))),
			"cd": float(st.get("cd", def.get("cd", 1.0))),
			"color": def.get("color", Color(1, 1, 1)),
			"buy_cost": maxi(0, cost),
		}
		weapons.append(nw)
		return true
	if tier >= max_lv:
		return false
	var ti := find_tier(weapons, str(def.get("key", "")), tier)
	if ti < 0:
		return false
	_upgrade_to(weapons, ti, tier + 1, combat_cfg)
	weapons[ti]["buy_cost"] = int(weapons[ti].get("buy_cost", 0)) + maxi(0, cost)
	return true

# 是否存在"两把相同 key 且相同等级（未满级）"可合成 —— 决定"合成"按钮是否可点
static func has_mergeable(weapons: Array, max_lv: int) -> bool:
	var seen: Dictionary = {}
	for w in weapons:
		if not (w is Dictionary):
			continue
		var lv := int(w.get("lv", 1))
		if lv >= max_lv:
			continue
		var k := str(w.get("key", "")) + "|" + str(lv)
		if seen.has(k):
			return true
		seen[k] = true
	return false

# 手动合成：把所有"同 key 同等级"的成对武器合并升一级（循环到没有可合为止）。
# 合出来的高档武器买入价 = 两把之和（保证售出不会凭空赚，也不会亏到买入总额之外）。
# 返回本次合成的 (key, 新等级) 列表，供表现层做特效。
static func merge_pairs(weapons: Array, max_lv: int, combat_cfg: Dictionary = {}) -> Array:
	var done: Array = []
	var again := true
	while again:
		again = false
		var seen: Dictionary = {}   # key|lv -> index
		for i in weapons.size():
			var w = weapons[i]
			if not (w is Dictionary):
				continue
			var lv := int(w.get("lv", 1))
			if lv >= max_lv:
				continue
			var k := str(w.get("key", "")) + "|" + str(lv)
			if seen.has(k):
				var j: int = seen[k]
				# j 升一级，i 被吸收（删除），买入价累加
				_upgrade_to(weapons, j, lv + 1, combat_cfg)
				weapons[j]["buy_cost"] = int(weapons[j].get("buy_cost", 0)) + int(w.get("buy_cost", 0))
				weapons.remove_at(i)
				done.append({"key": str(w.get("key", "")), "lv": lv + 1})
				again = true
				break
			seen[k] = i
	return done

# 找 weapons[idx] 的"另一把同 key 同等级"搭档下标；没有 / 自己已满级 → -1
static func partner_index(weapons: Array, idx: int, max_lv: int) -> int:
	if idx < 0 or idx >= weapons.size():
		return -1
	var w = weapons[idx]
	if not (w is Dictionary):
		return -1
	var lv := int(w.get("lv", 1))
	if lv >= max_lv:
		return -1
	var key := str(w.get("key", ""))
	for j in weapons.size():
		if j == idx:
			continue
		var o = weapons[j]
		if o is Dictionary and str(o.get("key", "")) == key and int(o.get("lv", 1)) == lv:
			return j
	return -1

# 该格此刻点下去能不能合成（用于给格子画金色"可合"高亮）
static func has_partner(weapons: Array, idx: int, max_lv: int) -> bool:
	return partner_index(weapons, idx, max_lv) >= 0

# 手动合成（用户拍板的"点格子"式）：点第 idx 格 → 另一把"同 key 同等级"的武器
# 被吸进来（那把从物品栏消失），本格升一级，买入价累加。没搭档 / 已满级 → false。
static func merge_into(weapons: Array, idx: int, max_lv: int, combat_cfg: Dictionary = {}) -> bool:
	var j := partner_index(weapons, idx, max_lv)
	if j < 0:
		return false
	# 成品统一停在"两格里靠左的那格"：删掉靠右的那格，靠左那格的位次就不会被挪动，
	# 玩家点左边或点右边得到的是同一个画面，不会有"怎么跳到隔壁格"的困惑。
	var dst := mini(idx, j)
	var src := maxi(idx, j)
	_upgrade_to(weapons, dst, int(weapons[dst].get("lv", 1)) + 1, combat_cfg)
	weapons[dst]["buy_cost"] = int(weapons[dst].get("buy_cost", 0)) + int(weapons[src].get("buy_cost", 0))
	weapons.remove_at(src)
	return true

# 售出第 idx 把武器：返回回收金币（≤ 买入价），并从数组移除。idx 越界返回 0。
static func sell_weapon(weapons: Array, idx: int, ratio: float) -> int:
	if idx < 0 or idx >= weapons.size():
		return 0
	# 至少保留 1 把武器，避免把最后一把卖掉后陷入"无武器软锁"
	if weapons.size() <= 1:
		return 0
	var w = weapons[idx]
	if not (w is Dictionary):
		return 0
	var bc := int(w.get("buy_cost", 0))
	var gain := int(floor(float(bc) * clampf(ratio, 0.0, 1.0)))
	weapons.remove_at(idx)
	return gain

# 买一把武器：能合成就升级，否则占新槽（保留给 headless 模拟器直接调用，不参与 UI 手动合成）。
static func merge_or_add(weapons: Array, def: Dictionary, max_slot: int, max_lv: int,
		combat_cfg: Dictionary = {}) -> bool:
	var key := str(def.get("key", ""))
	var buy_lv := int(def.get("lv", 1))
	if buy_lv > 1:
		var ti := find_tier(weapons, key, buy_lv - 1)
		if ti >= 0:
			_upgrade_to(weapons, ti, buy_lv, combat_cfg)
			return true
	var idx := -1
	for i in weapons.size():
		var w = weapons[i]
		if w is Dictionary and str(w.get("key", "")) == key and int(w.get("lv", 1)) < max_lv:
			idx = i
			break
	if idx >= 0:
		_upgrade_to(weapons, idx, int(weapons[idx].get("lv", 1)) + 1, combat_cfg)
		return true
	if weapons.size() >= max_slot:
		return false
	var nw: Dictionary = def.duplicate()
	nw["lv"] = buy_lv
	nw["buy_cost"] = int(def.get("cost", 0))
	if buy_lv > 1:
		var dmg_mul := float(combat_cfg.get("merge_dmg_multiplier", 1.30))
		var cd_mul := float(combat_cfg.get("merge_cd_multiplier", 0.93))
		nw["dmg"] = int(round(float(nw.get("dmg", 1)) * pow(dmg_mul, float(buy_lv - 1))))
		nw["cd"] = float(nw.get("cd", 1.0)) * pow(cd_mul, float(buy_lv - 1))
	weapons.append(nw)
	return true

# 把强化应用到属性表（stat 字段决定加到哪）
#
# 两种写法：
#   {"stat": "dmg_pct", "value": 0.2}                 —— 单属性，绝大多数道具
#   {"stats": {"dmg_pct": 0.5, "max_hp": -30}}        —— 多属性，用于"有取舍"的道具
#
# 为什么要多属性：只有单属性就做不出「玻璃大炮（伤害 +50%、血上限 -30）」
# 这类"拿好处要付代价"的道具，而这类道具才是构筑里真正让人纠结的东西。
static func apply_upgrade(stats: Dictionary, up: Dictionary) -> Dictionary:
	var multi = up.get("stats", null)
	if multi is Dictionary:
		for k in (multi as Dictionary):
			stats = _add_one(stats, str(k), (multi as Dictionary)[k])
		return stats
	return _add_one(stats, str(up.get("stat", "")), up.get("value", 0))

# 取出一个道具的全部属性条目（单属性 / 多属性统一成 [{"stat","value"}]）
static func stat_entries(up: Dictionary) -> Array:
	var out: Array = []
	var multi = up.get("stats", null)
	if multi is Dictionary:
		for k in (multi as Dictionary):
			out.append({"stat": str(k), "value": (multi as Dictionary)[k]})
	elif str(up.get("stat", "")) != "":
		out.append({"stat": str(up.get("stat", "")), "value": up.get("value", 0)})
	return out

static func _add_one(stats: Dictionary, stat: String, value) -> Dictionary:
	var v := float(value)
	match stat:
		# 血上限要连带把当前血一起抬，否则每买一次 +15 上限就要自己去补血
		"max_hp":
			stats["max_hp"] = float(stats.get("max_hp", 0)) + v
			stats["hp"] = minf(float(stats.get("hp", 0)) + v, float(stats.get("max_hp", 0)))
		"heal_now":
			stats["hp"] = minf(float(stats.get("hp", 0)) + v, float(stats.get("max_hp", 100)))
		_:
			# 其余属性一律走"同名累加"。白名单来自 core/Stats 的属性目录：
			# 以前这里是逐条 match，漏一条（crit_chance / melee_pct 就漏过）道具就
			# 静默失效 —— 买了强化、数字不变、还查不出原因。现在目录里有的就能加，
			# 目录里没有的照旧报警，下次加属性不用再回来改这里。
			if not is_known_stat(stat):
				push_warning("Inventory: 未知强化类型 " + stat)
				return stats
			stats[stat] = float(stats.get(stat, 0)) + v
	return stats

# 这条属性在目录里登记过吗（登记过 = 有真实供给源，见 core/Stats 顶部说明）
static func is_known_stat(stat: String) -> bool:
	for s in Stats.catalog():
		if str((s as Dictionary).get("key", "")) == stat:
			return true
	return false

# 当前武器总 DPS（用于配平模拟）
static func total_dps(weapons: Array, dmg_pct: float = 0.0, rate_pct: float = 0.0) -> float:
	var total := 0.0
	for w in weapons:
		if w is Dictionary:
			total += Combat.weapon_dps(w, dmg_pct, rate_pct)
	return total
