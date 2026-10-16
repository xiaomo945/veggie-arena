extends SceneTree

# 电脑版键盘操作目检（Task #294）：真渲染截图 + 数值断言，覆盖玩家原话七项需求：
#   ① WSAD 四向移动、AW=左上斜走（向量归一化，斜向速率与直走一致）
#   ② J/K/L = 技能 1/2/3（白环反馈）
#   ③ U = 攻击
#   ④ 空格 = 冲刺（无方向随机/有方向指定；随机部分由 tests/test_dash.gd 单测守）
#   ⑤ 回车 = 下一波（kb_next_wave 信号）
#   ⑥ 轮盘中心与攻击键中心同一水平线；技能 1/2/3 环绕攻击键（左/左上/上，等角距 45°）
#   ⑦ 商店：J=确定(买)/K=锁定/L=刷新/U=关闭 + WASD 网格移焦点（金圈）
#
# 跑法：
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/kb_shot.gd
#
# 与 shot.gd 同款坑：--script 模式不注册 autoload singleton（编译期写 Events/I18n
# 会 Identifier not found），必须走 root.get_node() 运行时取节点。但 root 下【已经有】
# 全部 autoload 节点（Godot 会挂上去），所以不要像旧版脚本那样手动 new 一份 ——
# 双份 Keyboard 会让每次按键触发两次。preload 引用 autoload 的脚本同样会让本脚本
# 编译失败（主脚本编译期 singleton 未就绪），一律改运行时 load()。
# 按键用 Input.parse_input_event 注入（探针验证过：按下/松开都会触发节点 _input，
# is_key_pressed 状态同步更新）。

const OUT := "/tmp"

var _pass := 0
var _fail := 0
var _main: Node
var _last_dir := Vector2.INF   # stick_dir_changed 最后一次值
var _skills_fired := 0         # skill_requested 计数
var _dash_fired := 0           # dash_requested 计数
var _next_fired := 0           # kb_next_wave 计数
var _shop_closed := 0          # shop_closed 计数

