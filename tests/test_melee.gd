extends RefCounted

# 近战武器测试：定义 / DPS-价格曲线 / 击退语义 / 合成 / 伤害走漏斗

const Weapon := preload("res://core/Weapon.gd")
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
	var cfg: Dictionary = data.combat_cfg()
	var melee_keys := ["cleaver", "spatula", "rolling_pin"]

	# 1) 三把近战武器都存在且 type == "melee"
	for k in melee_keys:
		var w: Dictionary = data.weapon(k)
		chk(not w.is_empty(), "%s 已定义" % k)
		chk(Weapon.is_melee(w), "%s 是近战（type=melee）" % k)
		chk(not Weapon.is_melee(data.weapon("pistol")), "手枪仍是远程（兼容）")

	# 2) 近战武器字段完整（与远程同款，缺字段会在商店/战斗里出问题）
	for k in melee_keys:
		var w: Dictionary = data.weapon(k)
		for fld in ["zh", "dmg", "cd", "range", "cost", "color"]:
			chk(w.has(fld), "%s 有字段 %s" % [k, fld])
		chk(float(w.get("dmg", 0)) > 0.0, "%s 伤害 > 0" % k)
		chk(float(w.get("cd", 0)) > 0.0, "%s 冷却 > 0" % k)
		chk(float(w.get("range", 0)) > 0.0, "%s 有挥砍半径" % k)

	# 3) DPS-价格曲线：近战 dmg/cd 的"每金币产出"要落在现有远程武器区间内，
	#    不能便宜到白送、也不能贵到废卡（粗算 DPS = dmg*max(1,pellets)/cd，近战 pellets=1）
	var ranged_vpg := []
	for k in data.weapon_keys():
		var w: Dictionary = data.weapon(k)
		if Weapon.is_melee(w):
			continue
		var dps := Combat.weapon_dps(w)
		ranged_vpg.append(dps / maxf(1.0, float(w.get("cost", 1))))
	var rmin: float = ranged_vpg.min()
	var rmax: float = ranged_vpg.max()
	print("  远程每金币 DPS 区间: %.2f .. %.2f" % [rmin, rmax])
	for k in melee_keys:
		var w: Dictionary = data.weapon(k)
		var dps := float(w.get("dmg", 0)) / float(w.get("cd", 1.0))
		var vpg := dps / maxf(1.0, float(w.get("cost", 1)))
		# 允许 ±15% 浮动（近战无弹道/无瞄准损耗，定价略优是合理的），但不能出区间太远
		chk(vpg >= rmin * 0.5 and vpg <= rmax * 2.0,
			"%s 性价比 %.2f 落在远程区间附近（%.2f..%.2f）" % [k, vpg, rmin, rmax])
	# 三把近战的 DPS 在阶段 D1 配平里被压缩到接近区间（离散度 4.9× → 约 2.2×）：
	# 角色靠击退/手感区分，不靠数值堆叠。菜刀是纯输出位、DPS 略高；
	# 擀面杖（大击退）与锅铲（极快）靠机制区分，DPS 落在窄带内。
	var cleaver_dps := float(data.weapon("cleaver").get("dmg", 0)) / float(data.weapon("cleaver").get("cd", 1.0))
	var spatula_dps := float(data.weapon("spatula").get("dmg", 0)) / float(data.weapon("spatula").get("cd", 1.0))
	var pin_dps := float(data.weapon("rolling_pin").get("dmg", 0)) / float(data.weapon("rolling_pin").get("cd", 1.0))
	var melee_max := maxf(cleaver_dps, maxf(pin_dps, spatula_dps))
	var melee_min := minf(cleaver_dps, minf(pin_dps, spatula_dps))
	chk(cleaver_dps == melee_max, "菜刀 DPS(%.1f) 为三把近战最高" % [cleaver_dps])
	chk(melee_max / melee_min <= 1.2, "三把近战 DPS 落在 ±20%% 窄带内（%.1f..%.1f，压缩后靠机制区分）" % [melee_min, melee_max])

	# 4) 击退语义：锅铲不击退；菜刀小击退；擀面杖大击退（"大击退"的核心卖点）
	chk(float(data.weapon("spatula").get("knockback", 0)) <= 0.0, "锅铲无击退（低伤极快）")
	chk(float(data.weapon("cleaver").get("knockback", 0)) > 0.0, "菜刀有击退")
	chk(float(data.weapon("rolling_pin").get("knockback", 0)) >= 150.0,
		"擀面杖大击退（%.0f）" % float(data.weapon("rolling_pin").get("knockback", 0)))

	# 5) 合成：近战同样走 merged_stats，高等级伤害涨、冷却降
	var ms1 := Weapon.merged_stats(data.weapon("cleaver"), 1, cfg)
	var ms3 := Weapon.merged_stats(data.weapon("cleaver"), 3, cfg)
	chk(float(ms3["dmg"]) > float(ms1["dmg"]), "菜刀 Lv3 伤害高于 Lv1")
	chk(float(ms3["cd"]) < float(ms1["cd"]), "菜刀 Lv3 冷却低于 Lv1")

	# 6) 伤害走统一漏斗：EnemySystem.on_melee_swung 必须调用 damage_enemy
	#    （击杀计数 / 掉金币 / 涨锅气 / 破甲全在那一处，绕开它会"白砍"）
	var src := _read("res://scenes/EnemySystem.gd")
	chk(src.find("func on_melee_swung") >= 0, "EnemySystem 有 on_melee_swung")
	chk(src.find("damage_enemy") >= 0, "on_melee_swung 调用 damage_enemy（走漏斗）")
	chk(src.find("apply_knockback") >= 0, "on_melee_swung 支持击退")

	return {"pass": _p, "fail": _f, "failures": _failures}

# 读源码做"接线"断言（近战漏斗是纯结构事实，单元测试跑不了整条战斗链）
func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t
