extends CanvasLayer

# 角色详情独立页（D3-4）：点角色卡弹出，只在【这一页】讲清楚
#   「本命是什么 / 该买什么武器 / 该点什么技能 / 怎么玩 / 自带什么属性」
# 主选角页（CharacterPicker）从此只留形象 + 名字 —— 用户原话"只突出角色形象"。
#
# 这是"对话框式独立页面"：将来扩到 60 个角色，也只换这一页的文字，
# 绝不靠把卡片缩小来塞进主页面（arch_guard 盯着 PICKER_MAX_H 就为这事）。

const Character := preload("res://core/Character.gd")
const SkillDef := preload("res://core/SkillDef.gd")
const UnlockText := preload("res://ui/UnlockText.gd")

signal picked(key: String)

var _root: Control
var _portrait: TextureRect
var _name_lbl: Label
var _aff_lbl: Label
var _body: VBoxContainer
var _pick_btn: Button
var _close_btn: Button
var _key: String = ""
var _open := false

func _ready() -> void:
	layer = 55
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.06, 0.86)
	_root.add_child(shade)

	var panel := Panel.new()
	panel.set_size(Vector2(470, 690))
	panel.position = Vector2((540 - 470) * 0.5, (900 - 690) * 0.5)
	_root.add_child(panel)

	# 头部：立绘 + 名字 + 职业倾向（不随内容滚动）
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.custom_minimum_size = Vector2(104, 104)
	_portrait.set_position(Vector2(470 * 0.5 - 52, 22))
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_portrait)

	_name_lbl = _mk_label(22, Color(0.98, 0.86, 0.32), HORIZONTAL_ALIGNMENT_CENTER)
	_name_lbl.set_position(Vector2(20, 134))
	_name_lbl.set_size(Vector2(430, 30))
	panel.add_child(_name_lbl)

	_aff_lbl = _mk_label(15, Color(0.62, 0.66, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_aff_lbl.set_position(Vector2(20, 168))
	_aff_lbl.set_size(Vector2(430, 24))
	panel.add_child(_aff_lbl)

	# 正文区：可滚动（tip 文案长，且要能塞下"该买什么/技能/属性"四块）
	var scroll := ScrollContainer.new()
	scroll.set_position(Vector2(20, 200))
	scroll.set_size(Vector2(430, 410))
	# 滚动条加宽到 28px、常显：手机上拉得动，与武器详情页一致
	scroll.add_theme_constant_override("scrollbar_width", 28)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.11, 0.16, 0.0)   # 透明底，只留漂亮滚动条
	scroll.add_theme_stylebox_override("bg", bg)
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(410, 0)
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_pick_btn = Button.new()
	_pick_btn.text = I18n.t("char_detail_pick")
	_pick_btn.set_size(Vector2(210, 60))
	_pick_btn.set_position(Vector2(470 * 0.5 - 215, 622))
	_pick_btn.add_theme_font_size_override("font_size", 22)
	Art.style_button(_pick_btn, Color(0.98, 0.62, 0.22), Color(0.30, 0.14, 0.04), Color(0.88, 0.52, 0.16))
	_pick_btn.pressed.connect(_on_pick)
	panel.add_child(_pick_btn)

	_close_btn = Button.new()
	_close_btn.text = I18n.t("char_detail_close")
	_close_btn.set_size(Vector2(190, 60))
	_close_btn.set_position(Vector2(470 * 0.5 + 5, 622))
	_close_btn.add_theme_font_size_override("font_size", 20)
	Art.style_button(_close_btn, Color(0.70, 0.62, 0.50), Color(0.22, 0.16, 0.08), Color(0.60, 0.54, 0.44))
	_close_btn.pressed.connect(_on_close)
	panel.add_child(_close_btn)

func _mk_label(fs: int, c: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# 正文里的一节：小标题 + 内容（自动换行）
func _section(title: String, text: String) -> void:
	if text.is_empty():
		return
	var h := _mk_label(16, Color(1.0, 0.84, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	h.text = title
	h.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(h)
	var t := _mk_label(15, Color(0.88, 0.90, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(410, 0)
	_body.add_child(t)

func show_for(key: String) -> void:
	_key = key
	_refresh()
	_open = true
	_root.visible = true

func hide_page() -> void:
	_open = false
	_root.visible = false

func is_open() -> bool:
	return _open

func _on_locale_changed(_l: String = "") -> void:
	if _open:
		_refresh()

# 取 localized 字段：zh 用 X，en 用 X_en（缺则回落中文），从未经过 __loc 的字段也一样
func _loc(e: Dictionary, base: String) -> String:
	if I18n.locale == "en":
		return str(e.get(base + "_en", e.get(base, "")))
	return str(e.get(base, ""))

func _refresh() -> void:
	if _key.is_empty():
		return
	var entry: Dictionary = Data.character(_key)
	var accent := Color(str(entry.get("color", "#ffffff")))
	_portrait.texture = Art.sprite("char_" + _key)
	_name_lbl.text = I18n.pick(entry)
	var aff := str(entry.get("affinity", "mixed"))
	_aff_lbl.text = Character.affinity_text(aff, I18n.locale)
	_aff_lbl.add_theme_color_override("font_color", Character.affinity_color(aff))

	for c in _body.get_children():
		c.queue_free()

	_lock_state()

	# 1) 本命特性（一句话说清这角色的核心机制）
	_section(I18n.t("char_detail_trait"), _loc(entry, "trait"))
	# 2) 怎么玩（长文本，这一页的价值所在）
	_section(I18n.t("char_detail_how"), _loc(entry, "tip"))
	# 3) 该买什么：本命武器 + 配装方向
	_section(I18n.t("char_detail_buy"), _buy_text(entry))
	# 4) 该点什么技能
	_section(I18n.t("char_detail_skill"), _skill_text(entry))
	# 5) 自带属性（没有就是基准角色）
	var desc := Character.describe(entry)
	if desc.is_empty() or (entry.get("stats", {}) as Dictionary).is_empty():
		desc = I18n.t("char_base")
	_section(I18n.t("char_detail_stats"), desc)
	_name_lbl.add_theme_color_override("font_color", accent)

# 锁没锁：[选他] 按钮的状态 + 锁住时在最前面挂一段"怎么解锁"。
# 摆在第一节的理由：玩家点进来第一眼就该知道"我差什么"，而不是先读完一页才被告知拿不到。
# Soulstone 的教训：把规则藏起来，玩家只会觉得这游戏莫名其妙。
func _lock_state() -> void:
	var open := SaveMgr.is_character_unlocked(_key)
	if not open:
		var info := SaveMgr.character_remaining(_key)
		var dep := str(info.get("char", ""))
		var who := I18n.pick(Data.character(dep)) if Data.characters.has(dep) else ""
		_section(UnlockText.title_locked(I18n.locale),
			UnlockText.sentence(info, who, I18n.locale))
	_pick_btn.text = I18n.t("char_detail_pick") if open else UnlockText.btn_locked(I18n.locale)
	_pick_btn.disabled = not open

# 「该买什么」：本命武器 + 羁绊（几件起效）+ 明确的配装建议
func _buy_text(entry: Dictionary) -> String:
	var parts := []
	var sig := entry.get("signature", {}) as Dictionary
	var sig_key := str(sig.get("key", ""))
	if sig_key != "":
		var need := []
		for t in (sig.get("tiers", []) as Array):
			need.append(str(int(t.get("need", 0))))
		parts.append(I18n.t("char_detail_sig") % [I18n.pick(Data.weapon(sig_key)), "/".join(need)])
	var bond := entry.get("bond", {}) as Dictionary
	var btag := str(bond.get("tag", ""))
	if btag != "":
		var bn := []
		for t in (bond.get("tiers", []) as Array):
			bn.append(str(int(t.get("need", 0))))
		parts.append(I18n.t("char_detail_bond") % [I18n.t("set_" + btag), "/".join(bn)])
	var best := _loc(entry, "best")
	if not best.is_empty():
		parts.append(best)
	return "\n".join(parts)

# 「该点什么技能」：角色自带的主动技能 + 它的作用说明
# skills_cfg() 是【数组】（每项含 id/zh/en/tip/tip_en），所以按 id 线性查找，别当字典 get。
func _skill_text(entry: Dictionary) -> String:
	var sid := SkillDef.skill_id_of(entry)
	if sid.is_empty():
		return ""
	for s in Data.skills_cfg():
		var sd := s as Dictionary
		if str(sd.get("id", "")) != sid:
			continue
		var tp := I18n.tip(sd)
		return I18n.pick(sd) if tp.is_empty() else I18n.pick(sd) + "：" + tp
	return I18n.t("skill_" + sid)

func _on_pick() -> void:
	if _key.is_empty() or _pick_btn.disabled:
		return
	Sfx.ui_click()
	picked.emit(_key)
	hide_page()

func _on_close() -> void:
	Sfx.ui_click()
	hide_page()
