extends CanvasLayer

# 补给站：波次结束后弹出。手机竖屏单列：顶部金币/属性 → 我的武器(可售) → 4 张购买卡 → 合成/刷新/下一波。
# 卡片画法交给 ShopCard（哑组件）；本文件只做：算报价 → 组装展示 → 接线购买/合成/售出 → 刷新。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const InventoryPanelScript := preload("res://ui/Shop/InventoryPanel.gd")

const PANEL_W := 496.0
const PANEL_H := 762.0
const CARD_H := 110.0
const CARD_GAP := 8.0

const GOLD := Color(0.99, 0.87, 0.40)
const GOLD_DK := Color(0.80, 0.60, 0.26)
const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]

var _root: Control
var _panel: Panel
var _gold_lbl: Label
var _stats_lbl: Label
var _cards: Array = []
var _reroll_btn: Button
var _next_btn: Button
var _merge_btn: Button
var _inv: Control
var _offers: Array = []
var _reroll_times := 0
var _sold := []
var _rng := RandomNumberGenerator.new()
var _max_slot := 6
var _max_lv := 4

func _ready() -> void:
	layer = 30
	_rng.randomize()
	_build()
	_root.visible = false
	Events.shop_opened.connect(_open)
	I18n.locale_changed.connect(_on_locale_changed)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	_root.add_child(shade)
	_panel = Panel.new()
	_panel.set_size(Vector2(PANEL_W, PANEL_H))
	_panel.set_position(Vector2((540 - PANEL_W) * 0.5, (900 - PANEL_H) * 0.5))
	_panel.add_theme_stylebox_override("panel", _flat_box(Color(0.14, 0.10, 0.07, 0.985), GOLD_DK, 18))
	_root.add_child(_panel)
	_panel.add_child(_coin_rect(Vector2(18, 16), 30))
	var title := Label.new()
	title.text = I18n.t("shop_title")
	title.set_position(Vector2(58, 17))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", GOLD)
	_panel.add_child(title)
	var pill := Panel.new()
	pill.set_size(Vector2(152, 38)); pill.set_position(Vector2(PANEL_W - 166, 12))
	pill.add_theme_stylebox_override("panel", _flat_box(Color(0.30, 0.21, 0.06, 0.95), Color(0.85, 0.66, 0.22), 19))
	_panel.add_child(pill)
	pill.add_child(_coin_rect(Vector2(7, 6), 26))
	_gold_lbl = Label.new(); _gold_lbl.set_position(Vector2(40, 5))
	_gold_lbl.add_theme_font_size_override("font_size", 19)
	_gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50))
	pill.add_child(_gold_lbl)
	# 基础属性名牌
	var stats_bg := Panel.new()
	stats_bg.set_size(Vector2(PANEL_W - 28, 48)); stats_bg.set_position(Vector2(14, 60))
	stats_bg.add_theme_stylebox_override("panel", _flat_box(Color(0.20, 0.16, 0.09, 0.92), Color(0.42, 0.34, 0.18, 0.9), 10))
	_panel.add_child(stats_bg)
	_stats_lbl = Label.new(); _stats_lbl.set_size(Vector2(PANEL_W - 40, 44)); _stats_lbl.set_position(Vector2(22, 64))
	_stats_lbl.add_theme_font_size_override("font_size", 13)
	_stats_lbl.add_theme_color_override("font_color", Color(0.62, 0.90, 0.63))
	_panel.add_child(_stats_lbl)
	# 我的武器（可售出）面板
	_inv = InventoryPanelScript.new()
	_inv.set_size(Vector2(PANEL_W - 28, 78)); _inv.set_position(Vector2(14, 112))
	_inv.sell_requested.connect(_sell)
	_panel.add_child(_inv)
	# 4 张购买卡
	var y := 200.0
	for i in 4:
		var card = ShopCardScript.new()
		card.set_size(Vector2(PANEL_W - 28, CARD_H)); card.set_position(Vector2(14, y))
		card.on_click = _buy.bind(i)
		_panel.add_child(card); _cards.append(card)
		y += CARD_H + CARD_GAP
	# 底部按钮：合成（橙，可合并时点亮）/ 刷新（绿）/ 下一波（金）
	var by := 674.0
	_merge_btn = Button.new(); _merge_btn.set_size(Vector2(126, 58)); _merge_btn.set_position(Vector2(14, by))
	_merge_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(_merge_btn, Color(0.95, 0.62, 0.16), Color(0.22, 0.13, 0.03), Color(0.86, 0.56, 0.14))
	_merge_btn.pressed.connect(_merge); _panel.add_child(_merge_btn)
	_reroll_btn = Button.new(); _reroll_btn.set_size(Vector2(144, 58)); _reroll_btn.set_position(Vector2(146, by))
	_reroll_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(_reroll_btn, Color(0.24, 0.33, 0.18), Color(0.74, 0.91, 0.54), Color(0.48, 0.64, 0.32))
	_reroll_btn.pressed.connect(_reroll_bought); _panel.add_child(_reroll_btn)
	_next_btn = Button.new(); _next_btn.set_size(Vector2(180, 58)); _next_btn.set_position(Vector2(296, by))
	_next_btn.text = I18n.t("shop_next"); _next_btn.add_theme_font_size_override("font_size", 19)
	_style_btn(_next_btn, Color(0.98, 0.80, 0.22), Color(0.24, 0.15, 0.04), Color(0.88, 0.66, 0.16))
	_next_btn.pressed.connect(_next_wave); _panel.add_child(_next_btn)

