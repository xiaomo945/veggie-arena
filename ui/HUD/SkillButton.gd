extends Control

# 右侧技能按钮（王者荣耀式）：锅气/冲刺/主动技各自认领矩形内还没被占用的那根手指
# （多指各管各的）；不处理 GUI 点击，触摸靠 _input 判矩形命中，桌面同路径不双触发。

const TYPE_WOK := "wok"
const TYPE_DASH := "dash"
const TYPE_SKILL := "skill"      # 通用主动技能按钮（冰镇/毒雾…），由 skill_id 区分
const TYPE_ATTACK := "attack"    # 手动攻击键：右下角大按钮，释放"最常用的技能"（primary）

const SkillDef := preload("res://core/SkillDef.gd")
const SkillLook := preload("res://ui/SkillLook.gd")
const KeyCap := preload("res://ui/HUD/KeyCap.gd")

var btn_type := "dash"
var skill_id := ""               # TYPE_SKILL 时有效：对应 data/skills.json 的 id
var slot_index := -1             # 技能槽下标 0/1/2 → 键盘 J/K/L（KeyCap 角标用；固定槽 -1）

var _touch_index := -1
var _flash := 0.0   # 键盘触发白环的剩余强度（1→0 衰减，见 flash()/_process）

var _heat := 0.0          # 锅气状态：火候 0..100
var _charges := 0         # 存了几发颠勺
var _dash_ratio := 1.0    # 冲刺状态：冷却进度
var _dash_ready := true
var _skill_ratio := 1.0   # 主动技能（冷却）
var _skill_ready := true
var _skill_form := "base"    # 当前形态 key：凑够某类武器后技能"换了招"，名字和颜色都跟着变

const SIZE := Vector2(88.0, 88.0)
const WOK_SIZE := Vector2(80.0, 80.0)   # 扇面里和冰/毒技能键斜 45° 相邻，80 是横屏 540 高内不出屏的上限（见 HudLayout.buttons_arc_r 的几何推导）
const SKILL_SIZE := Vector2(76.0, 76.0)
const ATTACK_SIZE := Vector2(100.0, 100.0)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# 切语言：按钮名/文案全部走 _draw 里的 I18n，重画即刷新（locale_changed 带参数，不能直连 queue_redraw）
	I18n.locale_changed.connect(_on_locale_changed)
	if btn_type == TYPE_WOK:
		size = WOK_SIZE
		Events.wok_heat_changed.connect(_on_heat)
		Events.wok_charges_changed.connect(_on_charges)
	elif btn_type == TYPE_DASH:
		size = SIZE
		Events.dash_state_changed.connect(_on_dash)
	elif btn_type == TYPE_SKILL:
		size = SKILL_SIZE
		# 没被外部指定的话，就用当前角色自己的专属技能
		if skill_id.is_empty():
			skill_id = _char_skill_id()
			# 换角色 = 换招：角色进战斗前才定（标题页/选角页），按钮必须跟着换；
			# 外部指定过 id 的按钮绑死某技能，不跟随。
			Events.character_changed.connect(_on_char_changed)
		Events.skill_cooldown_changed.connect(_on_skill_cd)
		Events.skill_form_changed.connect(_on_form_changed)
	elif btn_type == TYPE_ATTACK:
		size = ATTACK_SIZE
		# 攻击键释放当前角色的专属技能（换角色 = 换招，这是"换个角色像换个游戏"的一环）
		skill_id = _char_skill_id()
		Events.skill_cooldown_changed.connect(_on_skill_cd)
		Events.skill_form_changed.connect(_on_form_changed)
	queue_redraw()

# 当前角色该放哪个技能：角色表里写了 skill id；没写就退回通用技，按钮绝不变哑巴
func _char_skill_id() -> String:
	return SkillDef.skill_id_of(Data.character(GameState.character))

# 换角色后重取技能 id：显示名/配色/冷却曲线全跟着变
func _on_char_changed(_key: String) -> void:
	var id := _char_skill_id()
	if id == skill_id:
		return
	skill_id = id
	_skill_ratio = 1.0
	_skill_ready = true
	_skill_form = "base"        # 形态是"这局的武器凑出什么"，换角色必须从头算
	queue_redraw()

