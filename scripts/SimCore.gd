extends RefCounted

# =====================================================================
# 整局模拟内核：商店 + 经济 + 战斗推演（只读，不进游戏运行时）
#
# 为什么抽出来：power_probe（通用玩家）与 fullbuild_probe（每角色本命 build）
# 必须跑【同一套】推演。历史教训：早先手写过一次"三选一商店"模型，等于假设每张
# 卡都是玩家最想要的那张，成长被全记到武器上、ratio 冲到 20 —— 纯属建模偏差。
# 两套口径 = 两次犯同样错的机会，所以只留一份实现，两个探针都是薄壳 CLI。
#
# 数据源原则：**一律直调真实 core/ 代码**，不重造第二套公式。
#   敌人侧 Spawner.wave_total_hp ／ 玩家侧 Combat.weapon_dps + Inventory.buy_weapon
#   ／ 商店侧 Economy.build_pool + roll_offers ／ 合成侧 Inventory.merge_pairs
#   ／ 收入侧 Economy.wave_income ／ 羁绊侧 Synergy.bonuses（在 SimChar 里）。
# =====================================================================

const DataScript := preload("res://autoload/Data.gd")
const Spawner := preload("res://core/Spawner.gd")
const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")
const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopPlan := preload("res://core/ShopPlan.gd")
const Synergy := preload("res://core/Synergy.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")
const SimChar := preload("res://scripts/SimChar.gd")
const SP := preload("res://tests/SrcParse.gd")

const MAX_REROLL := 2    # 每波最多整店刷新几次（真实玩家要留钱，也要留时间）
const SURVIVAL_W := 0.6  # 生存/功能类道具相对最优输出卡的性价比（见 _shop 里的说明）

var targets := 3
var defs := {}          # key -> 武器原始 def（算对群折算要用 behavior / aoe）
var wok := 1.7          # 锅气倍率（tier1 与 tier2 的中点）
var pieces := 0         # 本局累计买了几件道具
var gold := 0           # 钱包（_shop 要改它，用成员而不是来回传参）
var fav := 1.0          # 本命武器溢价：模拟玩家愿为羁绊多付钱（1.0 = 完全不偏心）
var char_entry := {}
var char_key := ""
var skills := []
var enemies := {}
var ch := SimChar.new()   # 角色侧建模（属性/技能/EHP）


# 对群折算：单把武器打 N 个目标时输出是单体的几倍。口径与 tests/test_weapon.gd
# 的 _multiplier 一致 —— 按单体 DPS 排会让 AOE/连锁武器显得很弱，逼着配平去堆
# 单体数值，正是用户嫌的"武器只是数值堆叠"。链式衰减现读源码，不抄常数。
func group_mult(def: Dictionary) -> float:
	var beh := Weapon.behavior_of(def)
	if float(def.get("aoe", 0)) > 0.0 or beh == "pulse" or beh == "beam":
		return float(targets)
	if beh == "chain":
		var m := 1.0
		var hop := 1.0
		for _i in range(int(def.get("chain", 0))):
			hop *= SP.const_val(SP.read("res://scenes/BulletSystem.gd"), "CHAIN_FALLOFF")
			m += hop
		return m
	return 1.6 if beh == "boomerang" else (1.15 if beh == "homing" else 1.0)


func eff_dps(w: Dictionary, dmg_pct: float, rate_pct: float) -> float:
	var d: Dictionary = defs.get(str(w.get("key", "")), {})
	return Combat.weapon_dps(w, dmg_pct, rate_pct) * group_mult(d)


# 当前这堆武器若全停在 Lv1 会有多少输出 —— need_lv / eq_lv 的分母，
# 让"该到几级"这句话有一个和玩家手上武器同口径的尺子。
func sum_d1(weapons: Array, ccfg: Dictionary) -> float:
	var t := 0.0
	for w in weapons:
		var d: Dictionary = defs.get(str(w.get("key", "")), {})
		t += Combat.weapon_dps(Weapon.merged_stats(d, 1, ccfg)) * group_mult(d)
	return t


