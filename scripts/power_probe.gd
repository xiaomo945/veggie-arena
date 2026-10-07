extends SceneTree

# =====================================================================
# 每波强度规划探针（只读，不进游戏运行时）
# 数据源原则：**商店与经济一律直调真实 core/ 代码**，本文件不重造第二套公式。
#   敌人侧 Spawner.wave_total_hp ／ 玩家侧 Combat.weapon_dps + Inventory.buy_weapon
#   ／ 商店侧 Economy.build_pool + roll_offers（卡片构成、武器保底、价格全在里面）
#   ／ 合成侧 Inventory.merge_pairs ／ 收入侧 Economy.wave_income。
# ⚠️ 踩过的坑：早先手写"三选一商店"模型，等于假设每张卡都是玩家最想要的那张。
#   真实商店每波只保底 1~2 把武器卡（roll_offers 的 w_quota），其余全是道具，
#   于是模型把成长全记到武器上、ratio 冲到 20 —— 纯属建模偏差，不是游戏的问题。
# 用法：godot --headless --path . --script res://scripts/power_probe.gd -- --waves=12
# =====================================================================

const DataScript := preload("res://autoload/Data.gd")
const Spawner := preload("res://core/Spawner.gd")
const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")
const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopPlan := preload("res://core/ShopPlan.gd")
const SP := preload("res://tests/SrcParse.gd")

const MAX_WAVES := 12
const MAX_REROLL := 2    # 每波最多整店刷新几次（真实玩家要留钱，也要留时间）
const SURVIVAL_W := 0.6  # 生存/功能类道具相对最优输出卡的性价比（见 _shop 里的说明）
const RUNS := 5          # 商店是随机的：跑几局取中位数，不让单局运气决定配平

var _targets := 3
var _defs := {}          # key -> 武器原始 def（算对群折算要用 behavior / aoe）
var _wok := 1.7          # 锅气倍率（tier1 与 tier2 的中点）
var _pieces := 0         # 本局累计买了几件道具
var _gold := 0           # 钱包（_shop 要改它，用成员而不是来回传参）


# 对群折算：单把武器打 N 个目标时输出是单体的几倍。口径与 tests/test_weapon.gd
# 的 _multiplier 一致 —— 按单体 DPS 排会让 AOE/连锁武器显得很弱，逼着配平去堆
# 单体数值，正是用户嫌的"武器只是数值堆叠"。链式衰减现读源码，不抄常数。
func _group_mult(def: Dictionary) -> float:
	var beh := Weapon.behavior_of(def)
	if float(def.get("aoe", 0)) > 0.0 or beh == "pulse" or beh == "beam":
		return float(_targets)
	if beh == "chain":
		var m := 1.0
		var hop := 1.0
		for _i in range(int(def.get("chain", 0))):
			hop *= SP.const_val(SP.read("res://scenes/BulletSystem.gd"), "CHAIN_FALLOFF")
			m += hop
		return m
	return 1.6 if beh == "boomerang" else (1.15 if beh == "homing" else 1.0)


func _eff_dps(w: Dictionary, dmg_pct: float, rate_pct: float) -> float:
	var d: Dictionary = _defs.get(str(w.get("key", "")), {})
	return Combat.weapon_dps(w, dmg_pct, rate_pct) * _group_mult(d)


# 当前这堆武器若全停在 Lv1 会有多少输出 —— need_lv / eq_lv 的分母，
# 让"该到几级"这句话有一个和玩家手上武器同口径的尺子（不拿全武器的中位数糊弄）。
func _sum_d1(weapons: Array, ccfg: Dictionary) -> float:
	var t := 0.0
	for w in weapons:
		var d: Dictionary = _defs.get(str(w.get("key", "")), {})
		t += Combat.weapon_dps(Weapon.merged_stats(d, 1, ccfg)) * _group_mult(d)
	return t


# 当前总输出。pierce / aoe 只给保守折算（穿透要怪排队才吃得到、范围要够大才多打
# 到一个），完全不计会让探针只认 dmg/rate/crit 三类道具，把玩家算弱、把敌人配软。
func _total_dps(weapons: Array, st: Dictionary) -> float:
	var dp := float(st.get("dmg_pct", 0.0))
	var rp := float(st.get("rate_pct", 0.0))
	var pa := float(st.get("pellets_add", 0.0))
	var t := 0.0
	for w in weapons:
		var ww: Dictionary = w.duplicate()
		ww["pellets"] = float(w.get("pellets", 1)) + pa
		t += _eff_dps(ww, dp, rp)
	var cc := clampf(float(st.get("crit_chance", 0.0)), 0.0, 1.0)
	var pierce := 1.0 + 0.10 * minf(float(st.get("pierce_add", 0.0)), 4.0)
	var aoe := 1.0 + 0.08 * minf(float(st.get("aoe_add", 0.0)) / 20.0, 4.0)
	return t * (1.0 + cc * float(st.get("crit_mult", 0.0))) * pierce * aoe * _wok


