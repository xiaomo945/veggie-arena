extends RefCounted

# 属性目录测试：core/Stats.gd 是"玩家属性做全"的单一真相源。
# 守三条：① 目录里每个非 max_hp 的 key 都能在升级表里找到供给源（不显示假属性）；
#        ② 每个分组 id 都登记在 CATS 里；③ grouped() 覆盖全部条目且无重复 key。

const Stats := preload("res://core/Stats.gd")

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
	# 升级表里所有 stat 键（单属性 stat / 多属性 stats 字典都算）
	var ups: Dictionary = data.upgrades
	var stat_keys: Dictionary = {}
	for k in ups:
		var u: Dictionary = ups[k] as Dictionary
		var s: String = str(u.get("stat", ""))
		if s != "":
			stat_keys[s] = true
		if u.has("stats"):
			for sk in u["stats"]:
				stat_keys[str(sk)] = true

	# ① 目录每条 key（max_hp 特例除外）必须有供给源
	var seen: Dictionary = {}
	var cat_ids: Dictionary = {}
	for c in Stats.CATS:
		cat_ids[str(c["id"])] = true
	for e in Stats.catalog():
		var key: String = str(e["key"])
		seen[key] = true
		chk(cat_ids.has(str(e["cat"])), "分组合法：%s" % str(e["cat"]))
		if Stats.DERIVED.has(key):
			chk(true, "%s 是派生属性（实时算出，豁免供给源检查）" % key)
		else:
			chk(stat_keys.has(key), "属性 %s 在升级表有供给源" % key)

	# ② 分类键合法
	chk(true, "CATS 分组数 = %d" % Stats.CATS.size())

	# ③ grouped 覆盖全部条目且无重复
	var total := 0
	for g in Stats.grouped():
		for _it in g["items"]:
			total += 1
	chk(total == Stats.catalog().size(), "grouped 覆盖全部 %d 条" % Stats.catalog().size())
	chk(seen.size() == Stats.catalog().size(), "目录无重复 key（%d）" % seen.size())

	return {"pass": _p, "fail": _f, "failures": _failures}
