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
	# 扩充后的三类身份萝卜：暴击 / 连击 / 反刺
	var commando: Dictionary = table.get("commando", {}) as Dictionary
	var martial: Dictionary = table.get("martial", {}) as Dictionary
	var hedgehog: Dictionary = table.get("hedgehog", {}) as Dictionary
	chk(Character.stats_of(commando).get("crit_chance", 0.0) > 0.0, "特种兵萝卜暴击为正（暴击专精）")
	chk(Character.stats_of(commando).get("max_hp", 0.0) < 0.0, "特种兵萝卜生命为负")
	chk(Character.stats_of(martial).get("rate_pct", 0.0) > 0.0, "武术家萝卜攻速为正（连击专精）")
	chk(Character.stats_of(martial).get("armor", 0.0) < 0.0, "武术家萝卜护甲为负（连击的代价）")
	chk(Character.stats_of(hedgehog).get("armor", 0.0) > 0.0, "刺猬萝卜护甲为正（反刺专精）")
	chk(Character.stats_of(hedgehog).get("speed_pct", 0.0) < 0.0, "刺猬萝卜移速为负")
	# 扩充规模守卫：主角已从 6 扩到 10 个（未来目标 60）
	chk(table.size() >= 10, "萝卜职业已扩充到至少 10 个（实有 %d 个）" % table.size())
	# 每个职业都要有玩法特征与最佳武器提示（深度：告诉玩家该怎么玩）
	for k in keys:
		var e5: Dictionary = table[k] as Dictionary
		chk(not str(e5.get("trait", "")).is_empty(), "%s 有玩法特征 trait" % str(k))
		chk(not str(e5.get("best", "")).is_empty(), "%s 有最佳武器提示 best" % str(k))
		chk(str(e5.get("affinity", "mixed")) in ["mixed", "ranged", "melee", "elem"],
			"%s 亲和合法" % str(k))

	# 8) 每个角色都必须有专属贴图 art/sprite_char_<key>.png
	# 缺图不会崩，但会静默回落成同一个通用萝卜，玩家看到的就是"10 个角色长得一样"，
	# 职业辨识度直接归零 —— 所以这里当硬失败守卫。贴图要抠掉背景（alpha 有真透明）、
	# 画布一致（512×512），否则游戏里大小不一。
	for k in keys:
		var kn2 := str(k)
		var p := "res://art/sprite_char_%s.png" % kn2
		if not ResourceLoader.exists(p):
			chk(false, "%s 有专属贴图 sprite_char_%s.png" % [kn2, kn2])
			continue
		var tex: Texture2D = load(p)
		chk(tex != null, "%s 贴图可加载" % kn2)
		if tex == null:
			continue
		chk(tex.get_width() == 512 and tex.get_height() == 512,
			"%s 贴图画布 512×512（实 %d×%d）" % [kn2, tex.get_width(), tex.get_height()])
		# 抽样统计 alpha：必须既有真透明（背景抠掉了）也有不透明（角色实体）
		var img := tex.get_image()
		var opaque := 0
		var clear := 0
		var total := 0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				total += 1
				var a := img.get_pixel(x, y).a
				if a < 0.1:
					clear += 1
				elif a > 0.6:
					opaque += 1
		chk(opaque > total * 0.05, "%s 贴图有实体像素（不透明 %.0f%%）" % [
			kn2, 100.0 * float(opaque) / maxf(1.0, float(total))])
		chk(clear > total * 0.30, "%s 贴图背景已抠透明（空白 %.0f%%）" % [
			kn2, 100.0 * float(clear) / maxf(1.0, float(total))])

	# 9) 不同角色之间不能是同一个套路（玩法要有区分度）
	var kinds := {}
	for k in keys:
		var st := Character.stats_of(table[k] as Dictionary)
		var pos_key := ""
		for s in st:
			if float(st[s]) > 0.0:
				pos_key += str(s) + ","
		kinds[pos_key] = int(kinds.get(pos_key, 0)) + 1
	chk(kinds.size() >= 3, "角色流派有区分度（%d 种不同正向加成组合）" % kinds.size())

	# 10) 反向用例：纯加强角色必须被判为不合格（守卫测试本身要有效）
	var op := {"stats": {"dmg_pct": 0.5, "rate_pct": 0.5}}
	chk(not Character.is_balanced(op), "守卫有效：纯加强角色被判为不合格")
	var op2 := {"stats": {"dmg_pct": -0.5}}
	chk(not Character.is_balanced(op2), "守卫有效：纯削弱角色也被判为不合格（没人会选）")

	return {"pass": _p, "fail": _f, "failures": _failures}