func _flat_box(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.set_corner_radius_all(int(radius)); sb.border_color = border; sb.set_border_width_all(2)
	return sb

func _coin_rect(pos: Vector2, sz: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Art.coin_icon(); tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.set_size(Vector2(sz, sz)); tr.set_position(pos)
	return tr

func _style_btn(b: Button, bg: Color, fg: Color, border: Color) -> void:
	var n := _flat_box(bg, border, 14); n.shadow_color = Color(0, 0, 0, 0.35); n.shadow_size = 4; n.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat; hov.bg_color = bg.lightened(0.12); b.add_theme_stylebox_override("hover", hov)
	var pre := n.duplicate() as StyleBoxFlat; pre.bg_color = bg.darkened(0.15); b.add_theme_stylebox_override("pressed", pre)
	var dis := n.duplicate() as StyleBoxFlat; dis.bg_color = bg.darkened(0.45); b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg); b.add_theme_color_override("font_disabled_color", Color(fg, 0.45))

func _open() -> void:
	_reroll_times = 0; _roll(); _root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_refresh()

func _roll() -> void:
	var cfg := Data.shop_cfg()
	_max_slot = int(cfg.get("max_slot", 6)); _max_lv = int(cfg.get("max_lv", 4))
	var infl := float(cfg.get("price_inflation", 0.0))
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades,
		_max_slot, _max_lv, SaveMgr.unlocked_weapons(), GameState.stat_value("shop_discount"),
		GameState.wave, infl)
	_offers = Economy.roll_offers(pool, int(cfg.get("offer_count", 4)), _rng)
	_sold = []; for i in _offers.size(): _sold.append(false)
	_refresh()

func _refresh() -> void:
	_gold_lbl.text = I18n.t("shop_gold") % GameState.gold
	_refresh_stats()
	for i in _cards.size():
		var c: ShopCardScript = _cards[i]
		if i >= _offers.size(): c.visible = false; continue
		c.visible = true
		var o: Dictionary = _offers[i]
		var afford := Economy.can_buy(GameState.gold, int(o.get("cost", 0)))
		c.setup(_card_data(o, _sold[i], afford))
	_merge_btn.text = I18n.t("shop_merge_btn")
	_merge_btn.disabled = not Inventory.has_mergeable(GameState.weapons, _max_lv)
	_inv.refresh(GameState.weapons, _max_lv)

func _refresh_stats() -> void:
	if _stats_lbl == null: return
	var spd := int(round(float(Data.player_cfg().get("speed", 180)) * (1.0 + GameState.stat_value("speed_pct"))))
	var g1 := "生命 %d   护甲 %d   移速 %d" % [GameState.max_hp, int(GameState.stat_value("armor")), spd]
	var g2 := "攻击 +%d%%   射速 +%d%%   范围 +%d%%   暴击 %d%%" % [
		int(GameState.stat_value("dmg_pct") * 100.0), int(GameState.stat_value("rate_pct") * 100.0),
		int(GameState.stat_value("range_pct") * 100.0), int(GameState.stat_value("crit_chance") * 100.0)]
	_stats_lbl.text = g1 + "\n" + g2

