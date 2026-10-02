extends CanvasLayer

# 补给站：波次结束后弹出，4 张卡 + 刷新 + 下一波。手机竖屏卡片竖排单列，按钮 ≥56px。
# 卡片画法交给 ShopCard（哑组件）；本文件只做：算报价 → 组装展示 → 接线购买 → 刷新。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")

const PANEL_W := 496.0
const PANEL_H := 732.0
const CARD_H := 118.0
const CARD_GAP := 11.0

const GOLD := Color(0.99, 0.87, 0.40)
const GOLD_DK := Color(0.80, 0.60, 0.26)

# §8.4 道具稀有度边框配色
const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]

var _root: Control
var _panel: Panel
var _gold_lbl: Label
var _stats_lbl: Label
var _cards: Array = []
var _reroll_btn: Button
var _next_btn: Button
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

	# 圆角深棕底 + 金描边，卡片叠在上面
	_panel = Panel.new()
	_panel.set_size(Vector2(PANEL_W, PANEL_H))
	_panel.set_position(Vector2((540 - PANEL_W) * 0.5, (900 - PANEL_H) * 0.5))
	var sb := _flat_box(Color(0.14, 0.10, 0.07, 0.985), GOLD_DK, 18)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)

	_panel.add_child(_coin_rect(Vector2(18, 16), 30))
	var title := Label.new()
	title.text = I18n.t("shop_title")
	title.set_position(Vector2(58, 17))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", GOLD)
	_panel.add_child(title)

	var pill := Panel.new()
	pill.set_size(Vector2(152, 38))
	pill.set_position(Vector2(PANEL_W - 166, 12))
	pill.add_theme_stylebox_override("panel",
		_flat_box(Color(0.30, 0.21, 0.06, 0.95), Color(0.85, 0.66, 0.22), 19))
	_panel.add_child(pill)
	pill.add_child(_coin_rect(Vector2(7, 6), 26))
	_gold_lbl = Label.new()
	_gold_lbl.set_position(Vector2(40, 5))
	_gold_lbl.add_theme_font_size_override("font_size", 19)
	_gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50))
	pill.add_child(_gold_lbl)

	# 基础属性名牌（参照 Brotato）：属性名用绿色，看清"买什么能提升什么"
	var stats_bg := Panel.new()
	stats_bg.set_size(Vector2(PANEL_W - 28, 56))
	stats_bg.set_position(Vector2(14, 60))
	stats_bg.add_theme_stylebox_override("panel",
		_flat_box(Color(0.20, 0.16, 0.09, 0.92), Color(0.42, 0.34, 0.18, 0.9), 10))
	_panel.add_child(stats_bg)
	_stats_lbl = Label.new()
	_stats_lbl.set_size(Vector2(PANEL_W - 40, 52))
	_stats_lbl.set_position(Vector2(22, 64))
	_stats_lbl.add_theme_font_size_override("font_size", 13)
	_stats_lbl.add_theme_color_override("font_color", Color(0.62, 0.90, 0.63))
	_panel.add_child(_stats_lbl)
	var y := 128.0
	for i in 4:
		var card = ShopCardScript.new()
		card.set_size(Vector2(PANEL_W - 28, CARD_H))
		card.set_position(Vector2(14, y))
		card.on_click = _buy.bind(i)
		_panel.add_child(card)
		_cards.append(card)
		y += CARD_H + CARD_GAP

	# 底部按钮：刷新（绿，次要）+ 下一波（金，主要）
	var by := y + 10.0
	_reroll_btn = Button.new()
	_reroll_btn.set_size(Vector2(186, 62))
	_reroll_btn.set_position(Vector2(14, by))
	_reroll_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(_reroll_btn, Color(0.24, 0.33, 0.18), Color(0.74, 0.91, 0.54), Color(0.48, 0.64, 0.32))
	_reroll_btn.pressed.connect(_reroll_bought)
	_panel.add_child(_reroll_btn)

	_next_btn = Button.new()
	_next_btn.set_size(Vector2(272, 62))
	_next_btn.set_position(Vector2(210, by))
	_next_btn.text = I18n.t("shop_next")
	_next_btn.add_theme_font_size_override("font_size", 20)
	_style_btn(_next_btn, Color(0.98, 0.80, 0.22), Color(0.24, 0.15, 0.04), Color(0.88, 0.66, 0.16))
	_next_btn.pressed.connect(_next_wave)
	_panel.add_child(_next_btn)

