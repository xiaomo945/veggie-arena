extends RefCounted

# 角色【身份机制】的专属测试：杂食线（variety）+ 自带命中持续伤害（on_hit_dot）。
#
# 为什么从 test_synergy.gd 里拆出来：
#   test_synergy.gd 管的是"羁绊这条线有没有接对"（本命/羁绊/技能/道具四元素），
#   而这两条是"某几个角色独有的玩法机制"，性质不同；况且 synergy 那个文件
#   已经贴着 300 行红线（架构守卫 R1 是硬失败），塞进去会直接拦下。
#
# 这两条为什么值得单独钉死：
#   1) 杂食 variety 是全游戏唯一【不鼓励堆同一把】的成长线，和 bond 方向相反。
#      若哪天被人配成"堆件数"，田园萝卜的人设就没了，而且不会有任何报错 ——
#      它只会安静地退化成第 13 个"堆同一把"的角色。
#   2) on_hit_dot 存在的唯一理由是【上手门槛】：焦辣萝卜的"毒 + 灼烧"人设
#      原本只写在 tip 里、机制只挂在技能冷却上，玩家选它开枪三秒看不到一点火，
#      只看到自己普攻比别人低。这条测试保证"第一次命中就看得见"不会退化。

const Synergy := preload("res://core/Synergy.gd")
const Character := preload("res://core/Character.gd")
const SimChar := preload("res://scripts/SimChar.gd")
const SimCore := preload("res://scripts/SimCore.gd")

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)

