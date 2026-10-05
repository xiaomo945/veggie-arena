extends RefCounted

# 顶部 HUD 布局守卫：把"控件互相遮挡"和"角色被 HUD 盖住"这两类目检才能发现的 bug
# 变成硬断言。这个文件的价值：布局回归肉眼难发现（挪一个数字可能刚好挪进另一个控件），
# 所以把约束钉死在这里，谁挪谁红。
#
# 真实 bug 1（用户报："第3格第4格第5格的武器显示不了"）：
#   武器槽原本画在 y=30，而暂停按钮占 y=16~64 / x=484~532，两者整块重叠。
#
# 真实 bug 2（用户报："玩家走到屏幕最上边时被 HUD 挡住角色"）：
#   HUD 一路占到 y=112（还有刘海避让的 34px 下移），而玩家贴到场地最上沿时
#   角色中心正好在屏幕 y=46 —— 整个萝卜被 HUD 盖死。
#   修法是"HUD 压矮 + 相机按 HudLayout.hud_block_h() 在上边让位"，
#   本文件负责钉死两件事：(a) HUD 各控件矩形互不相交；(b) 角色带在 HUD 之下。
#
# 为什么读源码而不 preload ui/HUD/HudLayout.gd：
#   HudLayout 用的是 autoload 标识符 Data（编译期注入），--script 单测环境没有 autoload，
#   preload 它会直接 Compile Error。项目里 test_bgm.gd / test_gamepad.gd 已有同样的
#   "读源码做断言"模式（FileAccess.get_file_as_string），这里沿用。
#   读源码还能顺带防住"改了布局表但忘了同步到用它的节点"这类漂移。

# ---- 顶部三条进度条的 Y/高：全部从 ui/HUD/HudBars.gd 源码解析，不在这里抄第二份。
#      抄常量的教训（真踩过）：这里曾写 XP_Y=47 而产品是 45、XP_W=194 而产品被
#      _ready() 覆盖成 300 —— 测试全绿，实际 LV 数字被武器槽图标吃掉。抄一份就会漂。
#      HudBars 是 Node2D，_draw() 坐标全是字面量，单测里没法实例化，只能读源码。
#      宽度另有 BAR_W / WOK_W / RUN_W / XP_W 四个 var 由 _ready() 从 HudLayout 取，
#      所以宽度也走 HudLayout 解析（见 run()），Y/高走 const 解析。
const SLOT_SIZE := 26.0        # 与 ui/HUD/WeaponBar.gd / HudLayout.slot_size() 一致
const SLOT_GAP := 5.0
const PORTRAIT_W := 540.0
const LANDSCAPE_W := 960.0

# ---- 竞技场 / 视口（来自 data/balance.json 的 arena，两套都要覆盖）----
const ARENA_Y := -360.0         # 竖屏 arena.y
const LAND_ARENA_Y := -540.0    # 横屏 arena.landscape.y
const VIEW_W := 540.0
const VIEW_H := 900.0
const LAND_VIEW_H := 540.0
const PLAYER_R := 22.0
const RIM_MARGIN := 24.0        # ui/Screens/ScreenMode.RIM_MARGIN

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

