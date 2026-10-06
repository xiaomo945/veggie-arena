extends RefCounted

# 武器逻辑测试：合成、选目标、冷却、弹道

const Weapon := preload("res://core/Weapon.gd")
const Combat := preload("res://core/Combat.gd")
const SP := preload("res://tests/SrcParse.gd")

# 链式每跳的衰减系数【现解析】BulletSystem 里的实装常数 —— 抄一份到测试里就会漂
# （SrcParse 的注释里记过这个坑：test_hud_layout 抄坐标抄出过假通过）。
# 不能写成 const：GDScript 的 const 只接受常量表达式，函数调用会 Parse Error。
var _falloff := -1.0
func _chain_falloff() -> float:
	if _falloff < 0.0:
		_falloff = SP.const_val(SP.read("res://scenes/BulletSystem.gd"), "CHAIN_FALLOFF")
	return _falloff

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
	var cfg: Dictionary = data.combat_cfg()
	var pistol: Dictionary = data.weapon("pistol")
	var shotgun: Dictionary = data.weapon("shotgun")
	var bow: Dictionary = data.weapon("bow")

	# 1) Lv1 就是原样
	var s1 := Weapon.merged_stats(pistol, 1, cfg)
	chk(abs(float(s1["dmg"]) - float(pistol["dmg"])) < 0.001,
		"Lv1 伤害不变（%.1f）" % float(s1["dmg"]))
	chk(abs(float(s1["cd"]) - float(pistol["cd"])) < 0.001,
		"Lv1 冷却不变（%.2fs）" % float(s1["cd"]))

	# 2) 合成后伤害涨、冷却降
	var s3 := Weapon.merged_stats(pistol, 3, cfg)
	chk(float(s3["dmg"]) > float(s1["dmg"]),
		"Lv3 伤害更高：%.1f → %.1f" % [float(s1["dmg"]), float(s3["dmg"])])
	chk(float(s3["cd"]) < float(s1["cd"]),
		"Lv3 冷却更短：%.3f → %.3f" % [float(s1["cd"]), float(s3["cd"])])

	# 3) 等级上限内，合成有明显的正收益（否则合成没意义）
	var s4 := Weapon.merged_stats(pistol, 4, cfg)
	chk(Combat.weapon_dps(s4) > Combat.weapon_dps(s1) * 1.5,
		"满级 DPS 至少是 1 级的 1.5 倍（%.1f vs %.1f）" % [
			Combat.weapon_dps(s4), Combat.weapon_dps(s1)])

	# 4) 冷却：就绪判定
	chk(not Weapon.can_fire(0.0, 0.42), "刚开火不就绪")
	chk(Weapon.can_fire(0.42, 0.42), "到冷却时间就就绪")
	chk(Weapon.can_fire(0.999, 0.42), "超过冷却更就绪")

	# 5) 冷却计时保留余数（掉帧不损失射速）
	var leftover := Weapon.next_cooldown(0.5, 0.42)
	chk(abs(leftover - 0.08) < 0.0001, "冷却余数保留：0.5-0.42=%.3f" % leftover)

	# 6) 零冷却武器不会卡死
	chk(Weapon.can_fire(0.0, 0.0), "零冷却武器永远就绪（防除零）")

	# 7) 选目标：射程内最近的
	var enemies := [
		{"pos": Vector2(100, 0)},
		{"pos": Vector2(30, 0)},
		{"pos": Vector2(500, 0)},
	]
	chk(Weapon.nearest_target(Vector2.ZERO, enemies, 300.0) == 1,
		"选中最近的目标（30 距离那个）")
	chk(Weapon.nearest_target(Vector2.ZERO, enemies, 20.0) == -1,
		"射程内没目标时返回 -1")
	chk(Weapon.nearest_target(Vector2.ZERO, [], 300.0) == -1,
		"空列表不崩，返回 -1")

	# 8) 单发武器永远打正前方（不受散布影响）
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var one := Weapon.pellet_directions(Vector2(1, 0), 1, 0.34, rng)
	chk(one.size() == 1 and (one[0] as Vector2).normalized().distance_to(Vector2(1, 0)) < 0.001,
		"单发武器走正前方，散布不影响")

	# 9) 霰弹枪 4 发
	var many := Weapon.pellet_directions(Vector2(1, 0), 4, 0.34, rng)
	chk(many.size() == 4, "霰弹枪一次 4 发弹丸")

	# 10) 弹丸方向都在扇形内（不会打到身后）
	var all_forward := true
	for d in many:
		var v: Vector2 = d
		if v.x <= 0.0:
			all_forward = false
	chk(all_forward, "弹丸全部朝前，不会反向飞")

	# 11) 弹丸数量安全上限（数据表填错也不卡死手机）
	chk(Weapon.pellet_directions(Vector2(1, 0), 999, 0.5, rng).size() <= Weapon.MAX_PELLETS,
		"弹丸数有上限 %d（防数据表填错卡死）" % Weapon.MAX_PELLETS)

	# 12) 武器环绕站位：不重叠、围绕中心
	var p0 := Weapon.mount_position(Vector2(100, 100), 0, 6, 40)
	var p3 := Weapon.mount_position(Vector2(100, 100), 3, 6, 40)
	chk(abs(p0.distance_to(Vector2(100, 100)) - 40.0) < 0.001,
		"武器站位半径正确（40px）")
	chk(p0.distance_to(p3) > 60.0, "对侧武器分得开（%.0fpx）" % p0.distance_to(p3))

	# 13) 穿透武器属性完整
	chk(int(bow.get("pierce", 0)) == 2, "长弓穿透 2")
	chk(Combat.bullet_alive_after_hit(2), "穿透 2 命中后子弹继续飞")
	chk(not Combat.bullet_alive_after_hit(0), "穿透 0 命中后子弹消失")

	# 14) 每种武器都要能算 DPS（数据表没填错）
	var all_ok := true
	for k in data.weapon_keys():
		var d := Combat.weapon_dps(data.weapon(k))
		if d <= 0.0:
			all_ok = false
			print("    ⚠ %s 的 DPS 为 0" % k)
	chk(all_ok, "全部 %d 把武器都能算出 DPS" % data.weapon_keys().size())

	# 15) 贵的武器必须对得起价格 —— 但要用"群体输出"衡量，
	#     否则带 aoe 的武器会被低估（火箭筒的价值就是一发炸一片）
	var cheap := _value_per_gold(pistol, 1)
	var dear := _value_per_gold(data.weapon("rocket"), 3)
	chk(dear > cheap,
		"火箭筒打群体时性价比超过手枪（%.2f vs %.2f，按同时命中 3 个算）" % [dear, cheap])

	# 16) 每一把武器在某个场景下都该是"值得买"的（不然就是废卡）
	var weakest := ""
	var worst := INF
	for k in data.weapon_keys():
		var w: Dictionary = data.weapon(k)
		# 带 aoe 的按"同时命中 3 个"折算；脉冲 / 光束本身就是群体打法，同样折算
		# （不然砂锅这类"身周一圈"的武器会被当成单体武器低估成废卡）
		var beh := Weapon.behavior_of(w)
		var multi := float(w.get("aoe", 0)) > 0.0 or beh == "pulse" or beh == "beam"
		var v := _value_per_gold(w, 3 if multi else 1)
		if v < worst:
			worst = v
			weakest = str(w.get("zh", k))
	chk(worst > cheap * 0.5,
		"最弱的武器（%s）性价比也有手枪的一半（%.2f vs %.2f）" % [weakest, worst, cheap])

	# 17) 行为分支：老武器缺省 projectile，近战自动归 melee，data 写了就按写的
	chk(Weapon.behavior_of(pistol) == "projectile", "老武器缺省还是普通弹（向后兼容）")
	chk(Weapon.behavior_of(data.weapon("cleaver")) == "melee", "近战武器自动归到 melee")
	chk(Weapon.behavior_of(data.weapon("microwave")) == "beam", "微波炉是瞬发光束")

	# 18) 扇形半角：近战 120°、光束是一条线、脉冲整圈
	chk(abs(rad_to_deg(Weapon.melee_half_arc(data.weapon("cleaver"))) * 2.0 - 120.0) < 0.001,
		"近战张角 120°")
	chk(rad_to_deg(Weapon.sector_half_arc(data.weapon("microwave"))) * 2.0 < 10.0,
		"光束张角小于 10°，读起来是一条线")
	chk(abs(Weapon.sector_half_arc(data.weapon("pan")) - PI) < 0.001,
		"脉冲是整圈（半角 PI = 360°）")
	chk(Weapon.is_sector(data.weapon("pan")) and Weapon.is_sector(data.weapon("cleaver")),
		"脉冲与近战共用同一套扇形结算")
	chk(not Weapon.is_sector(pistol), "普通弹不走扇形结算")

	# 19) 打法必须铺开：不能清一色普通弹（"换武器只换数字"的老毛病）
	#  C1 后 40 把里 projectile 只占 40%（16/40）——这是硬下限，谁往表里
	#  灌一堆普通弹把占比顶回去，这里直接红。
	var kinds := {}
	var proj := 0
	for k in data.weapon_keys():
		var b := Weapon.behavior_of(data.weapon(k))
		kinds[b] = true
		if b == "projectile":
			proj += 1
	chk(kinds.size() >= 5, "武器打法至少 5 种（实际 %d 种）" % kinds.size())
	chk(proj * 2 < data.weapon_keys().size(),
		"普通弹不超过一半（%d/%d），换武器必须换手感" % [proj, data.weapon_keys().size()])

	# 19b) C1 验收：每个武器类 ≥8 把 —— 任一角色凑羁绊 6 件都得有得挑
	var tag_n := {}
	for k in data.weapon_keys():
		for t in (data.weapon(k) as Dictionary).get("tags", []):
			tag_n[str(t)] = int(tag_n.get(str(t), 0)) + 1
	chk(tag_n.size() >= 5, "武器类 ≥5 类（实际 %d 类）" % tag_n.size())
	var thin: Array = []
	for t in tag_n:
		if int(tag_n[t]) < 8:
			thin.append("%s=%d" % [t, tag_n[t]])
	chk(thin.is_empty(), "每类武器 ≥8 把（太薄的：%s）"
		% (", ".join(thin) if thin.size() > 0 else "无"))

	# 20) behavior 拼错会静默退化成普通弹 —— 必须有测试兜住
	var known := {"projectile": true, "melee": true, "beam": true, "pulse": true,
		"chain": true, "boomerang": true, "homing": true}
	var bad := ""
	for k in data.weapon_keys():
		var b := Weapon.behavior_of(data.weapon(k))
		if not known.has(b):
			bad += "%s=%s " % [str(k), b]
	chk(bad == "", ("没有拼错的 behavior" if bad == "" else "拼错：%s" % bad))

	# 19c) 守卫自己的尺子不能歪：CHAIN_FALLOFF 必须真的从 BulletSystem 读出来
	#  （读不到会静默退化成 0，连锁武器被当成单体算，整排配平断言全失真）
	chk(_chain_falloff() > 0.0 and _chain_falloff() < 1.0,
		"链式衰减系数是从源码现读的（%.2f，不是写死的猜测值）" % _chain_falloff())

	return {"pass": _p, "fail": _f, "failures": _failures}

