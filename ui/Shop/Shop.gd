extends CanvasLayer

# 补给站：波次结束后弹出。手机竖屏单列：顶部金币/属性 → 我的武器(可售) → 购买卡 → 合成/刷新/下一波。
# 骨架与样式在 ShopPanel.gd；卡片画法在 ShopCard.gd；本文件只做业务。节奏（core/ShopPlan.gd）：
# 每 big_every 波开一次"大商店"（全场打折）。⚠️ 卡数不随波次变：每波固定开满 6 张、不留空位（硬要求）。

const Economy := preload("res://core/Economy.gd")
const Inventory := preload("res://core/Inventory.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")
const ShopPanelScript := preload("res://ui/Shop/ShopPanel.gd")
const ShopTiers := preload("res://core/ShopTiers.gd")
const ShopPlan := preload("res://core/ShopPlan.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")
const Weapon := preload("res://core/Weapon.gd")
const ShopCardSyn := preload("res://ui/Shop/ShopCardSyn.gd")
const ShopSetProgress := preload("res://ui/Shop/ShopSetProgress.gd")
const Stats := preload("res://core/Stats.gd")
const ItemIcons := preload("res://core/ItemIcons.gd")
const SellUndo := preload("res://ui/Shop/SellUndo.gd")
const ShopOfferDetailScript := preload("res://ui/Shop/ShopOfferDetail.gd")

const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]

var _root: Control
var _panel: ShopPanelScript
var _offers: Array = []
var _reroll_times := 0
var _locked: Array = []        # 被锁定的卡位下标（整店刷新时保留）
var _card_count := 6          # 本场开了几张（每波固定 6，见 ShopPlan.offer_count）
var _sold := []
var _rng := RandomNumberGenerator.new()
var _max_slot := 6
var _max_lv := 6
var _undo := SellUndo.new(); var _undo_btn: Button = null   # 卖出撤销（点错了可恢复）
var _offer_detail: ShopOfferDetailScript = null   # 武器/道具独立详情页（点小卡弹出，见 ui/Shop/ShopOfferDetail.gd）

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
	# 撤销按钮：浮在面板下方安全区，卖出后才出现（点错可恢复最近一次卖出）
	_undo_btn = Button.new()
	_undo_btn.set_size(Vector2(220, 54)); _undo_btn.set_position(Vector2(160, 824))
	_undo_btn.text = "↩ 撤销卖出"; _undo_btn.add_theme_font_size_override("font_size", 18)
	ShopPanelScript.style_btn(_undo_btn, Color(0.30, 0.18, 0.08, 0.95), Color(0.98, 0.86, 0.50), Color(0.60, 0.44, 0.22, 0.95))
	_undo_btn.visible = false; _root.add_child(_undo_btn)
	_undo.wire(_undo_btn, Callable(self, "_refresh"))
	# 独立详情页（点小卡弹出）。⚠️ 延后一拍再挂：Shop 常在父节点 _ready 里被 add_child，
	#   此刻父节点正"busy setting up children"，直接 add 会失败（进不了树 → 点小卡没反应）
	_offer_detail = ShopOfferDetailScript.new()
	get_parent().add_child.call_deferred(_offer_detail)
	_offer_detail.buy_requested.connect(_buy)
	_offer_detail.lock_requested.connect(_lock_toggle)
	_offer_detail.reroll_one_requested.connect(_reroll_one)
	_offer_detail.data_cb = func(idx):
		return _card_data(_offers[idx], _sold[idx], Economy.can_buy(GameState.gold, int(_offers[idx].get("cost", 0))))
	for i in _panel.cards.size():
		var c: ShopCardScript = _panel.cards[i]
		c.on_click = _offer_detail.show_for.bind(i)

func _open() -> void:
	_reroll_times = 0; _locked = []; _undo.reset(); _roll(); _root.visible = true

func _on_locale_changed(_l: String = "") -> void:
	_refresh()