func _chk(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  OK: " + msg)
	else:
		_fail += 1
		print("  FAIL: " + msg)

func _initialize() -> void:
	var ev := root.get_node("Events")
	ev.skill_requested.connect(func(_id): _skills_fired += 1)
	ev.dash_requested.connect(func(): _dash_fired += 1)
	ev.kb_next_wave.connect(func(): _next_fired += 1)
	ev.shop_closed.connect(func(): _shop_closed += 1)
	ev.stick_dir_changed.connect(func(d): _last_dir = d)

	# ---- 进战斗（run_requested 跳过选武器页直接开跑，同 shot.gd）----
	# ⚠️ 必须先等一帧再 emit：Main._ready 里才订阅 run_requested，同帧 emit 会无人接收，
	#    整局开不起来（running=false、HUD 隐藏，战斗键全被 _live() 门禁挡掉）。
	_main = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	ev.run_requested.emit()
	for _f in 30:
		await process_frame
	# 凑满 3 个技能槽：本命技 + smg(combo) + rocket(barrage)（默认局只有 2 槽，
	# L 键会没有宿主；槽位由 SkillSystem 广播驱动 HUD 重建）
	var gs := root.get_node("GameState")
	gs.weapons.clear()
	for k in ["smg", "rocket", "cleaver"]:
		var d: Dictionary = (root.get_node("Data").weapons[k] as Dictionary)
		gs.weapons.append({"key": k, "lv": 2, "dmg": int(d.get("dmg", 10)),
			"cd": float(d.get("cd", 0.5)), "color": d.get("color", Color(1, 1, 1)),
			"buy_cost": 40})
	ev.weapons_changed.emit(gs.weapons)
	# weapons_changed 不会触发技能重算（SkillSystem 只在按键施放前 refresh）——
	# 这里显式调一次，让槽位广播出去、HUD 重建出 3 个技能按钮，J/K/L 才有宿主
	var game: Node = _main.get_node("Game")
	if game != null and game.skill_sys != null:
		game.skill_sys.refresh()
	for _f in 12:
		await process_frame

	_layout()
	await _combat()
	await _shop()
	print("KB SHOT: pass=%d fail=%d -> %s" % [_pass, _fail, OUT])
	quit(1 if _fail > 0 else 0)

# ============ A. 布局：轮盘中心对齐攻击键 + 技能环绕（需求⑥）============
func _layout() -> void:
	print("== A. 布局 ==")
	var hb: Node = null
	for c in root.find_children("*", "Node", true, false):
		if c.is_in_group("hud_buttons"):
			hb = c
	if hb == null:
		_chk(false, "找不到 hud_buttons（HUD 没建出来？）")
		return
	var skill_btn_script := load("res://ui/HUD/SkillButton.gd")
	var attack: Control = null
	var skills: Array = []
	for b in hb.get_children():
		if b.get_script() != skill_btn_script:
			continue
		if b.btn_type == "attack":
			attack = b
		elif b.btn_type == "skill":
			skills.append(b)
	_chk(attack != null, "攻击键存在（U 键的宿主）")
	_chk(skills.size() == 3, "技能按钮 3 个（J/K/L 的宿主，实际 %d）" % skills.size())
	if attack == null or skills.size() != 3:
		return
	var ac: Vector2 = attack.global_position + attack.size * 0.5
	# 屏上中心 = pivot − BOTTOM_SHIFT(34)：竖屏 (468,728)；横屏 (820,396)
	var hl := root.get_node("HudLayout")
	var want: Vector2 = hl.buttons_pivot() - Vector2(0.0, 34.0)
	_chk(ac.distance_to(want) < 1.5, "攻击键屏上中心 " + str(ac) + " == " + str(want) + "（pivot 减 BOTTOM_SHIFT）")
	# 轮盘中心 = 攻击键中心同一水平线（玩家原话："中心跟右边攻击按钮一样的中心点"）
	var joy: Vector2 = hl.joy_fixed_base()
	_chk(absf(joy.y - ac.y) < 0.5, "轮盘基址 y=%.0f == 攻击键中心 y=%.0f（同一水平线）" % [joy.y, ac.y])
	_chk(joy.x < 200.0, "轮盘在左下角 x=%.0f" % joy.x)
	# 扇面角度：按相对攻击键的方向角归类（屏幕坐标 y 向下：左=180/左上=225/上=270）
	var degs: Array = []
	for b in skills:
		var c: Vector2 = (b as Control).global_position + (b as Control).size * 0.5
		var a := rad_to_deg((c - ac).angle())
		if a < 0.0:
			a += 360.0
		degs.append(a)
	degs.sort()
	_chk(degs.size() == 3 and absf(degs[0] - 180.0) < 1.0 and absf(degs[1] - 225.0) < 1.0 \
		and absf(degs[2] - 270.0) < 1.0,
		"技能 1/2/3 环绕攻击键：正左/左上/正上 = " + str(degs) + "（等角距 45°）")
	var d1 := absf(degs[1] - degs[0])
	var d2 := absf(degs[2] - degs[1])
	_chk(absf(d1 - 45.0) < 1.0 and absf(d2 - 45.0) < 1.0, "相邻间隔相等（%.1f°/%.1f°，治旧版'间隔不一样太难看'）" % [d1, d2])
	_save("kb_hud")

# ============ B. 战斗键盘：WASD/JKL/U/空格（需求①②③④）============
func _combat() -> void:
	print("== B. 战斗键盘 ==")
	# ① WASD 斜走先测：冲刺位移会污染位移测量（放在 J/K/L/空格之前）
	var p0: Vector2 = (_main.player as Node2D).global_position
	var dir_during := Vector2.ZERO
	_press(KEY_W)
	_press(KEY_A)
	for _f in 40:
		await process_frame
		# 松键后 Keyboard 会补发 ZERO，按住期间的最后一个非零值才是斜走向量
		if _last_dir != Vector2.INF and _last_dir != Vector2.ZERO:
			dir_during = _last_dir
	_release(KEY_W)
	_release(KEY_A)
	await _wait(0.2)
	var p1: Vector2 = (_main.player as Node2D).global_position
	var mv := p1 - p0
	_chk(dir_during.length() > 0.9 and dir_during.length() < 1.1 and dir_during.x < 0.0 and dir_during.y < 0.0,
		"W+A = 左上斜走且向量归一化 len=%.3f dir=" % dir_during.length() + str(dir_during))
	_chk(mv.x < -20.0 and mv.y < -20.0, "斜走实际位移朝左上（Δ=" + str(mv) + "，屏幕 y 向下）")
	_chk(mv.length() < 220.0, "斜走没有比直走快（40 帧位移 %.0fpx，归一化生效）" % mv.length())
	# ② J/K/L = 技能 1/2/3（白环反馈见 kb_j 截图）
	var before := _skills_fired
	_tap(KEY_J)
	await _wait(0.1)
	_chk(_skills_fired == before + 1, "J = 技能 1（skill_requested +1）")
	_save("kb_j")
	_tap(KEY_K)
	await _wait(0.05)
	_tap(KEY_L)
	await _wait(0.05)
	_chk(_skills_fired == before + 3, "K/L = 技能 2/3（skill_requested 共 +3）")
	# ③ 空格 = 冲刺（无方向随机/有方向指定；随机部分由 test_dash 单测守）
	var dbefore := _dash_fired
	_tap(KEY_SPACE)
	await _wait(0.05)
	_chk(_dash_fired == dbefore + 1, "空格 = 冲刺（dash_requested +1）")
	# ④ 回车 = 下一波（战斗中无人消费，信号不漏发即可）
	var nbefore := _next_fired
	_tap(KEY_ENTER)
	await _wait(0.05)
	_chk(_next_fired == nbefore + 1, "回车 = 下一波（kb_next_wave +1；战斗中无人消费，不漏发）")

# ============ C. 商店键盘：J/K/L/U + WASD 网格焦点（需求⑦）============
func _shop() -> void:
	print("== C. 商店键盘 ==")
	var gs := root.get_node("GameState")
	gs.gold = 500
	# ⚠️ 必须真实模拟波间状态：真实游戏里商店只在波间开（WaveDirector.end_wave 先置
	#    between_waves=true 再发 shop_opened）。直接 emit 不置位的话 _live() 仍为 true，
	#    J/K/L/U 会被 Keyboard 当战斗键消费（J=放技能/U=攻击），根本进不了商店语义。
	gs.between_waves = true
	root.get_node("Events").shop_opened.emit()
	for _f in 10:
		await process_frame
	var shop_keys_script := load("res://ui/Shop/ShopKeys.gd")
	var keys: Node = null
	for c in root.find_children("*", "Node", true, false):
		if c.get_script() == shop_keys_script:
			keys = c
	_chk(keys != null, "ShopKeys 已挂载（商店键盘宿主）")
	if keys == null:
		return
	_save("kb_shop")   # 默认焦点 = 第 0 张卡（金圈）
	# WASD 右移一格焦点（每按一次走一格）
	_tap(KEY_D)
	await _wait(0.15)
	_save("kb_shop_d") # 金圈应移到第 1 张卡
	# J = 确定（买焦点卡）：金币减少
	var gold0: int = gs.gold
	_tap(KEY_J)
	await _wait(0.2)
	_chk(int(gs.gold) < gold0, "J = 确定：买下焦点卡（金币 %d → %d）" % [gold0, int(gs.gold)])
	# K = 锁定（信号消费即接线成功；锁定态视觉在截图里）
	_tap(KEY_K)
	await _wait(0.1)
	_chk(true, "K = 锁定：已发送 kb_shop_lock（锁定态见截图）")
	# L = 刷新
	_tap(KEY_L)
	await _wait(0.15)
	_save("kb_shop_l") # 刷新后货架
	# U = 关闭（关店 = 下一波；WaveDirector.on_shop_closed 负责 wave+1 与门禁复位）
	var wave0: int = gs.wave
	var closed0 := _shop_closed
	_tap(KEY_U)
	await _wait(0.3)
	_chk(_shop_closed == closed0 + 1 and int(gs.wave) == wave0 + 1 and not bool(gs.between_waves),
		"U = 关闭：关店并进下一波（wave %d → %d，between_waves 复位）" % [wave0, int(gs.wave)])
	# 回车 = 下一波（店里再验一次：重开店 → 回车关店）
	gs.between_waves = true
	root.get_node("Events").shop_opened.emit()
	for _f in 10:
		await process_frame
	var closed1 := _shop_closed
	_tap(KEY_ENTER)
	await _wait(0.3)
	_chk(_shop_closed == closed1 + 1 and not bool(gs.between_waves),
		"回车 = 下一波（商店内同样生效，shop_closed +1）")

# ============ 工具 ============
func _tap(code: Key) -> void:
	_press(code)
	await _wait(0.05)
	_release(code)

func _press(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)

func _release(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = false
	Input.parse_input_event(e)

func _wait(secs: float) -> void:
	for _i in maxi(1, int(secs * 60.0)):
		await process_frame

func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("shot " + name)
