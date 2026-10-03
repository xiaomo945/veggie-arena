extends Control

# HUD 底部 / 右侧技能按钮区：锅气（大号，带充能进度环）/ 冲刺 / 快进 2 倍速。
#
# 布局用 slots 数组描述，方便老板以后把"锅气技能拆成多个按钮" —— 直接往里加一项即可，
# 右侧矩形自动避让摇杆（见 Joystick 的 MOVE_ZONE_W）。每个按钮是独立的 SkillButton，
# 各自认领自己矩形内的那根手指，与左侧摇杆互不抢指。
#
# 锅气按钮常驻可见（有充能显示 x{n}，没充能显示"锅气"+ 火候进度环）。

const SkillButtonScript := preload("res://ui/HUD/SkillButton.gd")

# 按钮槽：local_center 是相对本容器的局部中心（容器会被安全区上移，矩形自动跟随）
# 顺序即绘制顺序。右侧技能簇（x>250，避开左下摇杆区）：
#   锅气（大号，右下，爆炸+击退）、冲刺（右下偏左）、冰镇（中右）、毒雾（中）。
# 锅气/冰镇/毒雾 = 3 个手动释放技能（王者荣耀式），左手走位+右手点技能同时成立。
const SLOTS := [
	{"type": "wok",   "center": Vector2(470, 786)},
	{"type": "dash",  "center": Vector2(300, 856)},
	{"type": "skill", "id": "frost",  "center": Vector2(430, 672)},
	{"type": "skill", "id": "poison", "center": Vector2(330, 672)},
]

var _btns: Array = []          # [{type, node}]
var _wok_btn = null
var _dash_btn = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(540.0, 900.0)
	for s in SLOTS:
		var b = SkillButtonScript.new()
		b.btn_type = s["type"]
		if s["type"] == "skill":
			b.skill_id = s["id"]
		var sz: Vector2 = b.size
		b.position = (s["center"] as Vector2) - sz * 0.5
		add_child(b)
		if s["type"] == "wok":
			_wok_btn = b
		elif s["type"] == "dash":
			_dash_btn = b
		_btns.append({"type": s["type"], "node": b})

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

# 预留：以后"锅气技能拆成多个按钮"，直接从这里取第 n 个技能按钮的矩形
func slot_rect(index: int) -> Rect2:
	if index >= 0 and index < _btns.size():
		return (_btns[index]["node"] as Control).get_global_rect()
	return Rect2()

func tick(_delta: float) -> void:
	pass   # 各按钮自行绘制，无需统一脉动

# 竖屏安全区：底部按钮上移，避开全面屏手势条 / Home Indicator。
func apply_safe_area(bottom: float) -> void:
	position -= Vector2(0.0, bottom)
