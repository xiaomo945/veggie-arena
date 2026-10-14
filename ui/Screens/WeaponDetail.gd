extends Control

# 武器详情独立页：开局选武器时点卡片弹出，盖在选武器页之上。
#
# 为什么要独立成一页：卡片上塞不下"这把武器怎么打、数值多少、谁拿它最狠"，
# 而开局这一选直接决定整局的打法 —— 玩家在按下之前需要看得懂。
# 与角色详情（CharDetail）同一套路：主页面只留"形象 + 名字"，点开才是详情。
#
# 用 Control 而不是 CanvasLayer 的理由：由选武器页把它挂成自己的最后一个子节点，
# 于是"收起选武器页"天然把详情一起收掉，不需要再管一层 CanvasLayer 的显隐生命周期；
# 以后商店里要复用这一页，挂进 shop 的 CanvasLayer 即可，逻辑一行不用改。
#
# 文案全部走 ui/WeaponInfo.gd（自带中英双语、纯函数），不碰已经满载的 I18n.gd。

const WeaponInfo := preload("res://ui/WeaponInfo.gd")
const Stats := preload("res://core/Stats.gd")

signal picked(key: String)

var _root: Control
var _icon: TextureRect
var _name_lbl: Label
var _class_lbl: Label
var _body: VBoxContainer
var _pick_btn: Button
var _key: String = ""
var _open := false