# 本波敌人的加权平均掉金。⚠️ 必须按"这波真正会刷的怪"加权，不能对所有敌人取平均：
# 全体平均 6.08 金，但第 1 波只刷 grunt(2 金)，用全体平均会把前期收入虚高 4 倍。
func _avg_gold(data, scfg: Dictionary, w: int) -> float:
	var fc := 0.0
	var tc := 0.0
	if w >= int(scfg.get("fast_from_wave", 2)):
		fc = float(scfg.get("fast_chance", 0.18))
	if w >= int(scfg.get("tank_from_wave", 3)):
		tc = float(scfg.get("tank_chance", 0.13))
	if w >= int(scfg.get("tank_late_from_wave", 6)):
		tc = float(scfg.get("tank_chance_late", 0.1))
	var gc := maxf(0.0, 1.0 - fc - tc)
	return (gc * float(data.enemy("grunt").get("gold", 2))
		+ fc * float(data.enemy("fast").get("gold", 2))
		+ tc * float(data.enemy("tank").get("gold", 5)))


# 买这张卡能涨多少 DPS（买不了返回 -1）。用真实 Inventory 落法，不自己推演。
func _gain(weapons: Array, st: Dictionary, o: Dictionary, max_slot: int,
		max_lv: int, ccfg: Dictionary) -> float:
	var base := _total_dps(weapons, st)
	if str(o.get("kind", "")) == "weapon":
		var w2: Array = weapons.duplicate(true)
		if not Inventory.buy_weapon(w2, o, int(o.get("lv", 1)),
				int(o.get("cost", 0)), max_slot, ccfg, max_lv):
			return -1.0
		return _total_dps(w2, st) - base
	return _total_dps(weapons, Inventory.apply_upgrade(st.duplicate(), o)) - base


# 一间店的完整流程：抽卡 → 贪心买 → 有余钱就刷新再来一轮。
# 贪心按"每金币换到的 DPS"排，买得起的都买（真实玩家不会把有用的卡留在店里）。
# ⚠️ 合成（merge_pairs）绝不是每波无条件做：2 合 1 只涨 1.398 倍却少一半槽位，
#   总输出是【下降】的，真实玩家不会干。早先每波无条件合成，贪心买的同款武器
#   被一路合掉，6 把武器塌成 1 把（lv_list 只剩一个数字），输出直接失真。
#   合成真正的用处只有一个：满槽且啥也买不动时，腾出槽位去买更强的武器。
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
		for o in Economy.roll_offers(pool, n, rng, _gold):
			var g := _gain(weapons, st, o, max_slot, max_lv, ccfg)
			if g > 0.0:
				var pg := g / float(maxi(1, int(o.get("cost", 1))))
				best_pg = maxf(best_pg, pg)
				cand.append([o, pg])
			elif str(o.get("kind", "")) != "weapon":
				noncombat.append(o)
		# 生存 / 功能类道具（血上限、护甲、移速、吸血、锅气…）对 DPS 的增益是 0，
		# 但真实玩家一定会买 —— 不建模就会得出"后期钱永远花不掉"的假象
		# （实测第 19 波余钱攒到 3288，实际上是被探针自己判定成'没用'才剩下的）。
		# 折算成"约等于本店最优输出卡 60% 的性价比"，排在输出卡后面，钱就有去处了。
		for o in noncombat:
			cand.append([o, best_pg * SURVIVAL_W])
		cand.sort_custom(func(a, b): return a[1] > b[1])
		var bought := 0
		for c in cand:
			var o: Dictionary = c[0]
			var cost := int(o.get("cost", 0))
			if _gold < cost:
				continue
			var ok := true
			if str(o.get("kind", "")) == "weapon":
				ok = Inventory.buy_weapon(weapons, o, int(o.get("lv", 1)),
					cost, max_slot, ccfg, max_lv)
			else:
				st = Inventory.apply_upgrade(st, o)
				_pieces += 1
			if ok:
				_gold -= cost
				bought += 1
		if bought > 0:
			if rolls >= MAX_REROLL:
				break
			_gold -= Economy.reroll_cost(rolls, shop)
			rolls += 1
			continue
		# 一张都买不下：合成腾槽再试一轮；连合都没得合，就真的收手（钱留到下波）
		if Inventory.merge_pairs(weapons, max_lv, ccfg).is_empty():
			break
		rolls += 1


