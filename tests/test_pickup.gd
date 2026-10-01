extends RefCounted

# 金币掉落物测试：磁吸范围/吸附飞行/拾取判定/掉落散开/面额拆分。
#
# 这层逻辑决定了"走位收钱"的手感，也是 upgrades.json 里 pick（拾取范围+30%）
# 唯一生效的地方 —— 所以除了纯函数，还断言配表真的存在 pickup 段。

const Pickup := preload("res://core/Pickup.gd")

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
	var raw: Dictionary = {}
	if data != null and data.balance.has("pickup"):
		raw = data.balance["pickup"] as Dictionary
	var c := Pickup.cfg(raw)
	var magnet := float(c["magnet"])
	var pull := float(c["pull_speed"])
	var collect := float(c["collect_radius"])

	# 1) 配表里必须有 pickup 段（缺了说明 balance.json 被改坏）
	chk(not raw.is_empty(), "balance.json 存在 pickup 配置段")
	chk(magnet > 0.0 and pull > 0.0, "磁吸半径 %.0f / 吸附速度 %.0f 均为正" % [magnet, pull])
	# 吸附速度必须明显快于玩家速度，否则金币永远追不上跑动的玩家
	var pspeed := 240.0
	if data != null:
		pspeed = float((data.player_cfg()).get("speed", 240))
	chk(pull > pspeed, "吸附速度 %.0f 快于玩家速度 %.0f（追得上）" % [pull, pspeed])

	# 2) 拾取范围强化：pickup_pct 直接放大磁吸半径
	chk(absf(Pickup.magnet_range(100.0, 0.0) - 100.0) < 0.001, "无强化时磁吸半径 = 基础值")
	chk(absf(Pickup.magnet_range(100.0, 0.3) - 130.0) < 0.001, "pickup_pct +30% → 半径 100→130")
	chk(absf(Pickup.magnet_range(100.0, -5.0) - 100.0) < 0.001, "负的强化值不会把半径缩没（钳到 0 加成）")

	# 3) 磁吸圈外不动
	var far := Vector2(0, 0)
	var pp := Vector2(500, 0)
	var r := Pickup.step(far, pp, magnet, pull, collect, 0.016)
	chk(not bool(r["collected"]), "圈外(500px)金币不会被吸")
	chk((r["pos"] as Vector2).distance_to(far) < 0.001, "圈外金币原地不动")

	# 4) 进圈后被拉近，且方向朝玩家
	var near := Vector2(magnet - 5, 0)
	r = Pickup.step(near, Vector2.ZERO, magnet, pull, collect, 0.016)
	var moved: Vector2 = r["pos"]
	chk(moved.x < near.x, "圈内(%.0fpx)金币朝玩家移动" % near.x)
	chk(moved.distance_to(Vector2.ZERO) < near.distance_to(Vector2.ZERO), "圈内金币离玩家更近了")

	# 5) 贴脸就吃到
	r = Pickup.step(Vector2(collect - 1, 0), Vector2.ZERO, magnet, pull, collect, 0.016)
	chk(bool(r["collected"]), "进入 collect_radius(%.0f) 内即被拾取" % collect)

	# 6) 高速+大 delta 不会"冲过头"后跑到玩家另一侧（必须判定吃到而不是穿过去）
	var big := 0.5   # 半秒一帧，极端情况
	r = Pickup.step(Vector2(collect + 30, 0), Vector2.ZERO, magnet, pull, collect, big)
	chk(bool(r["collected"]), "大 delta(%.1fs) 下不会穿过玩家，直接判定拾取" % big)
	chk((r["pos"] as Vector2).distance_to(Vector2.ZERO) < 400.0, "大 delta 下位置不会飞到场外")

	# 7) 越近吸得越快（吸附感）
	var d_far: float = Vector2(magnet - 2, 0).distance_to(Vector2.ZERO)
	var s_far: Vector2 = Pickup.step(Vector2(magnet - 2, 0), Vector2.ZERO, magnet, pull, collect, 0.016)["pos"]
	var s_near: Vector2 = Pickup.step(Vector2(collect + 10, 0), Vector2.ZERO, magnet, pull, collect, 0.016)["pos"]
	var v_far: float = Vector2(magnet - 2, 0).distance_to(s_far)
	var v_near: float = Vector2(collect + 10, 0).distance_to(s_near)
	chk(v_near > v_far, "离得越近吸得越快(近 %.2f > 远 %.2f px/帧)" % [v_near, v_far])

	# 8) 掉落散开：spread=0 原地，有 spread 时不超过半径
	chk(Pickup.drop_position(Vector2(10, 10), 0.5, 0.5, 0.0) == Vector2(10, 10), "spread=0 时金币掉在原地")
	for i in 40:
		var a := float(i) / 40.0
		var dp: Vector2 = Pickup.drop_position(Vector2.ZERO, a, 1.0 - a, 26.0)
		if dp.length() > 26.001:
			chk(false, "散开位置超出 spread 半径")
			break
	chk(Pickup.drop_position(Vector2.ZERO, 0.3, 1.0, 26.0).length() <= 26.001,
		"散开位置不超过 spread 半径")

	# 9) 面额拆分：总和守恒，枚数受 max_pieces 限制
	chk(Pickup.split_count(1, 4) == 1, "1 金币只掉 1 枚")
	chk(Pickup.split_count(40, 4) <= 4, "大额金币也最多拆 4 枚（不刷屏）")
	var vals := Pickup.split_values(7, 3)
	var total := 0
	for v in vals:
		total += int(v)
	chk(total == 7, "拆分后总额守恒（7 → %s）" % str(vals))
	chk(vals.size() == 3, "拆成 3 枚")
	chk(int(Pickup.split_values(7, 3)[0]) >= int(Pickup.split_values(7, 3)[2]),
		"余数塞进第一枚（先掉的那枚更大）")

	# 10) 实体冒烟：spawn → 远处不动 → 强制吸取能收到钱
	var scene := load("res://entities/Pickup/Pickup.tscn")
	if scene == null:
		chk(false, "Pickup.tscn 可加载")
		return {"pass": _p, "fail": _f, "failures": _failures}
	var node = scene.instantiate()
	node.spawn(Vector2(300, 300), 5, raw)
	chk(node.active == true, "spawn 后金币激活")
	chk(node.value == 5, "spawn 后价值 = 5")
	# ⚠️ 必须显式声明 int：node 来自 instantiate()（Variant），用 := 会推断失败并让整个文件 Parse Error
	var got: int = node.advance(0.016, Vector2(0, 0), 0.0, false)
	chk(got == 0, "远离玩家时收不到钱")
	# 强制吸取 = 无视磁吸半径全速飞过来（波末清场用），需要若干帧才飞到
	var frames := 0
	while frames < 300 and node.active:
		got += node.advance(1.0 / 60.0, Vector2(0, 0), 0.0, true)
		frames += 1
	chk(got == 5, "强制吸取时全速飞向玩家并收满 5 金币（%d 帧）" % frames)
	chk(node.active == false, "收取后金币回池（active=false）")
	node.free()

	# 11) 池子：掉的钱一分不少（池满时最老的直接结算，不蒸发）
	var field_scene := load("res://entities/Pickup/PickupField.tscn")
	if field_scene == null:
		chk(false, "PickupField.tscn 可加载")
		return {"pass": _p, "fail": _f, "failures": _failures}
	var field = field_scene.instantiate()
	# ⚠️ 测试里没有把节点挂进树，_ready 不会跑（池是空的），手动建池
	field._ready()
	var pool_n: int = field.alive_count()   # 建池后是 0 枚激活
	chk(pool_n == 0, "建池后场上没有金币")
	var dropped := 0
	var overflowed := 0
	for _i in 30:
		dropped += 6
		overflowed += field.drop(Vector2(100, 100), 6)
	chk(field.alive_count() > 0, "掉钱后场上有金币（%d 枚）" % field.alive_count())
	var swept: int = field.collect_all(Vector2(100, 100))
	chk(swept + overflowed == dropped,
		"掉的钱一分不少：地上 %d + 池满直结 %d = 掉的 %d" % [swept, overflowed, dropped])
	chk(field.alive_count() == 0, "清场后场上没有残留金币")
	field.free()

	# 12) 新拾取模型参数齐全（真实磁吸半径靠 GameState.pickup_magnet 算，这里校验配表）
	var pdict: Dictionary = data.balance["pickup"] as Dictionary
	chk(pdict.has("magnet_base") and float(pdict.get("magnet_base", 0)) > 0.0,
		"pickup.magnet_base(%.0f) 存在且为正（无强化时仅贴近才捡）" % float(pdict.get("magnet_base", 0)))
	chk(pdict.has("magnet_autopick") and float(pdict.get("magnet_autopick", 0)) > float(pdict.get("magnet_base", 0)),
		"pickup.magnet_autopick(%.0f) > magnet_base（自动拾取范围更大）" % float(pdict.get("magnet_autopick", 0)))
	chk(pdict.has("wave_end_loss") and float(pdict.get("wave_end_loss", 0)) > 0.0,
		"pickup.wave_end_loss(%.2f) 存在且为正（波末散落按损耗入袋）" % float(pdict.get("wave_end_loss", 0)))

	# 13) 波末"部分损耗落袋"模型（与 GameState.gold_sweep_loss 同公式）
	# 复算：fullauto→0；否则 base，autopick 减半，再随 pickup_pct 小幅降
	var base_loss := float(pdict.get("wave_end_loss", 0.25))
	var loss_for = func(autopick: bool, fullauto: bool, pct: float) -> float:
		if fullauto:
			return 0.0
		var l := base_loss
		if autopick:
			l *= 0.5
		l *= (1.0 - 0.2 * clampf(pct, 0.0, 1.0))
		return clampf(l, 0.0, 1.0)
	chk(absf(loss_for.call(false, false, 0.0) - base_loss) < 0.001,
		"裸装波末损耗 = %.0f%%（散落钱只收回约 %d%%）" % [base_loss * 100, int((1.0 - base_loss) * 100)])
	chk(loss_for.call(false, true, 0.0) == 0.0, "全屏自动拾取 → 损耗 0%（零损耗落袋）")
	chk(loss_for.call(true, false, 0.0) < base_loss, "自动拾取 → 损耗减半")
	# 模拟：散落 100 金币，裸装收回 75、全屏自动拾取收回 100、自动拾取收回 87
	var sim_total := 100
	chk(int(float(sim_total) * (1.0 - loss_for.call(false, false, 0.0))) == 75,
		"裸装散落 100 → 落袋 75（损耗 25）")
	chk(int(float(sim_total) * (1.0 - loss_for.call(false, true, 0.0))) == 100,
		"全屏自动拾取散落 100 → 落袋 100（零损耗）")

	return {"pass": _p, "fail": _f, "failures": _failures}