# 每金币能买到多少输出。
# ⚠️ 这里【必须】按每种打法的真实命中数折算，否则就是在奖励数值堆叠：
#   旧模型只给 aoe / pulse / beam 乘 3，链式/回旋一律按单体算 —— 结果一把
#   能串 3 只怪的连锁武器，为了过这道坎只能把单体伤害堆到离谱，
#   而真正意义上的"废物卡"（单体 dps 低、又打不到第二只）反而看不出来。
# 倍率全部对齐 scenes/BulletSystem.gd 的实装常数，不是拍脑袋：
#   chain     = 1 + Σ CHAIN_FALLOFF^i（BulletSystem 每跳 ×0.72）
#   boomerang = 1.6（去程+回程各能命中一次，但回程常常打空）
#   homing    = 1.15（只追一个目标，贵在不空枪，不算群体）
func _multiplier(w: Dictionary, targets: int) -> float:
	var beh := Weapon.behavior_of(w)
	if float(w.get("aoe", 0)) > 0.0 or beh == "pulse" or beh == "beam":
		return float(targets)
	if beh == "chain":
		var n := int(w.get("chain", 0))
		var m := 1.0
		var hop := 1.0
		for _i in range(n):
			hop *= _chain_falloff()
			m += hop
		return m
	if beh == "boomerang":
		return 1.6
	if beh == "homing":
		return 1.15
	return 1.0

func _value_per_gold(w: Dictionary, targets: int) -> float:
	var dps := Combat.weapon_dps(w)
	return dps * _multiplier(w, targets) / maxf(1.0, float(w.get("cost", 1)))
