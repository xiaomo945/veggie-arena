extends SceneTree

# =====================================================================
# 每波强度规划探针（只读，不进游戏运行时）
# 只是 SimCore 的一层薄壳 CLI：跑【通用玩家】（不带角色，不吃羁绊）的多局模拟，
# 取中位数后打印 JSON。推演逻辑全在 scripts/SimCore.gd 里，改推演改那里。
#
# 用法：godot --headless --path . --script res://scripts/power_probe.gd -- --waves=12
# =====================================================================

const SimCore := preload("res://scripts/SimCore.gd")
const DataScript := preload("res://autoload/Data.gd")

const MAX_WAVES := 12
# 商店是随机的：跑几局取中位数，不让单局运气决定配平。
# 5 → 9（2026-10-06）：商店改成每波 6 张后，单局能买的东西变多、方差也跟着变大，
#   5 局取中位数仍会被某一局的"神抽/鬼抽"带偏（实测第 17 波出现 1.8% 的战力倒退，
#   纯属抽样噪声，却被成长线判成设计事故）。9 局后曲线平滑，配平才有稳定解。
const RUNS := 9


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

	var runs: Array = []
	for i in range(RUNS):
		var sim := SimCore.new()
		sim.wok = wok
		runs.append(sim.run(data, waves, 20261005 + i * 7919))
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
	print(JSON.stringify({"runs": RUNS, "targets": 3, "wok": wok, "rows": rows}))
	quit()