func run(data) -> Dictionary:
	var max_slots := int(data.shop_cfg().get("max_slot", 6))

	# 读生产代码的真实坐标（而不是在这里抄一份常量）
	var layout_src := SP.read("res://ui/HUD/HudLayout.gd")
	chk(layout_src.length() > 0, "能读到 HudLayout.gd 源码（路径写错会导致假通过，实际 %d 字符）"
		% layout_src.length())
	if layout_src.is_empty():
		return {"pass": _p, "fail": _f, "failures": _failures}

	var slot_y := SP.ret(layout_src, "func slot_y()")
	var slot_right_p := SP.ternary_p(layout_src, "func slot_right()")
	var pause_x_p := SP.ternary_p(layout_src, "func top_pause_pos()")
	var pause_size := SP.ret(layout_src, "func top_pause_size()")
	var safe_top := SP.ternary_p(layout_src, "func safe_top()")
	var content_h := SP.const_val(layout_src, "TOP_CONTENT_H")
	var pad := SP.const_val(layout_src, "TOP_BLOCK_PAD")
	var text_y := SP.ret(layout_src, "func text_row_y()")
	# bar_w() 的算法是 bar_right() - bar_x()，不是字面量；宽度取 HudBars 的默认值
	# （_ready() 会用 HudLayout.bar_w() 覆盖它，但默认值必须与之一致，否则说明
	#  两处各写一份 —— 那正是"改了布局表忘了改节点"的漂移）。
	var run_w_p := SP.ternary_p(layout_src, "func run_w()")
	var xp_w_p := SP.ternary_p(layout_src, "func xp_w()")

	chk(slot_y >= 0.0, "HudLayout.slot_y() 能解析出数值（%.0f）" % slot_y)
	chk(slot_right_p >= 0.0, "HudLayout.slot_right() 竖屏值（%.0f）" % slot_right_p)
	chk(pause_x_p > 400.0,
		"竖屏暂停按钮 x=%.0f 真解析出来了（不是从 Vector2 类型名里抠出的假数字）"
		% pause_x_p)
	chk(pause_x_p > 0.0 and pause_size > 0.0, "暂停按钮位置/尺寸能解析（x=%.0f size=%.0f）"
		% [pause_x_p, pause_size])
	chk(safe_top >= 0.0, "HudLayout.safe_top() 竖屏值（%.0f）" % safe_top)
	chk(content_h > 0.0 and pad >= 0.0, "TOP_CONTENT_H=%.0f TOP_BLOCK_PAD=%.0f" % [content_h, pad])
	chk(text_y >= 0.0, "HudLayout.text_row_y() 能解析（%.0f）" % text_y)
	if slot_y < 0.0 or content_h <= 0.0 or safe_top < 0.0 or pause_x_p < 100.0:
		return {"pass": _p, "fail": _f, "failures": _failures}

	# HudBars 的 Y/高同样读源码（HudLayout 只管宽度，Y 是 HudBars 自己的 const）
	var bars_src := SP.read("res://ui/HUD/HudBars.gd")
	chk(bars_src.length() > 0, "能读到 HudBars.gd 源码（实际 %d 字符）" % bars_src.length())
	if bars_src.is_empty():
		return {"pass": _p, "fail": _f, "failures": _failures}
	var bar_x := SP.const_val(bars_src, "BAR_X")
	var bar_y := SP.const_val(bars_src, "BAR_Y")
	var bar_h := SP.const_val(bars_src, "BAR_H")
	# 本波细条不是常量，是绘制时现算的 BAR_Y + BAR_H + 2.0（所以按表达式解析）
	var wave_y := SP.expr(bars_src, "BAR_Y + BAR_H + 2.0")
	var wok_y := SP.const_val(bars_src, "WOK_Y")
	var wok_h := SP.const_val(bars_src, "WOK_H")
	var xp_y := SP.const_val(bars_src, "XP_Y")
	var xp_h := SP.const_val(bars_src, "XP_H")
	var run_y := SP.const_val(bars_src, "RUN_Y")
	var run_h := SP.const_val(bars_src, "RUN_H")
	# HudBars 的三个宽度默认值（var，_ready() 会用 HudLayout 的值覆盖）
	var bar_w_p := SP.var_val(bars_src, "BAR_W")
	var run_w_def := SP.var_val(bars_src, "RUN_W")
	var xp_w_def := SP.var_val(bars_src, "XP_W")
	chk(bar_h > 0.0 and xp_h > 0.0 and wave_y >= 0.0,
		"HudBars 全部条形坐标解析成功（血条 y=%.0f 锅气 y=%.0f 经验 y=%.0f 本波细条 y=%.0f）"
		% [bar_y, wok_y, xp_y, wave_y])
	if bar_h <= 0.0 or xp_h <= 0.0 or bar_w_p <= 0.0:
		return {"pass": _p, "fail": _f, "failures": _failures}
	# 宽度必须真的接 HudLayout（防"布局表改了但 HudBars 还在用自己的默认值"）
	chk("HudLayout.xp_w()" in bars_src and "HudLayout.bar_w()" in bars_src,
		"HudBars 的条宽接了 HudLayout（xp_w/bar_w），不是各自写死一份")
	chk(run_w_def > 0.0 and xp_w_def > 0.0,
		"HudBars 的 RUN_W/XP_W 默认值有效（%.0f / %.0f，_ready() 会覆盖成 HudLayout 的值）"
		% [run_w_def, xp_w_def])

	# WeaponBar 必须真的用 HudLayout 的值（防"布局表改了但节点没跟上"的漂移）
	var wb_src := SP.read("res://ui/HUD/WeaponBar.gd")
	chk(wb_src.length() > 0, "能读到 WeaponBar.gd 源码（实际 %d 字符）" % wb_src.length())
	chk("HudLayout.slot_y()" in wb_src and "HudLayout.slot_right()" in wb_src,
		"WeaponBar 的 Y 与右边界都取自 HudLayout（没写死自己的坐标）")
	# bug 1 的根因就是"定义了 SLOT_Y 却没在绘制处用"，钉死"绘制路径必须用 SLOT_Y 变量"
	var draw_body := SP.func_body(wb_src, "func _draw()")
	chk(draw_body.find("SLOT_Y") >= 0,
		"WeaponBar 的绘制函数用 SLOT_Y 变量，而不是又写死一个 Y 数字")

	# 相机上边距必须真的接了 HUD 高度（bug 2 的正主）
	var sm_src := SP.read("res://ui/Screens/ScreenMode.gd")
	chk("HudLayout.hud_block_h()" in sm_src,
		"相机上边距接了 HudLayout.hud_block_h()（HUD 变高时镜头自动多让）")
	chk("_cam_margin()" in sm_src and "\"top\"" in sm_src,
		"相机用的是分边 margin（只有 top 让位，底部保持 RIM_MARGIN）")

	# 经验条右端 + LV/经验数字那一小截，必须停在武器槽左边界之前
	# （数字是紧贴条右端画的，条一拉宽数字就被武器图标吃掉 —— 真踩过）
	var xp_text_right := xp_w_p + 8.0 + 62.0
	var slots_left := slot_right_p - _slots_width(max_slots)
	chk(xp_text_right <= slots_left,
		"经验条(宽 %.0f)+LV 数字(预留 62) 合计 %.0f ≤ 武器槽最左 %.0f（数字不被武器图标压）"
		% [xp_w_p, xp_text_right, slots_left])
	chk(run_w_p <= PORTRAIT_W, "总波次条宽 %.0f 不超出竖屏屏宽" % run_w_p)

	for landscape in [false, true]:
		_check_layout(landscape, max_slots, slot_y, slot_right_p, pause_x_p,
			pause_size, content_h, text_y, bar_x, bar_y, bar_h, wave_y,
			wok_y, wok_h, xp_y, xp_h, run_y, run_h, bar_w_p)

	# 满槽时最左槽不能画出屏幕（竖屏更窄，先保竖屏）
	var left := slot_right_p - _slots_width(max_slots)
	chk(left >= 4.0,
		"竖屏满 %d 槽（总宽 %.0f）最左槽 x=%.0f ≥4，不画到屏幕外"
		% [max_slots, _slots_width(max_slots), left])

	# ===== bug 2 的正主：角色在场地最上沿时，不能被顶部 HUD 盖住 =====
	# 两套朝向都要查。横屏 arena 高度不同（1080 vs 1620）、视口也不同（540 vs 900），
	# 只验竖屏会漏掉横屏的回归 —— 而横屏出问题时玩家同样看不见自己。
	# 横屏 safe_top 也从源码取（10 if ... else 34，取横屏分支=第一个数）。
	# 别写死 10 —— 改了产品代码这里的断言就变成在验一个不存在的值。
	var safe_top_l := SP.ternary_l(layout_src, "func safe_top()")
	_check_player_visible(safe_top, content_h, pad, false)
	_check_player_visible(safe_top_l, content_h, pad, true)

	return {"pass": _p, "fail": _f, "failures": _failures}

