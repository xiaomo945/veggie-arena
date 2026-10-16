extends RefCounted

# 键盘模块测试（电脑版输入契约）：
#   行为级目检在 scripts/kb_shot.gd（xvfb 真渲染 + Input.parse_input_event 注入，
#   量真实位移/信号计数）；这里守【源码契约】—— 删了某条接线、丢了某个分支，
#   门禁当场挂，防"键盘操作 silently 回归"。
#   覆盖：WASD / JKL / U / 空格 / 回车 + ESC 暂停/恢复/关店。

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> bool:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)
	return cond

func run(_arg = null) -> Dictionary:
	var src := FileAccess.get_file_as_string("res://autoload/Keyboard.gd")

	# ESC：桌面端暂停/恢复/关店（gamepad 的 START 早接了暂停，键盘不能没有）
	chk(src.contains("KEY_ESCAPE"), "Keyboard 处理 ESC 键")
	chk(src.contains("Events.pause_requested.emit"), "ESC(战斗中) → 暂停 pause_requested")
	chk(src.contains("Events.resume_requested.emit"), "ESC(暂停中) → 恢复 resume_requested")
	chk(src.contains("Events.kb_shop_close.emit"), "ESC(补给站) → 关店 kb_shop_close")
	# 恢复要判"暂停中且局中"，不能把标题页的 ESC 也吞成恢复
	chk(src.contains("GameState.paused and GameState.running"), "恢复带 GameState.paused+running 守卫")

	# 原有七项契约不丢
	chk(src.contains("KEY_W") and src.contains("KEY_A") \
		and src.contains("KEY_S") and src.contains("KEY_D"), "WASD 四向移动")
	chk(src.contains("KEY_J") and src.contains("KEY_K") and src.contains("KEY_L"),
		"JKL = 技能 1/2/3")
	chk(src.contains("KEY_U"), "U = 攻击")
	chk(src.contains("KEY_SPACE"), "空格 = 冲刺")
	chk(src.contains("KEY_ENTER") or src.contains("KEY_KP_ENTER"), "回车 = 下一波")

	# 暂停/恢复信号必须有消费端（Game.gd），单有发射方等于没接
	var game := FileAccess.get_file_as_string("res://scenes/Game.gd")
	chk(game.contains("Events.pause_requested.connect"), "Game 订阅 pause_requested")
	chk(game.contains("Events.resume_requested.connect"), "Game 订阅 resume_requested")

	return {"pass": _p, "fail": _f, "failures": _failures}