# 小工具：统一的暖色圆角盒（卡通金币图标走 Art.coin_icon）
func _flat_box(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	sb.border_color = border
	sb.set_border_width_all(2)
	return sb

func _coin_rect(pos: Vector2, sz: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Art.coin_icon()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_size(Vector2(sz, sz))
	tr.set_position(pos)
	return tr

func _style_btn(b: Button, bg: Color, fg: Color, border: Color) -> void:
	var n := _flat_box(bg, border, 14)
	n.shadow_color = Color(0, 0, 0, 0.35)
	n.shadow_size = 4
	n.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat
	hov.bg_color = bg.lightened(0.12)
	b.add_theme_stylebox_override("hover", hov)
	var pre := n.duplicate() as StyleBoxFlat
	pre.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("pressed", pre)
	var dis := n.duplicate() as StyleBoxFlat
	dis.bg_color = bg.darkened(0.45)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.45))

func _open() -> void:
	_reroll_times = 0
	_roll()
	_root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_refresh()

func _roll() -> void:
	var cfg := Data.shop_cfg()
	_max_slot = int(cfg.get("max_slot", 6))
	_max_lv = int(cfg.get("max_lv", 4))
	# 只卖已解锁的武器（未解锁的根本不进池子）；讲价打折 + 波次通胀都在 build_pool 里结算
	var infl := float(cfg.get("price_inflation", 0.0))
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades,
		_max_slot, _max_lv, SaveMgr.unlocked_weapons(), GameState.stat_value("shop_discount"),
		GameState.wave, infl)
	_offers = Economy.roll_offers(pool, int(cfg.get("offer_count", 4)), _rng)
	_sold = []
	for i in _offers.size():
		_sold.append(false)
	_refresh()

func _refresh() -> void:
	_gold_lbl.text = I18n.t("shop_gold") % GameState.gold
	_refresh_stats()
	for i in _cards.size():
		var c: ShopCardScript = _cards[i]
		if i >= _offers.size():
			c.visible = false
			continue
		c.visible = true
		var o: Dictionary = _offers[i]
		var cost := int(o.get("cost", 0))
		var afford := Economy.can_buy(GameState.gold, cost)
		c.setup(_card_data(o, _sold[i], afford))
	_reroll_btn.text = I18n.t("shop_reroll") % Economy.reroll_cost(_reroll_times, Data.shop_cfg())
	_reroll_btn.disabled = not Economy.can_buy(GameState.gold, Economy.reroll_cost(_reroll_times, Data.shop_cfg()))

# 基础属性名牌：当前局的派生属性（生命/护甲/移速/攻击/射速/范围/暴击），绿色更显眼
func _refresh_stats() -> void:
	if _stats_lbl == null:
		return
	var spd := int(round(float(Data.player_cfg().get("speed", 180)) * (1.0 + GameState.stat_value("speed_pct"))))
	var g1 := "生命 %d   护甲 %d   移速 %d" % [
		GameState.max_hp, int(GameState.stat_value("armor")), spd]
	var g2 := "攻击 +%d%%   射速 +%d%%   范围 +%d%%   暴击 %d%%" % [
		int(GameState.stat_value("dmg_pct") * 100.0),
		int(GameState.stat_value("rate_pct") * 100.0),
		int(GameState.stat_value("range_pct") * 100.0),
		int(GameState.stat_value("crit_chance") * 100.0)]
	_stats_lbl.text = g1 + "\n" + g2

