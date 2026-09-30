extends RefCounted

# 锅气 Wok Heat 状态机测试：档位、衰减、挨打掉火候、颠勺、攻速/伤害倍率。
# 直接测 core/Wok.gd 纯逻辑（不依赖 autoload，--script 模式可跑）。
# GameState 是这层逻辑的薄封装，数值与这里完全一致。

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

	# 1) 开局火候清零、微温、不可颠勺
	var s := Wok.make(w)
	chk(absf(Wok.heat_of(s)) < 0.001, "开局锅气 = 0")
	chk(Wok.tier(s) == 0, "开局档位 = 微温(0)")
	chk(not Wok.ready(s), "开局不能颠勺（未满锅气）")

	# 2) 攒火候越过档位线
	Wok.add(s, w, stir + 1.0)
	chk(Wok.tier(s) == 1, "越过翻炒线(%.0f) → 档位1" % stir)
	Wok.add(s, w, hei - stir + 1.0)
	chk(Wok.tier(s) == 2, "越过爆炒线(%.0f) → 档位2" % hei)
	chk(not Wok.ready(s), "爆炒档(%.0f)还没满锅气，不能颠勺" % hei)
	Wok.add(s, w, maxv - hei)   # 推到上限 100
	chk(Wok.ready(s), "锅气满 %.0f → 可颠勺" % maxv)

	# 3) 超过上限被钳制（不会无限涨）
	Wok.add(s, w, 999.0)
	chk(absf(Wok.heat_of(s) - maxv) < 0.001, "锅气被钳制在上限 %.0f" % maxv)

	# 4) 衰减：停手会凉
	s = Wok.make(w)
	Wok.add(s, w, 50.0)
	var before := Wok.heat_of(s)
	Wok.decay(s, w, 1.0)
	chk(Wok.heat_of(s) < before, "停手 1 秒锅气下降(%.1f→%.1f)" % [before, Wok.heat_of(s)])

	# 5) 挨打掉火候：被摸一下火候回落
	s = Wok.make(w)
	Wok.add(s, w, 80.0)
	var b2 := Wok.heat_of(s)
	Wok.cool(s, w, 10.0)   # 模拟挨 10 点伤害
	chk(Wok.heat_of(s) < b2, "挨打后锅气回落(%.1f→%.1f)" % [b2, Wok.heat_of(s)])

	# 6) 颠勺：满锅气触发后火候回落到 toss_reset，且未就绪时返回 false
	s = Wok.make(w)
	chk(Wok.toss(s, w) == false, "未满锅气颠勺失败")
	Wok.add(s, w, 200.0)
	var ok := Wok.toss(s, w)
	chk(ok == true, "满锅气颠勺成功")
	chk(absf(Wok.heat_of(s) - float(w.get("toss_reset", 18))) < 0.001, "颠勺后火候回落到 toss_reset")
	chk(not Wok.ready(s), "颠勺后回到不可颠勺状态")

	# 7) 攻速/伤害倍率随档位提升
	s = Wok.make(w)
	chk(absf(Wok.fire_mult(s, w) - 1.0) < 0.001, "微温攻速倍率 = 1.0")
	chk(absf(Wok.dmg_mult(s, w) - 1.0) < 0.001, "微温伤害倍率 = 1.0")
	Wok.add(s, w, stir + 1.0)
	chk(absf(Wok.fire_mult(s, w) - (1.0 + float(w.get("tier1_fire", 0.25)))) < 0.001, "翻炒档攻速 +%.0f%%" % int(float(w.get("tier1_fire", 0.25)) * 100))
	chk(absf(Wok.dmg_mult(s, w) - 1.0) < 0.001, "翻炒档伤害不加（仅爆炒档加）")
	Wok.add(s, w, hei - stir + 1.0)
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
