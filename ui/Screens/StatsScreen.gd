extends CanvasLayer

# 独立属性页：从暂停菜单进入，竖屏 540x900。
# 把这一局玩家堆出来的所有真实属性（核心 / 经济 / 锅气 / 机动）分组滚动展示，
# 每条显示当前数值。目录来自 core/Stats.gd（单一真相源，加属性只改那一处）。
# 取值走 GameState.stat_value；max_hp 特例直接读 GameState.max_hp。
# 数值为 0 的可选强化行做半透明，既展示完整系统又让玩家一眼看清自己有啥。
#
# 打开方式仿 SettingsMenu：PauseScreen 注入 back_pressed 回调，本页只负责显示与发声。

const Stats := preload("res://core/Stats.gd")

const TOP_INSET := 92.0
const BOTTOM_INSET := 28.0
const PAD := 28.0

var _root: Control
var _title_lbl: Label
var _back_btn: Button
var _val_labels: Dictionary = {}   # stat key -> 数值 Label（show 时刷新）
var _rows: Array = []              # [{entry, name_l, val_l}]（show 时刷新透明度）
var _headers: Dictionary = {}      # I18n 标题 key -> 分组标题 Label

func _ready() -> void:
	layer = 36
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)   # 横屏下把竖屏菜单缩放到 960x540 视口内、居中
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.94)
	_root.add_child(shade)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 34)
	_title_lbl.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.set_position(Vector2(0, 40))
	_title_lbl.set_size(Vector2(540, 44))
	_root.add_child(_title_lbl)

	# 滚动区：标题下方到返回键上方。
	# ⚠️ 不能先 set_anchors_preset(FULL_RECT) 再 set_size：跨越式锚点(0..1)下
	#    set_size 会把手工宽度叠到锚点宽度上（540+484=1024，数值列直接顶出屏幕）。
	#    纯手工坐标（默认 0,0,0,0 锚点）在这里最稳。
	var scroll := ScrollContainer.new()
	scroll.set_position(Vector2(PAD, TOP_INSET))
	scroll.set_size(Vector2(540 - PAD * 2.0, 900 - TOP_INSET - BOTTOM_INSET - 64.0))
	_root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	for grp in Stats.grouped():
		_add_section(vbox, grp)

	_back_btn = Button.new()
	_back_btn.set_size(Vector2(300, 60))
	_back_btn.set_position(Vector2((540 - 300) * 0.5, 900 - BOTTOM_INSET - 60))
	_back_btn.add_theme_font_size_override("font_size", 22)
	Art.style_button(_back_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_back_btn.pressed.connect(_on_back)
	_root.add_child(_back_btn)

	_refresh_texts()

# 一个分组：小标题 + 若干属性行
func _add_section(parent: VBoxContainer, grp: Dictionary) -> void:
	var hdr := Label.new()
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	hdr.add_theme_constant_override("margin_top", 10)
	hdr.text = I18n.t(grp["title"])
	parent.add_child(hdr)
	_headers[grp["title"]] = hdr
	for entry in grp["items"]:
		_add_row(parent, entry)

# 一条属性：左名称 / 右数值，两端对齐
func _add_row(parent: VBoxContainer, entry: Dictionary) -> void:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := Label.new()
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", Color(0.90, 0.92, 0.95))
	name_l.text = I18n.t(entry["name"])
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := Label.new()
	val_l.add_theme_font_size_override("font_size", 17)
	val_l.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_l)
	hb.add_child(val_l)
	parent.add_child(hb)
	_val_labels[entry["key"]] = val_l
	_rows.append({"entry": entry, "name_l": name_l, "val_l": val_l})

# 数值格式化
func _fmt(fmt: String, v: float) -> String:
	match fmt:
		"pct": return "+%d%%" % int(round(v * 100.0))
		"atk": return "%d" % int(round(v))
		"flat": return "+%d" % int(round(v))
		"lvl": return "×%d" % int(round(v))
		"hp": return "%d" % int(round(v))
		_: return str(v)

# 取某条属性的当前值（max_hp / attack 特例）
func _value(entry: Dictionary) -> float:
	if entry["key"] == "max_hp":
		return float(GameState.max_hp)
	if entry["key"] == "attack":
		return Stats.attack_power(GameState.weapons, GameState.stat_value,
			Data.weapon, Data.combat_cfg())
	return GameState.stat_value(entry["key"])

func show_menu(on_back: Callable = Callable()) -> void:
	_back = on_back
	_refresh_texts()
	for r in _rows:
		var entry: Dictionary = r["entry"]
		var v := _value(entry)
		var vl: Label = r["val_l"]
		vl.text = _fmt(entry["fmt"], v)
		# 0 值的可选强化半透明（hp / attack 永不透明）。
		# ⚠️ 零判定要按显示口径来：pct 的 v 是 0..1 小数，直接 round(v) 会把
		#    +5% 这种小加成误判成 0 而置灰，必须先 ×100 再取整。
		var eff := v * 100.0 if entry["fmt"] == "pct" else v
		var dim: bool = (entry["fmt"] != "hp" and entry["fmt"] != "atk") and (int(round(eff)) == 0)
		vl.modulate.a = 0.35 if dim else 1.0
		(r["name_l"] as Label).modulate.a = 0.35 if dim else 1.0
	_root.visible = true

func hide_menu() -> void:
	_root.visible = false

func _refresh_texts() -> void:
	_title_lbl.text = I18n.t("stats_title")
	_back_btn.text = I18n.t("stats_back")
	for title_key in _headers:
		var lbl: Label = _headers[title_key]
		if lbl != null:
			lbl.text = I18n.t(title_key)
	for r in _rows:
		var entry: Dictionary = r["entry"]
		(r["name_l"] as Label).text = I18n.t(entry["name"])

func _on_locale_changed(_locale: String = "") -> void:
	if _root != null and _root.visible:
		_refresh_texts()

func _on_back() -> void:
	Sfx.ui_click()
	hide_menu()
	if _back.is_valid():
		_back.call()

# 打开时由调用方传入的返回回调（HUD 属性键→恢复世界；暂停菜单→重新显示暂停菜单）
var _back: Callable = Callable()
