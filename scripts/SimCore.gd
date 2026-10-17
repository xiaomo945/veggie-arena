extends RefCounted

# =====================================================================
# 整局模拟内核：商店 + 经济 + 战斗推演（只读，不进游戏运行时）
#
# 为什么抽出来：power_probe（通用玩家）与 fullbuild_probe（每角色本命 build）必须跑同一套推演。
# 历史教训：早先手写过一次"三选一商店"模型，等于假设每张卡都是玩家最想要的那张，
# 成长被全记到武器上、ratio 冲到 20 —— 纯属建模偏差。两套口径 = 两次犯同样错的
# 机会，所以只留一份实现，两个探针都是薄壳 CLI。
#
# 数据源原则：**一律直调真实 core/ 代码**（敌人侧 Spawner ／ 玩家侧 Combat+Inventory ／
# 商店侧 Economy ／ 合成 Inventory ／ 收入 Economy ／ 羁绊 Synergy），不重造第二套公式。
# =====================================================================

const DataScript := preload("res://autoload/Data.gd")
const Spawner := preload("res://core/Spawner.gd")
const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")
const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopPlan := preload("res://core/ShopPlan.gd")
const Synergy := preload("res://core/Synergy.gd")
const SimChar := preload("res://scripts/SimChar.gd")
const SimDps := preload("res://scripts/SimDps.gd")

const MAX_REROLL := 2    # 每波最多整店刷新几次（真实玩家要留钱，也要留时间）
const SURVIVAL_W := 0.6  # 生存/功能类道具相对最优输出卡的性价比（见 _shop 里的说明）
const SURV_LINE_MAX := 6  # 每条非战斗线单局购买上限：贪心买家会把续抽放量的整条生存线买穿（实测 armor 14 件/heal 12 件），真实玩家按对局压力自主购买、不会这么干

var targets := 3
var defs := {}          # key -> 武器原始 def（算对群折算要用 behavior / aoe）
var de := SimDps.new()  # DPS 数学（对群折算/锅气档位/DoT），_sync() 后与上面同步
var wok_cfg := {}       # data/balance.json 的 wok 段（锅气档位倍率用）
var pieces := 0         # 本局累计买了几件道具
var gold := 0           # 钱包（_shop 要改它，用成员而不是来回传参）
var bought_keys := {}    # 已购强化 key -> 次数，供属性线续抽（与真机 GameState.upgrades 同口径）
var line_load := {}      # 各属性线(stat)已购件数：非战斗线饱和上限的判据（SURV_LINE_MAX）
var fav := 1.0          # 本命武器溢价：模拟玩家愿为羁绊多付钱（1.0 = 完全不偏心）
var char_entry := {}
var char_key := ""
var skills := []
var enemies := {}
# 模拟专用商店池（run() 里从 data.upgrades 过滤）：见 run() 里的注释
var sim_upgrades := {}
var ch := SimChar.new()   # 角色侧建模（属性/技能/EHP）
var hp_avg := 0.0       # 本波敌人平均血量：毒系结算的乘数（敌血随波次二次成长）
var spawn_ps := 0.0     # 本波每秒刷新只数：算"同时能点着几只"
var alive_cap := 38.0   # 同屏上限（spawn.max_alive）


# DPS 数学已拆去 scripts/SimDps.gd（锅气按角色浮动 + 自带 DoT 两项新口径没地方长）。
# 对外保留同名薄壳：探针（wspread_probe 的 sim.group_mult 等）调用点不变。
func _sync() -> void:
	de.defs = defs
	de.targets = targets
	de.wok_cfg = wok_cfg


func group_mult(def: Dictionary) -> float:
	_sync()
	return de.group_mult(def)


func eff_dps(w: Dictionary, dmg_pct: float, rate_pct: float) -> float:
	_sync()
	return de.eff_dps(w, dmg_pct, rate_pct)