func _sim(data, waves: int, seed_base: int) -> Array:
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

	# 开局 2 把中位武器 Lv1（GameState.reset 给的手枪 + 冲锋枪）
	var dps1: Array = []
	for k in data.weapons:
		var d: Dictionary = data.weapon(str(k))
		dps1.append([str(k), Combat.weapon_dps(Weapon.merged_stats(d, 1, ccfg))])
	dps1.sort_custom(func(a, b): return a[1] < b[1])
	var start: Array = [dps1[dps1.size() / 2][0], dps1[maxi(0, dps1.size() / 2 - 1)][0]]
	var weapons: Array = []
	for k in data.weapons:
		_defs[str(k)] = data.weapon(str(k))
	for k in start:
		var d: Dictionary = data.weapon(str(k))
		var ms := Weapon.merged_stats(d, 1, ccfg)
		weapons.append({"key": str(k), "lv": 1,
			"dmg": float(ms.get("dmg", d.get("dmg", 1))),
			"cd": float(ms.get("cd", d.get("cd", 1.0))),
			"pellets": float(ms.get("pellets", d.get("pellets", 1)))})
	var per_lv := float(ccfg.get("merge_dmg_multiplier", 1.3)) / float(
		ccfg.get("merge_cd_multiplier", 0.93))

	var st := {}
	var gold := 0
	_gold = 0
	_pieces = 0
	var rows: Array = []
	for w in range(1, waves + 1):
		var total_hp := Spawner.wave_total_hp(w, scfg, data.enemies, length)
		var n_spawn := Spawner.spawn_rate(w, scfg) * length
		var clear_dps := total_hp / maxf(0.001, length)
		var base1 := _sum_d1(weapons, ccfg) * _wok   # 全槽都停在 Lv1 时的输出
		# ⚠️ 打这一波用的是【上一波商店之后】的战力，不是本波商店之后的。
		# 早先拿本波买完的 DPS 去比本波的清场需求，等于白送玩家一次采购，
		# ratio 系统性虚高，配平就会往"敌人再肉一点"的错误方向调。
		var dps := _total_dps(weapons, st)
		# 等效等级：把当前总输出反解成"相当于全槽升到几级"。道具、锅气的收益
		# 都折算进来，所以它会高于武器上的数字 —— 这正是用户问的"该到几级"。
		var lv := log(per_lv)
		var eq_lv := clampf(1.0 + log(dps / maxf(0.001, base1)) / lv, 1.0, float(max_lv))
		var need := clampf(1.0 + log(clear_dps / maxf(0.001, base1)) / lv, 1.0, float(max_lv))
		# 负反馈不能省：杀不完 → 钱少 → 更杀不完。假设"全清"会盖掉后期追不上。
		var avg_hp := total_hp / maxf(0.001, n_spawn)
		var kills := int(minf(n_spawn, dps * length / maxf(1.0, avg_hp)))
		var income := Economy.wave_income(w, kills, _avg_gold(data, scfg, w), wcfg)
		gold += income
		_gold = gold
		_shop(weapons, st, w, data, shop, ccfg, infl, max_slot, max_lv, rng)
		gold = _gold
		var top_lv := 1
		var lv_list := ""
		for x in weapons:
			top_lv = maxi(top_lv, int(x.get("lv", 1)))
			lv_list += "%d " % int(x.get("lv", 1))
		rows.append({"w": w, "n_spawn": n_spawn, "clear_dps": clear_dps,
			"lv_list": lv_list.strip_edges(), "base1": base1,
			"slots": weapons.size(), "top_lv": top_lv, "need_lv": need, "eq_lv": eq_lv,
			"income": income, "pieces": _pieces, "gold_left": int(gold),
			"dps_fight": dps, "dps_reach": _total_dps(weapons, st),
			"ratio_fight": dps / maxf(0.001, clear_dps),
			"kills": kills, "clear_frac": kills / maxf(1.0, n_spawn)})
	return rows


func _med(arr: Array) -> float:
	var a: Array = arr.duplicate()
	a.sort()
	return float(a[a.size() / 2])


func _initialize() -> void:
	var waves := MAX_WAVES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--waves="):
			waves = int(a.split("=")[1])
		elif a.begins_with("--targets="):
			_targets = int(a.split("=")[1])
	var data = DataScript.new()
	data.load_all()
	var wk: Dictionary = data.wok_cfg()
	_wok = ((1.0 + float(wk.get("tier1_fire", 0.3))) + (1.0 + float(wk.get("tier2_fire", 0.65)))
		* (1.0 + float(wk.get("tier2_dmg", 0.3)))) * 0.5

	var runs: Array = []
	for i in range(RUNS):
		runs.append(_sim(data, waves, 20261005 + i * 7919))
	var rows: Array = []
	for w in range(waves):
		var r: Dictionary = {}
		for k in runs[0][w]:
			if k == "lv_list":
				r[k] = runs[0][w][k]   # 字符串没法取中位数，直接看第 1 局
				continue
			var vals: Array = []
			for run in runs:
				vals.append(float(run[w][k]))
			r[k] = _med(vals)
		r["w"] = w + 1
		r["ratio_reach"] = float(r["dps_reach"]) / maxf(0.001, float(r["clear_dps"]))
		rows.append(r)
	print(JSON.stringify({"runs": RUNS, "targets": _targets, "wok": _wok, "rows": rows}))
	quit()