# 当前总输出。pierce / aoe 只给保守折算（穿透要怪排队才吃得到、范围要够大才多打
# 到一个），完全不计会让探针只认 dmg/rate/crit 三类道具，把玩家算弱、把敌人配软。
func total_dps(weapons: Array, st: Dictionary) -> float:
	var rp := float(st.get("rate_pct", 0.0))
	var pa := float(st.get("pellets_add", 0.0))
	var t := 0.0
	for w in weapons:
		var key := str(w.get("key", ""))
		var d: Dictionary = defs.get(key, {})
		var ww: Dictionary = w.duplicate()
		ww["pellets"] = float(w.get("pellets", 1)) + pa
		# ⚠️ 伤害必须走 WeaponSets.damage_mult，不能只套 dmg_pct：实战里
		#    近战吃 melee_pct、远程吃 ranged_pct、元素额外吃 elem_pct
		#    （entities/Player/PlayerWeapons.gd 就这么算的）。只套 dmg_pct
		#    会把所有"元素流 / 近战流"角色的羁绊收益算成 0，排名彻底失真。
		t += Combat.weapon_dps(ww, 0.0, rp) * WeaponSets.damage_mult(d, st) * group_mult(d)
	var cc := clampf(float(st.get("crit_chance", 0.0)), 0.0, 1.0)
	var pierce := 1.0 + 0.10 * minf(float(st.get("pierce_add", 0.0)), 4.0)
	var aoe := 1.0 + 0.08 * minf(float(st.get("aoe_add", 0.0)) / 20.0, 4.0)
	return t * (1.0 + cc * float(st.get("crit_mult", 0.0))) * pierce * aoe * wok


# 武器 + 技能一起算：技能要么加输出，要么给攻速窗口，要么给生存系数。
func combat_power(weapons: Array, st: Dictionary) -> Dictionary:
	var es := ch.eff_st(weapons, st, char_entry, defs)
	var sp := ch.skill_parts(weapons, es, char_key, char_entry, defs, skills,
		targets, ch.avg_enemy_hp(enemies))
	return {"es": es,
		"dps": total_dps(weapons, es) * (1.0 + float(sp["rate"])) + float(sp["dps"]),
		"skill_dps": float(sp["dps"]), "ctrl": float(sp["ctrl"])}


# 本波敌人的加权平均掉金。⚠️ 按"这波真正会刷的怪"加权：第 1 波只刷 grunt(2 金)，用全体平均会虚高 4 倍。
func avg_gold(w: int, scfg: Dictionary) -> float:
	var fc := 0.0
	var tc := 0.0
	if w >= int(scfg.get("fast_from_wave", 2)):
		fc = float(scfg.get("fast_chance", 0.18))
	if w >= int(scfg.get("tank_from_wave", 3)):
		tc = float(scfg.get("tank_chance", 0.13))
	if w >= int(scfg.get("tank_late_from_wave", 6)):
		tc = float(scfg.get("tank_chance_late", 0.1))
	var gc := maxf(0.0, 1.0 - fc - tc)
	# ⚠️ 掉金必须带【波次成长】，与 core/Spawner.stats_for 同公式：
	#   gold = gold + round(wave * gold_per_wave)
	#   以前只取基础值（grunt 恒 2 金），真实第 11 波掉 19.6 金 —— 收入被低估约 10 倍，
	#   据此调出的通胀 / 血量全是错方向（玩家中期钱多到花不完，后期 ratio 冲到 22）。
	var per := ["grunt", "fast", "tank"]
	var wgt := [gc, fc, tc]
	var total := 0.0
	for i in per.size():
		var d: Dictionary = enemies.get(per[i], {}) as Dictionary
		total += wgt[i] * (float(d.get("gold", 2))
			+ float(w) * float(d.get("gold_per_wave", 0.0)))
	return total


func _favored(key: String, weapons: Array) -> bool:
	if char_entry.is_empty() or key.is_empty():
		return false
	if Synergy.is_signature(char_entry, key):
		return true
	if Synergy.in_bond(char_entry, key, defs):
		return true
	return Synergy.is_variety_gain(char_entry, key, defs, weapons)


