extends RefCounted

# 模拟器口径保真测试（2026-10-12，docs/07 §6.5 三处盲区的收口）。
#
# 背景：scripts/SimChar.gd / SimCore.gd 是配平决策的唯一依据，它系统性低估过
# 三个人设 —— 爆炒萝卜的 heat 技能被算成 0 输出、它和文火萝卜的 wok_pct 被
# 全局常数 1.7 抹掉、焦辣萝卜的 on_hit_dot 完全没进推演。盲区不报错，只会
# 安静地让下一次配平砍错人（"给弱角色加伤害"这种错误结论就是这么来的）。
#
# 这组测试钉死三件事：
#   1) 通用玩家（无角色）的锅气倍率必须精确等于旧常数中点 —— 配平基线零漂移；
#   2) scorch 的 DoT / sizzle 的 heat+wok_pct 必须进得了推演，且幅度合理
#      （进得去 + 不吹爆，两个方向都要钉）；
#   3) 口径公式本身（elem_pct 放大、覆盖率折算、clamp 封顶）与实战规则一致。

const SimCore := preload("res://scripts/SimCore.gd")
const SimChar := preload("res://scripts/SimChar.gd")

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


# 造一个和 fullbuild_probe 同构的 sim（角色可选，空 = 通用玩家）
func _sim(data, char_key: String) -> SimCore:
	var sim := SimCore.new()
	sim.wok_cfg = data.wok_cfg()
	sim.char_key = char_key
	if char_key != "":
		sim.char_entry = data.character(char_key)
	sim.skills = data.skills_cfg()
	for k in data.enemies:
		sim.enemies[str(k)] = data.enemy(str(k))
	for k in data.weapons:
		sim.defs[str(k)] = data.weapon(str(k))
	return sim