func _roll() -> void:
	var cfg := Data.shop_cfg()
	_max_slot = int(cfg.get("max_slot", 6)); _max_lv = int(cfg.get("max_lv", 10))
	_card_count = clampi(ShopPlan.offer_count(GameState.wave, cfg), 1, _panel.cards.size())
	# 钱包交给 roll_offers：保底搭档挑玩家买得起的最高档
	_offers = Economy.roll_offers(_pool_now(), _card_count, _rng, GameState.gold)
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
		d["can_lock"] = false   # 锁定/单张刷新在详情页，小卡上不画按钮
		d["locked"] = _locked.has(i)
		d["reroll_one_cost"] = ShopPlan.single_reroll_cost(_reroll_times, Data.shop_cfg())
		c.setup(d)
	_panel.merge_btn.text = I18n.t("shop_merge_btn")
	_panel.merge_btn.disabled = not Inventory.has_mergeable(GameState.weapons, _max_lv)
	# 刷新按钮文字以前没人设过（截图目检才发现是空白按钮），补上 + 显示当前刷新价
	_panel.reroll_btn.text = I18n.t("shop_reroll") % Economy.reroll_cost(_reroll_times, Data.shop_cfg())
	# 槽满提示"先卖一把"；大商店亮促销标识（攒钱这一波能大买的节奏要被看见）
	var cfg := Data.shop_cfg()
	if _slots_full():
		_panel.hint_lbl.text = I18n.t("shop_slots_full_hint")
	elif ShopPlan.is_big(GameState.wave, cfg):
		_panel.hint_lbl.text = I18n.t("shop_big_tag") % int(round(ShopPlan.discount(GameState.wave, cfg) * 100.0))
	else:
		_panel.hint_lbl.text = ""
	_panel.inv.refresh(GameState.weapons, _max_lv, _max_slot)
	_panel.sets_bar.refresh(ShopSetProgress.rows(GameState.weapons, Data.weapons, Data.weapon_sets))

# 套装条数据见 ui/Shop/ShopSetProgress.gd（件数 / 还差几件 / 档位 / 颜色 / 名字）
func _refresh_stats() -> void:
	if _panel == null or _panel.stats_lbl == null: return
	var spd := int(round(minf(float(Data.player_cfg().get("speed", 180)) * (1.0 + GameState.stat_value("speed_pct")), float(Data.player_cfg().get("speed_cap", 600.0)))))
	# 攻击力是派生实数（全武器齐射一轮的伤害）—— 走 Stats 聚合口径，与 entities 开火时的乘法完全一致
	var atk := Stats.attack_power(GameState.weapons, GameState.stat_value, Data.weapon, Data.combat_cfg())
	var g1 := "生命 %d   护甲 %d   移速 %d" % [GameState.max_hp, int(GameState.stat_value("armor")), spd]
	var g2 := "攻击力 %d(+%d%%)   射速 +%d%%   范围 +%d%%   暴击 %d%%" % [int(atk), int(GameState.stat_value("dmg_pct") * 100.0), int(GameState.stat_value("rate_pct") * 100.0), int(GameState.stat_value("range_pct") * 100.0), int(GameState.stat_value("crit_chance") * 100.0)]
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
		# 套装名前置：买之前就知道"这把属于哪一套"
		var tags: Array = def.get("tags", [])
		var set_name := I18n.t("set_" + str(tags[0])) if tags.size() > 0 else ""
		var state := I18n.t("shop_merge") if Inventory.owned_max_lv(GameState.weapons, key) > 0 else I18n.t("shop_new")
		d["tag"] = (set_name + "·" if set_name != "" else "") + state
		# 羁绊标记（本命描金边 / 羁绊类描蓝边），见 ui/Shop/ShopCardSyn.gd
		ShopCardSyn.decorate(d, Data.character(GameState.character), key, Data.weapons, GameState.weapons)
		# 左侧套装色竖条：整套已激活就亮起来（与 HUD 武器槽同一套视觉语言）
		if tags.size() > 0:
			var sd := Data.weapon_set(str(tags[0]))
			var cnt := int(WeaponSets.tag_counts(GameState.weapons, Data.weapons).get(str(tags[0]), 0))
			d["set_color"] = Color(str(sd.get("color", "#8a7a5a")))
			d["set_on"] = WeaponSets.tier_of(cnt, sd) > 0
			# 详情页要展示套装进度：名称 / 当前件数 / 下一档门槛 / 已激活档位
			d["set_name"] = set_name
			d["set_count"] = cnt
			d["set_need"] = WeaponSets.next_need(cnt, sd)
			d["set_tier"] = WeaponSets.tier_of(cnt, sd)
		# 行为类型：买之前就知道这把"怎么打"（追踪/弹射/连锁…）
		d["behavior_zh"] = Weapon.behavior_zh(def)
		d["disabled"] = not Inventory.can_accept_tier(GameState.weapons, key, lv, _max_slot, _max_lv)
	else:
		var rar := clampi(int(def.get("rarity", 1)), 1, 3)
		d["accent"] = RARITY_COLORS[rar - 1]; d["rarity"] = rar; d["tag"] = I18n.t("shop_upgrade")
		# 道具也有真图标了（18 类覆盖 136 个）；没配映射的 stat 落回宝石画法
		var ik := str(ItemIcons.key_for_def(def))
		if ik != "": d["icon"] = Art.icon(ik)
	return d
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
		var key := str(o.get("key", ""))
		GameState.buy_upgrade(key); bought = true
		# 强化效果可见化：弹一条"你买了什么 / 干嘛用的"，拾取类再补一圈范围环
		var def := Data.upgrade(key)
		if def != null:
			_pop_effect(I18n.pick(def) + "：" + I18n.tip(def), Color(1.0, 0.82, 0.29))
			if Inventory.stat_entries(def).any(func(e): return str(e.get("stat", "")) in ["pickup_pct", "autopick", "fullauto"]):
				Events.player_range_preview.emit(GameState.pickup_magnet())
	# 买成就关详情页：真机反馈"买完看不出买没买成、容易重复点"，开着也会挡住货架绿勾
	if bought:
		_offer_detail.hide_page()
	_sold[index] = bought; _refresh(); _flash_card(index, bought); _undo.reset()

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