func _ready() -> void:
	# ⚠️ anchors 必须配显式 size：本页在 _ready 时已经入树，
	#    只 set_anchors_preset 会把 offsets 改写成"保持当前 0x0 矩形"，页面永远画不出来。
	#    （WeaponPicker 同款写法能活，靠的就是它多给了 size = 540x900 这一行。）
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(540.0, 900.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# ⚠️ 关键修复：本页默认【自身隐藏】。之前只把内层 _root.visible=false，
	# 但 WeaponDetail 这个 Control 节点自身默认 visible=true、铺满全屏、mouse_filter=STOP，
	# 又作为选武器页的最后一个子节点叠在最上层 —— 没打开时也一直挡在上面，吞掉整页点击，
	# 表现就是"选武器界面点哪儿都点不动"。详情没打开时它必须不可见、不拦截输入。
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.size = Vector2(540.0, 900.0)
	_root.visible = false
	add_child(_root)
	_build()
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.size = Vector2(540.0, 900.0)
	shade.color = Color(0.02, 0.03, 0.06, 0.88)
	_root.add_child(shade)

	var panel := Panel.new()
	# 自带一块不透明底板：不赌引擎默认主题的 Panel 样式长什么样
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.15, 0.985)
	sb.border_color = Color(0.72, 0.60, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_size(Vector2(470, 700))
	panel.position = Vector2((540 - 470) * 0.5, (900 - 700) * 0.5)
	_root.add_child(panel)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 64px 在这页上偏小：全界面目检时详情页主图像"缩在一角"，认不出是哪把武器。
	# 与选武器卡片同款写法（IGNORE_SIZE + 自定义最小尺寸 → 节点即绘制尺寸）。
	_icon.custom_minimum_size = Vector2(96, 96)
	_icon.set_position(Vector2(470 * 0.5 - 48, 14))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_icon)

	_name_lbl = _mk_label(24, Color(0.98, 0.86, 0.32), HORIZONTAL_ALIGNMENT_CENTER)
	_name_lbl.set_position(Vector2(20, 118))
	_name_lbl.set_size(Vector2(430, 30))
	panel.add_child(_name_lbl)

	_class_lbl = _mk_label(16, Color(0.62, 0.66, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_class_lbl.set_position(Vector2(20, 152))
	_class_lbl.set_size(Vector2(430, 22))
	panel.add_child(_class_lbl)

	var scroll := ScrollContainer.new()
	# 滚动条加宽到 30px：默认约 12px，手机上几乎拉不动、还显得"不能往下滚"
	scroll.add_theme_constant_override("scrollbar_width", 30)
	scroll.set_position(Vector2(20, 186))
	scroll.set_size(Vector2(430, 430))
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(410, 0)
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_pick_btn = Button.new()
	_pick_btn.set_size(Vector2(210, 60))
	_pick_btn.set_position(Vector2(470 * 0.5 - 215, 626))
	_pick_btn.add_theme_font_size_override("font_size", 22)
	Art.style_button(_pick_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_pick_btn.pressed.connect(_on_pick)
	panel.add_child(_pick_btn)

	var close := Button.new()
	close.text = I18n.t("char_detail_close")
	close.set_size(Vector2(190, 60))
	close.set_position(Vector2(470 * 0.5 + 5, 626))
	close.add_theme_font_size_override("font_size", 20)
	Art.style_button(close, Color(0.70, 0.62, 0.50), Color(0.22, 0.16, 0.08), Color(0.60, 0.54, 0.44))
	close.pressed.connect(_on_close)
	panel.add_child(close)

func _mk_label(fs: int, c: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func show_for(key: String) -> void:
	_key = key
	_refresh()
	_open = true
	visible = true
	_root.visible = true

func hide_page() -> void:
	_open = false
	visible = false
	_root.visible = false

func is_open() -> bool:
	return _open

func _on_locale_changed(_l: String = "") -> void:
	if _open:
		_refresh()

func _section(title: String, text: String) -> void:
	if text.is_empty():
		return
	var h := _mk_label(17, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = title
	_body.add_child(h)
	var t := _mk_label(17, Color(0.88, 0.90, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(410, 0)
	_body.add_child(t)

# 数值：两列小表，比一长串文字好扫
func _stat_section() -> void:
	var rows := WeaponInfo.stat_rows(Data.weapon(_key), I18n.locale)
	if rows.is_empty():
		return
	var h := _mk_label(17, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = WeaponInfo.title_stat(I18n.locale)
	_body.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	_body.add_child(grid)
	for r in rows:
		var kk := _mk_label(15, Color(0.66, 0.70, 0.76), HORIZONTAL_ALIGNMENT_LEFT)
		kk.text = str((r as Dictionary).get("label", ""))
		grid.add_child(kk)
		var vv := _mk_label(15, Color(0.95, 0.96, 0.98), HORIZONTAL_ALIGNMENT_LEFT)
		vv.text = str((r as Dictionary).get("value", ""))
		grid.add_child(vv)

func _refresh() -> void:
	if _key.is_empty():
		return
	var def: Dictionary = Data.weapon(_key)
	_icon.texture = Art.icon("weapon_" + _key)
	_name_lbl.text = I18n.pick(def)
	_name_lbl.add_theme_color_override("font_color", Color(str(def.get("color", "#ffffff"))))
	_class_lbl.text = _class_text(def)
	_pick_btn.text = WeaponInfo.btn_pick(I18n.locale)

	for c in _body.get_children():
		c.queue_free()

	# 1) 一句话卖点 + 打法特点合并成一节：
	#    以前拆两节，但 tip（人写）和 trait_lines（机器生成）经常说的是同一件事
	#    （长弓："一句话"讲穿透两人、"打法特点"又讲一遍穿透 2），玩家读到两遍重复内容。
	#    现在：tip 打头，trait 行经过去重后只补讲 tip 没覆盖的机制，逐行列出。
	var tip := I18n.tip(def)
	var traits := _dedup_lines(tip, WeaponInfo.trait_lines(def, I18n.locale))
	var glance := tip
	for t in traits:
		glance += ("" if glance.is_empty() else "\n") + "· " + str(t)
	if not glance.is_empty():
		_section(WeaponInfo.title_summary(I18n.locale), glance)
	# 2) 数值表
	_stat_section()
	# 3) 套装 / 羁绊：当前角色拿这把武器能吃到哪几档加成（有数才看得懂）
	var set_text := _set_bonus_text(def)
	if not set_text.is_empty():
		_section(WeaponInfo.title_set(I18n.locale), set_text)
	# 5) 谁拿它最狠：把"角色 × 武器"这条线明说出来
	var masters: Array = WeaponInfo.masters(_key, Data.characters)
	if not masters.is_empty():
		var names := []
		for c in masters:
			names.append(I18n.pick(Data.character(str(c))))
		_section(WeaponInfo.title_master(I18n.locale), "、".join(names))

# 归类标签（gun/blade/heavy/elemental/kitchen → 玩家看得懂的套装名）
func _class_text(def: Dictionary) -> String:
	var out := []
	for t in (def.get("tags", []) as Array):
		var key := "set_" + str(t)
		var name := I18n.t(key)
		if not name.is_empty() and name != key:
			out.append(name)
	return " / ".join(out) if not out.is_empty() else str(def.get("type", ""))

# 套装加成：当前角色与这把武器的类羁绊（bond）能吃到哪几档。
# 以前这里只报一个类目名（"厨房套装"）——玩家还是不知道"攒几件、加什么、加多少"，
# 而羁绊数值就明摆在 characters.json 里，没理由不亮出来。
# 取不到当前角色 / 该类目不是角色的 bond 时，退回原来的类目名。
# 属性名与数值格式全部走 core/Stats.gd 的目录（单一真相源，与属性页同一把尺）。
func _set_bonus_text(def: Dictionary) -> String:
	var tags: Array = def.get("tags", []) as Array
	var bond: Dictionary = (Data.character(GameState.character) as Dictionary).get("bond", {}) as Dictionary
	var btag := str(bond.get("tag", ""))
	var tiers: Array = bond.get("tiers", []) as Array
	if btag.is_empty() or tiers.is_empty() or not tags.has(btag):
		return _class_text(def)
	var head := I18n.t("set_" + btag)
	if head == "set_" + btag:
		head = _class_text(def)
	var lines := [head]
	var j := "、" if I18n.locale == "zh" else ", "   # 顿号只属于中文（目检：英文行里混"、"很出戏）
	for t in tiers:
		var td := t as Dictionary
		var parts := []
		for k in (td.get("stats", {}) as Dictionary):
			var entry: Dictionary = Stats.entry(str(k))
			if entry.is_empty():
				continue
			parts.append(I18n.t(str(entry.get("name", ""))) + " " \
				+ Stats.fmt_value(str(entry.get("fmt", "")), float((td.get("stats", {}) as Dictionary)[k])))
		if not parts.is_empty():
			lines.append(WeaponInfo.set_tier_line(int(td.get("need", 0)), j.join(parts), I18n.locale))
	return "\n".join(lines)

# 两句话是不是在讲同一件事：去掉标点空白后互相包含即判重。
# 例：长弓 tip "Pierces 2 foes in a line." vs trait "Pierces 2 foes" → 后者被去掉。
func _dedup_lines(tip: String, traits: Array) -> Array:
	var nt := _norm(tip)
	var out: Array = []
	for t in traits:
		var nl := _norm(str(t))
		if nl.is_empty():
			continue
		if not nt.is_empty() and (nt.find(nl) >= 0 or nl.find(nt) >= 0):
			continue
		var dup := false
		for o in out:
			if _norm(str(o)) == nl:
				dup = true
				break
		if not dup:
			out.append(t)
	return out

# 归一化：只留字母/数字/汉字，其余（标点、空白、引号）全部剔除后转小写。
func _norm(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.substr(i, 1)
		var code := c.unicode_at(0)
		var keep := (code >= 48 and code <= 57) \
			or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) \
			or (code >= 0x4E00 and code <= 0x9FFF)
		if keep:
			out += c.to_lower()
	return out

func _on_pick() -> void:
	if _key.is_empty():
		return
	Sfx.ui_click()
	picked.emit(_key)
	hide_page()

func _on_close() -> void:
	Sfx.ui_click()
	hide_page()
