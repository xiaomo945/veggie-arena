extends Control

# HUD 右下角技能簇 + 手动攻击键（王者荣耀式布局）。
#
# 布局（王者荣耀式环绕，全部写死，绝不漂移）：
#   · 圆心 PIVOT 放"手动攻击键"——释放最常用的那个技能（skills.json 的 primary）
#   · 技能 1/2/3 绕圆心排在【正左 / 左上 / 正上】，锅气大按钮去左下
#   · 冲刺固定在扇面左上 (455,500) 竖屏，不压技能环、不进左下摇杆移动区
#
# 角度用屏幕坐标系（y 向下）：wok 135°=左下，技能 180/225/270°=从正左扫到正上，
# 等角距 45°（治旧版"间隔不一样太难看"）。技能槽不再是写死的 1 个 ——
# 武器/道具会【赠送】技能（core/SkillSlots.gd，最多 3 槽），槽位序列由
# Events.skill_slots_changed 广播驱动重建；序列没变就一个按钮都不动
# （重建会重置按钮上的冷却扇形，所以"变了才建"很重要）。
#
# ⚠️ 踩过的坑：以前是 `var sz = b.size` 再 add_child —— _ready 还没跑，size 是 (0,0)，
#    于是每个按钮都按"左上角对齐中心"摆，整体偏右下半个按钮。现在先入树再对中心。

const SkillButtonScript := preload("res://ui/HUD/SkillButton.gd")
const SkillSlots := preload("res://core/SkillSlots.gd")

# 圆心 / 弧半径 / 环绕角度 / 冲刺位 全部走 HudLayout（竖屏 540x900 / 横屏 960x540 双布局）。
# 按钮是"轴对齐方块"，斜向排布时不能只看圆心距 —— 必须让相邻两块的 |dx| 或 |dy|
# 大于两者半宽之和，否则边角会叠、一根手指落进两个按钮被重复触发（守卫见 test_button_layout.gd）。

var _btns: Array = []          # [{type, node}]（全部按钮，供 slot_rect 取矩形）
var _skill_btns: Array = []    # 只装技能按钮（槽位变化时整体重建的那一批）
var _skill_ids: Array = []     # 当前技能槽位的 id 序列（没变就不重建）
var _wok_btn = null
var _dash_btn = null
var _attack_btn = null         # 攻击键（圆心大按钮）：键盘 U 经 press_attack 触发

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# 键盘操作（autoload/Keyboard）经本组找按钮层：发信号 + 白环闪，零跨对象私有访问
	add_to_group("hud_buttons")
	# 技能槽位广播：买了带技能的武器/道具 → 多一个按钮；卖了 → 少一个
	Events.skill_slots_changed.connect(_on_slots_changed)
	relayout()
	# 初始槽位自己算一份：HUD._ready 早于 Game._ready（子节点先就绪），
	# 那时 SkillSystem 还没 setup；等它的广播来了会再对齐一次（同一序列不会重建）。
	var ce := Data.character(GameState.character)
	_rebuild_skills(SkillSlots.ids_of(SkillSlots.slots_of(ce, GameState.weapons,
		Data.weapons, GameState.upgrades.keys(), Data.upgrades, Data.skills)))

# 布局重排（横竖屏翻转 / 窗口缩放）：坐标全来自 HudLayout，整体重建最省事 ——
# 逐个挪会漏（按钮种类会随槽位变），重建和 _ready 走同一条码路。
# ⚠️ _skill_ids 先存档再清：_rebuild_skills 用"序列没变就不重建"防抖，清了才会重建。
func relayout(_land: bool = false) -> void:
	var ids := _skill_ids.duplicate()
	for b in _btns:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	_btns.clear()
	_skill_btns.clear()
	_skill_ids.clear()
	position = Vector2.ZERO
	size = HudLayout.design_size()
	for s in _slots():
		_add(s)
	_rebuild_skills(ids)
	# 底部安全区自己重放（HUD 不再代为转发）：翻转时 position 已归零，重放一次刚好
	apply_safe_area(HudLayout.bottom_shift())
	# 共享矩形（Keyboard 点按钮 / Joystick 避让都读 GameState 这两个）自刷
	GameState.wok_toss_rect = toss_rect()
	GameState.dash_rect = dash_rect()

# 固定槽（wok + 攻击键 + 冲刺）；技能槽不在这里 —— 序列由 SkillSystem 广播驱动。
func _slots() -> Array:
	var pivot := HudLayout.buttons_pivot()
	var out: Array = []
	for s in HudLayout.buttons_fan():
		if str(s.get("type", "")) != "wok":
			continue
		var a: float = deg_to_rad(float(s["deg"]))
		out.append({
			"type": "wok",
			"center": pivot + Vector2(cos(a), sin(a)) * HudLayout.buttons_arc_r(),
		})
	out.append({"type": "attack", "center": pivot})
	out.append({"type": "dash", "center": HudLayout.buttons_dash_center()})
	return out

