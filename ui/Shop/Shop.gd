extends CanvasLayer

# 补给站：波次结束后弹出，4 张卡 + 刷新 + 下一波。
# 手机竖屏：卡片竖排单列，按钮高度 ≥ 56px（拇指点得中）。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")

const PANEL_W := 496.0
const CARD_H := 104.0
const CARD_GAP := 10.0

var _root: Control
var _gold_lbl: Label
var _cards: Array = []
var _reroll_btn: Button
var _next_btn: Button
var _offers: Array = []
var _reroll_times := 0
var _sold := []
var _rng := RandomNumberGenerator.new()

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

	var panel := PanelContainer.new()
	panel.set_size(Vector2(PANEL_W, 700))
	panel.set_position(Vector2((540 - PANEL_W) * 0.5, 100))
	_root.add_child(panel)

	var title := Label.new()
	title.text = I18n.t("shop_title")
	title.set_position(Vector2(20, 14))
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)

	_gold_lbl = Label.new()
	_gold_lbl.set_position(Vector2(300, 18))
	_gold_lbl.add_theme_font_size_override("font_size", 18)
	_gold_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	panel.add_child(_gold_lbl)

	# 装饰：金币计数左侧的硬币图标
	var gold_coin := TextureRect.new()
	gold_coin.texture = Art.ui_icon("coin")
	gold_coin.custom_minimum_size = Vector2(28, 28)
	gold_coin.set_size(Vector2(24, 24))
	gold_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_coin.set_position(Vector2(268, 19))
	panel.add_child(gold_coin)

	var y := 52.0
	for i in 4:
		var b := Button.new()
		b.set_size(Vector2(PANEL_W - 28, CARD_H))
		b.set_position(Vector2(14, y))
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_buy.bind(i))
		panel.add_child(b)
		_cards.append(b)
		# 装饰：卡片右下角价格数字旁的硬币图标
		var coin := TextureRect.new()
		coin.texture = Art.ui_icon("coin")
		coin.custom_minimum_size = Vector2(28, 28)
		coin.set_size(Vector2(26, 26))
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.set_position(Vector2(PANEL_W - 46, y + CARD_H - 34))
		panel.add_child(coin)
		y += CARD_H + CARD_GAP

	_reroll_btn = Button.new()
	_reroll_btn.set_size(Vector2(200, 58))
	_reroll_btn.set_position(Vector2(14, y + 6))
	_reroll_btn.add_theme_font_size_override("font_size", 17)
	_reroll_btn.pressed.connect(_reroll_bought)
	panel.add_child(_reroll_btn)

	_next_btn = Button.new()
	_next_btn.set_size(Vector2(262, 58))
	_next_btn.set_position(Vector2(228, y + 6))
	_next_btn.text = I18n.t("shop_next")
	_next_btn.add_theme_font_size_override("font_size", 19)
	_next_btn.pressed.connect(_next_wave)
	panel.add_child(_next_btn)

func _open() -> void:
	_reroll_times = 0
	_roll()
	_root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_refresh()

func _roll() -> void:
	var cfg := Data.shop_cfg()
	# 只卖已解锁的武器（未解锁的根本不进池子）
	var pool := Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades,
		int(cfg.get("max_slot", 6)), int(cfg.get("max_lv", 4)),
		SaveMgr.unlocked_weapons())
	_offers = Economy.roll_offers(pool, int(cfg.get("offer_count", 4)), _rng)
	_sold = []
	for i in _offers.size():
		_sold.append(false)
	_refresh()

func _refresh() -> void:
	_gold_lbl.text = I18n.t("shop_gold") % GameState.gold
	var cfg := Data.shop_cfg()
	for i in _cards.size():
		var b: Button = _cards[i]
		if i >= _offers.size():
			b.visible = false
			continue
		b.visible = true
		var o: Dictionary = _offers[i]
		var cost := int(o.get("cost", 0))
		var name := I18n.pick(o)
		var tip := I18n.tip(o)
		var kind := str(o.get("kind", ""))
		var tag := I18n.t("shop_weapon") if kind == "weapon" else I18n.t("shop_upgrade")
		if _sold[i]:
			b.text = "[%s] %s\n%s" % [tag, name, I18n.t("shop_sold")]
			b.disabled = true
			continue
		b.text = "[%s] %s\n%s\n%d %s" % [tag, name, tip, cost, I18n.t("shop_gold_unit")]
		b.disabled = not Economy.can_buy(GameState.gold, cost)
	_reroll_btn.text = I18n.t("shop_reroll") % Economy.reroll_cost(_reroll_times, cfg)
	_reroll_btn.disabled = not Economy.can_buy(GameState.gold, Economy.reroll_cost(_reroll_times, cfg))

func _buy(index: int) -> void:
	if index >= _offers.size() or _sold[index]:
		return
	var o: Dictionary = _offers[index]
	var cost := int(o.get("cost", 0))
	if not Economy.can_buy(GameState.gold, cost):
		return
	GameState.spend_gold(cost)
	if str(o.get("kind", "")) == "weapon":
		# merge_or_add 是原地修改数组并返回"是否成功"，不是返回新数组
		var cfg := Data.shop_cfg()
		var ok := Inventory.merge_or_add(GameState.weapons, o,
			int(cfg.get("max_slot", 6)), int(cfg.get("max_lv", 4)), Data.combat_cfg())
		if ok:
			Events.weapons_changed.emit(GameState.weapons)
		else:
			GameState.add_gold(cost)   # 买不了就把钱退回去，别白扣
	else:
		GameState.buy_upgrade(str(o.get("key", "")))
	_sold[index] = true
	_refresh()

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
