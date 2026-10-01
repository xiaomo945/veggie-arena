extends RefCounted

# 锅气 Wok Heat 状态机测试：档位、银行充能、衰减、颠勺、攻速/伤害倍率。
# 直接测 core/Wok.gd 纯逻辑（不依赖 autoload，--script 模式可跑）。
# GameState 是这层逻辑的薄封装，数值与这里完全一致。
#
# 迭代后核心机制：火候攒到 100 自动"银行"一个颠勺充能（火候归零），
# 充能可叠存（默认封顶 3 个），按钮常驻；衰减只降火候不消耗充能；
# 颠勺消耗 1 个充能、火候不变。

const Wok := preload("res://core/Wok.gd")

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
	var w: Dictionary = data.wok_cfg()
	var stir := float(w.get("stir_from", 34))
	var hei := float(w.get("wokhei_from", 68))
	var maxv := float(w.get("max", 100))
	var maxc := int(w.get("max_charges", 3))

	# 1) 开局火候清零、微温、无充能、不可颠勺
	var s := Wok.make(w)
	chk(absf(Wok.heat_of(s)) < 0.001, "开局锅气 = 0")
	chk(Wok.tier(s) == 0, "开局档位 = 微温(0)")
	chk(Wok.charges_of(s) == 0, "开局充能 = 0")
	chk(not Wok.ready(s), "开局不能颠勺（无充能）")

	# 2) 档位（停在 100 以下，避免银行）
	s = Wok.make(w)
	Wok.add(s, w, stir + 1.0)
	chk(Wok.tier(s) == 1, "越过翻炒线(%.0f) → 档位1" % stir)
	Wok.add(s, w, hei - stir - 1.0)   # 到 hei-1，档位2 但未满
	chk(Wok.tier(s) == 2, "越过爆炒线(%.0f) → 档位2" % hei)
	chk(not Wok.ready(s), "爆炒档(%.0f)还没满锅气，不能颠勺" % hei)
	chk(Wok.charges_of(s) == 0, "未到 100 时不银行充能")

	# 3) 到 100 自动银行 1 个充能，火候归零，仍可颠勺
	s = Wok.make(w)
	Wok.add(s, w, maxv)
	chk(Wok.charges_of(s) == 1, "到 100 自动银行 1 个充能")
	chk(Wok.ready(s), "有充能 → 可颠勺")
	chk(absf(Wok.heat_of(s)) < 0.001, "银行后火候归零（爆炒/翻炒增益结束）")

	# 4) 衰减：只降火候，不消耗已存充能
	s = Wok.make(w)
	Wok.add(s, w, maxv)        # 银行 1 充能，heat=0
	Wok.add(s, w, 60.0)        # 重新攒到 60
	var c0 := Wok.charges_of(s)
	var before := Wok.heat_of(s)
	Wok.decay(s, w, 2.0)       # decay_per_sec=4 → 降 8
	chk(Wok.charges_of(s) == c0, "衰减不消耗已存充能（仍为 %d）" % c0)
	chk(Wok.heat_of(s) < before, "衰减降低火候(%.1f→%.1f)" % [before, Wok.heat_of(s)])

	# 5) 颠勺消耗 1 个充能，火候不变；充能为 0 时失败
	s = Wok.make(w)
	Wok.add(s, w, maxv)        # charges=1, heat=0
	Wok.add(s, w, 40.0)        # heat=40
	var hb := Wok.heat_of(s)
	var ok := Wok.toss(s, w)
	chk(ok == true, "有充能颠勺成功")
	chk(Wok.charges_of(s) == 0, "颠勺消耗 1 个充能")
	chk(absf(Wok.heat_of(s) - hb) < 0.001, "颠勺后火候不变(%.1f)" % hb)
	chk(not Wok.ready(s), "充能用完 → 不可颠勺")
	chk(Wok.toss(s, w) == false, "无充能颠勺失败")

	# 6) 充能上限封顶，封顶后火候保留在满值（不浪费进度）
	s = Wok.make(w)
	for i in range(maxc + 3):
		Wok.add(s, w, maxv)
	chk(Wok.charges_of(s) == maxc, "充能上限封顶 = %d" % maxc)
	chk(absf(Wok.heat_of(s) - maxv) < 0.001, "封顶后火候保留在满值 %.0f" % maxv)

	# 7) 攻速/伤害倍率随档位提升（仍基于火候）
	s = Wok.make(w)
	chk(absf(Wok.fire_mult(s, w) - 1.0) < 0.001, "微温攻速倍率 = 1.0")
	chk(absf(Wok.dmg_mult(s, w) - 1.0) < 0.001, "微温伤害倍率 = 1.0")
	Wok.add(s, w, stir + 1.0)
	chk(absf(Wok.fire_mult(s, w) - (1.0 + float(w.get("tier1_fire", 0.25)))) < 0.001, "翻炒档攻速 +%.0f%%" % int(float(w.get("tier1_fire", 0.25)) * 100))
	chk(absf(Wok.dmg_mult(s, w) - 1.0) < 0.001, "翻炒档伤害不加（仅爆炒档加）")
	Wok.add(s, w, hei - stir - 1.0)
	chk(absf(Wok.fire_mult(s, w) - (1.0 + float(w.get("tier2_fire", 0.55)))) < 0.001, "爆炒档攻速 +%.0f%%" % int(float(w.get("tier2_fire", 0.55)) * 100))
	chk(absf(Wok.dmg_mult(s, w) - (1.0 + float(w.get("tier2_dmg", 0.30)))) < 0.001, "爆炒档伤害 +%.0f%%" % int(float(w.get("tier2_dmg", 0.30)) * 100))

	# 8) 击杀攒锅气按金币放大（公式与 Game 一致）
	s = Wok.make(w)
	var kill_heat := float(w.get("kill_heat", 9))
	Wok.add(s, w, kill_heat * (1.0 + 0.2 * 1.0))   # 金币=1 的小怪
	var h_grunt := Wok.heat_of(s)
	s = Wok.make(w)
	Wok.add(s, w, kill_heat * (1.0 + 0.2 * 20.0))  # 金币=20 的 Boss
	var h_boss := Wok.heat_of(s)
	chk(h_boss > h_grunt, "击杀 Boss 攒的锅气(%.1f) > 小怪(%.1f)" % [h_boss, h_grunt])

	return {"pass": _p, "fail": _f, "failures": _failures}
