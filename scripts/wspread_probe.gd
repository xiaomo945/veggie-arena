extends SceneTree

# =====================================================================
# 武器强度离散度探针（只读，不进游戏运行时）
#
# 输出每把武器 lv1 的"有效 DPS" = 单体 DPS × 对群折算（复用 SimCore.group_mult，
# 与战斗里真实打多个目标时的口径一致）。这是阶段 D1 判断"武器之间差多少"的尺子。
#
# 为什么必须用"有效 DPS"而不是单体 DPS：只看单体会让 AOE / 连锁武器显得很弱，
# 逼着配平去给它们堆单体数值 —— 那正是用户嫌的"武器只是数值堆叠"。
#
# 用法：godot --headless --path . --script res://scripts/wspread_probe.gd -- --lv=1
# =====================================================================

const SimCore := preload("res://scripts/SimCore.gd")
const DataScript := preload("res://autoload/Data.gd")
const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")


func _initialize() -> void:
	var lv := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lv="):
			lv = int(a.split("=")[1])
	var data = DataScript.new()
	data.load_all()
	var cc := data.combat_cfg()
	var sim := SimCore.new()
	var out := {}
	for k in data.weapons:
		var d: Dictionary = data.weapon(str(k))
		sim.defs[str(k)] = d
		var ms := Weapon.merged_stats(d, lv, cc)
		var single := Combat.weapon_dps(ms, 0.0, 0.0)
		out[str(k)] = {
			"single": single,
			"mult": sim.group_mult(d),
			"eff": single * sim.group_mult(d),
			"dmg": float(d.get("dmg", 0)),
			"tags": d.get("tags", []),
			"behavior": Weapon.behavior_of(d),
		}
	print(JSON.stringify({"lv": lv, "weapons": out}))
	quit()
