extends RefCounted

# 持续伤害（毒/灼烧）节流守门：验证 core/DotTicker 把每帧微小 dot 按 DOT_TICK(0.5s) 累加，
# 在 <DOT_TICK 期间返回 0（不每帧结算），到 DOT_TICK 时一次性返回累积值；
# 且全周期总伤害与"逐帧积分"完全等价（线性累加、不丢伤害、不无限累加）。
# 这是毒雾/颠勺毒不再卡死手机的根因修复。
#
# 三条核心不变式：
#   1) 节流生效：前 0.5s 内不得有任何结算（否则等于每帧结算，卡顿回来）。
#   2) 数值等价：全周期（含到期后尾巴）结算的总伤害 ≈ 理论值（毒+灼烧 dps × 时长），不丢伤害。
#   3) 低频：结算次数 ≈ 时长 / DOT_TICK（2 次/秒），远小于帧数（60 次/秒）—— 这才是降负载的关键。
#   4) 自动停：效果到期后不再结算，效果表清空。

const DotTicker := preload("res://core/DotTicker.gd")

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

func run(_data) -> Dictionary:
	var tk := DotTicker.new()
	# 每秒 6 点中毒 + 4 点灼烧 = 每秒 10 点，持续 5 秒 → 理论总伤害 50
	var fx := {"poison": {"v": 6.0, "t": 5.0}, "burn": {"v": 4.0, "t": 5.0}}
	var dt := 1.0 / 60.0
	var settled := 0.0
	var flushes := 0
	var early_hits := 0      # 前 0.5s 内错误"每帧都返回 >0"的帧数

	# 整周期 5 秒（300 帧）
	for i in 300:
		var dmg := tk.accumulate(fx, dt)
		if dmg > 0.0:
			settled += dmg
			flushes += 1
			if i < 30:
				early_hits += 1
	chk(early_hits == 0, "前 0.5s 内不结算（节流生效，early_hits=%d）" % early_hits)

	# 周期结束后多跑 1 秒，把"到期后尾巴"那次残留 flush 也收进来，再确认彻底停止
	var after := 0.0
	for i in 60:
		var dmg := tk.accumulate(fx, dt)
		if dmg > 0.0:
			after += dmg
			flushes += 1
	settled += after

	# 不变式 2：总伤害 ≈ 理论值（50），不丢不增
	chk(abs(settled - 50.0) < 1.0,
		"全周期结算总伤害 ≈ 50（实际 %.2f，与逐帧积分等价、无损耗）" % settled)
	# 不变式 3：结算频率远低于逐帧（300 帧里只结算 ~10 次 ≈ 2次/秒）
	chk(flushes <= 15, "结算次数远低于帧数（flushes=%d ≤ 15，低频节流生效）" % flushes)
	chk(flushes >= 8, "结算次数不为零（flushes=%d ≥ 8，确实在按节拍结算）" % flushes)
	# 不变式 4：到期彻底停止
	chk(after < 10.0, "到期后尾巴已收口（after=%.4f，仅最后一次残留 flush）" % after)
	var leaked := 0.0
	for i in 60:
		leaked += tk.accumulate(fx, dt)
	chk(leaked < 0.001, "彻底到期后零伤害（leaked=%.4f，效果表已清空=%s）" % [leaked, fx.is_empty()])

	return {"pass": _p, "fail": _f, "failures": _failures}