# 扇面里技能槽的角度表（按顺序：槽 0 本命技放最顺手的 240°）
func _skill_slots() -> Array:
	var out: Array = []
	for s in HudLayout.buttons_fan():
		if str(s.get("type", "")) == "skill":
			out.append(s)
	return out

# 槽位序列变了才重建：queue_free 旧按钮 + 按新序列建。序列相同直接返回 ——
# 每帧重建会让按钮的冷却扇形不停重置（表现为"冷却转圈永远回不到满"）。
func _on_slots_changed(ids: Array) -> void:
	_rebuild_skills(ids)

func _rebuild_skills(ids: Array) -> void:
	if _skill_ids == ids:
		return
	_skill_ids = ids
	for b in _skill_btns:
		b.queue_free()
	_skill_btns.clear()
	var slots := _skill_slots()
	var pivot := HudLayout.buttons_pivot()
	var arc_r := HudLayout.buttons_arc_r()
	for i in ids.size():
		if i >= slots.size():
			break
		var a: float = deg_to_rad(float((slots[i] as Dictionary)["deg"]))
		_add({
			"type": "skill",
			"id": str(ids[i]),
			"center": pivot + Vector2(cos(a), sin(a)) * arc_r,
		})

func _add(s: Dictionary) -> void:
	var b = SkillButtonScript.new()
	b.btn_type = str(s.get("type", ""))
	# 槽位带 id（SkillSystem 广播的：角色本命技 + 武器/道具赠送技）就按上：
	# 不带的（wok/attack/dash 固定槽）留空，SkillButton 自己回落本命技。
	# ⚠️ 这行丢过：合并时被删，导致多个技能槽全部回落成同一个本命技，
	#    赠送技按钮放出来却放本命的招（tests/test_synergy.gd 的"不写死 id"就是防这个）。
	var sid: String = str(s.get("id", ""))
	if sid != "":
		b.skill_id = sid
	add_child(b)                                    # 先入树，_ready 里才定下 size
	b.position = (s["center"] as Vector2) - b.size * 0.5
	if b.btn_type == "wok":
		_wok_btn = b
	elif b.btn_type == "dash":
		_dash_btn = b
	elif b.btn_type == "attack":
		_attack_btn = b
	elif b.btn_type == "skill":
		_skill_btns.append(b)
	_btns.append({"type": b.btn_type, "node": b})

# ---- 对外接口（由 HUD.gd 调用）----

# 锅气充能数（HUD 转发；SkillButton 自己也已订阅信号，这里再保险地同步一次）
func set_charges(n: int) -> void:
	if _wok_btn != null:
		_wok_btn.set_charges(n)

# 锅气按钮矩形（共享给其它模块；本作摇杆已用固定移动区，这里主要供兼容）
func toss_rect() -> Rect2:
	if _wok_btn != null:
		return _wok_btn.get_global_rect()
	return Rect2()

func dash_rect() -> Rect2:
	if _dash_btn != null:
		return _dash_btn.get_global_rect()
	return Rect2()

# 预留：取第 n 个按钮的矩形
func slot_rect(index: int) -> Rect2:
	if index >= 0 and index < _btns.size():
		return (_btns[index]["node"] as Control).get_global_rect()
	return Rect2()

func tick(_delta: float) -> void:
	pass   # 各按钮自行绘制，无需统一脉动

# ---- 键盘操作入口（autoload/Keyboard 经 "hud_buttons" 组调用）----
# 只让按钮自己 _trigger（发 Events 信号 + 白环闪），不碰 SkillSlots/数据 ——
# 键盘与手指点按走完全同一条路径，冷却/充能/形态的账仍只在一处算。

# 第 i 个技能槽（0/1/2 = J/K/L）：槽位不够就静默忽略（赠送技没那么多）
func press_slot(i: int) -> void:
	if i < 0 or i >= _skill_btns.size():
		return
	(_skill_btns[i] as SkillButtonScript).press()

# 攻击键（U）：释放当前角色专属技能
func press_attack() -> void:
	if _attack_btn != null:
		_attack_btn.press()

# 冲刺键（空格）：有方向输入冲那边，没有就随机冲（见 Player._on_dash_requested）
func press_dash() -> void:
	if _dash_btn != null:
		_dash_btn.press()

# 竖屏安全区：底部按钮上移，避开全面屏手势条 / Home Indicator。
func apply_safe_area(bottom: float) -> void:
	position -= Vector2(0.0, bottom)
