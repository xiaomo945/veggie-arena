extends Node2D

# UI / 输入层自动化守卫（headless --scene 模式运行，此时 autoload 已注册）。
#
# 为什么必须有这一层：
#   本项目 1522 个单测全压在 core/ 纯逻辑上，但最近 8 次提交修的 bug
#   （触屏点不动 / 卡片偏移 / START 点不到 / 详情页全屏拦截 / 商店双卖）
#   100% 出在 UI 与输入层 —— 那一层当时【零测试】，所以 bug 永远修不完。
#   这里把那一类 bug 变成机器可判的断言。
#
# 三个守卫：
#   G1 开局流程：标题 START → 选武器页必须出现 → 确认 → 必须有敌人
#      （"选完角色没有选武器页 / 进游戏没怪"的永久回归测试）
#   G2 可达性：每个关键按钮的中心点，顶层命中必须是它自己（没被更高层的
#      可见遮罩压住）—— 复刻 Godot 的输入路由做真命中测试
#   G3 输入配置：emulate_mouse_from_touch 必须为 true（关了手机就点不动）
#
# ⚠️ 架构守卫 R3：本文件不得读写其他对象的私有字段（X._yyy）。
#    所有断言只走公开 API（visible / get_global_rect / pressed 信号 / text）。

var _pass := 0
var _fail := 0
var _failures: Array = []

# ---- 命中测试状态（顶层优先：先比 CanvasLayer.layer，再比绘制顺序）----
var _hit_layer := -1000000
var _hit_seq := -1
var _hit_node: Control = null
var _seq := 0

func chk(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  OK: " + msg)
	else:
		_fail += 1
		_failures.append(msg)
		print("  FAIL: " + msg)

func _ready() -> void:
	var m := Node2D.new()
	m.set_script(preload("res://ui/Screens/Main.gd"))
	add_child(m)
	await get_tree().process_frame
	_guard_input()
	# ⚠️ 必须 await：_guard_title 内部有 await（模拟点击后要等一帧）。
	# 不写 await 的话它会挂起并把控制权交回这里，下面这行 quit 会立刻把进程杀掉，
	# 后面的断言一条都不会跑（踩过一次，现象是"跑到一半静默退出"）。
	await _guard_title(m)
	get_tree().quit(1 if _fail > 0 else 0)

# ---- G3 输入配置 ----
# 回归背景：commit 536c872 修的就是它 —— 关掉后手机上所有点击失效。
func _guard_input() -> void:
	var on := bool(ProjectSettings.get_setting(
		"input_devices/pointing/emulate_mouse_from_touch", false))
	chk(on, "G3 emulate_mouse_from_touch=true（关了手机点不动）")

# ---- G1 开局流程 + G2 可达性 ----
func _guard_title(m: Node) -> void:
	var title := _find_script(m, "TitleScreen.gd")
	chk(title != null, "G1 标题页已构建")
	if title == null:
		return

	# G2：START 按钮必须可点（不被任何更高层的可见控件压住）
	var start := _find_button(m, I18n.t("title_start"))
	chk(start != null, "G2 找到 START 按钮")
	if start != null:
		chk(_reachable(m, start), "G2 START 按钮可点（未被遮挡）")
		chk(_on_screen(start), "G2 START 按钮在屏幕内")

	if start == null:
		return
	start.pressed.emit()
	await get_tree().process_frame

	# G1：选武器页必须出现（这条就是"选完角色直接进游戏"的回归测试）
	var picker := _find_script(m, "WeaponPicker.gd")
	chk(picker != null, "G1 选武器页节点存在")
	if picker == null:
		return
	chk(picker.is_visible_in_tree(),
		"G1 点 START 后选武器页必须可见（回归：不得跳过直接进游戏）")

	# G2：选武器页的确认 / 返回按钮可点
	var confirm := _find_button(m, I18n.t("pick_weapon_confirm"))
	chk(confirm != null and _reachable(m, confirm),
		"G2 选武器页确认按钮可点（未被遮挡）")
	var back := _find_button(m, I18n.t("pick_weapon_back"))
	chk(back != null and _reachable(m, back), "G2 选武器页返回按钮可点")

	if confirm == null:
		return
	confirm.pressed.emit()
	await get_tree().process_frame

	# G1：开局后必须真的刷出敌人（"进游戏没怪"的回归测试）
	chk(GameState.running, "G1 确认后 GameState.running=true（正式开跑）")
	var game: Node = m.get("game") as Node
	chk(game != null, "G1 取到 Game 协调器")
	if game != null:
		var n := int(game.alive_enemy_count())
		chk(n > 0, "G1 开局必须刷出敌人（实测同屏 %d 只）" % n)

# ---- 可达性：复刻 Godot 输入路由，找出某点最顶层的可交互控件 ----
# 判据：CanvasLayer.layer 大的在上；同层里后绘制的在上（前序 DFS 序号更大）。
# 最终命中的必须是【目标按钮本身或它的子节点】—— 否则说明被别的东西压住了。
func _reachable(root: Node, target: Control) -> bool:
	var r := target.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	var hit := _topmost_at(root, r.get_center())
	return hit == target or target.is_ancestor_of(hit)

func _on_screen(c: Control) -> bool:
	var vp := c.get_viewport_rect()
	return c.get_global_rect().intersects(vp)

func _topmost_at(root: Node, p: Vector2) -> Control:
	_hit_layer = -1000000
	_hit_seq = -1
	_hit_node = null
	_seq = 0
	_scan(root, 0, p)
	return _hit_node

func _scan(node: Node, layer: int, p: Vector2) -> void:
	_seq += 1
	var cur := layer
	if node is CanvasLayer:
		cur = (node as CanvasLayer).layer
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if c.get_global_rect().has_point(p):
				if cur > _hit_layer or (cur == _hit_layer and _seq > _hit_seq):
					_hit_layer = cur
					_hit_seq = _seq
					_hit_node = c
	for ch in node.get_children():
		_scan(ch, cur, p)

# ---- 按脚本 / 文案找节点（只走公开 API，不碰私有字段）----
func _find_script(root: Node, suffix: String) -> Node:
	var s: Script = root.get_script() as Script
	if s != null and str(s.resource_path).ends_with(suffix):
		return root
	for ch in root.get_children():
		var r := _find_script(ch, suffix)
		if r != null:
			return r
	return null

# 只认【可见】的按钮：设置页/数据页也有同文案的"返回"，不判可见性会撞上隐藏的那个
# （它不可见 → _reachable 恒 false → 假失败）。
func _find_button(root: Node, txt: String) -> Button:
	if root is Button and (root as Button).text == txt and (root as Button).is_visible_in_tree():
		return root as Button
	for ch in root.get_children():
		var r := _find_button(ch, txt)
		if r != null:
			return r
	return null