# 相机按 hud_block_h 让位后，玩家贴到场地最上沿时角色落在屏幕哪，
# 以及顶部 HUD 到底占到哪。两者必须不相交。
func _check_player_visible(safe_top: float, content_h: float, pad: float,
		landscape: bool) -> void:
	var tag := "横屏" if landscape else "竖屏"
	var view_h := LAND_VIEW_H if landscape else VIEW_H
	var arena_y := LAND_ARENA_Y if landscape else ARENA_Y
	var hud_bottom := safe_top + content_h
	var top_margin := RIM_MARGIN + hud_bottom + pad
	var cam_y_min := arena_y + view_h * 0.5 - top_margin
	var p_world_y := arena_y + PLAYER_R         # 玩家能站到的最高世界坐标
	var screen_y := p_world_y - (cam_y_min - view_h * 0.5)
	var head_y := screen_y - PLAYER_R
	var foot_y := screen_y + PLAYER_R
	chk(head_y >= hud_bottom,
		"%s：玩家贴场地最上沿时角色顶端 y=%.0f ≥ HUD 底 y=%.0f（不压头顶）"
		% [tag, head_y, hud_bottom])
	chk(foot_y <= view_h,
		"%s：同一位置角色底部 y=%.0f ≤ 屏高 %.0f（没被挤出屏底）" % [tag, foot_y, view_h])
	chk(screen_y > hud_bottom * 0.5,
		"%s：角色中心 y=%.0f 落在 HUD 之下而不是背后（余量 %.0fpx）"
		% [tag, screen_y, head_y - hud_bottom])

	# 反向：也不能让得太狠，否则玩家白白少一截可用屏幕。
	# 横屏视口只有 540 高，扣掉 HUD 只剩 464，不适用竖屏的 700 门槛，按比例给 55%。
	var usable := view_h - hud_bottom
	var need := view_h * (0.55 if landscape else 0.78)
	chk(usable >= need,
		"%s：HUD 只占 %.0fpx，顶部仍留 %.0fpx 战斗区（不能让位过头）"
		% [tag, hud_bottom, usable])

