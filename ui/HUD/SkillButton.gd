extends Control

# 右侧技能按钮（王者荣耀式）：锅气大按钮 / 冲刺 / 快进 / 主动技，各自处理自己的触摸
# index，与左侧摇杆互不抢指 —— 左手按住摇杆时，右手点这里全部生效。
# ⚠️ 每个按钮只认领"落在自己矩形内、且还没被占用的那根手指"，记住 index，松开只清
#   自己的 —— 多指触控下摇杆和按钮各管各的。不处理 GUI 点击（mouse_filter=IGNORE），
#   触摸靠 _input 判矩形命中，移动端/桌面同一条路径，不会"点一下触发两次"。

const TYPE_WOK := "wok"
const TYPE_DASH := "dash"
const TYPE_FF := "ff"
const TYPE_SKILL := "skill"      # 通用主动技能按钮（冰镇/毒雾…），由 skill_id 区分
const TYPE_ATTACK := "attack"    # 手动攻击键：右下角大按钮，释放"最常用的技能"（primary）

const SkillDef := preload("res://core/SkillDef.gd")

var btn_type := "dash"
var skill_id := ""               # TYPE_SKILL 时有效：对应 data/skills.json 的 id

var _touch_index := -1

# 锅气状态
var _heat := 0.0
var _charges := 0
# 冲刺状态
var _dash_ratio := 1.0
var _dash_ready := true
# 快进状态（本地开关）
var _ff_on := false
# 主动技能状态（冷却）
var _skill_ratio := 1.0
var _skill_ready := true

const SIZE := Vector2(88.0, 88.0)
const WOK_SIZE := Vector2(88.0, 88.0)   # 半圆扇面上要和冰/毒拉开距离，不能太大
const FF_SIZE := Vector2(80.0, 80.0)
const SKILL_SIZE := Vector2(76.0, 76.0)
const ATTACK_SIZE := Vector2(100.0, 100.0)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if btn_type == TYPE_WOK:
		size = WOK_SIZE
		Events.wok_heat_changed.connect(_on_heat)
		Events.wok_charges_changed.connect(_on_charges)
	elif btn_type == TYPE_DASH:
		size = SIZE
		Events.dash_state_changed.connect(_on_dash)
	elif btn_type == TYPE_FF:
		size = FF_SIZE
		Events.fast_forward_toggled.connect(_on_ff_sync)
	elif btn_type == TYPE_SKILL:
		size = SKILL_SIZE
		# 没被外部指定的话，就用当前角色自己的专属技能
		if skill_id.is_empty():
			skill_id = _char_skill_id()
			# 换角色 = 换招：角色是进战斗前才定的（标题页/选角页），按钮必须跟着换。
			# 外部指定过 id 的按钮是绑死某技能的，不跟随。
			Events.character_changed.connect(_on_char_changed)
		Events.skill_cooldown_changed.connect(_on_skill_cd)
	elif btn_type == TYPE_ATTACK:
		size = ATTACK_SIZE
		# 攻击键释放当前角色的专属技能（换角色 = 换招，这是"换个角色像换个游戏"的一环）
		skill_id = _char_skill_id()
		Events.skill_cooldown_changed.connect(_on_skill_cd)
	queue_redraw()

# 当前角色该放哪个技能：角色表里写了 skill id；没写就退回通用技，按钮绝不变哑巴
func _char_skill_id() -> String:
	return SkillDef.skill_id_of(Data.character(GameState.character))

# 换角色后重取技能 id：显示名/配色/冷却曲线全跟着变（不同步会显示错误进度）
func _on_char_changed(_key: String) -> void:
	var id := _char_skill_id()
	if id == skill_id:
		return
	skill_id = id
	_skill_ratio = 1.0
	_skill_ready = true
	queue_redraw()

func _on_heat(value: float, _tier: int) -> void:
	_heat = value
	queue_redraw()

func _on_charges(n: int) -> void:
	_charges = n
	queue_redraw()

# 公开接口：HUD 转发锅气充能数（避免外部直接碰 _charges 私有字段）
func set_charges(n: int) -> void:
	_charges = n
	queue_redraw()

# 主动技能冷却状态（SkillSystem 每帧广播）
func _on_skill_cd(id: String, ratio: float, ready: bool) -> void:
	if id != skill_id:
		return
	_skill_ratio = clampf(ratio, 0.0, 1.0)
	_skill_ready = ready
	queue_redraw()

func _on_dash(ratio: float, ready: bool) -> void:
	_dash_ratio = clampf(ratio, 0.0, 1.0)
	_dash_ready = ready
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not GameState.running or GameState.paused:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch_index == -1 and _rect().has_point(t.position):
				_press(t.index)
		elif t.index == _touch_index:
			_touch_index = -1
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch_index == -1 and _rect().has_point(mb.position):
				_press(-1)
			elif not mb.pressed and _touch_index == -1:
				_touch_index = -1
		return

