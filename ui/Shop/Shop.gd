extends CanvasLayer

# 补给站：波次结束后弹出。手机竖屏单列：顶部金币/属性 → 我的武器(可售) → 购买卡 → 合成/刷新/下一波。
# 骨架与样式在 ShopPanel.gd（纯 UI）；卡片画法在 ShopCard.gd（哑组件）；
# 本文件只做业务：算报价 → 组装展示 → 接线购买/合成/售出 → 刷新。
#
# 节奏（core/ShopPlan.gd）：每 big_every 波开一次"大商店"（卡多 + 打折），其余波次只有
# 2 张卡快速选完；单卡可锁定（整店刷新时保留）/ 单独刷新（半价只换这一张）。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")
const ShopPanelScript := preload("res://ui/Shop/ShopPanel.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const ShopPlan := preload("res://core/ShopPlan.gd")

const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]

var _root: Control
var _panel: ShopPanelScript
var _offers: Array = []
var _reroll_times := 0
var _locked: Array = []        # 被锁定的卡位下标（整店刷新时保留）
var _card_count := 4          # 本场开了几张（大商店 6 / 小商店 2）
var _sold := []
var _rng := RandomNumberGenerator.new()
var _max_slot := 6
var _max_lv := 6

func _ready() -> void:
	layer = 30
	if OS.has_environment("SIM_SEED"):
		_rng.seed = int(OS.get_environment("SIM_SEED")) + 4
	else:
		_rng.randomize()
	_build()
	_root.visible = false
	ScreenMode.fit_overlay(_root)   # 横屏下把竖屏菜单缩放到 960x540 视口内、居中
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
	_panel = ShopPanelScript.new()
	_panel.build()
	_root.add_child(_panel)
	_panel.inv.sell_requested.connect(_sell)
	_panel.inv.merge_requested.connect(_merge_at)
	_panel.merge_btn.pressed.connect(_merge)
	_panel.reroll_btn.pressed.connect(_reroll_bought)
	_panel.next_btn.pressed.connect(_next_wave)
	for i in _panel.cards.size():
		var c: ShopCardScript = _panel.cards[i]
		c.on_click = _buy.bind(i)
		c.on_lock = _lock_toggle.bind(i)
		c.on_reroll_one = _reroll_one.bind(i)

func _open() -> void:
	_reroll_times = 0; _locked = []; _roll(); _root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_refresh()

func _roll() -> void:
	var cfg := Data.shop_cfg()
	_max_slot = int(cfg.get("max_slot", 6)); _max_lv = int(cfg.get("max_lv", 6))
	_card_count = clampi(ShopPlan.offer_count(GameState.wave, cfg), 1, _panel.cards.size())
	_offers = Economy.roll_offers(_pool_now(), _card_count, _rng)
	_sold = []; for i in _offers.size(): _sold.append(false)
	_panel.layout_cards(_offers.size())
	_refresh()

func _refresh() -> void:
	_panel.gold_lbl.text = I18n.t("shop_gold") % GameState.gold
	_refresh_stats()
	for i in _panel.cards.size():
		var c: ShopCardScript = _panel.cards[i]
		if i >= _offers.size(): c.visible = false; continue
		c.visible = true
		var o: Dictionary = _offers[i]
		var afford := Economy.can_buy(GameState.gold, int(o.get("cost", 0)))
		var d := _card_data(o, _sold[i], afford)
		# 单卡可控：锁 / 单张刷新（已售出的卡不给按钮）
		d["can_lock"] = not _sold[i]
		d["locked"] = _locked.has(i)
		d["reroll_one_cost"] = ShopPlan.single_reroll_cost(_reroll_times, Data.shop_cfg())
		c.setup(d)
	_panel.merge_btn.text = I18n.t("shop_merge_btn")
	_panel.merge_btn.disabled = not Inventory.has_mergeable(GameState.weapons, _max_lv)
	# 刷新按钮的文字一直没人设置过（截图目检才发现是空白按钮），补上 + 显示当前刷新价
	_panel.reroll_btn.text = I18n.t("shop_reroll") % Economy.reroll_cost(_reroll_times, Data.shop_cfg())
	# 槽位满了还刷不出新武器时，明确告诉玩家"先卖一把"——否则只会以为商店坏了；
	# 否则大商店亮出促销标识，让"攒钱这一波能大买"的节奏被看见。
	var cfg := Data.shop_cfg()
	if _slots_full():
		_panel.hint_lbl.text = I18n.t("shop_slots_full_hint")
	elif ShopPlan.is_big(GameState.wave, cfg):
		_panel.hint_lbl.text = I18n.t("shop_big_tag") % int(round(ShopPlan.discount(GameState.wave, cfg) * 100.0))
	else:
		_panel.hint_lbl.text = ""
	_panel.inv.refresh(GameState.weapons, _max_lv, _max_slot)

