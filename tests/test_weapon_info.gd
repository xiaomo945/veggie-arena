extends RefCounted

# 武器详情页内容（ui/WeaponInfo.gd）+ 开局候选池的守门测试。
#
# 盯的是"以后加武器 / 改数值时最容易翻的车"：
#   1) 数值表缺项、或 cd=0 触发除零 → 详情页直接显示空白 / "-" / NaN
#   2) 新 behavior 没进 trait_lines → 玩家看详情页会觉得"这把武器没特点"
#   3) 中文有、英文漏翻 → 出海玩家看到串味儿的字串
#   4) masters 指错角色 → 详情页向玩家推荐一个根本不吃这把武器的人
#   5) 【回归】武器全解锁之后，开局候选池要真能装下它们
#      —— 历史上候选池被写死成 list.slice(0, 6)，40 把武器解锁了也只给挑那 6 把，
#         解锁系统一半的意义被这一行吃掉。这一条连同 arch_guard 的源码不变量一起拦。

const WeaponInfo := preload("res://ui/WeaponInfo.gd")
const Save := preload("res://core/Save.gd")

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
	var weapons: Dictionary = data.weapons
	var unlocks: Dictionary = data.unlocks_cfg()

	# ---- 1) 数值表：每把武器 4 行，且不许出现缺值 ----
	var thin: Array = []
	var dashy: Array = []
	for k in weapons:
		var def: Dictionary = weapons[k] as Dictionary
		var rows: Array = WeaponInfo.stat_rows(def, "zh")
		if rows.size() < 4:
			thin.append(str(k))
			continue
		for r in rows:
			var v := str((r as Dictionary).get("value", ""))
			if v.is_empty() or v == "-" or v == "nan":
				dashy.append(str(k))
				break
	chk(thin.is_empty(), "每把武器的数值表都有 4 项（缺项：%s）" % _j(thin))
	chk(dashy.is_empty(), "每把武器的数值都是有效数字（异常：%s）" % _j(dashy))

	# ---- 2) cd=0 的除零保护：不许崩，也不许写成 inf ----
	var zero := WeaponInfo.stat_rows({"dmg": 1, "cd": 0.0, "range": 1, "cost": 1}, "zh")
	var rate_ok := false
	for r in zero:
		var v := str((r as Dictionary).get("value", ""))
		if v == "-" or v == "0.00/s":
			rate_ok = true
	chk(zero.size() >= 4 and rate_ok, "cd=0（同一帧连发类武器）不崩，攻速退化为 -")

	# ---- 3) 中英条目数必须一一对应（漏翻会让详情页两种语言说得不一样长） ----
	var bad_lang: Array = []
	for k in weapons:
		var def: Dictionary = weapons[k] as Dictionary
		var zh: Array = WeaponInfo.trait_lines(def, "zh")
		var en: Array = WeaponInfo.trait_lines(def, "en")
		if zh.size() != en.size():
			bad_lang.append(str(k))
	chk(bad_lang.is_empty(), "每把武器的打法说明中英条目一一对应（异常：%s）" % _j(bad_lang))

	# ---- 4) 有机制的武器必须在详情页"说得出话" ----
	# 这是最容易被静默吞掉的一类：加了 behavior / pierce 却忘了补文案，
	# 玩家看到的就是一张只有数值的卡 —— 等于新武器白做。
	var silent: Array = []
	for k in weapons:
		var def: Dictionary = weapons[k] as Dictionary
		var has_hook := false
		if not str(def.get("behavior", "")).is_empty():
			has_hook = true
		if int(def.get("pierce", 0)) > 0 or float(def.get("aoe", 0.0)) > 0.0:
			has_hook = true
		if int(def.get("pellets", 1)) > 1 or float(def.get("knockback", 0.0)) > 0.0:
			has_hook = true
		if str(def.get("type", "")) == "melee" or not (def.get("scl", {}) as Dictionary).is_empty():
			has_hook = true
		if has_hook and WeaponInfo.trait_lines(def, "zh").is_empty():
			silent.append(str(k))
	chk(silent.is_empty(), "有机制的武器都说得出一条打法特点（没说话：%s）" % _j(silent))

	# ---- 5) masters：本命角色不能指错 ----
	var bad_master: Array = []
	var mism: Array = []
	for k in weapons:
		var masters: Array = WeaponInfo.masters(str(k), data.characters)
		for m in masters:
			var e: Dictionary = data.characters[str(m)] as Dictionary
			if str((e.get("signature", {}) as Dictionary).get("key", "")) != str(k):
				bad_master.append("%s→%s" % [str(k), str(m)])
	# 反向：每个角色都要能被自己的本命武器搜到（搜不到 = 详情页推荐名单漏人）
	for c in data.characters:
		var e: Dictionary = data.characters[c] as Dictionary
		var sig: Dictionary = e.get("signature", {}) as Dictionary
		var wk := str(sig.get("key", ""))
		if wk.is_empty() or not weapons.has(wk):
			mism.append(str(c))
			continue
		if not WeaponInfo.masters(wk, data.characters).has(str(c)):
			mism.append(str(c))
	chk(bad_master.is_empty(), "本命名单只收录真正以它为招牌的角色（异常：%s）" % _j(bad_master))
	chk(mism.is_empty(), "每个角色都能被自己的本命武器检索到（漏掉：%s）" % _j(mism))

	# ---- 6) 回归：全解锁档的候选池要能装下所有武器 ----
	# 把存档里各条统计刷到规则的最高需求，模拟"老玩家什么都解锁了"，
	# 再看 Save.unlocked_weapons 能不能交出整张武器表。
	var maxed: Dictionary = Save.defaults()
	var rules: Dictionary = unlocks.get("weapons", {}) as Dictionary
	for key in rules:
		var rule: Dictionary = rules[key] as Dictionary
		var t := str(rule.get("type", ""))
		var need := int(rule.get("need", 0))
		if not t.is_empty() and int(maxed.get(t, 0)) < need:
			maxed[t] = need
	var pool: Array = Save.unlocked_weapons(maxed, unlocks)
	chk(pool.size() >= weapons.size(),
		"全解锁后开局可选武器 = %d / 武器总数 %d（不得写死前 N 把）" % [pool.size(), weapons.size()])
	chk(pool.has("pistol"), "保底手枪始终在解锁列表里（开局必定带一把）")

	return {"pass": _p, "fail": _f, "failures": _failures}

func _j(arr: Array) -> String:
	return "无" if arr.is_empty() else ", ".join(arr)
