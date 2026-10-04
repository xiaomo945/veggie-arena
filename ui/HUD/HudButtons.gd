extends Control

# HUD 右下角技能簇 + 手动攻击键。
#
# 布局（全部写死，绝不漂移）：
#   · 圆心 PIVOT 放"手动攻击键"——释放最常用的那个技能（skills.json 的 primary）
#   · 三个技能（锅气爆炸 / 冰镇 / 毒雾）绕圆心排成半圆扇面，固定在右下角
#   · 冲刺挪到扇面外（右上侧），既不压技能环，也不进左下摇杆的移动区
#
# 角度用屏幕坐标系（y 向下）：150°=左下、195°=左、240°=左上，
# 三档正好扫出绕着右下角的半圆扇面，右手拇指一划就能从最常用的技能扫到大招。
#
# ⚠️ 踩过的坑：以前是 `var sz = b.size` 再 add_child —— _ready 还没跑，size 是 (0,0)，
#    于是每个按钮都按"左上角对齐中心"摆，整体偏右下半个按钮。现在先入树再对中心。

const SkillButtonScript := preload("res://ui/HUD/SkillButton.gd")

# 圆心 / 半径 / 扇面角度 / 冲刺位 全部走 HudLayout（竖屏 540x900 / 横屏 960x540 双布局）。
# 按钮是"轴对齐方块"，斜向排布时不能只看圆心距 —— 必须让相邻两块的 |dx| 或 |dy|
# 大于两者半径之和，否则边角会叠、一根手指落进两个按钮被重复触发。

var _btns: Array = []          # [{type, node}]
var _wok_btn = null
var _dash_btn = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = HudLayout.design_size()
	for s in _slots():
		_add(s)

# 扇面中心由 (圆心, 半径, 角度) 算出，全部取自 HudLayout（竖屏 / 横屏两套坐标）
func _slots() -> Array:
	var pivot := HudLayout.buttons_pivot()
	var arc_r := HudLayout.buttons_arc_r()
	var out: Array = []
	for s in HudLayout.buttons_fan():
		var a: float = deg_to_rad(float(s["deg"]))
		out.append({
			"type": s["type"],
			"id": str(s.get("id", "")),
			"center": pivot + Vector2(cos(a), sin(a)) * arc_r,
		})
	out.append({"type": "attack", "center": pivot})
	out.append({"type": "dash", "center": HudLayout.buttons_dash_center()})
	return out

func _add(s: Dictionary) -> void:
	var b = SkillButtonScript.new()
	b.btn_type = str(s.get("type", ""))
	var sid: String = str(s.get("id", ""))
	if sid != "":
		b.skill_id = sid
	add_child(b)                                    # 先入树，_ready 里才定下 size
	b.position = (s["center"] as Vector2) - b.size * 0.5
	if b.btn_type == "wok":
		_wok_btn = b
	elif b.btn_type == "dash":
		_dash_btn = b
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

# 竖屏安全区：底部按钮上移，避开全面屏手势条 / Home Indicator。
func apply_safe_area(bottom: float) -> void:
	position -= Vector2(0.0, bottom)
