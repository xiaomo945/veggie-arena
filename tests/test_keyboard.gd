extends RefCounted

# 键盘操作层（电脑版）契约测试。
#
# 用户诉求："WASD 分别代表上下左右，还要能斜着走（W+A 就是左上）；右边技能也要有键盘
# 操作，JKL 分别代表 123 技能；U 代表攻击；冲刺不配合方向键单独按就随机冲一个方向，
# 配合方向键就冲指定方向。"
#
# 为什么读源码而不实例化：--script 测试模式不注册 autoload，Keyboard.gd 引用
# GameState / Events / Gamepad 会直接编译失败（tests/SrcParse.gd 文件头已说明）。
# 真正"按下去会发生什么"由 scripts/kb_shot.gd 跑真实主场景验证。
#
# 断言分三类：① 键位映射齐全；② 复用现有输入管线（不复制业务流程）；
# ③ 三层输入源隔离（触屏 / 手柄优先 / 键盘互不打架）。

const SP := preload("res://tests/SrcParse.gd")

const KB_SRC := "res://autoload/Keyboard.gd"
const PAD_SRC := "res://autoload/Gamepad.gd"
const HUD_SRC := "res://ui/HUD/HUD.gd"
const BTN_SRC := "res://ui/HUD/HudButtons.gd"
const SKILL_SRC := "res://ui/HUD/SkillButton.gd"
const PROJ := "res://project.godot"

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

