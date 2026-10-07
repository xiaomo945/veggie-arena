extends SceneTree

# =====================================================================
# 满 build 强度对比探针（阶段 D1 的取数端。只读，不进游戏运行时）
#
# 回答两个问题（都是用户原话里的事）：
#   A. **无一家独大**：13 个角色各自玩到自己的最强，彼此差多少？
#   B. **人设是不是真的**：按角色本命 build 玩，是不是就是最优解？
#
# 取数口径：**固定预算**。每个角色拿到【同样多的一笔钱】
# （= 通用玩家打到第 W 波的累计收入，由真实 Economy 产出），在预算内自己挑
# 6 把武器和等级。为什么必须是预算而不是"6 把满级随便挑"：后者等于假设资源
# 无限，实测会让 13 个角色全部算出"6 把叉子"（叉子 DPS 最高），角色差异被
# 武器基础强度一笔勾销，比较直接退化 —— 预算才是真实玩家面对的约束。
#
#   dps_best      预算内能达到的最强（任意搭配）→ 用于 A：角色间的强度差
#   dps_identity  预算内最强、且【本命堆满 + 羁绊类堆满】→ 用于 B：人设强度
#   identity      dps_identity / dps_best。接近 1 = 按人设玩就是最优解；
#                 明显小于 1 = 这个角色的人设是装饰，玩家照着玩反而更弱。
#
# 为什么不用"真实商店模拟"排名：它带随机性，而且贪心对"好凑的 build"天然更
# 友好 —— 实测给出 turnip 8.8 / mage 1.9 的 4.7 倍差，拆开看主要是可达性差异，
# 不是角色设计的差距。拿它排名会逼着配平去砍错的地方。它只留作参考列。
#
# 用法：godot --headless --path . --script res://scripts/fullbuild_probe.gd -- --waves=12
# =====================================================================

const SimCore := preload("res://scripts/SimCore.gd")
const DataScript := preload("res://autoload/Data.gd")
const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const Spawner := preload("res://core/Spawner.gd")
const Synergy := preload("res://core/Synergy.gd")

const MAX_WAVES := 12
const CAND_CAP := 14     # 候选池上限（本命 + 羁绊类 + DPS 最高的几把）
const SIM_RUNS := 3      # 参考列：真实商店模拟跑几局

var _base_cost := {}


func _mk(sim: SimCore, key: String, lv: int, ccfg: Dictionary) -> Dictionary:
	var d: Dictionary = sim.defs.get(key, {})
	var ms := Weapon.merged_stats(d, lv, ccfg)
	return {"key": key, "lv": lv,
		"dmg": float(ms.get("dmg", d.get("dmg", 1))),
		"cd": float(ms.get("cd", d.get("cd", 1.0))),
		"pellets": float(ms.get("pellets", d.get("pellets", 1)))}


func _weps(sim: SimCore, keys: Array, lv: int, ccfg: Dictionary) -> Array:
	var a: Array = []
	for k in keys:
		a.append(_mk(sim, k, lv, ccfg))
	return a


# 这套搭配在预算内能买到几级。价格走真实 ShopTiers.price_for_tier，
# 所以"选贵的还是选高级"这个取舍就是游戏里真实存在的那一个。
func _afford_lv(keys: Array, budget: float, max_lv: int, tiers) -> int:
	var lv := 1
	for L in range(2, max_lv + 1):
		var c := 0.0
		for k in keys:
			c += float(tiers.price_for_tier(int(_base_cost.get(k, 20)), L))
		if c > budget:
			break
		lv = L
	return lv


func _score(sim: SimCore, keys: Array, lv: int, ccfg: Dictionary, length: float,
		w: int) -> Dictionary:
	var cp := sim.combat_power(_weps(sim, keys, lv, ccfg), {})
	var es: Dictionary = cp["es"]
	var e := sim.ch.ehp(es, w, length, 0.0, sim.enemies) * float(cp["ctrl"])
	return {"dps": float(cp["dps"]), "skill_dps": float(cp["skill_dps"]),
		"ehp": e, "score": float(cp["dps"]) * e, "lv": lv}


# 枚举"可重复的 6 件组合"（必须允许重复：堆 6 把本命是 signature 档位的正解，
# 只搜不重复组合会让所有"堆同款"的角色被系统性低估）。
func _search(sim: SimCore, cand: Array, slots: int, ccfg: Dictionary, length: float,
		w: int, budget: float, max_lv: int, tiers, start: int, cur: Array,
		best: Dictionary, ident: Dictionary, need_sig: int, need_bond: int,
		bond_tag: String, sig_key: String) -> void:
	if cur.size() == slots:
		var lv := _afford_lv(cur, budget, max_lv, tiers)
		var s := _score(sim, cur, lv, ccfg, length, w)
		if float(s["score"]) > float(best.get("score", -1.0)):
			for k in s:
				best[k] = s[k]
			best["keys"] = cur.duplicate()
		if need_sig > 0 and need_bond > 0:
			var ws := _weps(sim, cur, lv, ccfg)
			if (Synergy.signature_count(ws, sig_key) >= need_sig
					and Synergy.bond_count(ws, bond_tag, sim.defs) >= need_bond
					and float(s["score"]) > float(ident.get("score", -1.0))):
				for k in s:
					ident[k] = s[k]
				ident["keys"] = cur.duplicate()
		return
	for i in range(start, cand.size()):
		cur.append(cand[i])
		_search(sim, cand, slots, ccfg, length, w, budget, max_lv, tiers, i, cur,
			best, ident, need_sig, need_bond, bond_tag, sig_key)
		cur.pop_back()


