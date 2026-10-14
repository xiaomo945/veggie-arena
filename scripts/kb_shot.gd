extends SceneTree

# 电脑版键盘操作 · 真运行时目检（headless 合成按键事件，跑完整链路）
# 用法：godot --headless --path . --script res://scripts/kb_shot.gd
#
# 与 tests/test_keyboard.gd（源码契约）互补：那个静态断言"文件里写了什么"，
# 本脚本合成真按键事件走一遍运行时 —— 信号真的发出、按钮真的被按、店真的开。
# 覆盖：WASD 走位（含斜向归一化）、J/K/L 技能、U 攻击、Space 冲刺（定向/随机）、
# 商店 J 确定 / K 锁定 / L 刷新 / U 关闭、波次超时自然开店、最后一波通关、
# 商店打开时战斗键层停业（不走位、不放技能）。
#
# ⚠️ 事件合成只调 Input.parse_input_event，绝不叠加 flush_buffered_events ——
#    两个一起调每个按键会被派发两次（scripts/probe_input.gd 实测，已删）。

# --script(SceneTree) 模式下 autoload 不自动注册：按 project.godot 的顺序手动挂。
# 顺序即依赖：Events 必须早于 Keyboard/Gamepad；Data 早于几乎所有模块。
const AUTOLOADS := {
	"Art": "res://autoload/Art.gd",
	"Data": "res://autoload/Data.gd",
	"Events": "res://autoload/Events.gd",
	"GameState": "res://autoload/GameState.gd",
	"Settings": "res://autoload/Settings.gd",
	"Steam": "res://autoload/Steam.gd",
	"SaveMgr": "res://autoload/SaveMgr.gd",
	"Sfx": "res://autoload/Sfx.gd",
	"Bgm": "res://autoload/Bgm.gd",
	"Keyboard": "res://autoload/Keyboard.gd",
	"Gamepad": "res://autoload/Gamepad.gd",
	"I18n": "res://autoload/I18n.gd",
	"HudLayout": "res://ui/HUD/HudLayout.gd",
	"ScreenMode": "res://ui/Screens/ScreenMode.gd",
	"Perf": "res://autoload/Perf.gd",
}

var _dirs: Array = []        # stick_dir_changed 收到的方向（按到达顺序）
var _released := 0           # stick_released 次数
var _dash_dirs: Array = []   # dash_started 的冲刺方向
var _skill_ids: Array = []   # skill_requested 的技能 id
var _wok := 0                # wok_toss_requested 次数
var _ff: Array = []          # fast_forward_toggled 的开/关值
var _shop_opened := false
var _shop_closed := false
var _won := false
var _dash_ready := false

var _p := 0
var _f := 0
var _lock_hits: Array = []    # 每张卡的 on_lock 是否被调用过（K 锁定派发验证）
var _orig_locks: Array = []   # 各卡原 on_lock 绑定（间谍调完要还原行为）