func run(_arg = null) -> Dictionary:
	var src := SP.read(KB_SRC)
	chk(src.length() > 0, "能读到 Keyboard.gd 源码（读不到下面全是假通过）")
	chk(SP.read(PAD_SRC).length() > 0, "能读到 Gamepad.gd 源码")
	chk(SP.read(HUD_SRC).length() > 0, "能读到 HUD.gd 源码")
	if src.is_empty():
		return {"pass": _p, "fail": _f, "failures": _failures}

	# ---- ① 键位映射：WASD + 方向键 ----
	for k in ["KEY_W", "KEY_A", "KEY_S", "KEY_D"]:
		chk(src.contains(k), "%s 已映射（上/左/下/右）" % k)
	chk(src.contains("KEY_UP") and src.contains("KEY_DOWN")
		and src.contains("KEY_LEFT") and src.contains("KEY_RIGHT"),
		"方向键 ↑↓←→ 与 WASD 等价映射（双份操作习惯都照顾）")
	var dir_fn := SP.func_body(src, "func _dir()")
	chk(dir_fn.contains("normalized()"), "斜向移动归一化（W+A = 左上，速度不比单方向快）")
	chk(src.contains("Events.stick_dir_changed.emit"), "移动走 stick_dir_changed（与摇杆/手柄同一信号）")
	chk(src.contains("Events.stick_released.emit"), "松开发 stick_released（交还控制权）")

	# ---- ① 键位映射：J/K/L = 技能 1/2/3，U = 攻击 ----
	chk(src.contains("KEY_J") and src.contains("KEY_K") and src.contains("KEY_L"),
		"J / K / L 已映射（三个环绕技能键）")
	chk(src.contains("KEY_U"), "U 已映射（攻击键）")
	chk(src.contains("_press_addon(0)") and src.contains("_press_addon(1)")
		and src.contains("_press_addon(2)"),
		"J/K/L 按下标 0/1/2 取环绕技能键（顺序 = 左/左上/上，见 HudLayout.addon_slots）")
	chk(src.contains("_press_attack()"), "U 走攻击键入口（attack_button）")

	# ---- ① 冲刺：Space + Shift，方向 = 当前按键状态 ----
	chk(src.contains("KEY_SPACE"), "Space 映射冲刺")
	chk(src.contains("Events.kb_dash_requested.emit"), "冲刺走 kb_dash_requested（Player 执行）")
	chk(src.contains("kb_dash_requested.emit(_dir()"), "冲刺方向取当前按键状态（配合方向键 = 冲刺该方向）")

	# ---- ② 复用现有输入管线：技能/攻击必须走按钮 press()，不能自己 emit ----
	chk(src.contains("addon_buttons()"), "J/K/L 从 HUD.addon_buttons() 取按钮（与触屏同一按钮）")
	chk(src.contains("attack_button()"), "U 从 HUD.attack_button() 取按钮")
	chk(src.contains("b.press()"), "技能/攻击最终调用按钮 press()（冷却/信号/重绘只有一份实现）")
	chk(src.contains("get_first_node_in_group"), "通过 hud 组拿 HUD（R3：不跨对象摸私有字段）")
	chk(src.contains("has_method"), "动态派发前先 has_method（HUD 未就绪时不炸）")

	# ---- ③ 三层输入源隔离 ----
	chk(src.contains("Gamepad.was_pressed()"), "手柄有活动时键盘整体让位（掌根压键盘不双触发）")
	chk(src.contains("GameState.running and not GameState.paused"),
		"只在运行中且未暂停时接管（标题/暂停/死亡/通关页不响应）")
	chk(src.contains("k.echo"), "过滤长按自动重复（echo），按一下只触发一次")
	chk(src.contains("NOTIFICATION_APPLICATION_FOCUS_OUT"),
		"失焦时清键态（Alt-Tab 回来不会一直狂奔）")
	# 商店暂停不置 GameState.paused（那是暂停菜单的旗），战斗层必须自己盯开关店信号
	chk(src.contains("Events.shop_opened.connect") and src.contains("Events.shop_closed.connect"),
		"Keyboard 自己监听 shop_opened/shop_closed（商店暂停不进 GameState.paused）")
	chk(src.contains("_on_shop_opened") and src.contains("_release_all"),
		"进店即松开全部方向键（否则出店后 W 卡在按下态，一路狂奔）")
	# 商店键不进这一层：Enter / 确认 / 锁定 / 刷新归 ShopKeys（两层天然互斥）
	chk(not src.contains("KEY_ENTER"), "战斗层不碰 Enter（下一波归商店层，职责不混）")

	# ---- 接线：HUD / HudButtons / SkillButton 三个公开入口都要在 ----
	var hud := SP.read(HUD_SRC)
	var btns := SP.read(BTN_SRC)
	var skill := SP.read(SKILL_SRC)
	chk(hud.contains("func addon_buttons()") and hud.contains("func attack_button()"),
		"HUD.gd 有 addon_buttons() / attack_button() 转发访问器")
	chk(btns.contains("func addon_buttons()"), "HudButtons.gd 暴露 addon_buttons()")
	chk(btns.contains("func attack_button()"), "HudButtons.gd 暴露 attack_button()")
	chk(skill.contains("func press()"), "SkillButton.gd 有 press() 键盘入口（与 _press 同路径）")
	chk(skill.contains("const ADDON_SIZE"), "三个环绕键统一尺寸 ADDON_SIZE（间隔一致才好看）")

	# ---- autoload 注册：project.godot / arch_guard / check.sh 三处名单一致 ----
	var proj := SP.read(PROJ)
	chk(proj.contains('Keyboard="*res://autoload/Keyboard.gd"'), "project.godot 注册 Keyboard autoload")
	var guard := SP.read("res://scripts/arch_guard.py")
	chk(guard.contains('"Keyboard"'), "arch_guard.py 的 AUTOLOADS 名单含 Keyboard（R2 检查不误报）")
	var chk_sh := SP.read("res://scripts/check.sh")
	chk(chk_sh.contains("Keyboard"), "check.sh 的语法检查跳过名单含 Keyboard（否则误报语法错误）")

	# ---- 手柄让位判据存在 ----
	var pad := SP.read(PAD_SRC)
	chk(pad.contains("func was_pressed()"), "Gamepad.was_pressed() 存在（键盘层让位判据）")

	# ---- ④ 商店键盘层（ShopKeys.gd，电脑版店里操作）----
	# 用户诉求："J 在商店代表确定，K 代表锁定，L 代表刷新，U 代表攻击和商店的关闭，
	# 回车键代表下一波。" 店里这套键与战斗完全不同，单独一个文件、由开关店信号驱动。
	var shop := SP.read("res://ui/Shop/ShopKeys.gd")
	chk(shop.length() > 0, "能读到 ShopKeys.gd 源码")
	var shop_src := SP.read("res://ui/Shop/Shop.gd")
	chk(shop_src.contains('preload("res://ui/Shop/ShopKeys.gd")'),
		"Shop.gd 把键盘层挂成自己的子节点")
	chk(shop_src.contains("func panel()"), "Shop.gd 有 panel() 公开访问器（R3：键盘层不摸 _panel）")
	chk(shop.contains('Events.shop_opened.connect') and shop.contains('Events.shop_closed.connect'),
		"ShopKeys 由开关店信号驱动（关店后键自动失效）")
	chk(shop.contains("_card_callable(\"on_click\")"), "J = 确定 → 走卡片 on_click（与手指购买同一条路）")
	chk(shop.contains("_card_callable(\"on_lock\""), "K = 锁定 → 走卡片 on_lock")
	chk(shop.contains("reroll_btn"), "L = 刷新 → 按 reroll_btn（整店刷新）")
	chk(shop.contains("next_btn"), "U / Enter = 下一波 → 按 next_btn（关店）")
	chk(shop.contains("KEY_ENTER") and shop.contains("KEY_KP_ENTER"), "Enter（含小键盘）映射下一波")
	chk(shop.contains("KEY_W") and shop.contains("KEY_S")
		and shop.contains("KEY_UP") and shop.contains("KEY_DOWN"), "W/S/↑/↓ 在卡片间移动光标")
	chk(shop.contains("visible"), "光标只在可见卡片间移动（卡少时不落到隐藏卡上）")
	chk(not shop.contains("KEY_J") or shop.contains("on_click"), "商店层 J 语义 = 确定（不与战斗层混）")

	return {"pass": _p, "fail": _f, "failures": _failures}
