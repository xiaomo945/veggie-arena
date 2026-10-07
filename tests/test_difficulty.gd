extends RefCounted

# 难度曲线守卫：把用户提的诉求写成硬断言，防止数值被"顺手调回去"。
#
# 原始反馈（一条都不能忘）：
#   1) "第 5 波我已经装备 6 级全满了，而且第 5 波看不到怪，怪就被打死了"
#   2) "怪物密度要大幅增加"
#   3) "血量也是大幅增加"
#   4) "移动速度太快了"
#   5) "提升要慢点"
#
# 这个文件的价值在于"锚定"：谁都可以觉得某个数字该调大调小，
# 但只要这些诉求里任何一条被回退，这里立刻红 —— 想改必须先改这里的断言并说明理由。

const Spawner := preload("res://core/Spawner.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const Combat := preload("res://core/Combat.gd")

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
	var sp: Dictionary = data.spawn_cfg()
	var enemies: Dictionary = data.enemies
	var st := ShopTiers.new()
	var player_spd := float(data.player_cfg().get("speed", 300))

	# ---- 诉求：怪物密度要大幅增加 ----
	# 标定依据（scripts/balance_model.py 实测，见 balance.json 的 _doc_density）：
	# max_alive 是断崖式生死线（38→40 普通画像直接崩到第1波），同屏数不敢大幅加；
	# "密度大幅增加"由 base_rate/per_wave/各怪 chance 承担，后期靠血量斜率。
	# 所以这里的门槛按实测可玩值定，不是按"看起来应该很大"定。
	chk(float(sp.get("base_rate", 0.0)) >= 2.8,
		"第 1 波起刷怪 ≥2.8 只/秒（实测 %.2f，开场不再空荡）" % float(sp.get("base_rate", 0.0)))
	chk(float(sp.get("per_wave", 0.0)) >= 0.6,
		"每波密度增量 ≥0.6（实测 %.2f，后期爬升够陡）" % float(sp.get("per_wave", 0.0)))
	# 关键：cap 不能很早封顶，否则第 10 波之后每波难度完全一样（= "玩到后面没变化"）
	chk(st.max_tier_for_wave(1) >= 1, "第 1 波至少有 1 档武器可买（门禁不至于把商店锁死）")
	chk(Spawner.spawn_rate(20, sp) > Spawner.spawn_rate(1, sp) * 3.0,
		"第 20 波密度 ≥第 1 波的 3 倍（%.2f vs %.2f）" % [
			Spawner.spawn_rate(20, sp), Spawner.spawn_rate(1, sp)])
	# 速率上限到第 20 波才吃到（不能第 10 波就撞 cap）
	var cap := float(sp.get("cap", 0.0))
	var uncapped_at_20: bool = float(sp.get("base_rate", 0.0)) + 20.0 * float(sp.get("per_wave", 0.0)) < cap
	chk(uncapped_at_20, "速率上限留有余量：base+20*per=%.2f 应高于 cap=%.2f（第 20 波正好吃满上限）"
		% [float(sp.get("base_rate", 0.0)) + 20.0 * float(sp.get("per_wave", 0.0)), cap])
	# max_alive 用"上下夹逼"守：不能太小（ Density 诉求落空），也不能太大（必崩）。
	# 上界 40 是 balance_model 实测出的断崖线（39 活 / 40 死），留 1 只余量防临界抖动。
	chk(int(sp.get("max_alive", 0)) >= 38,
		"同屏上限 ≥38 只（实测 %d）" % int(sp.get("max_alive", 0)))
	chk(int(sp.get("max_alive", 0)) <= 40,
		"同屏上限 ≤40 只（实测 %d）：超过就是断崖线，普通画像会第1波就死" % int(sp.get("max_alive", 0)))
	# 各类怪出现概率必须比原版高（"密度增加"的真实载体）
	var chance_up := {"tank_chance": 0.13, "fly_chance": 0.17, "swarm_chance": 0.09,
		"brute_chance": 0.09, "shooter_chance": 0.065, "bomber_chance": 0.04}
	var low_chance := []
	for k in chance_up:
		if float(sp.get(k, 0.0)) < float(chance_up[k]):
			low_chance.append(k)
	chk(low_chance.is_empty(),
		"重甲/飞行/集群/爆破等怪的出现概率均 ≥ 标定值"
		+ ("" if low_chance.is_empty() else " 偏低: " + str(low_chance)))

	# ---- 诉求：血量大幅增加 ----
	# 形状是"前平后陡"：hp_base 基本持平（原 15 → 14.2），
	# hp_per_wave 拉斜率，hp_accel 二次项负责"后期陡起来"。
	# 直接调真实 Spawner.stats_for（含 hp_accel），让断言反映真实游戏，
	# 而不是一套会和 core 漂离的本地简化公式。
	var gr: Dictionary = enemies.get("grunt", {}) as Dictionary
	var hp1 := float(Spawner.stats_for("grunt", 1, enemies).get("hp", 0.0))
	var hp20 := float(Spawner.stats_for("grunt", 20, enemies).get("hp", 0.0))
	chk(hp20 > hp1 * 6.0, "小兵第 20 波血量 ≥第 1 波的 6 倍（%.0f vs %.0f）" % [hp20, hp1])
	# 后期强度才是"第5波满级秒怪"的解药：第 20 波小兵必须够厚
	chk(hp20 >= 300.0,
		"小兵第 20 波血量 ≥300（实测 %.0f；满级武器一波秒不完）" % hp20)
	var no_curve := []
	for k in enemies:
		if k == "_doc":
			continue
		var e: Dictionary = enemies[k] as Dictionary
		if float(e.get("hp_per_wave", 0.0)) <= 0.0:
			no_curve.append(str(k))
	chk(no_curve.is_empty(),
		"每种怪都有 hp_per_wave 曲线" + ("" if no_curve.is_empty() else " 缺: " + str(no_curve)))
	# 整波总血量必须随波次显著增长（这才是"怪打不完"的根因）
	var w1 := Spawner.wave_total_hp(1, sp, enemies, 60.0)
	var w10 := Spawner.wave_total_hp(10, sp, enemies, 60.0)
	chk(w10 > w1 * 3.0, "第 10 波整波总血量 ≥第 1 波的 3 倍（%.0f vs %.0f）" % [w10, w1])

	# ---- 诉求：第一关怪稍快，但移动速度有硬上限（不能快到不跟手）----
	# 新设计（用户最新反馈）：开局玩家比怪略慢一点（制造张力、逼走位），
	# 后期靠 speed_pct 道具反超，但玩家有 speed_cap 硬封顶（balance.json 的 speed_cap），
	# 避免 speed_pct 道具无限堆导致"移速过高、操作不跟手"。
	var spd_cap := float(data.player_cfg().get("speed_cap", 999.0))
	# 1) 第 1 波小兵应比玩家基础速度"稍快一点点"——这就是游戏开局张力的来源
	var grunt1 := float(gr.get("speed_base", 0.0)) + 1.0 * float(gr.get("speed_per_wave", 0.0))
	chk(grunt1 >= player_spd * 0.9 and grunt1 <= player_spd * 1.25,
		"第1波小兵 %.0f ∈ 玩家[%.0f,%.0f] 的 [0.9,1.25] 倍（开局怪稍快一点点，靠走位/道具反超）"
		% [grunt1, player_spd * 0.9, player_spd * 1.25])
	# 2) 任何怪第 20 波都不能超过玩家"硬上限"——否则满级玩家也甩不掉它（黏死）
	var over_cap := []
	var too_fast := []
	for k in enemies:
		if k == "_doc":
			continue
		var e2: Dictionary = enemies[k] as Dictionary
		var s20 := float(e2.get("speed_base", 0.0)) + 20.0 * float(e2.get("speed_per_wave", 0.0))
		if s20 > spd_cap:
			over_cap.append("%s(%.0f)" % [str(k), s20])
		if float(e2.get("speed_per_wave", 0.0)) > 3.0:
			too_fast.append("%s(%.1f)" % [str(k), float(e2.get("speed_per_wave", 0.0))])
	chk(over_cap.is_empty(),
		"没有任何怪在第 20 波超过玩家硬上限 %.0f" % spd_cap
		+ ("" if over_cap.is_empty() else " 超速: " + str(over_cap)))
	chk(too_fast.is_empty(),
		"所有怪 speed_per_wave ≤3.0（移速增长已放缓）" + ("" if too_fast.is_empty() else " 过快: " + str(too_fast)))

	# ---- 诉求：提升要慢点（第 5 波不该满级）----
	chk(st.max_tier_for_wave(4) <= 2,
		"第 4 波最高只能买 2 档武器（实测 %d 档）—— 满级不可能在第 5 波发生" % st.max_tier_for_wave(4))
	chk(st.max_tier_for_wave(6) <= 3,
		"第 6 波最高 3 档（实测 %d 档）" % st.max_tier_for_wave(6))
	chk(st.max_tier_for_wave(18) < 6, "第 18 波还买不到满级 6 档（实测 %d 档）" % st.max_tier_for_wave(18))
	chk(st.max_tier_for_wave(19) >= 6, "第 19 波才解锁满级 6 档（实测 %d 档）" % st.max_tier_for_wave(19))
	chk(st.max_tier_for_wave(13) < st.max_tier_for_wave(19),
		"高阶门禁确实随波次逐步放开（第 13 波 %d 档 < 第 19 波 %d 档）"
		% [st.max_tier_for_wave(13), st.max_tier_for_wave(19)])
	# 高阶权重必须远低于低阶（否则"白送第二把 5 级"又回来了，第 5 波满级）
	var w1v := st.tier_weight(1)
	var w6v := st.tier_weight(6)
	chk(w6v > 0.0 and w1v / w6v >= 50.0,
		"1 级与 6 级权重比 ≥50:1（实测 %.0f:1），高阶不会白送" % (w1v / maxf(0.0001, w6v)))
	chk(int(data.shop_cfg().get("max_lv", 6)) >= 6,
		"武器仍可升到 6 级（慢不等于砍掉上限）")

	# ---- 交叉校验：密度涨了但没把玩家开局逼死 ----
	chk(w1 > 0.0, "第 1 波整波总血量可计算（%.0f），难度配置有效" % w1)
	var pistol: Dictionary = data.weapon("pistol")
	chk(float(pistol.get("dmg", 0.0)) > 0.0, "起手武器有伤害值（实测 %.0f，配平测试依赖）"
		% float(pistol.get("dmg", 0.0)))
	# 起手 DPS 必须仍然打得动第 1 波的一小部分（防"密度血量一起拉满，开局就被秒"）。
	# 口径说明：判定用"开局真实配置"= 手枪 + 冲锋枪（镜像 GameState.reset），
	# 而不是只看手枪 —— 只看手枪会因为血量提升而误报"起手无效"。
	# 门槛 30%：实测开局配置能打出 58%，留足余量防后续再调血量时静默劣化。
	var start_dps := Combat.weapon_dps(pistol) + Combat.weapon_dps(data.weapon("smg"))
	chk(start_dps * 60.0 > w1 * 0.30,
		"开局配置(手枪+冲锋枪) 60 秒输出 ≥第 1 波总血量的 30%%（%.0f vs %.0f）"
		% [start_dps * 60.0, w1])
	# 单看手枪也要有存在感（≥12%），否则"起手枪"这个设计就废了
	chk(Combat.weapon_dps(pistol) * 60.0 > w1 * 0.12,
		"手枪单独 60 秒输出 ≥第 1 波总血量的 12%%（%.0f vs %.0f）"
		% [Combat.weapon_dps(pistol) * 60.0, w1])

	return {"pass": _p, "fail": _f, "failures": _failures}