func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	var ev := root.get_node("Events")
	# ⚠️ --script 模式下主脚本编译时 autoload 全局标识还没注册，直接写 GameState.xxx
	#    会 "Identifier not found"（工程里其它脚本是运行时 load 的，没这个限制）。
	#    所以本文件一律用 root.get_node() 取节点，不碰 autoload 单例标识符。
	var gs: Node = root.get_node("GameState")
	var data: Node = root.get_node("Data")
	ev.stick_dir_changed.connect(func(d): _dirs.append(d))
	ev.stick_released.connect(func(): _released += 1)
	ev.dash_started.connect(func(_pos, d): _dash_dirs.append(d))
	ev.skill_requested.connect(func(id): _skill_ids.append(id))
	ev.wok_toss_requested.connect(func(): _wok += 1)
	ev.fast_forward_toggled.connect(func(on): _ff.append(on))
	ev.shop_opened.connect(func(): _shop_opened = true)
	ev.shop_closed.connect(func(): _shop_closed = true)
	ev.run_won.connect(func(): _won = true)
	ev.dash_state_changed.connect(func(_r, ready): _dash_ready = ready)

	var main: Node2D = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	ev.run_requested.emit()
	await process_frame
	await process_frame
	chk(main.player != null, "主场景里玩家在（键盘链路的前提）")
	var hud: Node = get_first_node_in_group("hud")
	chk(hud != null, "HUD 在场景里且已加入 hud 组")

	# ---- §1 WASD 走位：与触屏摇杆同一个信号，斜向要归一化 ----
	_tap(KEY_W, true); await process_frame
	_dir_is(Vector2(0, -1), "W = 向上")
	_tap(KEY_A, true); await process_frame
	_dir_is(Vector2(-0.70710678, -0.70710678), "W+A = 左上且归一化（斜不前冲更快）")
	_tap(KEY_D, true); await process_frame
	_dir_is(Vector2(0, -1), "W+A+D 左右抵消 = 上")
	_tap(KEY_D, false); await process_frame
	_dir_is(Vector2(-0.70710678, -0.70710678), "松开 D 后回到 W+A = 左上")
	_tap(KEY_W, false); await process_frame
	_dir_is(Vector2(-1, 0), "再松开 W 只剩 A = 左")
	_tap(KEY_A, false); await process_frame
	_dir_is(Vector2.ZERO, "全部松开 = 零向量")
	chk(_released >= 1, "归零时补发 stick_released（控制权交还）")

	# ---- §2 J / K / L / U：与手指点踩同一条 press() 路径 ----
	var addons: Array = hud.addon_buttons()
	chk(addons.size() == 3, "环绕技能键 3 个（顺序 = HudLayout.addon_slots）")
	chk(str(addons[0].btn_type) == "skill" and str(addons[1].btn_type) == "wok"
		and str(addons[2].btn_type) == "ff", "键位顺序 skill/wok/ff 对应 J/K/L")
	var atk = hud.attack_button()
	chk(atk != null, "攻击键在（对应 U）")

	_skill_ids.clear(); _wok = 0; _ff.clear()
	_tap(KEY_J, true); await process_frame; _tap(KEY_J, false); await process_frame
	chk(_skill_ids.size() >= 1 and str(_skill_ids[-1]) == str(addons[0].skill_id),
		"J → 技能1（skill_requested 带按钮自己的 skill_id）")
	_tap(KEY_K, true); await process_frame; _tap(KEY_K, false); await process_frame
	chk(_wok >= 1, "K → 颠勺（wok_toss_requested）")
	_tap(KEY_L, true); await process_frame; _tap(KEY_L, false); await process_frame
	chk(_ff.has(true), "L → 快进打开")
	# U = 攻击键：把它的 skill_id 临时换成探针 id，才能和 J 区分开
	var orig_id: String = str(atk.skill_id)
	atk.skill_id = "probe_attack"
	_skill_ids.clear()
	_tap(KEY_U, true); await process_frame; _tap(KEY_U, false); await process_frame
	chk(_skill_ids.size() >= 1 and str(_skill_ids[-1]) == "probe_attack",
		"U → 攻击键（skill_requested 带攻击键的 id）")
	atk.skill_id = orig_id

	# ---- §3 Space 冲刺：单独按 = 随机单位长方向；配方向键 = 该方向 ----
	gs.elapsed_in_wave = 0.0   # 别让波次计时在测试中途把店开出来
	_dash_dirs.clear()
	_tap(KEY_SPACE, true); await process_frame; _tap(KEY_SPACE, false); await process_frame
	chk(_dash_dirs.size() >= 1, "Space 触发冲刺（dash_started）")
	if _dash_dirs.size() > 0:
		var d0: Vector2 = _dash_dirs[-1]
		chk(absf(d0.length() - 1.0) < 0.001, "单独按 Space = 随机方向且是单位长")
	await _wait(func(): return _dash_ready, 900)
	chk(_dash_ready, "冲刺冷却结束（等不到 ready 说明冷却链路断了）")
	_dash_dirs.clear()
	_tap(KEY_W, true); await process_frame
	_tap(KEY_SPACE, true); await process_frame; _tap(KEY_SPACE, false); await process_frame
	chk(_dash_dirs.size() >= 1 and (_dash_dirs[-1] as Vector2).is_equal_approx(Vector2(0, -1)),
		"按着 W 再按 Space = 向上冲刺")
	_tap(KEY_W, false); await process_frame

	# ---- §4 商店：波次超时自然开店；J 确定 / K 锁定 / L 刷新 / U 关闭 ----
	gs.weapons = []          # 清空槽位：保证光标卡买得下（不会进满槽退款分支）
	gs.add_gold(5000)
	gs.elapsed_in_wave = 9999.0
	await _wait(func(): return _shop_opened, 240)
	chk(_shop_opened, "波次时长超时 → WaveDirector 自然开补给站")
	var shop := _find_shop(root)
	chk(shop != null, "找到 Shop 节点（靠 panel() 公开访问器）")
	var panel = shop.panel()
	chk(panel.cards.size() >= 2, "卡片数组至少 2 张（光标移动才测得出来）")
	# 间谍 Callable：on_click/on_lock 是公开字段，包一层记录再调原绑定（R3 安全）。
	# ⚠️ 本模式合成一次按键会派发两次（parse_input_event 立即派发 + 缓冲派发，真机不会），
	#    所以光标断言只说"换了一张卡"，不说死具体下标。
	var c0 = panel.cards[0]
	var hit_click := [false]
	var o_c0: Callable = c0.on_click
	c0.on_click = func(): hit_click[0] = true; o_c0.call()
	_lock_hits.clear(); _orig_locks.clear()
	for i in panel.cards.size():
		_lock_hits.append(false)
		_orig_locks.append(panel.cards[i].on_lock)
		panel.cards[i].on_lock = _lock_spy(i)

	# 商店打开 = 战斗键层停业。用 A 而不是 W：W 在店里是光标键，会先把光标移走。
	_dirs.clear(); _skill_ids.clear()
	_tap(KEY_A, true); await process_frame
	chk(_dirs.is_empty(), "商店打开时 A 不触发走位（战斗键层停业）")
	_tap(KEY_A, false); await process_frame

	var gold0: int = gs.gold
	_tap(KEY_J, true); await process_frame; _tap(KEY_J, false); await process_frame
	chk(hit_click[0], "J = 确定 → 买下光标所在卡（on_click，与手指同路径）")
	chk(gs.gold < gold0, "J 真的买了：金币扣掉")
	chk(_skill_ids.is_empty(), "商店里 J 不触发战斗技能（两层不混）")

	# K = 锁定：光标在卡0，先锁卡0
	_tap(KEY_K, true); await process_frame; _tap(KEY_K, false); await process_frame
	chk(_lock_hits[0], "K = 锁定 → 光标所在卡（卡0）的 on_lock")
	# S 移光标，再 K：必须锁到另一张（光标真的动了）
	_tap(KEY_S, true); await process_frame; _tap(KEY_S, false); await process_frame
	_lock_hits[0] = false
	_tap(KEY_K, true); await process_frame; _tap(KEY_K, false); await process_frame
	var moved_locked := false
	for i in _lock_hits.size():
		if i != 0 and _lock_hits[i]:
			moved_locked = true
	chk(moved_locked and not _lock_hits[0], "S 移光标后 K 锁的是另一张卡（光标移动生效）")

	var text0: String = str(panel.reroll_btn.text)
	var gold1: int = gs.gold
	_tap(KEY_L, true); await process_frame; _tap(KEY_L, false); await process_frame
	chk(str(panel.reroll_btn.text) != text0, "L = 刷新 → 刷新价递增（_reroll_times 变了）")
	chk(gs.gold < gold1, "L 真的刷了：金币扣掉")

	_tap(KEY_U, true); await process_frame; _tap(KEY_U, false); await process_frame
	await _wait(func(): return _shop_closed, 60)
	chk(_shop_closed, "U = 关店（next_btn，与手指点下一波同路径）")
	chk(int(gs.wave) == 2, "关店后进入第 2 波")
	_dirs.clear()
	_tap(KEY_W, true); await process_frame
	chk(_dirs.size() >= 1, "关店后战斗键层恢复接管")
	_tap(KEY_W, false); await process_frame

	# ---- §5 最后一波超时 = 通关 ----
	var total := int(data.wave_cfg().get("total", 20))
	gs.wave = total
	gs.elapsed_in_wave = 9999.0
	await _wait(func(): return _won, 240)
	chk(_won, "最后一波超时 → 通关（run_won）")
	chk(not gs.running, "通关后停跑（running=false）")

	print("KB_SHOT 计数 dirs=%d skill=%d wok=%d ff=%d dash=%d" % [
		_dirs.size(), _skill_ids.size(), _wok, _ff.size(), _dash_dirs.size()])
	print("KB_SHOT 通过 %d 项，失败 %d 项" % [_p, _f])
	quit(1 if _f > 0 else 0)