# 买这张卡能涨多少 DPS（买不了返回 -1）。用真实 Inventory 落法，不自己推演。
# ⚠️ 基准与候选必须用【同一套】属性口径（都过一遍 eff_st 带上角色 + 羁绊）：
#    早先基准用道具裸属性、候选却带上羁绊，等于把羁绊的收益记成"这张卡的功劳"，
#    高羁绊角色每张卡都显得超值，贪心就会无脑买满 —— 排名因此完全失真。
func gain(weapons: Array, st: Dictionary, o: Dictionary, max_slot: int,
		max_lv: int, ccfg: Dictionary) -> float:
	var base := combat_power(weapons, st)["dps"] as float
	if str(o.get("kind", "")) == "weapon":
		var w2: Array = weapons.duplicate(true)
		if not Inventory.buy_weapon(w2, o, int(o.get("lv", 1)),
				int(o.get("cost", 0)), max_slot, ccfg, max_lv):
			return -1.0
		var g := (combat_power(w2, st)["dps"] as float) - base
		# 本命溢价：真实玩家为了吃满羁绊，会去买 DPS 略差但能跨档的那把。
		# 不建模这一条，探针就只会堆纯数值武器，羁绊系统被算成"不存在"。
		return g * (fav if _favored(str(o.get("key", "")), weapons) else 1.0)
	var st2 := Inventory.apply_upgrade(st.duplicate(), o)
	return (combat_power(weapons, st2)["dps"] as float) - base


# 一间店的完整流程：抽卡 → 贪心买 → 有余钱就刷新再来一轮。
# ⚠️ 合成（merge_pairs）绝不是每波无条件做：2 合 1 只涨 1.398 倍却少一半槽位，
#   总输出是【下降】的，真实玩家不会干。早先每波无条件合成，6 把武器塌成 1 把，
#   输出直接失真。合成真正的用处只有一个：满槽且啥也买不动时腾槽买更强的。
func _shop(weapons: Array, st: Dictionary, w: int, data, shop: Dictionary,
		ccfg: Dictionary, infl: float, max_slot: int, max_lv: int, rng) -> void:
	var disc := ShopPlan.discount(w, shop)
	var n := ShopPlan.offer_count(w, shop)
	var rolls := 0
	while rolls <= MAX_REROLL * 2:
		var pool := Economy.build_pool(weapons, data.weapons, data.upgrades,
			max_slot, max_lv, [], disc, w, infl)
		var cand: Array = []
		var best_pg := 0.0
		var noncombat: Array = []
		for o in Economy.roll_offers(pool, n, rng, gold):
			var g := gain(weapons, st, o, max_slot, max_lv, ccfg)
			if g > 0.0:
				var pg := g / float(maxi(1, int(o.get("cost", 1))))
				best_pg = maxf(best_pg, pg)
				cand.append([o, pg])
			elif str(o.get("kind", "")) != "weapon":
				noncombat.append(o)
		# 生存 / 功能类道具对 DPS 增益是 0，但真实玩家一定会买 —— 不建模就会得出
		# "后期钱永远花不掉"的假象（实测第 19 波余钱攒到 3288，其实是探针自己
		# 判定成'没用'才剩下的）。折算成最优输出卡 60% 的性价比，钱就有去处了。
		for o in noncombat:
			cand.append([o, best_pg * SURVIVAL_W])
		cand.sort_custom(func(a, b): return a[1] > b[1])
		var bought := 0
		for c in cand:
			var o: Dictionary = c[0]
			var cost := int(o.get("cost", 0))
			if gold < cost:
				continue
			var ok := true
			if str(o.get("kind", "")) == "weapon":
				ok = Inventory.buy_weapon(weapons, o, int(o.get("lv", 1)),
					cost, max_slot, ccfg, max_lv)
			else:
				st = Inventory.apply_upgrade(st, o)
				pieces += 1
			if ok:
				gold -= cost
				bought += 1
		if bought > 0:
			if rolls >= MAX_REROLL:
				break
			gold -= Economy.reroll_cost(rolls, shop)
			rolls += 1
			continue
		if Inventory.merge_pairs(weapons, max_lv, ccfg).is_empty():
			break
		rolls += 1


