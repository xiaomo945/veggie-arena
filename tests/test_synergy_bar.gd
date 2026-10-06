extends RefCounted

# 羁绊进度条（ui/HUD/HudSynergy.gd）的布局与接线守卫。
#
# 为什么单独一个文件：test_hud_layout.gd 已经顶到 300 行红线（架构守卫 R1 是硬失败），
#   再往里塞就等于逼着把整块布局测试拆散。按项目"抽模块而不是放宽规则"的惯例，
#   这条新增控件自己一个守门文件，两边都还在红线内。
#
# 要保的三件事：
#   1) 羁绊条必须落在相机让位范围内（底边 ≤ HudLayout.TOP_CONTENT_H）—— 否则玩家
#      贴场地最上沿时头顶被这一条压住（顶部 HUD 挡住角色这个 bug 真踩过）。
#   2) 它的坐标必须取自 HudLayout，不能自己写死一份（写死两处必然漂移）。
#   3) HUD.gd 必须真的挂了它，并把跨档通知转给横幅 —— 防"加了个控件没人用"。
#
# 与 test_hud_layout.gd 一样走"读源码做断言"：HudLayout 用 autoload 标识符 Data，
# --script 单测环境没有 autoload，preload 它会直接编译失败。

const SP := preload("res://tests/SrcParse.gd")

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
	var layout_src := SP.read("res://ui/HUD/HudLayout.gd")
	chk(layout_src.length() > 0,
		"能读到 HudLayout.gd 源码（路径写错会导致假通过，实际 %d 字符）" % layout_src.length())
	if layout_src.is_empty():
		return {"pass": _p, "fail": _f, "failures": _failures}

	var content_h := SP.const_val(layout_src, "TOP_CONTENT_H")
	var safe_top := SP.ternary_p(layout_src, "func safe_top()")
	chk(content_h > 0.0 and safe_top >= 0.0,
		"TOP_CONTENT_H=%.0f / safe_top=%.0f 解析成功" % [content_h, safe_top])

	# 羁绊条：局部 y（safe_top 之后的偏移）+ 高度，必须落在相机让位范围内。
	# synergy_pos() 返回 Vector2(8.0, safe_top() + 80.0) —— 取行内最后一个数字就是那个 80。
	var line := SP.line_of(layout_src, "func synergy_pos()")
	var h := SP.ret(layout_src, "func synergy_h()")
	var re := RegEx.new()
	re.compile("([0-9.]+)")
	var nums: Array = []
	for m in re.search_all(line):
		nums.append(float(m.get_string(1)))
	chk(nums.size() >= 2 and h > 0.0,
		"羁绊条的局部 y 与高度解析成功（y=%.0f h=%.0f）"
		% [nums[-1] if nums.size() > 0 else -1.0, h])
	if nums.size() >= 2:
		chk(nums[-1] + h <= content_h,
			"羁绊条底边（局部 %.0f）≤ TOP_CONTENT_H %.0f（相机让位覆盖得到，不压玩家头顶）"
			% [nums[-1] + h, content_h])
		chk(nums[-1] > 76.0,
			"羁绊条顶边（局部 %.0f）在武器槽/文字行之下（>76，不与顶部控件叠）" % nums[-1])

	# 接线：HUD 挂了它 + 跨档通知进横幅
	var hud_src := SP.read("res://ui/HUD/HUD.gd")
	chk("HudSynergyScript" in hud_src and "tier_up" in hud_src,
		"HUD.gd 挂了羁绊条，并把跨档通知转发给横幅")
	var syn_src := SP.read("res://ui/HUD/HudSynergy.gd")
	chk("HudLayout.synergy_pos()" in syn_src,
		"羁绊条坐标取自 HudLayout（没自己写死一份）")
	chk("Synergy.progress(" in syn_src,
		"羁绊条的数据来自 Synergy.progress（与战斗结算同一套规则，不会两处不一致）")

	return {"pass": _p, "fail": _f, "failures": _failures}