func _merge() -> void:
	var done := Inventory.merge_pairs(GameState.weapons, _max_lv, Data.combat_cfg())
	for m in done: Events.weapon_merged.emit(m.get("key", ""), int(m.get("lv", 1)))
	if done.size() > 0: Events.weapons_changed.emit(GameState.weapons)
	_refresh()

# 售出：交给 SellUndo 执行并记录快照，点错可一键撤销（见 ui/Shop/SellUndo.gd）
func _sell(index: int) -> void:
	var r := _undo.sell(GameState.weapons, index, ShopTiers.new().sell_ratio())
	if bool(r.get("kept", false)):
		_pop_effect(I18n.t("shop_keep_one"), Color(0.95, 0.42, 0.40))
	_refresh()

func _flash_card(index: int, ok: bool) -> void:
	if index < 0 or index >= _panel.cards.size(): return
	var c: ShopCardScript = _panel.cards[index]
	c.modulate = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.45, 0.45)
	create_tween().tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

# 让 HUD 横幅弹一条短提示（买强化反馈 / 卖最后一把的红色告警）。
# 通过 HUD 的公开访问器拿到 HudBanners 实例，不读私有字段（R3）。
func _pop_effect(text: String, col: Color) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("banners"):
		return
	var b = hud.banners()
	if b != null and b.has_method("pop_effect"):
		b.pop_effect(text, col)

func _slots_full() -> bool:
	var n := 0
	for w in GameState.weapons:
		if int(w.get("lv", 1)) > 0: n += 1
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
	if not Economy.can_buy(GameState.gold, cost): return
	var pool := _pool_now()
	GameState.spend_gold(cost); _reroll_times += 1
	_offers = ShopPlan.reroll_one(_offers, index, pool, _rng, GameState.gold)
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
	GameState.spend_gold(cost); _reroll_times += 1; _undo.reset()
	if _locked.is_empty():
		_roll()
	else:
		_offers = ShopPlan.reroll_keep(_offers, _locked, _pool_now(), _card_count, _rng,
			GameState.gold)
		_sold = []; for i in _offers.size(): _sold.append(false)
		_refresh()

func _next_wave() -> void:
	_offer_detail.hide_page()
	_root.visible = false; Events.shop_closed.emit()
