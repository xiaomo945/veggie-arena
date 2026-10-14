extends Control

# HUD 右下角技能簇 + 手动攻击键（王者荣耀式布局）。
#
# 布局（全部来自 HudLayout，绝不各写一套）：
#   · 圆心 = attack_button_center() 放"手动攻击键"——释放最常用的技能（skills.json 的 primary）；
#     它与左下摇杆底盘水平镜像、垂直方向回补底部安全区，两个大拇拇指到屏幕边等距。
#   · 三个技能键等角距（45°）环绕圆心：左 / 左上 / 上，与键盘 J/K/L（技能 1/2/3）一一对应。
#   · 冲刺挪到扇面外（上方），既不压技能环，也不进左下摇杆的移动区。
#
# ⚠️ 踩过的坑：以前是 `var sz = b.size` 再 add_child —— _ready 还没跑，size 是 (0,0)，
#    于是每个按钮都按"左上角对齐中心"摆，整体偏右下半个按钮。现在先入树再对中心。

const SkillButtonScript := preload("res://ui/HUD/SkillButton.gd")

# 圆心 / 弧半径 / 环绕角度 / 冲刺位 全部走 HudLayout（竖屏 540x900 / 横屏 960x540 双布局）。
# 按钮是"轴对齐方块"，斜向排布时不能只看圆心距 —— 必须让相邻两块的 |dx| 或 |dy|
# 大于两者半宽之和，否则边角会叠、一根手指落进两个按钮被重复触发（守卫见 test_button_layout.gd）。

var _btns: Array = []          # [{type, node}]
var _wok_btn = null
var _dash_btn = null
var _attack_btn = null
var _addons: Array = []        # 环绕技能键，顺序即键盘 J/K/L（技能 1/2/3）

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = HudLayout.design_size()
	for s in _slots():
		_add(s)

# 圆心 + 半径 + 角度 全部取自 HudLayout；addon_slots 的顺序就是键盘 J/K/L 的顺序
func _slots() -> Array:
	var pivot := HudLayout.attack_button_center()
	var arc_r := HudLayout.addon_arc_r()
	var out: Array = []
	for s in HudLayout.addon_slots():
		var a: float = deg_to_rad(float(s["deg"]))
		out.append({
			"type": s["type"],
			"center": pivot + Vector2(cos(a), sin(a)) * arc_r,
			"kb": true,       # 环绕技能键：键盘 J/K/L 按下标取（顺序来自 addon_slots）
		})
	out.append({"type": "attack", "center": pivot})
	out.append({"type": "dash", "center": HudLayout.buttons_dash_center()})
	return out

func _add(s: Dictionary) -> void:
	var b = SkillButtonScript.new()
	b.btn_type = str(s.get("type", ""))
	add_child(b)                                    # 先入树，_ready 里才定下 size
	b.position = (s["center"] as Vector2) - b.size * 0.5
	if b.btn_type == "wok":
		_wok_btn = b
	elif b.btn_type == "dash":
		_dash_btn = b
	elif b.btn_type == "attack":
		_attack_btn = b
	if bool(s.get("kb", false)):
		_addons.append(b)
	_btns.append({"type": b.btn_type, "node": b})

# ---- 键盘入口（autoload/Keyboard 通过 HUD 组拿到这里）----

# 环绕技能键，顺序即 J/K/L。节点上有公开方法 press()（与手指点踩同一条路径）
func addon_buttons() -> Array:
	return _addons

# 手动攻击键（对应键盘 U）
func attack_button():
	return _attack_btn

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

# 竖屏安全区：底部按钮上移，避开全面屏手势条 / Home Indicator。
func apply_safe_area(bottom: float) -> void:
	position -= Vector2(0.0, bottom)
