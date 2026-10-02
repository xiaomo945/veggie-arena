extends RefCounted

# 存档与解锁测试。
#
# 最重要的一条：**存档坏了也不能让游戏起不来**。
# 网页版的存档走 IndexedDB，用户手改/无痕模式/旧版本残留都可能拿到脏数据；
# 这种时候宁可丢进度从头开始，也不能卡在加载页（玩家只会直接关掉页面）。

const Save := preload("res://core/Save.gd")
const Economy := preload("res://core/Economy.gd")

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

func run(data = null) -> Dictionary:
	# 解锁表：优先用测试传入的 data，否则自己读（本文件 run() 不一定拿得到参数）
	var unlocks: Dictionary = {}
	if data != null and data.unlocks_cfg != null:
		unlocks = data.unlocks_cfg() as Dictionary
	if unlocks.is_empty():
		var f := FileAccess.open("res://data/unlocks.json", FileAccess.READ)
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				unlocks = j.get_data() as Dictionary
			f.close()

	# ---- 1) 默认值 ----
	var s := Save.defaults()
	chk(int(s["version"]) == Save.VERSION, "默认存档带版本号 %d" % Save.VERSION)
	chk(int(s["runs"]) == 0 and int(s["best_score"]) == 0, "新档统计全为 0")
	chk(unlocks.has("start_weapons"), "unlocks.json 定义了初始武器")

	# ---- 2) 新档的解锁集合 = 初始武器 ----
	var start: Array = unlocks.get("start_weapons", []) as Array
	var un0 := Save.unlocked_weapons(s, unlocks)
	chk(un0.size() == start.size(), "新档解锁 %d 把武器（= 初始武器数）" % un0.size())
	for k in start:
		chk(un0.has(str(k)), "新档已解锁初始武器 %s" % str(k))
	# 初始武器不能包含需要解锁的（否则解锁系统形同虚设）
	var rules: Dictionary = unlocks.get("weapons", {}) as Dictionary
	for k in rules:
		chk(not start.has(str(k)), "%s 是需要解锁的，不能出现在初始武器里" % str(k))

	# ---- 3) 记录一局：统计累加 + 最佳刷新 ----
	Save.record_run(s, {"wave": 3, "kills": 40, "gold": 60, "score": 520, "won": false})
	chk(int(s["runs"]) == 1, "打完一局 runs = 1")
	chk(int(s["total_kills"]) == 40, "累计击杀 = 40")
	chk(int(s["total_gold"]) == 60, "累计金币 = 60")
	chk(int(s["best_score"]) == 520, "最佳分数 = 520")
	chk(int(s["best_wave"]) == 3, "最远波次 = 3")
	# 第二局更差：最佳不回退
	Save.record_run(s, {"wave": 2, "kills": 10, "gold": 20, "score": 300, "won": false})
	chk(int(s["best_score"]) == 520, "打得更差时最佳分数不回退")
	chk(int(s["best_wave"]) == 3, "打得更差时最远波次不回退")
	chk(int(s["total_kills"]) == 50, "累计击杀继续累加 = 50")
	# 第三局更好：最佳刷新
	Save.record_run(s, {"wave": 7, "kills": 90, "gold": 150, "score": 900, "won": false})
	chk(int(s["best_score"]) == 900, "打得更好时最佳分数刷新")
	chk(int(s["best_wave"]) == 7, "打得更好时最远波次刷新")
	chk(int(s["wins"]) == 0, "未通关时 wins = 0")

	# ---- 4) 解锁真的会达成 ----
	var s2 := Save.defaults()
	var before := Save.unlocked_weapons(s2, unlocks)
	var cleaver: Dictionary = rules.get("cleaver", {}) as Dictionary
	chk(int(cleaver.get("need", 0)) > 0, "菜刀有解锁门槛（累计击杀 %d）" % int(cleaver.get("need", 0)))
	Save.record_run(s2, {"wave": 2, "kills": int(cleaver.get("need", 0)),
		"gold": 0, "score": 10, "won": false})
	var after := Save.unlocked_weapons(s2, unlocks)
	var gained := Save.newly_unlocked(before, after)
	chk(gained.has("cleaver"), "累计击杀达标后解锁菜刀（新解锁 %s）" % str(gained))
	chk(after.size() == before.size() + gained.size(), "解锁数只增不减")

	# ---- 5) 通关解锁（blender）----
	var s3 := Save.defaults()
	var b3 := Save.unlocked_weapons(s3, unlocks)
	chk(not b3.has("blender"), "开局没解锁搅拌机")
	Save.record_run(s3, {"wave": 20, "kills": 500, "gold": 900, "score": 9000, "won": true})
	chk(int(s3["wins"]) == 1, "通关后 wins = 1")
	chk(Save.unlocked_weapons(s3, unlocks).has("blender"), "通关一次解锁搅拌机")

	# ---- 6) 脏存档必须被修回可用（这条最关键）----
	var bad_cases := [
		null,
		"not a dict",
		12345,
		[],
		{},
		{"version": 999},                      # 版本不对
		{"version": Save.VERSION, "runs": "abc"},  # 类型错
		{"version": Save.VERSION, "best_score": -5},
		{"version": Save.VERSION, "total_kills": 3.9},
		{"version": Save.VERSION, "character": 42},
	]
	for i in bad_cases.size():
		var fixed := Save.sanitize(bad_cases[i])
		var okv := int(fixed.get("version", -1)) == Save.VERSION
		var okn := int(fixed.get("runs", -1)) >= 0
		var oks := int(fixed.get("best_score", -1)) >= 0
		chk(okv and okn and oks, "脏存档#%d 被修回可用（version=%d runs=%d）" % [
			i, int(fixed.get("version", -1)), int(fixed.get("runs", -1))])
	# 版本不同的旧档一律回默认（不做跨版本迁移，避免迁移代码变成新的 bug 源头）
	var old := Save.sanitize({"version": 0, "runs": 99, "best_score": 9999})
	chk(int(old["runs"]) == 0, "旧版本存档直接回默认（丢弃进度，但游戏能起来）")

	# ---- 7) 有效存档要被保留（sanitize 不能把好档洗掉）----
	var good := {"version": Save.VERSION, "runs": 7, "best_score": 1234,
		"best_wave": 9, "total_kills": 400, "total_gold": 3000,
		"wins": 1, "character": "potato"}
	var kept := Save.sanitize(good)
	chk(int(kept["best_score"]) == 1234, "好档的最佳分数被保留")
	chk(int(kept["total_kills"]) == 400, "好档的累计击杀被保留")
	chk(str(kept["character"]) == "potato", "好档记住的角色被保留")
	chk(int(kept["wins"]) == 1, "好档的通关次数被保留")

	# ---- 8) 下一条解锁目标（标题页"再来一局"的钩子）----
	var s4 := Save.defaults()
	var nx := Save.next_unlock(s4, unlocks)
	chk(not nx.is_empty(), "新档有下一个解锁目标：%s" % str(nx.get("key", "")))
	chk(int(nx.get("left", -1)) > 0, "目标还差 %d（不会显示已达成）" % int(nx.get("left", -1)))
	# 全解锁后返回空（UI 要能处理"没有目标了"）
	var s5 := Save.defaults()
	s5["total_kills"] = 99999
	s5["total_gold"] = 99999
	s5["best_wave"] = 999
	s5["wins"] = 99
	chk(Save.next_unlock(s5, unlocks).is_empty(), "全解锁后没有下一个目标（UI 不再显示）")
	var all := Save.unlocked_weapons(s5, unlocks)
	chk(all.size() == start.size() + rules.size(), "全解锁后有 %d 把武器" % all.size())

	# ---- 9) 无尽段续命：只刷新最佳波次/分数，不把一局算成两局 ----
	var s6 := Save.defaults()
	Save.record_run(s6, {"wave": 20, "kills": 300, "gold": 500, "score": 8000, "won": true})
	chk(int(s6["runs"]) == 1 and int(s6["wins"]) == 1, "第 20 波通关只记一次（runs=1 wins=1）")
	Save.record_endless(s6, {"wave": 27, "score": 12000})
	chk(int(s6["best_wave"]) == 27, "无尽段最远波次刷新为 27")
	chk(int(s6["best_score"]) == 12000, "无尽段最佳分数刷新为 12000")
	chk(int(s6["runs"]) == 1, "无尽段不重复计入 runs")
	chk(int(s6["wins"]) == 1, "无尽段不重复计入 wins")
	chk(int(s6["total_kills"]) == 300, "无尽段不重复累加击杀")
	Save.record_endless(s6, {"wave": 22, "score": 9000})
	chk(int(s6["best_wave"]) == 27, "无尽段打得更差时最佳波次不回退")

	# ---- 10) 商店只卖已解锁的武器 ----
	if data != null:
		var wd: Dictionary = data.weapons
		var ud: Dictionary = data.upgrades
		var locked_pool := Economy.build_pool([], wd, ud, 6, 4, start)
		var pool_keys: Array = []
		for o in locked_pool:
			var od: Dictionary = o as Dictionary
			if str(od.get("kind", "")) == "weapon":
				pool_keys.append(str(od.get("key", "")))
		chk(pool_keys.size() == start.size(), "新档商店只有 %d 把武器可买" % pool_keys.size())
		for k in pool_keys:
			chk(start.has(k), "商店里的 %s 是已解锁的" % k)
		# 不传解锁列表 = 向后兼容，全部可买
		var full := Economy.build_pool([], wd, ud, 6, 4, [])
		var full_n := 0
		for o2 in full:
			var od2: Dictionary = o2 as Dictionary
			if str(od2.get("kind", "")) == "weapon":
				full_n += 1
		chk(full_n == wd.size(), "不传解锁列表时全部 %d 把武器可买（向后兼容）" % full_n)

	return {"pass": _p, "fail": _f, "failures": _failures}
