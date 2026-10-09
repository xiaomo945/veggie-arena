extends Control

# 单局时长三选一（短局 12 波 / 经典 20 波 / 无尽）。
#
# 为什么需要它：一局 20 波 ×60 秒实测 34 分钟，对手机竖屏割草来说太长
# （用户原话："单局 34 分钟太长"）。但直接把总波数砍到 12 又会惹恼想刷深的玩家，
# 所以做成标题页可选三档，选择写进存档，玩过一次之后默认沿用。
#
# 档位定义全在 data/balance.json 的 wave.run_modes，本文件不写死任何波数。
# 选完只做两件事：告诉 Data 当前档（Data.wave_cfg() 会把 total 换掉），
# 以及存进存档 —— 战斗/HUD/通关判定那一侧一行代码都不用改。

const BTN_W := 164.0
const BTN_H := 62.0
const GAP := 12.0
const LABEL_H := 26.0

const SEL_BG := Color(0.98, 0.86, 0.32)
const SEL_FG := Color(0.07, 0.08, 0.05)
const IDLE_BG := Color(0.17, 0.13, 0.09)
const IDLE_FG := Color(0.72, 0.75, 0.80)

# 顺序按"由短到长"，玩家从左往右读就是"越往右越久"
const ORDER := ["short", "classic", "endless"]

var content_size := Vector2.ZERO
var _label: Label
var _btns: Dictionary = {}

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var modes: Dictionary = Data.run_modes()
	var keys: Array = []
	for k in ORDER:
		if modes.has(k):
			keys.append(k)
	if keys.is_empty():
		for k in modes:
			keys.append(k)
	var row_w := float(keys.size()) * BTN_W + float(maxi(0, keys.size() - 1)) * GAP
	var x0 := (540.0 - row_w) * 0.5

	_label = Label.new()
	_label.set_position(Vector2(0, 0))
	_label.set_size(Vector2(540, LABEL_H))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	add_child(_label)

	for i in keys.size():
		var k := str(keys[i])
		var b := Button.new()
		b.set_position(Vector2(x0 + float(i) * (BTN_W + GAP), LABEL_H))
		b.set_size(Vector2(BTN_W, BTN_H))
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_pick.bind(k))
		_btns[k] = b
		add_child(b)

	content_size = Vector2(row_w, LABEL_H + BTN_H)
	# 存档里记过上次选的档就默认选它（新档默认 short）
	Data.set_run_mode(SaveMgr.run_mode())
	I18n.locale_changed.connect(_refresh)
	_refresh()

func _on_pick(mode: String) -> void:
	Sfx.ui_click()
	Data.set_run_mode(mode)
	SaveMgr.set_run_mode(mode)
	_refresh()

func _refresh(_l: String = "") -> void:
	_label.text = I18n.t("mode_label")
	var modes: Dictionary = Data.run_modes()
	for k in _btns:
		var b: Button = _btns[k]
		var m: Dictionary = modes.get(k, {})
		var total := int(m.get("total", 0))
		var sel := str(k) == Data.run_mode
		# total<=0 = 永不通关，显示"无限"而不是"0 波"
		var detail := I18n.t("mode_forever") if total <= 0 else I18n.t("mode_waves") % total
		var mins := int(m.get("minutes", 0))
		if mins > 0:
			detail += " · " + (I18n.t("mode_minutes") % mins)
		b.text = "%s\n%s" % [I18n.t("mode_" + str(k)), detail]
		b.add_theme_color_override("font_color", SEL_FG if sel else IDLE_FG)
		var sb := StyleBoxFlat.new()
		sb.bg_color = SEL_BG if sel else IDLE_BG
		sb.set_corner_radius_all(10)
		if sel:
			sb.border_width_bottom = 4
			sb.border_color = Color(0.72, 0.60, 0.16)
		else:
			sb.border_width_left = 2
			sb.border_width_right = 2
			sb.border_width_top = 2
			sb.border_width_bottom = 2
			sb.border_color = Color(0.34, 0.28, 0.20)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", sb)
