extends RefCounted

# 帧率自适应降级（core/PerfGuard.gd）的纯逻辑测试。
#
# 要保的事（这些错了，玩家在手机上得到的就是"忽明忽暗、敌人忽多忽少"）：
#   1) 掉帧要持续一段时间才降档 —— 偶发的一两帧卡顿（切后台、加载）不该降级。
#   2) 升档比降档慢得多（6 秒 vs 1 秒）+ 迟滞带（50/58），档位不许在阈值上抖。
#   3) 玩家手选画质是【下限】：手选"低"锁死保底档，自动降级不许把它拉高。
#   4) 已经到底/到顶时不再越界，档位永远在 [floor, 3]。

const PerfGuard := preload("res://core/PerfGuard.gd")

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

# 连续跑 n 帧（每帧 delta 秒、恒定 fps），返回最终档位
func _run(start: int, fps: float, seconds: float, floor_level := 0, delta := 1.0 / 60.0) -> int:
	var lv := start
	var hold := 0.0
	var n := int(ceil(seconds / delta))
	for _i in n:
		var r := PerfGuard.step(lv, fps, hold, delta, floor_level)
		lv = int(r[0])
		hold = float(r[1])
	return lv

func run(_data) -> Dictionary:
	# --- 掉帧降档：门槛 0.4 秒（原 1.0 太钝：玩家都感觉到卡了才降）---
	chk(_run(0, 30.0, 0.3) == 0, "掉帧 0.3 秒还不降（躲开偶发卡顿）")
	chk(_run(0, 30.0, 0.5) == 1, "掉帧 0.5 秒降一档")
	chk(_run(0, 30.0, 1.1) == 2, "持续掉帧会连降两档")
	chk(_run(0, 30.0, 6.0) == PerfGuard.MAX_LEVEL, "一路掉到底也不越过最低档")
	chk(_run(3, 20.0, 10.0) == 3, "已在保底档时不再往下")

	# --- 帧率回来要慢慢升：升档门槛 6 秒 ---
	chk(_run(2, 60.0, 3.0) == 2, "回稳 3 秒还不升（升档更慢）")
	chk(_run(2, 60.0, 6.5) == 1, "回稳 6.5 秒升一档")
	chk(_run(0, 60.0, 20.0) == 0, "已在满配档不会往上跑")

	# --- 迟滞带：50~58 之间不动 ---
	chk(_run(1, 54.0, 30.0) == 1, "54fps 落在迟滞带里，档位不动（防抖档）")

	# --- 手选画质是下限 ---
	chk(PerfGuard.floor_from_quality(0) == 3, "手选低画质 → 锁死保底档")
	chk(PerfGuard.floor_from_quality(1) == 1, "手选中画质 → 最多用到轻降档")
	chk(PerfGuard.floor_from_quality(2) == 0, "手选高画质 → 交给自动")
	# 手选"低"时，哪怕帧率 120 也不能升上去（玩家明确要省电/不烫）
	chk(_run(3, 120.0, 30.0, 3) == 3, "手选低画质时帧率再高也不许升档")
	chk(_run(0, 120.0, 30.0, 1) == 1, "手选中画质时最多升到轻降档")
	# 注意：起点 0 会被立刻夹到中画质下限 1，所以 0.5 秒正好降一档到 2
	chk(_run(0, 30.0, 0.5, 1) == 2, "手选中画质仍会继续自动降级")

	# --- 脏数据 ---
	chk(PerfGuard.step(0, 0.0, 0.0, 0.016)[0] == 0, "fps=0（首帧/异常 delta）不降级")
	chk(PerfGuard.step(0, -1.0, 0.0, 0.016)[0] == 0, "负帧率不降级")

	# --- 档位参数单调：越降越省 ---
	var ok := true
	for i in PerfGuard.MAX_LEVEL:
		var a := PerfGuard.caps(i)
		var b := PerfGuard.caps(i + 1)
		if int(a.get("floats", 0)) <= int(b.get("floats", 0)): ok = false
	chk(ok, "每降一档，飘字上限严格变少")

	# --- 同屏怪上限：档位与 spawn 配置取交集，且必须真的少怪 ---
	# ⚠️ 这里曾经踩过坑：档位表写 88/64/48/32，而 spawn.max_alive 实测只有 38，
	# 于是"降了两档、同屏一只怪没少"。现在的判据是"按真实量级(38)算，每档真的少怪"。
	var spawn_cap := 38
	chk(PerfGuard.alive_cap(spawn_cap, 0) == spawn_cap,
		"满配档不额外限制同屏怪数（= spawn 配置的 38，与改动前逐帧一致）")
	chk(PerfGuard.alive_cap(spawn_cap, 1) == 32, "轻降档同屏上限 32")
	chk(PerfGuard.alive_cap(spawn_cap, 2) == 26, "中降档同屏上限 26")
	chk(PerfGuard.alive_cap(spawn_cap, 3) == 20, "保底档同屏上限 20")
	var mono := true
	for i in PerfGuard.MAX_LEVEL:
		if PerfGuard.alive_cap(spawn_cap, i + 1) >= PerfGuard.alive_cap(spawn_cap, i): mono = false
	chk(mono, "每降一档，同屏怪上限按 38 的真实量级严格变少（不许再出现 88 这种空档）")
	# 档位上限比 spawn 配置更宽松时，取更小的那个（spawn 配置始终是硬顶）
	chk(PerfGuard.alive_cap(10, 1) == 10, "spawn 配置比档位更小时，取 spawn 配置")
	chk(PerfGuard.alive_cap(10, 0) == 10, "满配档下 spawn 配置依然是硬顶")
	chk(PerfGuard.caps(9) == PerfGuard.caps(PerfGuard.MAX_LEVEL), "越界档位被钳到保底档")
	chk(bool(PerfGuard.caps(0).get("far_detail", false)) \
		and not bool(PerfGuard.caps(3).get("far_detail", true)), "只有中降以上才砍远景柔影")

	return {"pass": _p, "fail": _f, "failures": _failures}