# 组装单卡展示数据：名称 / 描述 / 价格 / 主色 / 等级角标 / 稀有度 / 状态标签
func _card_data(o: Dictionary, sold: bool, afford: bool) -> Dictionary:
	var kind := str(o.get("kind", ""))
	var key := str(o.get("key", ""))
	var def: Dictionary = Data.weapon(key) if kind == "weapon" else Data.upgrade(key)
	var name := I18n.pick(def)
	var tip := I18n.tip(def)
	var cost := int(o.get("cost", 0))
	# 基础价（该档位的 1 级等价原价，未计通胀/打折）用于画"涨 N%"角标
	var base_cost := int(o.get("base_cost", cost))
	var inflated := cost > base_cost
	var infl_pct := 0
	if base_cost > 0 and inflated:
		infl_pct = int(round(float(cost - base_cost) / float(base_cost) * 100.0))
	var d: Dictionary = {
		"kind": kind, "name": name, "tip": tip, "cost": cost,
		"affordable": afford, "sold": sold, "disabled": false, "icon": null,
		"base_cost": base_cost, "inflated": inflated, "infl_pct": infl_pct,
	}
	if kind == "weapon":
		# 武器主色 = 分级配色（白1/绿2/蓝3/紫4/红5/传说6），不再是每把武器各一种颜色
		var lv := int(o.get("lv", 1))
		var accent := ShopTiers.new().tier_color(lv)
		var owned := _owned_lv(key)
		d["accent"] = accent
		d["lv"] = lv
		d["icon"] = Art.icon("weapon_" + key)
		d["tag"] = I18n.t("shop_merge") if owned > 0 else I18n.t("shop_new")
		d["disabled"] = not Inventory.can_accept_tier(GameState.weapons, key, lv, _max_slot, _max_lv)
	else:
		var rar := clampi(int(def.get("rarity", 1)), 1, 3)
		d["accent"] = RARITY_COLORS[rar - 1]
		d["rarity"] = rar
		d["tag"] = I18n.t("shop_upgrade")
	return d

func _owned_lv(key: String) -> int:
	for w in GameState.weapons:
		if w is Dictionary and str(w.get("key", "")) == key:
			return int(w.get("lv", 1))
	return 0

func _buy(index: int) -> void:
	if index >= _offers.size() or _sold[index]:
		return
	var o: Dictionary = _offers[index]
	var cost := int(o.get("cost", 0))
	if not Economy.can_buy(GameState.gold, cost):
		_flash_card(index, false)   # 金币不足：红闪提示
		return
	GameState.spend_gold(cost)
	var bought := true
	if str(o.get("kind", "")) == "weapon":
		# merge_or_add 是原地修改数组并返回"是否成功"，不是返回新数组
		var ok := Inventory.merge_or_add(GameState.weapons, o, _max_slot, _max_lv, Data.combat_cfg())
		if ok:
			Events.weapons_changed.emit(GameState.weapons)
		else:
			GameState.add_gold(cost)   # 买不了就把钱退回去，别白扣
			bought = false
	else:
		GameState.buy_upgrade(str(o.get("key", "")))
	_sold[index] = bought
	_refresh()
	_flash_card(index, bought)     # 买入成功绿闪 / 失败红闪

# 买入反馈：卡片短暂染色后恢复（绿=成功，红=失败/金币不足）
func _flash_card(index: int, ok: bool) -> void:
	if index < 0 or index >= _cards.size():
		return
	var c: ShopCardScript = _cards[index]
	c.modulate = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.45, 0.45)
	create_tween().tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

func _reroll_bought() -> void:
	var cfg := Data.shop_cfg()
	var cost := Economy.reroll_cost(_reroll_times, cfg)
	if not Economy.can_buy(GameState.gold, cost):
		return
	GameState.spend_gold(cost)
	_reroll_times += 1
	_roll()

func _next_wave() -> void:
	_root.visible = false
	Events.shop_closed.emit()