# 两把 Lv1 武器（和 SimCore._start_weapons 同构的最小合法装备）
func _weps(sim: SimCore, keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		var d: Dictionary = sim.defs.get(str(k), {})
		out.append({"key": str(k), "lv": 1,
			"dmg": float(d.get("dmg", 1)), "cd": float(d.get("cd", 1.0)),
			"pellets": float(d.get("pellets", 1))})
	return out


func run(data) -> Dictionary:
	var ch := SimChar.new()
	var wk: Dictionary = data.wok_cfg()
	var t1 := 1.0 + float(wk.get("tier1_fire", 0.3))
	var t2 := (1.0 + float(wk.get("tier2_fire", 0.65))) * (1.0 + float(wk.get("tier2_dmg", 0.3)))
	var mid := (t1 + t2) * 0.5
	var avg_hp: float = ch.avg_enemy_hp({
		"grunt": data.enemy("grunt"), "fast": data.enemy("fast"), "tank": data.enemy("tank")})

	# ---- 1) 回归：通用玩家锅气倍率必须精确等于旧常数中点 ----
	# power_band.py 的 20 波配平基线建立在"通用玩家 wok=中点"上，这里漂一丁点，
	# 整条难度曲线的结论都要重新解释。所以钉死精确相等，不是约等于。
	var s0 := _sim(data, "")
	var cp0: Dictionary = s0.combat_power(_weps(s0, ["cleaver", "pan"]), {})
	chk(absf(float(cp0["wok_mult"]) - mid) < 0.0001,
		"通用玩家锅气倍率 = tier1/tier2 中点 %.4f（实际 %.4f）" % [mid, float(cp0["wok_mult"])])
	chk(float(cp0["dot_dps"]) == 0.0, "通用玩家无自带 DoT（dot_dps = 0）")

	# ---- 2) scorch 的 on_hit_dot：算得进来，且公式与实战一致 ----
	var scorch: Dictionary = data.character("scorch")
	var se := s0.ch.eff_st(_weps(s0, ["blowtorch", "pan"]), {}, scorch, s0.defs)
	var dot := ch.dot_dps(scorch, se, avg_hp)
	var d: Dictionary = scorch.get("on_hit_dot", {}) as Dictionary
	var want := (float(d.get("burn", 0.0)) + float(d.get("poison_pct", 0.0)) * avg_hp) \
		* (1.0 + float(se.get("elem_pct", 0.0))) * SimChar.DOT_UPTIME
	chk(dot > 0.0, "焦辣萝卜自带 DoT 进得了推演（dot_dps = %.3f > 0）" % dot)
	chk(absf(dot - want) < 0.0001,
		"DoT 公式与 InnateDot 口径一致（burn+poison×avg_hp，吃 elem_pct、按覆盖率折算）")
	# elem_pct 放大：元素流道具/羁绊必须能放大这一层（四元素联动闭环）。
	# 用绝对值钉公式（scorch 基础自带 elem_pct 0.3，用相对比例会测成自证）。
	var per := float(d.get("burn", 0.0)) + float(d.get("poison_pct", 0.0)) * avg_hp
	var se_hi: Dictionary = se.duplicate()
	se_hi["elem_pct"] = 1.0
	var se_lo: Dictionary = se.duplicate()
	se_lo["elem_pct"] = 0.0
	chk(absf(ch.dot_dps(scorch, se_hi, avg_hp) - per * 2.0 * SimChar.DOT_UPTIME) < 0.0001
		and absf(ch.dot_dps(scorch, se_lo, avg_hp) - per * 1.0 * SimChar.DOT_UPTIME) < 0.0001,
		"DoT 按 InnateDot 口径吃 elem_pct（0→不放大，1.0→精确翻倍）")
	# 覆盖率折算防呆：不许按"每发命中都追加"算（那会让高射速武器变数值炸弹）
	chk(dot < (float(d.get("burn", 0.0)) + float(d.get("poison_pct", 0.0)) * avg_hp)
		* (1.0 + float(se.get("elem_pct", 0.0))),
		"DoT 按覆盖率折算（不叠层，低于每发全追加的上限）")
	# 战力差：带 DoT 的同一角色必须显著强于撕掉该字段的（既别算丢）
	var ss := _sim(data, "scorch")
	var nodot: Dictionary = scorch.duplicate(true)
	nodot.erase("on_hit_dot")
	var sn := _sim(data, "")
	sn.char_entry = nodot
	sn.char_key = "scorch"
	var wa: Array = _weps(ss, ["blowtorch", "pan"])
	var with_dot: float = float(ss.combat_power(wa, {})["dps"])
	var without_dot: float = float(sn.combat_power(wa, {})["dps"])
	var lift := with_dot / maxf(0.001, without_dot) - 1.0
	chk(lift > 0.01 and lift < 0.25,
		"DoT 对焦辣萝卜总战力贡献 1%%~25%%（实测 +%.1f%%）" % (lift * 100.0))

	# ---- 3) sizzle 的 heat 技能 + wok_pct：算得进来，且不超物理上限 ----
	var sizzle: Dictionary = data.character("sizzle")
	var sz := _sim(data, "sizzle")
	var cpz: Dictionary = sz.combat_power(_weps(sz, ["wok_scoop", "pan"]), {})
	var wm := float(cpz["wok_mult"])
	chk(wm > mid + 0.0001, "爆炒萝卜锅气倍率 > 中点（wok_pct 0.55 起手，实际 %.4f）" % wm)
	chk(wm <= t2 + 0.0001, "锅气倍率不超 tier2 封顶（clamp 生效，实际 %.4f ≤ %.4f）" % [wm, t2])
	# heat 技能当量：flashfire amount=34 / cd=9 / HEAT_REF_RATE=25
	var sp := ch.skill_parts(_weps(sz, ["wok_scoop", "pan"]),
		sz.ch.eff_st(_weps(sz, ["wok_scoop", "pan"]), {}, sizzle, sz.defs),
		"sizzle", sizzle, sz.defs, data.skills_cfg(), 3, avg_hp)
	var heat_pct := float(sp.get("wok_pct", 0.0))
	chk(heat_pct > 0.0,
		"heat 技能（爆燃火候）折算成充能当量 > 0（实测 %.4f，不再被算成 0 输出）" % heat_pct)
	chk(absf(heat_pct - 34.0 / 9.0 / SimChar.HEAT_REF_RATE) < 0.0001,
		"heat 当量公式 = amount/cooldown/HEAT_REF_RATE")
	# 无 heat 技能的角色不当量（scorch 的 sear 是 poison，不是 heat）
	var sp2 := ch.skill_parts(_weps(ss, ["blowtorch", "pan"]),
		ss.ch.eff_st(_weps(ss, ["blowtorch", "pan"]), {}, scorch, ss.defs),
		"scorch", scorch, ss.defs, data.skills_cfg(), 3, avg_hp)
	chk(float(sp2.get("wok_pct", 0.0)) == 0.0, "非 heat 技能不产生充能当量")

	# ---- 4) wok_pct 封顶：堆到顶也不超"全程爆炒" ----
	var hot: Dictionary = sizzle.duplicate(true)
	(hot.get("stats", {}) as Dictionary)["wok_pct"] = 5.0
	var sh := _sim(data, "")
	sh.char_entry = hot
	sh.char_key = "sizzle"
	chk(absf(float(sh.combat_power(_weps(sh, ["wok_scoop", "pan"]), {})["wok_mult"]) - t2) < 0.0001,
		"wok_pct 堆到 5.0 也钳在 tier2（%.4f）" % t2)

	return {"pass": _p, "fail": _f, "failures": _failures}
