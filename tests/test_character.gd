extends RefCounted

# 角色系统测试：数据完整、配平（有得必有失）、属性名合法、加成真的生效。
#
# 最关键的一条守卫：**不允许纯加强角色**。
# 一旦出现"只有好处没有代价"的角色，选择就退化成"选它"，其他角色形同虚设。

const Character := preload("res://core/Character.gd")

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
	# 自包含读表：本文件的 run() 不一定拿得到 data 参数
	var table: Dictionary = {}
	if data != null and data.characters != null:
		table = data.characters as Dictionary
	if table.is_empty():
		var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				table = j.get_data() as Dictionary
			f.close()

	chk(not table.is_empty(), "characters.json 可读且非空")
	chk(table.size() >= 2, "至少 2 个角色可选（实有 %d 个）" % table.size())

	var keys: Array = table.keys()
	keys.sort()
	print("  角色: " + str(keys))

	# 1) 必须有默认角色 turnip，且它是"零加成基准"
	chk(keys.has("turnip"), "存在默认角色 turnip")
	var base: Dictionary = table.get("turnip", {}) as Dictionary
	chk(Character.stats_of(base).is_empty(), "turnip 是零加成基准角色")

	# 2) 每个角色的必备字段（缺了 UI 会显示空白）
	for k in keys:
		var e: Dictionary = table[k] as Dictionary
		var kn := str(k)
		chk(not str(e.get("en", "")).is_empty(), "%s 有英文名（出海显示用）" % kn)
		chk(not str(e.get("zh", "")).is_empty(), "%s 有中文名" % kn)
		chk(not str(e.get("tip", "")).is_empty(), "%s 有一句话说明" % kn)
		chk(not str(e.get("color", "")).is_empty(), "%s 有主色（卡片描边/选中标）" % kn)

	# 3) 配平守卫：非基准角色必须"有正有负"
	for k in keys:
		var e2: Dictionary = table[k] as Dictionary
		chk(Character.is_balanced(e2), "%s 配平合格（有加成就必有代价）" % str(k))

	# 4) 属性名必须在白名单内（拼错的 stat 会静默失效）
	for k in keys:
		var e3: Dictionary = table[k] as Dictionary
		var bad := Character.has_unknown_stat(e3)
		chk(bad.is_empty(), "%s 的属性名都合法%s" % [
			str(k), "" if bad.is_empty() else "（发现非法属性 " + bad + "）"])

	# 5) 属性摘要能生成，且带正负号
	for k in keys:
		var e4: Dictionary = table[k] as Dictionary
		var d := Character.describe(e4)
		chk(not d.is_empty(), "%s 的属性摘要非空：%s" % [str(k), d.replace("\n", " / ")])

	# 6) 具体数值抽查（这几条是玩法卖点，改坏了要有提示）
	# 现在所有主角都是萝卜，区别在于"职业亲和"：远程/近战/法师
	var archer: Dictionary = table.get("archer", {}) as Dictionary
	var bruiser: Dictionary = table.get("bruiser", {}) as Dictionary
	var mage: Dictionary = table.get("mage", {}) as Dictionary
	chk(Character.stats_of(archer).get("ranged_pct", 0.0) > 0.0, "神射萝卜远程伤害为正（远程专精）")
	chk(Character.stats_of(archer).get("max_hp", 0.0) < 0.0, "神射萝卜生命为负（脆皮的代价）")
	chk(Character.stats_of(bruiser).get("melee_pct", 0.0) > 0.0, "铁壁萝卜近战伤害为正（近战专精）")
	chk(Character.stats_of(bruiser).get("speed_pct", 0.0) < 0.0, "铁壁萝卜移速为负（坦克的代价）")
	chk(Character.stats_of(mage).get("elem_pct", 0.0) > 0.0, "灵能萝卜元素伤害为正（法师专精）")
	chk(Character.stats_of(mage).get("dmg_pct", 0.0) < 0.0, "灵能萝卜基础伤害为负（法师的代价）")

	# 7) 不同角色之间不能是同一个套路（玩法要有区分度）
	var kinds := {}
	for k in keys:
		var st := Character.stats_of(table[k] as Dictionary)
		var pos_key := ""
		for s in st:
			if float(st[s]) > 0.0:
				pos_key += str(s) + ","
		kinds[pos_key] = int(kinds.get(pos_key, 0)) + 1
	chk(kinds.size() >= 3, "角色流派有区分度（%d 种不同正向加成组合）" % kinds.size())

	# 8) 反向用例：纯加强角色必须被判为不合格（守卫测试本身要有效）
	var op := {"stats": {"dmg_pct": 0.5, "rate_pct": 0.5}}
	chk(not Character.is_balanced(op), "守卫有效：纯加强角色被判为不合格")
	var op2 := {"stats": {"dmg_pct": -0.5}}
	chk(not Character.is_balanced(op2), "守卫有效：纯削弱角色也被判为不合格（没人会选）")

	return {"pass": _p, "fail": _f, "failures": _failures}