# 武器 + 技能一起算：技能要么加输出、要么给攻速窗口、要么给生存系数，要么（heat 系）折算成锅气充能当量。
# 角色自带命中 DoT 也在这里进总输出（skill_parts 首行记 innate_dot，下面各技能 += 累加）—— 焦辣萝卜面板是负的，收益全压在这一层。
func combat_power(weapons: Array, st: Dictionary) -> Dictionary:
	var es := ch.eff_st(weapons, st, char_entry, defs)
	# 毒按【本波真实敌血】hp_avg 结算（拿波次无关的常数算会把第 12 波低估约 4.7 倍）；同时点着的敌人数 = min(同屏上限, 刷新率×持续秒)，静态检定（无波次数据）下限 1。
	var lit := ch.lit_count(char_entry, spawn_ps, alive_cap)
	var sp := ch.skill_parts(weapons, es, char_key, char_entry, defs, skills,
		targets, hp_avg, lit)
	# 锅气档位：角色/道具的 wok_pct + heat 技能的充能当量，一起把档位推向爆炒
	var wp := float(es.get("wok_pct", 0.0)) + float(sp.get("wok_pct", 0.0))
	_sync()
	return {"es": es,
		"dps": de.total(weapons, es, wp) * (1.0 + float(sp["rate"])) + float(sp["dps"]),
		"skill_dps": float(sp["dps"]), "ctrl": float(sp["ctrl"]),
		"wok_mult": de.wok_mult(wp),
		# 诊断字段（不进 dps 链，避免与 skill_parts 里的 innate 双计）：dot_dps=单只怪覆盖率折算，innate_dps=全场被动总量。
		"dot_dps": ch.dot_dps(char_entry, es, hp_avg),
		"innate_dps": ch.innate_dot(char_entry, es, hp_avg, lit)}


# 本波加权平均掉金。⚠️ 必须按"这波真正会刷的怪"加权：全体平均 6.08 金，第 1 波只刷 grunt(2 金)，取全体平均会把前期收入虚高 4 倍。
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
	# ⚠️ 掉金必须带【波次成长】，与 core/Spawner.stats_for 同公式 gold = gold + round(wave*gold_per_wave)：
	#   以前只取基础值（grunt 恒 2 金），真实第 11 波掉 19.6 金 —— 收入被低估约 10 倍，
	#   据此调出的通胀/血量全是错方向（玩家中期钱多到花不完，后期 ratio 冲到 22）。
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


# 买这张卡能涨多少 DPS（买不了返回 -1），用真实 Inventory 落法不自己推演。
# ⚠️ 基准与候选必须同一口径（都过 eff_st 带角色+羁绊）：早先基准用裸属性、候选带羁绊，等于把羁绊收益记成卡的功劳。
func gain(weapons: Array, st: Dictionary, o: Dictionary, max_slot: int,
		max_lv: int, ccfg: Dictionary) -> float:
	var base := combat_power(weapons, st)["dps"] as float
	if str(o.get("kind", "")) == "weapon":
		var w2: Array = weapons.duplicate(true)
		if not Inventory.buy_weapon(w2, o, int(o.get("lv", 1)),
				int(o.get("cost", 0)), max_slot, ccfg, max_lv):
			return -1.0
		var g := (combat_power(w2, st)["dps"] as float) - base
		# 本命溢价：真实玩家为吃满羁绊，会去买 DPS 略差但能跨档的那把；不建模这条，探针只堆纯数值武器、羁绊系统被算成"不存在"。
		return g * (fav if _favored(str(o.get("key", "")), weapons) else 1.0)
	var st2 := Inventory.apply_upgrade(st.duplicate(), o)
	return (combat_power(weapons, st2)["dps"] as float) - base


