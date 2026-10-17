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
# 局数：商店随机，取中位数不让单局运气决定配平。
# ⚠️ 5 → 9（2026-10 属性线续抽调参时发现）：5 局的中位数会随倍率变化
#   整体跳到不同轨迹上（同一倍率改 0.25，违例波从 w18 凹陷跳到 w19 超标），
#   等于中位数本身在噪声里漂 —— 调参信号被淹没。9 局后中位数收敛，
#   power_band 的 subprocess 超时同步放到 600 秒。
const RUNS := 9


func _med(arr: Array) -> float:
	var a: Array = arr.duplicate()
	a.sort()
	return float(a[a.size() / 2])

# 各属性线的购买张数：属性线续抽的验收指标 —— 线喂得出来吗？
# crit_mult 线 4 张全买到 = 构筑线在单局时长内完成；只买到 1~2 张 = 续抽力度不够
# （设计背景见 data/shop_tiers.json 的 _doc_chain_pity：无续抽时中位 24 波才凑齐）。
func _line_counts(bought_keys: Dictionary, data) -> Dictionary:
	var counts := {}
	for key in bought_keys:
		var u: Dictionary = data.upgrade(str(key))
		if u.is_empty() or u.get("stats") is Dictionary:
			continue          # 多属性卡不属于任何单属性线
		var s := str(u.get("stat", ""))
		if s.is_empty():
			continue
		counts[s] = int(counts.get(s, 0)) + int(bought_keys[key])
	return counts


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
	var sims: Array = []
	for i in range(RUNS):
		var sim := SimCore.new()
		sim.wok_cfg = wk
		runs.append(sim.run(data, waves, 20261005 + i * 7919))
		sims.append(sim)
	# 代表局：末波 dps_reach 最接近五局中位数的那一局，整条轨迹一起发出。
	# 为什么要它：逐波中位数是"把 5 局的同一波搅在一起"，单波统计没问题，
	# 但【跨波】的成长/倒退检查在搅过的序列上就是假的 —— 第 19 波就报过
	# 一次假倒退（中位数序列上下跳，没有任何一局真的倒退）。成长是一条轨迹
	# 的性质，必须在局内判：局内战力单调不减由购买判据（gain>0 才掏钱）
	# 构造保证，代表局 = 中位数里位的真实玩家。
	var finals: Array = []
	for run in runs:
		finals.append(float((run[waves - 1] as Dictionary).get("dps_reach", 0.0)))
	var rep_i := 0
	var rep_gap := INF
	for i in range(runs.size()):
		var gap: float = absf(finals[i] - _med(finals))
		if gap < rep_gap:
			rep_gap = gap
			rep_i = i
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
	print(JSON.stringify({"runs": RUNS, "targets": 3, "wok": wok, "rows": rows,
		"rep_run": rep_i, "rep_dps_final": _med(finals),
		"rep_lines": _line_counts(sims[rep_i].bought_keys, data),
		"rep_rows": runs[rep_i]}))
	quit()
