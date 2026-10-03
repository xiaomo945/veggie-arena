extends Control

# 右侧技能按钮（王者荣耀式）：锅气大按钮 / 冲刺 / 快进，各自处理自己的触摸 index，
# 与左侧摇杆互不抢指 —— 左手按住摇杆时，右手点这里全部生效。
#
# ⚠️ 每个按钮只认领"落在自己矩形内、且还没被占用的那根手指"，记住 index；
#   松开时只清自己的 index。这样多指触控下，摇杆和按钮各管各的。
# ⚠️ 不处理 GUI 点击（mouse_filter = IGNORE），触摸靠 _input 自己判断矩形命中，
#   保证移动端 / 桌面走同一条路径，不会"点一下触发两次"。

const TYPE_WOK := "wok"
const TYPE_DASH := "dash"
const TYPE_FF := "ff"
const TYPE_SKILL := "skill"      # 通用主动技能按钮（冰镇/毒雾…），由 skill_id 区分

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

const SIZE := Vector2(96.0, 96.0)
const WOK_SIZE := Vector2(128.0, 128.0)
const FF_SIZE := Vector2(80.0, 80.0)
const SKILL_SIZE := Vector2(84.0, 84.0)

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
		Events.skill_cooldown_changed.connect(_on_skill_cd)
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
	elif btn_type == TYPE_SKILL:
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
	if ready:
		draw_string(fs, c + Vector2(-22.0, 10.0), "x%d" % _charges,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 1.0, 1.0, 0.98))
	else:
		draw_string(fs, c + Vector2(-22.0, 8.0), I18n.t("hud_wok_label"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.6, 0.8))

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
	var base := Color(0.20, 0.30, 0.42, 0.42)
	var ring := Color(1.0, 0.82, 0.32, 0.95) if _ff_on else Color(0.5, 0.6, 0.72, 0.7)
	draw_circle(c, radius, base)
	draw_arc(c, radius, 0.0, TAU, 36, ring, 3.0, true)
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var txt := "2x" if _ff_on else "1x"
	draw_string(fs, c + Vector2(-13.0, -2.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 1.0, 1.0, 0.95))
	draw_string(fs, c + Vector2(-20.0, 18.0), I18n.t("hud_ff"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.7, 0.9))

# 扇形多边形（圆心 + 半径 + 起止角），用于冲刺冷却遮罩
func _wedge(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(c)
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
	draw_string(fs, c + Vector2(-22.0, 7.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 1.0, 1.0, 0.96))

# 技能按钮主色：按 id 区分（与 FxSkill 的特效色一致）
func _skill_color() -> Color:
	if skill_id == "frost":
		return Color(0.5, 0.85, 1.0)
	if skill_id == "poison":
		return Color(0.55, 0.85, 0.4)
	return Color(0.9, 0.7, 0.4)