func _card_data(o: Dictionary, sold: bool, afford: bool) -> Dictionary:
	var kind := str(o.get("kind", "")); var key := str(o.get("key", ""))
	var def: Dictionary = Data.weapon(key) if kind == "weapon" else Data.upgrade(key)
	var cost := int(o.get("cost", 0))
	var base_cost := int(o.get("base_cost", cost))
	var inflated := cost > base_cost
	var infl_pct := 0
	if base_cost > 0 and inflated: infl_pct = int(round(float(cost - base_cost) / float(base_cost) * 100.0))
	var d: Dictionary = {"kind": kind, "name": I18n.pick(def), "tip": I18n.tip(def), "cost": cost,
		"affordable": afford, "sold": sold, "disabled": false, "icon": null,
		"base_cost": base_cost, "inflated": inflated, "infl_pct": infl_pct}
	if kind == "weapon":
		var lv := int(o.get("lv", 1))
		d["accent"] = ShopTiers.new().tier_color(lv)
		d["lv"] = lv; d["icon"] = Art.icon("weapon_" + key)
		d["tag"] = I18n.t("shop_merge") if _owned_lv(key) > 0 else I18n.t("shop_new")
		d["disabled"] = not Inventory.can_accept_tier(GameState.weapons, key, lv, _max_slot, _max_lv)
	else:
		var rar := clampi(int(def.get("rarity", 1)), 1, 3)
		d["accent"] = RARITY_COLORS[rar - 1]; d["rarity"] = rar; d["tag"] = I18n.t("shop_upgrade")
	return d

func _owned_lv(key: String) -> int:
	return Inventory.owned_max_lv(GameState.weapons, key)

# 购买：落一把独立成品占一个槽（不自动合成），买入价记进 buy_cost 供售出退款
func _buy(index: int) -> void:
	if index >= _offers.size() or _sold[index]: return
	var o: Dictionary = _offers[index]; var cost := int(o.get("cost", 0))
	if not Economy.can_buy(GameState.gold, cost): _flash_card(index, false); return
	GameState.spend_gold(cost)
	var bought := false
	if str(o.get("kind", "")) == "weapon":
		bought = Inventory.buy_weapon(GameState.weapons, o, int(o.get("lv", 1)), cost, _max_slot, Data.combat_cfg())
		if bought: Events.weapons_changed.emit(GameState.weapons)
		else: GameState.add_gold(cost)
	else:
		GameState.buy_upgrade(str(o.get("key", ""))); bought = true
	_sold[index] = bought; _refresh(); _flash_card(index, bought)

# 手动合成：把场上所有"同 key 同等级"的两把合一级（玩家长按 Brotato 式格子合成）
func _merge() -> void:
	var done := Inventory.merge_pairs(GameState.weapons, _max_lv, Data.combat_cfg())
	for m in done: Events.weapon_merged.emit(m.get("key", ""), int(m.get("lv", 1)))
	if done.size() > 0: Events.weapons_changed.emit(GameState.weapons)
	_refresh()

# 售出：回收价 ≤ 买入价（默认 80%），钱原路退回，并腾出一个槽
func _sell(index: int) -> void:
	var gain := Inventory.sell_weapon(GameState.weapons, index, ShopTiers.new().sell_ratio())
	if gain > 0:
		GameState.add_gold(gain)
		Events.weapons_changed.emit(GameState.weapons)
	_refresh()

func _flash_card(index: int, ok: bool) -> void:
	if index < 0 or index >= _cards.size(): return
	var c: ShopCardScript = _cards[index]
	c.modulate = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.45, 0.45)
	create_tween().tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

func _reroll_bought() -> void:
	var cfg := Data.shop_cfg(); var cost := Economy.reroll_cost(_reroll_times, cfg)
	if not Economy.can_buy(GameState.gold, cost): return
	GameState.spend_gold(cost); _reroll_times += 1; _roll()

func _next_wave() -> void:
	_root.visible = false; Events.shop_closed.emit()