# ---- 工具 ----

# 合成一次按键（只 down/up 一拍，不复读 echo）。只合成不 flush：
# flush_buffered_events 会让同一按键被派发两次，断言全乱。
func _tap(keycode: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = down
	Input.parse_input_event(e)

func _dir_is(want: Vector2, msg: String) -> void:
	var got: Vector2 = _dirs[-1] if _dirs.size() > 0 else Vector2(-99, -99)
	chk(_dirs.size() > 0 and got.is_equal_approx(want), "%s（实收 %s）" % [msg, str(got)])

# 等条件成立（每帧一次），超时返回条件终值
func _wait(cond: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if cond.call():
			return
		await process_frame

# 递归找第一个有 panel() 方法的节点 = Shop（公开访问器，不摸私有字段）
func _find_shop(n: Node) -> Node:
	if n != null and n.has_method("panel"):
		return n
	for c in n.get_children():
		var r: Node = _find_shop(c)
		if r != null:
			return r
	return null

# 第 idx 张卡的锁定间谍：记录"被调用过"，再调原绑定（行为不变，只旁路记录）
func _lock_spy(idx: int) -> Callable:
	return func(): _lock_hits[idx] = true; _orig_locks[idx].call()

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
		print("  ok   " + msg)
	else:
		_f += 1
		print("  FAIL " + msg)