func run(data) -> Dictionary:
	var defs: Dictionary = data.weapons
	var sets: Dictionary = data.weapon_sets
	var chars: Dictionary = data.characters

	# ---- 1) 杂食线只有田园萝卜有，且阶梯边际递增 ----
	var v_chars: Array = []
	for ck in chars:
		if not (chars[ck] as Dictionary).has("variety"):
			continue
		v_chars.append(ck)
		var vt := ((chars[ck] as Dictionary).get("variety", {}) as Dictionary).get("tiers", []) as Array
		var vprev := -1.0
		var vflat := 0
		for i in vt.size():
			var st := (vt[i] as Dictionary).get("stats", {}) as Dictionary
			var tot := 0.0
			for k in st:
				tot += absf(float(st[k]))
			if tot <= vprev:
				vflat += 1
			vprev = tot
		chk(vflat == 0, "%s 的杂食阶梯边际递增（异常档位数 %d）" % [ck, vflat])
	chk(v_chars == ["turnip"], "杂食线只有田园萝卜有（实际：%s）" % str(v_chars))

	# ---- 2) 类的清单不能和 weapon_sets.json 漂移 ----
	# Synergy.CLASSES 是写死的一份，加第六类武器时这里会失败提醒你同步。
	var drift: Array = []
	for c in Synergy.CLASSES:
		if not sets.has(c):
			drift.append(c)
	for s2 in sets:
		if str(s2) == "_doc":
			continue
		if not Synergy.CLASSES.has(str(s2)):
			drift.append(str(s2))
	chk(drift.is_empty(), "Synergy.CLASSES 与 weapon_sets.json 完全同步（差异：%s）" % str(drift))

	# ---- 3) 杂食数的是【种类】不是【件数】----
	var five_guns: Array = []
	for i in 5:
		five_guns.append({"key": "smg", "lv": 1})
	var mix3 := [{"key": "pistol", "lv": 1}, {"key": "cleaver", "lv": 1}, {"key": "whisk", "lv": 1}]
	var mix5 := mix3.duplicate()
	mix5.append({"key": "wok_scoop", "lv": 1})
	mix5.append({"key": "teapot", "lv": 1})
	chk(Synergy.variety_count(five_guns, defs) == 1,
		"5 把同一类枪只算 1 种（实际 %d）" % Synergy.variety_count(five_guns, defs))
	chk(Synergy.variety_count(mix3, defs) == 3,
		"3 把不同类算 3 种（实际 %d）" % Synergy.variety_count(mix3, defs))
	chk(Synergy.variety_count(mix5, defs) == 5, "五类各一把 = 5 种")

	# ---- 4) 杂食必须真的比"堆同一把"划算，否则它只是一句文案 ----
	var tp := chars["turnip"] as Dictionary
	var b_mix := Synergy.bonuses(mix3, tp, defs)
	var b_same := Synergy.bonuses(five_guns, tp, defs)
	chk(float(b_mix.get("dmg_pct", 0.0)) > float(b_same.get("dmg_pct", 0.0)),
		"田园萝卜：3 把不同类比 5 把同类伤害加成高（%.0f%% vs %.0f%%）"
		% [float(b_mix.get("dmg_pct", 0.0)) * 100.0, float(b_same.get("dmg_pct", 0.0)) * 100.0])
	var b5 := Synergy.bonuses(mix5, tp, defs)
	chk(float(b5.get("dmg_pct", 0.0)) >= 0.5,
		"杂食满档伤害加成到位（实测 %.0f%%）" % (float(b5.get("dmg_pct", 0.0)) * 100.0))
	var six_guns: Array = []
	for i in 6:
		six_guns.append({"key": "smg", "lv": 1})
	chk(float(b5.get("dmg_pct", 0.0)) > float(Synergy.bonuses(six_guns, tp, defs).get("dmg_pct", 0.0)) + 0.4,
		"杂食满档明显强于堆 6 把同类枪（这才是它值得单开一局的理由）")

	# ---- 5) 杂食进度必须进 HUD（看不见的进度等于不存在）----
	chk(Synergy.progress(mix3, tp, defs).has("variety"), "杂食进度会进 HUD 进度条")
	var vprog := Synergy.progress(mix5, tp, defs).get("variety", {}) as Dictionary
	chk(int(vprog.get("need_next", 9)) == 0, "五类凑齐后杂食已满档（不再提示还差几件）")

	# ---- 6) 角色自带命中持续伤害（焦辣萝卜"打中就着火"）----
	var dot_chars: Array = []
	for ck in chars:
		var dd := Character.on_hit_dot(chars[ck] as Dictionary)
		if dd.is_empty():
			continue
		dot_chars.append(ck)
		chk(float(dd.get("dur", 0.0)) > 0.0, "%s 的命中效果有持续时间" % ck)
		chk(float(dd.get("burn", 0.0)) + float(dd.get("poison_pct", 0.0)) > 0.0,
			"%s 的命中效果至少有一种伤害" % ck)
	chk(dot_chars.has("scorch"),
		"焦辣萝卜自带命中灼烧/中毒（实际有此机制的角色：%s）" % str(dot_chars))

	# ---- 7) 开局白送颠勺充能（爆炒萝卜：一进局就按，按一下就懂）----
	var swc: Array = []
	for ck in chars:
		var n := Character.start_wok_charges(chars[ck] as Dictionary)
		if n > 0:
			swc.append("%s×%d" % [ck, n])
	chk(Character.start_wok_charges(chars["sizzle"] as Dictionary) == 1,
		"爆炒萝卜开局自带 1 次颠勺（实际有此机制的角色：%s）" % str(swc))

	# ---- 8) 模拟器必须真的把命中 DoT 算进去（配平看不见的人设 = 不存在）----
	# 焦辣萝卜的面板是负的（dmg_pct -0.18 / rate_pct -0.08），全部收益压在"打中
	# 就着火"这一层上。模拟器不算它，13 角色强度排名看到的就是一个只有代价、
	# 没有收益的角色；而毒按敌人【最大血量】结算、敌血随波次二次成长，拿常数
	# 血量算毒（旧口径 59）会把第 12 波（真实 277）低估约 4.7 倍。
	var sc_entry := chars["scorch"] as Dictionary
	var d1 := SimChar.innate_dot(sc_entry, {}, 59.0, 1.0)
	var d12 := SimChar.innate_dot(sc_entry, {}, 277.0, 1.0)
	chk(d1 > 0.0, "焦辣萝卜的命中 DoT 在模拟器里有输出（%.2f/秒/只）" % d1)
	chk(d12 > d1 * 1.5,
		"毒伤随敌血成长：敌血 59→277 时 DoT %.2f→%.2f（不随敌血 = 人设失效）"
		% [d1, d12])
	chk(SimChar.innate_dot(chars["turnip"] as Dictionary, {}, 277.0, 10.0) == 0.0,
		"没有 on_hit_dot 的角色在模拟器里不产出 DoT")
	chk(absf(SimChar.lit_count(sc_entry, 1000.0, 38.0) - 38.0) < 0.001,
		"DoT 同时挂着的敌人数被同屏上限封住（刷新率再高也不超 max_alive）")
	# 接线层：DoT 必须进 combat_power 的输出，否则建模了也没人用
	var sim := SimCore.new()
	sim.char_entry = sc_entry
	sim.char_key = "scorch"
	sim.skills = data.skills_cfg()
	sim.spawn_ps = 10.0
	sim.alive_cap = 38.0
	sim.hp_avg = 59.0
	var lo := float(sim.combat_power([], {})["dps"])
	sim.hp_avg = 277.0
	var hi := float(sim.combat_power([], {})["dps"])
	chk(hi > lo and lo > 0.0,
		"命中 DoT 真的进了模拟器的输出（敌血 59→277 时 dps %.1f→%.1f）" % [lo, hi])

	return {"pass": _p, "fail": _f, "failures": _failures}