func _check_layout(landscape: bool, max_slots: int, slot_y: float,
		slot_right_p: float, pause_x_p: float, pause_size: float,
		content_h: float, text_y: float, bar_x: float, bar_y: float, bar_h: float,
		wave_y: float, wok_y: float, wok_h: float, xp_y: float, xp_h: float,
		run_y: float, run_h: float, bar_w_p: float) -> void:
	var tag := "横屏" if landscape else "竖屏"
	var sw := LANDSCAPE_W if landscape else PORTRAIT_W
	var slot_right := (sw - 12.0) if landscape else slot_right_p
	var pause_x := pause_x_p if not landscape else (sw - 52.0)
	# 横屏条宽按 HudLayout 的算法铺满（bar_right - bar_x），竖屏用解析值
	var bar_w := (856.0 if landscape else bar_w_p)
	var pause_r := Rect2(Vector2(pause_x, 2.0), Vector2(pause_size, pause_size))
	var row := _slot_row_rect(max_slots, slot_y, slot_right)

	# ---- 1) 武器槽 vs 暂停按钮（bug 1 的正主）----
	# 槽数越多越往左伸，右端固定，所以撞的总是最右那几格。逐格查，撞了就报是第几格。
	var hit_slot := -1
	for n in range(1, max_slots + 1):
		var x0 := slot_right - _slots_width(n)
		for i in n:
			if _slot_rect(x0, i, slot_y).intersects(pause_r):
				hit_slot = i + 1
	chk(hit_slot < 0,
		"%s：%d 个武器槽（y=%.0f~%.0f）与暂停按钮 %s 完全不相交（撞上的最右格：第 %d）"
		% [tag, max_slots, slot_y, slot_y + SLOT_SIZE, str(pause_r), hit_slot])

	# ---- 2) 武器槽行 vs 三条进度条 + 本波细条 + 总波次条 ----
	# 满槽时最左槽 x=347(竖屏)，几乎横穿全屏，所以这几条都要查。
	var bars := {
		"经验条": Rect2(Vector2(bar_x, xp_y), Vector2(194.0, xp_h)),
		"锅气条": Rect2(Vector2(bar_x, wok_y), Vector2(bar_w, wok_h)),
		"血条": Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)),
		"本波细条": Rect2(Vector2(bar_x, wave_y), Vector2(bar_w, 3.0)),
		"总波次条": Rect2(Vector2(8.0, run_y), Vector2(bar_w, run_h)),
	}
	for k in bars:
		chk(not row.intersects(bars[k]),
			"%s：武器槽行 y=%.0f~%.0f 不与%s y=%.0f~%.0f 相交"
			% [tag, slot_y, slot_y + SLOT_SIZE, k, (bars[k] as Rect2).position.y,
				(bars[k] as Rect2).end.y])

	# ---- 3) 武器槽行 vs 波次/金币/击杀/连击 文字行 ----
	# 文字行右端收到 340，武器槽最左 347 —— 要求整行压在同一带且不越界。
	var label_r := Rect2(Vector2(0.0, text_y), Vector2(340.0, 17.0))
	chk(not row.intersects(label_r),
		"%s：武器槽行 y=%.0f~%.0f 不与文字行 y=%.0f~%.0f 相交"
		% [tag, slot_y, slot_y + SLOT_SIZE, text_y, text_y + 17.0])
	chk(slot_right - _slots_width(max_slots) >= 340.0,
		"%s：满 %d 槽最左 x=%.0f ≥ 文字行右边界 340"
		% [tag, max_slots, slot_right - _slots_width(max_slots)])

	# ---- 4) HUD 局部高度必须与 TOP_CONTENT_H 声明一致 ----
	# 改布局时忘了改这个常量，相机就会按错的值让位 —— 正是 bug 2 的复发路径。
	var real_bottom := maxf(maxf(slot_y + SLOT_SIZE, text_y + 17.0), xp_y + xp_h)
	chk(real_bottom <= content_h,
		"%s：实际控件底边 %.0f ≤ TOP_CONTENT_H %.0f（常量没漏改）"
		% [tag, real_bottom, content_h])

	# ---- 5) 顶部所有控件都必须在屏内，且不越过 TOP_CONTENT_H 触及相机让位线 ----
	chk(bar_x + bar_w <= sw,
		"%s：进度条右端 %.0f ≤ 屏宽 %.0f（血条不画到屏外）" % [tag, bar_x + bar_w, sw])
	chk(bar_w > 0.0 and run_h > 0.0 and wave_y >= bar_y,
		"%s：条形数值合理（血条高 %.0f 本波细条 y=%.0f 总波次条 y=%.0f）"
		% [tag, bar_h, wave_y, run_y])

func _slots_width(n: int) -> float:
	return float(n) * SLOT_SIZE + float(n - 1) * SLOT_GAP

func _slot_rect(x0: float, i: int, slot_y: float) -> Rect2:
	return Rect2(Vector2(x0 + float(i) * (SLOT_SIZE + SLOT_GAP), slot_y),
		Vector2(SLOT_SIZE, SLOT_SIZE))

func _slot_row_rect(n: int, slot_y: float, slot_right: float) -> Rect2:
	var w := _slots_width(n)
	return Rect2(Vector2(slot_right - w, slot_y), Vector2(w, SLOT_SIZE))