func _refresh_stats() -> void:
	if _panel == null or _panel.stats_lbl == null: return
	var spd := int(round(float(Data.player_cfg().get("speed", 180)) * (1.0 + GameState.stat_value("speed_pct"))))
	var g1 := "生命 %d   护甲 %d   移速 %d" % [GameState.max_hp, int(GameState.stat_value("armor")), spd]
	var g2 := "攻击 +%d%%   射速 +%d%%   范围 +%d%%   暴击 %d%%" % [
		int(GameState.stat_value("dmg_pct") * 100.0), int(GameState.stat_value("rate_pct") * 100.0),
		int(GameState.stat_value("range_pct") * 100.0), int(GameState.stat_value("crit_chance") * 100.0)]
	_panel.stats_lbl.text = g1 + "\n" + g2

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

# 购买（两态落法）：没满槽 → 单独占一格不自动合；满槽 → 同 key 同等级的那把直接合成升一级。
# 买入价记进 buy_cost 供售出退款；买不了（满槽且没有可合的搭档）时金币原路退回。
func _buy(index: int) -> void:
	if index >= _offers.size() or _sold[index]: return
	var o: Dictionary = _offers[index]; var cost := int(o.get("cost", 0))
	if not Economy.can_buy(GameState.gold, cost): _flash_card(index, false); return
	GameState.spend_gold(cost)
	var bought := false
	if str(o.get("kind", "")) == "weapon":
		bought = Inventory.buy_weapon(GameState.weapons, o, int(o.get("lv", 1)), cost,
			_max_slot, Data.combat_cfg(), _max_lv)
		if bought: Events.weapons_changed.emit(GameState.weapons)
		else: GameState.add_gold(cost)
	else:
		GameState.buy_upgrade(str(o.get("key", ""))); bought = true
	_sold[index] = bought; _refresh(); _flash_card(index, bought)

# 手动合成（点格子）：点第 idx 格 → 另一把"同 key 同等级"的武器被吸进来并消失、本格升一级
func _merge_at(index: int) -> void:
	if index < 0 or index >= GameState.weapons.size():
		return
	var w = GameState.weapons[index]
	if not (w is Dictionary):
		return
	var key := str(w.get("key", ""))
	var lv := int(w.get("lv", 1))
	if not Inventory.merge_into(GameState.weapons, index, _max_lv, Data.combat_cfg()):
		return
	Events.weapon_merged.emit(key, lv + 1)
	Events.weapons_changed.emit(GameState.weapons)
	_refresh()

# 一键合成：把场上所有"同 key 同等级"的对子全部合一级（懒人快捷方式，等价于逐格点）
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
	if index < 0 or index >= _panel.cards.size(): return
	var c: ShopCardScript = _panel.cards[index]
	c.modulate = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.45, 0.45)
	create_tween().tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

func _slots_full() -> bool:
	var n := 0
	for w in GameState.weapons:
		if int(w.get("lv", 1)) > 0:
			n += 1
	return n >= _max_slot

func _lock_toggle(index: int) -> void:
	if index >= _offers.size():
		return
	if _locked.has(index):
		_locked.erase(index)
	else:
		_locked.append(index)
	_refresh()

func _reroll_one(index: int) -> void:
	if index >= _offers.size() or _locked.has(index):
		return
	var cfg := Data.shop_cfg()
	var cost := ShopPlan.single_reroll_cost(_reroll_times, cfg)
	if not Economy.can_buy(GameState.gold, cost):
		return
	var pool := _pool_now()
	GameState.spend_gold(cost); _reroll_times += 1
	_offers = ShopPlan.reroll_one(_offers, index, pool, _rng)
	_sold[index] = false
	_refresh()

func _pool_now() -> Array:
	var cfg := Data.shop_cfg()
	var infl := float(cfg.get("price_inflation", 0.0))
	var disc := GameState.stat_value("shop_discount") + ShopPlan.discount(GameState.wave, cfg)
	return Economy.build_pool(GameState.weapons, Data.weapons, Data.upgrades,
		_max_slot, _max_lv, SaveMgr.unlocked_weapons(), disc, GameState.wave, infl)

# 整店刷新：锁定的卡保留
func _reroll_bought() -> void:
	var cfg := Data.shop_cfg(); var cost := Economy.reroll_cost(_reroll_times, cfg)
	if not Economy.can_buy(GameState.gold, cost): return
	GameState.spend_gold(cost); _reroll_times += 1
	if _locked.is_empty():
		_roll()
	else:
		_offers = ShopPlan.reroll_keep(_offers, _locked, _pool_now(), _card_count, _rng)
		_sold = []; for i in _offers.size(): _sold.append(false)
		_refresh()

func _next_wave() -> void:
	_root.visible = false; Events.shop_closed.emit()