func _rect() -> Rect2:
	return get_global_rect()

func _press(index: int) -> void:
	_touch_index = index
	if btn_type == TYPE_WOK:
		Events.wok_toss_requested.emit()
	elif btn_type == TYPE_DASH:
		Events.dash_requested.emit()
	elif btn_type == TYPE_SKILL or btn_type == TYPE_ATTACK:
		Events.skill_requested.emit(skill_id)
	elif btn_type == TYPE_FF:
		_ff_on = not _ff_on
		Events.fast_forward_toggled.emit(_ff_on)
	queue_redraw()

# 与外部（如开局重置）同步快进状态，避免"按钮还亮着但游戏已恢复 1x"
func _on_ff_sync(on: bool) -> void:
	if _ff_on != on:
		_ff_on = on
		queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	if btn_type == TYPE_WOK:
		_draw_wok(c)
	elif btn_type == TYPE_DASH:
		_draw_dash(c)
	elif btn_type == TYPE_SKILL:
		_draw_skill(c)
	elif btn_type == TYPE_ATTACK:
		_draw_attack(c)
	else:
		_draw_ff(c)

# ---- 锅气：大号按钮 + 充能进度环 + 存了几发 ----
func _draw_wok(c: Vector2) -> void:
	var radius := size.x * 0.5 - 4.0
	var ready := _charges > 0
	var base := Color(0.92, 0.42, 0.26, 0.30)
	var ring := Color(1.0, 0.72, 0.42, 0.95) if ready else Color(0.55, 0.45, 0.4, 0.7)
	draw_circle(c, radius, base)
	# 充能进度环：火候 0..100 的进度（朝下一发颠勺攒了多少）
	var frac := clampf(_heat / 100.0, 0.0, 1.0)
	if frac > 0.001:
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * frac, 48,
			Color(1.0, 0.78, 0.42, 0.85), 6.0, true)
	draw_arc(c, radius, 0.0, TAU, 48, ring, 3.0, true)
	# 中心：存了几发就显示 x{n}，没充能时显示"锅气"
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var wtxt := "x%d" % _charges if ready else I18n.t("hud_wok_label")
	draw_string(fs, c + Vector2(-22.0, 9.0), wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		34 if ready else 22, Color(1.0, 1.0, 0.98) if ready else Color(1.0, 0.85, 0.6, 0.8))

# ---- 冲刺：带冷却扇形（从顶部顺时针扫过）----
func _draw_dash(c: Vector2) -> void:
	var radius := size.x * 0.5 - 4.0
	var base := Color(0.16, 0.20, 0.28, 0.42)
	var ring := Color(0.55, 0.85, 0.45, 0.95) if _dash_ready else Color(0.45, 0.52, 0.62, 0.85)
	draw_circle(c, radius, base)
	draw_arc(c, radius, 0.0, TAU, 40, ring, 4.0, true)
	if not _dash_ready:
		var span := TAU * (1.0 - _dash_ratio)
		draw_colored_polygon(_wedge(c, radius - 4.0, -PI * 0.5, -PI * 0.5 + span),
			Color(0.05, 0.07, 0.12, 0.55))
	var a := 0.95 if _dash_ready else 0.35
	var col := Color(0.86, 0.96, 0.84, a)
	for i in 2:
		var x := c.x - 8.0 + float(i) * 11.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 5.0, c.y - 9.0), Vector2(x + 4.0, c.y),
			Vector2(x - 5.0, c.y + 9.0)]), col)

# ---- 快进：2 倍速开关 ----
func _draw_ff(c: Vector2) -> void:
	var radius := size.x * 0.5 - 4.0
	var ring := Color(1.0, 0.82, 0.32, 0.95) if _ff_on else Color(0.5, 0.6, 0.72, 0.7)
	draw_circle(c, radius, Color(0.20, 0.30, 0.42, 0.42))
	draw_arc(c, radius, 0.0, TAU, 36, ring, 3.0, true)
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var txt := "2x" if _ff_on else "1x"
	draw_string(fs, c + Vector2(-13.0, -2.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 1.0, 1.0, 0.95))
	draw_string(fs, c + Vector2(-20.0, 18.0), I18n.t("hud_ff"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.7, 0.9))