# 一间店的完整流程：抽卡 → 贪心买 → 有余钱就刷新再来一轮。
# ⚠️ 合成不是每波无条件做：2 合 1 只涨 1.398 倍却少一半槽位，总输出反而下降 —— 真实玩家只在满槽且买不动时合成腾槽。
func _shop(weapons: Array, st: Dictionary, w: int, data, shop: Dictionary,
		ccfg: Dictionary, infl: float, max_slot: int, max_lv: int, rng) -> void:
	var disc := ShopPlan.discount(w, shop)
	var n := ShopPlan.offer_count(w, shop)
	var rolls := 0
	while rolls <= MAX_REROLL * 2:
		# 模拟专用池（滤掉送技能道具，防采购序列扭曲）+ 已购记录（属性线续抽 pity）
		var pool := Economy.build_pool(weapons, data.weapons, sim_upgrades,
			max_slot, max_lv, [], disc, w, infl, bought_keys)
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
		# 生存/功能类道具对 DPS 增益是 0，但真实玩家一定会买 —— 不建模就会得出"后期钱花不完"的假象（实测第 19 波余钱攒到 3288）。按最优输出卡 60% 性价比折算。
		# ⚠️ 饱和上限：续抽放量后贪心买家会把整条生存线买穿（armor 14 件 / heal 12 件），金币全砸生存线、dps 腰斩出带 —— 超出 SURV_LINE_MAX 的线不再以性价比进场。
		for o in noncombat:
			if int(line_load.get(str(o.get("stat", "")), 0)) < SURV_LINE_MAX:
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
				var bk := str(o.get("key", "")); bought_keys[bk] = int(bought_keys.get(bk, 0)) + 1
				var bs := str(o.get("stat", ""))
				if bs != "": line_load[bs] = int(line_load.get(bs, 0)) + 1
			if ok:
				gold -= cost
				bought += 1
		if bought > 0:
			if rolls >= MAX_REROLL:
				break
			# ⚠️ 刷新也要先问买不买得起（真实 UI 有 can_buy 前置检查）：漏了曾让探针刷出负金币（w6 -4），等于开一笔不用还的刷新贷。
			var rc := Economy.reroll_cost(rolls, shop, w, infl)
			if gold < rc:
				break
			gold -= rc
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
	wok_cfg = data.wok_cfg()
	_sync()
	var length := float(wcfg.get("length", 45))
	var max_slot := int(shop.get("max_slot", 6))
	var max_lv := int(shop.get("max_lv", 10))
	var infl := float(shop.get("price_inflation", 0.0))
	enemies = {}
	for k in data.enemies:
		enemies[str(k)] = data.enemy(str(k))
	# 送技能的道具（upgrades 的 skill 字段）整个滤出模拟商店池：模拟器只折算
	# 【角色本命技】，估不出赠送技的价。硬塞进池子只有两种坏结果 ——
	#   ① 当成 0 收益生存件买下：每买一件就触发下一轮抽卡，采购序列被扭曲成另一局游戏（实测 w19 ratio 2.30 → 3.02 出带）；
	#   ② 占着货架位却永远不买：中等波次被抽干（w12 ratio 1.89 → 1.34）。
	# 保守起见整个过滤：真实玩家因赠送技变出来的那份强，模拟选择看不见 —— 低估可以接受，扭曲不行。
	sim_upgrades = {}
	for k in data.upgrades:
		if str((data.upgrades[k] as Dictionary).get("skill", "")) == "":
			sim_upgrades[str(k)] = data.upgrades[k]

	var weapons := _start_weapons(data, ccfg)
	var st := {}
	var rows: Array = []
	pieces = 0; bought_keys = {}; line_load = {}
	gold = 0
	for w in range(1, waves + 1):
		var sr := Spawner.spawn_rate(w, scfg)
		var total_hp := Spawner.wave_total_hp(w, scfg, data.enemies, length)
		var n_spawn := sr * length
		hp_avg = total_hp / maxf(0.001, n_spawn)
		spawn_ps = sr
		alive_cap = float(scfg.get("max_alive", 38))
		var cp := combat_power(weapons, st)
		var es: Dictionary = cp["es"]
		var clear_dps := total_hp / maxf(0.001, length)
		# base1 与 dps 同一套锅气档位/被动 DoT 口径：eq_lv 量"武器爬了几级"，不能被角色被动污染
		# （早先 base1 固定中点、dps 浮动，scorch 虚高）；被动 DoT 与武器等级无关，两边都带才公平。
		var base1 := (de.sum_lv1(weapons, ccfg, float(cp.get("innate_dps", 0.0)))) \
			* float(cp.get("wok_mult", 1.7))
		# ⚠️ 打这一波用的是【上一波商店之后】的战力：早先拿本波买完的 DPS 比本波清场需求，
		# 等于白送玩家一次采购，ratio 系统性虚高，配平往"敌人再肉一点"的错误方向调。
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
