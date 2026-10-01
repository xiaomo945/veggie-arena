extends CanvasLayer

# 补给站：波次结束后弹出，4 张卡 + 刷新 + 下一波。
# 手机竖屏：卡片竖排单列，按钮高度 ≥ 56px（拇指点得中）。
# 卡片的"怎么画"全部交给 ShopCard（哑组件），本文件只做：算报价 → 组装展示数据
# → 接线购买 → 刷新。架构上把"视图"与"流程"分开，单文件不会随功能膨胀到 300 行红线。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")

const PANEL_W := 496.0
const CARD_H := 118.0
const CARD_GAP := 10.0

# §8.4 道具稀有度边框配色
const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]

var _root: Control
var _panel: Panel
var _gold_lbl: Label
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

	# 遮罩
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	_root.add_child(shade)

	# 面板（圆角深色底，卡片叠在上面）
	_panel = Panel.new()
	_panel.set_size(Vector2(PANEL_W, 700))
	_panel.set_position(Vector2((540 - PANEL_W) * 0.5, 100))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	sb.set_corner_radius_all(16)
	sb.border_color = Color(0.30, 0.33, 0.40, 0.9)
	sb.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)

	var title := Label.new()
	title.text = I18n.t("shop_title")
	title.set_position(Vector2(20, 16))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	_panel.add_child(title)

	_gold_lbl = Label.new()
	_gold_lbl.set_position(Vector2(300, 20))
	_gold_lbl.add_theme_font_size_override("font_size", 18)
	_gold_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	_panel.add_child(_gold_lbl)

	var gold_coin := TextureRect.new()
	gold_coin.texture = Art.ui_icon("coin")
	gold_coin.set_size(Vector2(24, 24))
	gold_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_coin.set_position(Vector2(268, 20))
	_panel.add_child(gold_coin)

	var y := 64.0
	for i in 4:
		var card = ShopCardScript.new()
		card.set_size(Vector2(PANEL_W - 28, CARD_H))
		card.set_position(Vector2(14, y))
		card.on_click = _buy.bind(i)
		_panel.add_child(card)
		_cards.append(card)
		y += CARD_H + CARD_GAP

	var by := y + 8.0
	_reroll_btn = Button.new()
	_reroll_btn.set_size(Vector2(200, 58))
	_reroll_btn.set_position(Vector2(14, by))
	_reroll_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(_reroll_btn, Color(0.20, 0.24, 0.32), Color(0.45, 0.75, 0.40))
	_reroll_btn.pressed.connect(_reroll_bought)
	_panel.add_child(_reroll_btn)

	_next_btn = Button.new()
	_next_btn.set_size(Vector2(262, 58))
	_next_btn.set_position(Vector2(228, by))
	_next_btn.text = I18n.t("shop_next")
	_next_btn.add_theme_font_size_override("font_size", 19)
	_style_btn(_next_btn, Color(0.98, 0.86, 0.32), Color(0.07, 0.08, 0.05))
	_next_btn.pressed.connect(_next_wave)
	_panel.add_child(_next_btn)

func _style_btn(b: Button, bg: Color, fg: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(12)
	n.border_color = Color(0.72, 0.60, 0.16)
	n.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat
	hov.bg_color = bg.lightened(0.12)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_color_override("font_color", fg)

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
	# 只卖已解锁的武器（未解锁的根本不进池子）；讲价道具打折已在 build_pool 里结算
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades,
		_max_slot, _max_lv, SaveMgr.unlocked_weapons(), GameState.stat_value("shop_discount"))
	_offers = Economy.roll_offers(pool, int(cfg.get("offer_count", 4)), _rng)
	_sold = []
	for i in _offers.size():
		_sold.append(false)
	_refresh()

func _refresh() -> void:
	_gold_lbl.text = I18n.t("shop_gold") % GameState.gold
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

# 组装单卡展示数据：名称 / 描述 / 价格 / 主色 / 等级角标 / 稀有度 / 状态标签
func _card_data(o: Dictionary, sold: bool, afford: bool) -> Dictionary:
	var kind := str(o.get("kind", ""))
	var key := str(o.get("key", ""))
	var def: Dictionary = Data.weapon(key) if kind == "weapon" else Data.upgrade(key)
	var name := I18n.pick(def)
	var tip := I18n.tip(def)
	var cost := int(o.get("cost", 0))
	var d: Dictionary = {
		"kind": kind, "name": name, "tip": tip, "cost": cost,
		"affordable": afford, "sold": sold, "disabled": false, "icon": null,
	}
	if kind == "weapon":
		var accent := Color(str(def.get("color", "#ffffff")))
		var owned := _owned_lv(key)
		var result_lv := owned + 1 if owned > 0 else 1
		d["accent"] = accent
		d["lv"] = result_lv
		d["icon"] = Art.icon("weapon_" + key)
		d["tag"] = I18n.t("shop_merge") if owned > 0 else I18n.t("shop_new")
		d["disabled"] = not Inventory.can_accept(GameState.weapons, key, _max_slot, _max_lv)
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
	var tw := create_tween()
	tw.tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

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