# 扇形多边形（圆心 + 半径 + 起止角），用于冷却遮罩
func _wedge(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array([c])
	var steps := 24
	for i in range(steps + 1):
		var ang := from + (to - from) * (float(i) / float(steps))
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts

# ---- 主动技能：彩色圆环 + 冷却扇形 + 技能名（冰镇/毒雾） ----
func _draw_skill(c: Vector2) -> void:
	var radius := size.x * 0.5 - 4.0
	var col := _skill_color()
	var base := Color(col.r, col.g, col.b, 0.22)
	draw_circle(c, radius, base)
	draw_arc(c, radius, 0.0, TAU, 40,
		Color(col.r, col.g, col.b, 0.95) if _skill_ready else Color(0.5, 0.55, 0.62, 0.8),
		3.5, true)
	if not _skill_ready:
		var span := TAU * (1.0 - _skill_ratio)
		draw_colored_polygon(_wedge(c, radius - 4.0, -PI * 0.5, -PI * 0.5 + span),
			Color(0.05, 0.07, 0.12, 0.55))
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var txt := I18n.t("skill_" + skill_id)
	# 按钮只有 76px 宽：技能名先按 18 号画，超宽一路缩到 12 号，绝不溢出按钮外
	# （技能名已角色化、长度不一，写死 18 号会让长名字顶出按钮）
	var tfs := 18
	var tw := fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	while tw > size.x - 12.0 and tfs > 12:
		tfs -= 1
		tw = fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	draw_string(fs, Vector2(c.x - tw * 0.5, c.y + 7.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1.0, 1.0, 1.0, 0.96))

# ---- 手动攻击键：右下角最大最显眼，释放"最常用的技能"（primary）；
# 复用 _skill_ready/_skill_ratio（_ready 已把 skill_id 绑到 primary，冷却自动同步）
func _draw_attack(c: Vector2) -> void:
	var radius := size.x * 0.5 - 4.0
	var col := _skill_color()
	draw_circle(c, radius, Color(col.r, col.g, col.b, 0.30))
	draw_arc(c, radius, 0.0, TAU, 52,
		Color(col.r, col.g, col.b, 0.98) if _skill_ready else Color(0.5, 0.55, 0.62, 0.85),
		5.0, true)
	if not _skill_ready:
		var span := TAU * (1.0 - _skill_ratio)
		draw_colored_polygon(_wedge(c, radius - 4.0, -PI * 0.5, -PI * 0.5 + span),
			Color(0.05, 0.07, 0.12, 0.55))
	# 卡通刀刃图标：刀身 + 护手 + 柄头
	var d: float = radius * 0.40
	var w := Color(1.0, 1.0, 1.0, 0.95) if _skill_ready else Color(1.0, 1.0, 1.0, 0.38)
	draw_line(c + Vector2(-d * 0.75, d * 0.75), c + Vector2(d * 0.62, -d * 0.62), w, 8.0, true)
	draw_line(c + Vector2(-d * 0.15, d * 0.95), c + Vector2(d * 0.35, d * 0.45), w, 7.0, true)
	draw_circle(c + Vector2(-d * 0.85, d * 0.85), radius * 0.10, w)
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	draw_string(fs, c + Vector2(-16.0, radius * 0.80), I18n.t("hud_attack"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 1.0, 1.0, 0.92))

# 技能按钮主色：按 id 区分（与 FxSkill 的特效色一致）。每个专属技能各给一色 ——
# 一眼认出"这一局的招是什么"，换角色颜色跟着变，也是"换个角色像换个游戏"的一环。
const SKILL_COLORS := {
	"frost": Color(0.50, 0.85, 1.00),      # 冰镇 —— 冰蓝
	"frost_nova": Color(0.62, 0.72, 1.00), # 冰霜新星 —— 淡紫蓝
	"pierce_shot": Color(0.55, 0.92, 0.78),# 穿透射击 —— 青
	"quake": Color(0.88, 0.66, 0.34),      # 震地 —— 土黄
	"gust": Color(0.60, 0.95, 0.62),       # 疾风 —— 浅绿
	"coin_rain": Color(1.00, 0.82, 0.30),  # 金币雨 —— 金
	"spike_burst": Color(0.82, 0.74, 0.52),# 尖刺爆发 —— 灰褐
	"mark": Color(0.96, 0.45, 0.38),       # 标记射击 —— 红
	"combo": Color(1.00, 0.55, 0.28),      # 连击狂潮 —— 橙红
	"magnet_pull": Color(0.45, 0.72, 0.95),# 磁吸 —— 蓝
	"sear": Color(0.94, 0.36, 0.20),      # 灼烧 —— 焦红（毒+火）
	"grind": Color(0.80, 0.66, 0.40),     # 碾压 —— 薯泥黄褐
	"flashfire": Color(1.00, 0.68, 0.20), # 爆燃火候 —— 旺火橙（全是锅气，不伤人）
}
const SKILL_COLOR_FALLBACK := Color(0.90, 0.70, 0.40)

func _skill_color() -> Color:
	return SKILL_COLORS.get(skill_id, SKILL_COLOR_FALLBACK) as Color
