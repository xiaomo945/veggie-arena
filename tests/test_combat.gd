extends RefCounted

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

func run() -> Dictionary:
	# 1) 护甲减伤
	chk(Combat.damage_after_armor(10, 2) == 8, "护甲减伤：10-2=8")
	chk(Combat.damage_after_armor(10, 0) == 10, "无护甲：10-0=10")

	# 2) 护甲高于伤害时保底 1 点（不能变成 0 或负数）
	chk(Combat.damage_after_armor(5, 20) == 1, "护甲过高保底 1 点伤害")
	chk(Combat.damage_after_armor(5, 5) == 1, "护甲等于伤害保底 1 点")

	# 3) 无敌帧
	chk(Combat.can_be_hit(0.0) == true, "无敌帧为 0 时可受击")
	chk(Combat.can_be_hit(0.38) == false, "无敌帧内不可受击")
	chk(Combat.can_be_hit(-0.1) == true, "无敌帧为负时可受击")

	# 4) 穿透
	chk(Combat.pierce_after_hit(2) == 1, "穿透 2 → 命中后剩 1")
	chk(Combat.pierce_after_hit(1) == 0, "穿透 1 → 命中后剩 0")
	chk(Combat.pierce_after_hit(0) == 0, "穿透 0 → 仍是 0（不会变负）")
	chk(Combat.bullet_alive_after_hit(2) == true, "还有穿透次数，子弹继续飞")
	chk(Combat.bullet_alive_after_hit(0) == false, "无穿透，子弹消失")

	# 5) 范围伤害
	var targets := [
		{"pos": Vector2(0, 0), "hp": 10},
		{"pos": Vector2(30, 0), "hp": 10},
		{"pos": Vector2(200, 0), "hp": 10},
	]
	var hit := Combat.aoe_targets(Vector2(0, 0), 50.0, targets)
	chk(hit.size() == 2, "半径 50 命中 2 个目标（实际 %d）" % hit.size())
	var hit2 := Combat.aoe_targets(Vector2(0, 0), 10.0, targets)
	chk(hit2.size() == 1, "半径 10 只命中 1 个（实际 %d）" % hit2.size())
	chk(Combat.aoe_targets(Vector2(0, 0), 50.0, []).size() == 0, "空目标列表不崩溃")

	# 6) DPS
	var pistol := {"dmg": 9, "cd": 0.42, "pellets": 1}
	var dps := Combat.weapon_dps(pistol)
	chk(abs(dps - 9.0 / 0.42) < 0.01, "手枪 DPS = 9/0.42 ≈ 21.4（实际 %.1f）" % dps)
	var shotgun := {"dmg": 8, "cd": 0.95, "pellets": 4}
	chk(abs(Combat.weapon_dps(shotgun) - 8.0 * 4 / 0.95) < 0.01, "霰弹枪按弹丸数计算 DPS")
	chk(abs(Combat.weapon_dps(pistol, 1.0, 0.0) - dps * 2.0) < 0.01, "伤害 +100% → DPS 翻倍")
	chk(Combat.weapon_dps({"dmg": 5, "cd": 0}) == 0.0, "冷却为 0 时 DPS 返回 0（不除零崩溃）")

	# 7) 击杀时间
	var ttk := Combat.time_to_kill(21.4, pistol)
	chk(abs(ttk - 1.0) < 0.05, "21.4 血的敌人，手枪约 1 秒杀（实际 %.2f）" % ttk)

	return {"pass": _p, "fail": _f, "failures": _failures}