# 跑一局，返回每波一行。char_entry 为空 = 通用玩家（power_probe 的旧口径）。
func run(data, waves: int, seed_base: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	var wcfg: Dictionary = data.wave_cfg()
	var scfg: Dictionary = data.spawn_cfg()
	var ccfg: Dictionary = data.combat_cfg()
	var shop: Dictionary = data.shop_cfg()
	var length := float(wcfg.get("length", 45))
	var max_slot := int(shop.get("max_slot", 6))
	var max_lv := int(shop.get("max_lv", 10))
	var infl := float(shop.get("price_inflation", 0.0))
	enemies = {}
	for k in data.enemies:
		enemies[str(k)] = data.enemy(str(k))

	var weapons := _start_weapons(data, ccfg)
	var st := {}
	var rows: Array = []
	pieces = 0
	gold = 0
	for w in range(1, waves + 1):
		var cp := combat_power(weapons, st)
		var es: Dictionary = cp["es"]
		var total_hp := Spawner.wave_total_hp(w, scfg, data.enemies, length)
		var n_spawn := Spawner.spawn_rate(w, scfg) * length
		var clear_dps := total_hp / maxf(0.001, length)
		var base1 := sum_d1(weapons, ccfg) * wok
		# ⚠️ 打这一波用的是【上一波商店之后】的战力，不是本波商店之后的。
		# 早先拿本波买完的 DPS 去比本波清场需求，等于白送玩家一次采购，
		# ratio 系统性虚高，配平就会往"敌人再肉一点"的错误方向调。
		var dps := float(cp["dps"])
		var lv := log(float(ccfg.get("merge_dmg_multiplier", 1.3))
			/ float(ccfg.get("merge_cd_multiplier", 0.93)))
		var eq_lv := clampf(1.0 + log(dps / maxf(0.001, base1)) / lv, 1.0, float(max_lv))
		var need := clampf(1.0 + log(clear_dps / maxf(0.001, base1)) / lv, 1.0, float(max_lv))
		# 负反馈不能省：杀不完 → 钱少 → 更杀不完。假设"全清"会盖掉后期追不上。
		var avg_hp := total_hp / maxf(0.001, n_spawn)
		var kills := int(minf(n_spawn, dps * length / maxf(1.0, avg_hp)))
		var income := Economy.wave_income(w, kills, avg_gold(w, scfg), wcfg)
		gold += income
		_shop(weapons, st, w, data, shop, ccfg, infl, max_slot, max_lv, rng)
		var top_lv := 1
		var lv_list := ""
		for x in weapons:
			top_lv = maxi(top_lv, int(x.get("lv", 1)))
			lv_list += "%d " % int(x.get("lv", 1))
		rows.append({"w": w, "n_spawn": n_spawn, "clear_dps": clear_dps,
			"lv_list": lv_list.strip_edges(), "base1": base1,
			"slots": weapons.size(), "top_lv": top_lv, "need_lv": need, "eq_lv": eq_lv,
			"income": income, "pieces": pieces, "gold_left": int(gold),
			"dps_fight": dps, "dps_reach": combat_power(weapons, st)["dps"],
			"ratio_fight": dps / maxf(0.001, clear_dps),
			"ehp": ch.ehp(es, w, length, float(kills), enemies) * float(cp["ctrl"]),
			"skill_dps": float(cp["skill_dps"]), "kills": kills,
			"clear_frac": kills / maxf(1.0, n_spawn)})
	return rows


# 开局 2 把武器。有本命就从本命起手（真实玩家会这么选），否则取中位两把。
func _start_weapons(data, ccfg: Dictionary) -> Array:
	var dps1: Array = []
	for k in data.weapons:
		var d: Dictionary = data.weapon(str(k))
		defs[str(k)] = d
		dps1.append([str(k), Combat.weapon_dps(Weapon.merged_stats(d, 1, ccfg))])
	dps1.sort_custom(func(a, b): return a[1] < b[1])
	var start: Array = [dps1[dps1.size() / 2][0], dps1[maxi(0, dps1.size() / 2 - 1)][0]]
	if not char_entry.is_empty():
		var sig := str((char_entry.get("signature", {}) as Dictionary).get("key", ""))
		if sig != "" and defs.has(sig):
			start = [sig, sig]
	var weapons: Array = []
	for k in start:
		var d: Dictionary = defs.get(str(k), {})
		var ms := Weapon.merged_stats(d, 1, ccfg)
		weapons.append({"key": str(k), "lv": 1,
			"dmg": float(ms.get("dmg", d.get("dmg", 1))),
			"cd": float(ms.get("cd", d.get("cd", 1.0))),
			"pellets": float(ms.get("pellets", d.get("pellets", 1)))})
	return weapons
