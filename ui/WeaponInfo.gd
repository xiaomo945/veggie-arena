extends RefCounted

# 武器详情页的数据包装 + 双语文案（纯函数：locale 由外部传入，不碰 autoload）。
#
# 为什么不塞进 autoload/I18n.gd：那条单例已经顶到架构守卫的 300 行上限（硬失败），
# 而武器这一族词还会随着 behavior / 特殊字段继续变长。
# 与 ui/UnlockText.gd 同一套路：**小而纯的一段文案自己管**，加词不用去挤 I18n。

# 数值面板：把"配置里的原始数据"翻译成"玩家真正关心的四个数"
# 冷却改显示成每秒攻击几次 —— 玩家比的是"快慢"，不是"0.62 秒"
static func stat_rows(def: Dictionary, locale: String = "zh") -> Array:
	var en := _en(locale)
	var rows := []
	rows.append({"label": _x("伤害", "DMG", en), "value": _num(def.get("dmg", 0))})
	var cd := float(def.get("cd", 0.0))
	rows.append({"label": _x("攻速", "RATE", en),
		"value": ("%.2f/s" % (1.0 / cd)) if cd > 0.0 else "-"})
	rows.append({"label": _x("射程", "RANGE", en), "value": _num(def.get("range", 0))})
	rows.append({"label": _x("售价", "COST", en), "value": _num(def.get("cost", 0))})
	return rows

# 这把武器的"脾气"（哪些字段真的改变了打法，就单独讲一句）
# 设计原则：只写玩家能直接感知的机制，纯数值字段一律不提（那是数值表的事）
static func trait_lines(def: Dictionary, locale: String = "zh") -> Array:
	var en := _en(locale)
	var out: Array = []
	var bh := str(def.get("behavior", ""))
	match bh:
		"chain":
			out.append(_x("跳跃 %d 次，每一跳伤害递减", "Chains to %d foes, weaker each hop", en,
				[int(def.get("chain", 0))]))
		"homing":
			out.append(_x("会自动追着敌人拐弯", "Bullets home in on targets", en))
		"pulse":
			out.append(_x("以自身为中心向外扩散一圈", "Pulses outward around you", en))
		"beam":
			out.append(_x("持续光束，站在原地扫射", "Continuous beam - stand and sweep", en))
		"boomerang":
			out.append(_x("飞出去会绕回来，来回都能打", "Comes back to you, hits twice", en))
	if int(def.get("pierce", 0)) > 0:
		out.append(_x("穿透 %d 个敌人", "Pierces %d foes", en, [int(def.get("pierce", 0))]))
	if float(def.get("aoe", 0.0)) > 0.0:
		out.append(_x("命中有范围溅射", "Area damage on hit", en))
	if int(def.get("pellets", 1)) > 1:
		out.append(_x("一次打出 %d 发", "Fires %d pellets", en, [int(def.get("pellets", 1))]))
	if float(def.get("knockback", 0.0)) > 0.0:
		out.append(_x("带击退，能把敌人推开", "Knocks enemies back", en))
	if str(def.get("type", "")) == "melee":
		out.append(_x("近战武器：要贴脸才打得到", "Melee - you have to get close", en))
	var scl: Dictionary = def.get("scl", {}) as Dictionary
	for s in scl:
		out.append(_x("吃「%s」属性加成", "Scales with %s", en, [_attr(str(s), en)]))
	return out

# 谁是这把武器的本命角色（角色方面的 signature.key 指向它）
static func masters(key: String, characters: Dictionary) -> Array:
	var out: Array = []
	for k in characters:
		var e: Dictionary = characters[k] as Dictionary
		var sig: Dictionary = e.get("signature", {}) as Dictionary
		if str(sig.get("key", "")) == key:
			out.append(str(k))
	return out

# ---- 详情页用的小标题 / 按钮词 ----
static func title_summary(locale: String) -> String:
	return "AT A GLANCE" if _en(locale) else "一句话"

static func title_trait(locale: String) -> String:
	return "HOW IT FIGHTS" if _en(locale) else "打法特点"

static func title_stat(locale: String) -> String:
	return "NUMBERS" if _en(locale) else "数值"

static func title_set(locale: String) -> String:
	return "SET BONUS" if _en(locale) else "套装 / 羁绊类"

static func title_master(locale: String) -> String:
	return "WHO WANTS IT" if _en(locale) else "谁拿它最狠"

static func btn_pick(locale: String) -> String:
	return "TAKE IT" if _en(locale) else "选它"

# 选武器页顶部的进度条文案：光有"能选几把"还不够，
# 告诉玩家"你已经攒到 12 / 40 把"—— 解锁本身才是这个页面存在的理由。
static func pool_hint(unlocked: int, total: int, locale: String) -> String:
	return ("%d / %d UNLOCKED" % [unlocked, total]) if _en(locale) \
		else ("已解锁 %d / 共 %d 把" % [unlocked, total])

# ---- 小工具 ----
static func _en(locale: String) -> bool:
	return locale != "zh"

static func _x(zh: String, en_txt: String, en: bool, args: Array = []) -> String:
	var t := en_txt if en else zh
	return (t % args) if (not args.is_empty() and _needs_args(t)) else t

# 中英%参数顺序一致才能这么写；不一致的场景各自在函数内用三元分支
static func _needs_args(t: String) -> bool:
	return t.find("%") >= 0

static func _attr(s: String, en: bool) -> String:
	match s:
		"melee": return "Melee Dmg" if en else "近战伤害"
		"ranged": return "Ranged Dmg" if en else "远程伤害"
		"elem": return "Elemental" if en else "元素伤害"
	return s

static func _num(v) -> String:
	var f := float(v)
	if absf(f - roundf(f)) < 0.001:
		return str(int(roundf(f)))
	return "%.1f" % f