# 形态变了（凑够某类武器）：按钮改名 + 换配色，玩家不用读说明就知道自己换了招
func _on_form_changed(id: String, form: String) -> void:
	if id != skill_id or form == _skill_form:
		return
	_skill_form = form
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

# 主动技能冷却状态（SkillSystem 广播）
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
	# between_waves：结算页/补给站期间按钮不响应 —— 那两层遮罩之上触摸事件照样
	# 会投递到按钮矩形上（_input 不吃 GUI 遮挡），不拦就是"商店里放技能"（既有漏洞）。
	if not GameState.running or GameState.paused or GameState.between_waves:
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
	_trigger()

# 触发动作：手指点按与键盘等价路径共用（只发 Events 信号，不碰任何数据/冷却）
func _trigger() -> void:
	if btn_type == TYPE_WOK:
		Events.wok_toss_requested.emit()
	elif btn_type == TYPE_DASH:
		Events.dash_requested.emit()
	elif btn_type == TYPE_SKILL or btn_type == TYPE_ATTACK:
		Events.skill_requested.emit(skill_id)
	queue_redraw()

# 公开触发（键盘 J/K/L/U/空格 经 HudButtons press_* 调）：同走 _trigger + 白环闪
func press() -> void:
	_trigger()
	flash()

# 键盘触发反馈：白环强度置 1，_process 衰减、_draw 画
func flash() -> void:
	_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
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
		_draw_dash(c)
	# 键盘触发白环：贴外圈、随 _flash 淡出（和冷却扇形/充能环区分开）
	if _flash > 0.0:
		draw_arc(c, size.x * 0.5 - 1.0, 0.0, TAU, 48, Color(1, 1, 1, _flash), 3.0, true)
		# 键位角标（映射口径见 ui/HUD/KeyCap.gd）
		KeyCap.draw(self, KeyCap.label(btn_type, slot_index), size)

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()

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

# ---- 冲刺：大号双箭头（»）+ "冲刺" 文字标签 ----
# 旧版玩家吐槽"有两个箭头是冲刺吗？没有效果"：换成粗双箭头 + 底部文字标签。
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
	# 双粗箭头（»）：整体偏上，给底部文字标签让位；冷却时整组变暗
	var a := 0.95 if _dash_ready else 0.35
	var col := Color(0.86, 0.96, 0.84, a)
	var cy := c.y - 9.0
	for i in 2:
		var ox := c.x - 9.0 + float(i) * 16.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(ox - 8.0, cy - 11.0), Vector2(ox + 6.0, cy),
			Vector2(ox - 8.0, cy + 11.0), Vector2(ox - 1.0, cy)]), col)
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var txt := I18n.t("hud_dash")
	var tw := fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(fs, Vector2(c.x - tw * 0.5, c.y + 26.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.90, 0.97, 0.90, 0.92))

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
	# 形态名优先：凑够同类武器换了招，按钮写新招名（法师 ="冰锥爆裂"而非"冰霜新星"）
	var txt := I18n.t("skill_" + _skill_form) if _skill_form != "base" \
		else I18n.t("skill_" + skill_id)
	# 76px 宽按钮：技能名 18 号起画，超宽一路缩到 12 号，绝不溢出
	var tfs := 18
	var tw := fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	while tw > size.x - 12.0 and tfs > 12:
		tfs -= 1
		tw = fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	draw_string(fs, Vector2(c.x - tw * 0.5, c.y + 7.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1.0, 1.0, 1.0, 0.96))

# ---- 手动攻击键：右下角最大最显眼，释放"最常用的技能"（primary，冷却自动同步）----
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

# 技能按钮主色：形态自带配色优先，否则按 id（与 FxSkill 的特效色同源，见 ui/SkillLook）
func _skill_color() -> Color:
	return SkillLook.color_of(skill_id, _skill_form)