# 满档需要的件数。不能去调 Synergy._max_need —— 那是别的模块的私有函数，
# 架构守卫 R3 会拦（跨模块碰私有字段是本项目的头号耦合源）。
func _max_need(tiers) -> int:
	var m := 0
	for t in tiers:
		m = maxi(m, int((t as Dictionary).get("need", 0)))
	return m


func _med(arr: Array) -> float:
	var a: Array = arr.duplicate()
	a.sort()
	return float(a[a.size() / 2])


func _initialize() -> void:
	var waves := MAX_WAVES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--waves="):
			waves = int(a.split("=")[1])
	var data = DataScript.new()
	data.load_all()
	var wk: Dictionary = data.wok_cfg()
	var wok := ((1.0 + float(wk.get("tier1_fire", 0.3))) + (1.0 + float(wk.get("tier2_fire", 0.65)))
		* (1.0 + float(wk.get("tier2_dmg", 0.3)))) * 0.5
	var wcfg: Dictionary = data.wave_cfg()
	var scfg: Dictionary = data.spawn_cfg()
	var ccfg: Dictionary = data.combat_cfg()
	var shop: Dictionary = data.shop_cfg()
	var length := float(wcfg.get("length", 45))
	var slots := int(shop.get("max_slot", 6))
	var max_lv := int(shop.get("max_lv", 10))
	var tiers := ShopTiers.new()
	var clear_dps := Spawner.wave_total_hp(waves, scfg, data.enemies, length) / maxf(0.001, length)

	# 预算：通用玩家打到第 W 波的累计收入（真实 Economy 产出，不是拍脑袋常数）。
	# 每个角色拿到的钱完全一样 —— 差异只能来自角色自身的设计。
	var sim0 := SimCore.new()
	sim0.wok = wok
	var budget := 0.0
	for r in sim0.run(data, waves, 20261005):
		budget += float(r["income"])
	for k in data.weapons:
		_base_cost[str(k)] = int(data.weapon(str(k)).get("cost", 20))

	var out: Array = []
	for ck in data.characters:
		var ce: Dictionary = data.character(str(ck))
		ce["_key"] = str(ck)
		var sim := SimCore.new()
		sim.wok = wok
		sim.char_entry = ce
		sim.char_key = str(ck)
		sim.skills = data.skills_cfg()
		for k in data.enemies:
			sim.enemies[str(k)] = data.enemy(str(k))
		for k in data.weapons:
			sim.defs[str(k)] = data.weapon(str(k))

		# 候选池 = 本命 + 全部羁绊类 + DPS 最高的几把。
		# 必须把羁绊类全放进来：只按 DPS 取前几把会漏掉"弱但对本命关键"的那把，
		# 于是本命 build 永远搜不出来，identity 被算成 0 —— 那是探针的错。
		var sig_key := str((ce.get("signature", {}) as Dictionary).get("key", ""))
		var bond_tag := str((ce.get("bond", {}) as Dictionary).get("tag", ""))
		var cand: Array = []
		if sig_key != "":
			cand.append(sig_key)
		for k in data.weapons:
			var d: Dictionary = data.weapon(str(k))
			if bond_tag != "" and bond_tag in (d.get("tags", []) as Array):
				if not cand.has(str(k)):
					cand.append(str(k))
		var by_dps: Array = []
		for k in data.weapons:
			by_dps.append([str(k), Combat.weapon_dps(Weapon.merged_stats(
				data.weapon(str(k)), 1, ccfg))])
		by_dps.sort_custom(func(a, b): return a[1] > b[1])
		for p in by_dps:
			if cand.size() >= CAND_CAP:
				break
			if not cand.has(p[0]):
				cand.append(p[0])
		var need_sig := _max_need((ce.get("signature", {}) as Dictionary).get("tiers", []))
		var need_bond := _max_need((ce.get("bond", {}) as Dictionary).get("tiers", []))

		var best := {}
		var ident := {}
		_search(sim, cand, slots, ccfg, length, waves, budget, max_lv, tiers, 0, [],
			best, ident, need_sig, need_bond, bond_tag, sig_key)

		var sim_rows: Array = []
		for i in range(SIM_RUNS):
			var s2 := SimCore.new()
			s2.wok = wok
			s2.char_entry = ce
			s2.char_key = str(ck)
			s2.fav = 1.35
			s2.skills = data.skills_cfg()
			sim_rows.append(s2.run(data, waves, 20261005 + i * 7919)[waves - 1])

		var db := float(best.get("dps", 0.0))
		var di := float(ident.get("dps", 0.0))
		out.append({"key": str(ck), "en": str(ce.get("en", ck)),
			"signature": sig_key, "bond": bond_tag, "skill": str(ce.get("skill", "")),
			"build": " ".join(best.get("keys", [])), "lv": int(best.get("lv", 1)),
			"dps": db, "skill_dps": float(best.get("skill_dps", 0.0)),
			"ehp": float(best.get("ehp", 0.0)), "ratio": db / clear_dps,
			"ident_dps": di, "ident_build": " ".join(ident.get("keys", [])),
			"identity": (di / db) if db > 0.001 else 0.0,
			"sim_ratio": _med(sim_rows.map(func(r): return float(r["ratio_fight"])))})
	print(JSON.stringify({"waves": waves, "budget": budget, "slots": slots,
		"clear_dps": clear_dps, "chars": out}))
	quit()
