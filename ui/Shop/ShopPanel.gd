extends Panel

# 补给站的【面板骨架】：只搭控件、定样式、排卡片，不含任何购买/刷新的业务判断。
#
# 为什么从 Shop.gd 拆出来：Shop.gd 加上"商店节奏 + 单卡可控"后到 338 行，
# 顶穿架构守卫 R1（单文件 ≤300 行）。骨架是纯 UI，跟业务逻辑天然可分，切得干净。
#
# ⚠️ 字段全部【公开】（不带下划线前缀）：架构守卫 R3 禁止跨对象读写私有字段（X._yyy），
#    Shop.gd 要直接拿这些控件引用，所以这里不能写成 _gold_lbl。

const InventoryPanelScript := preload("res://ui/Shop/InventoryPanel.gd")
const ShopCardScript := preload("res://ui/Shop/ShopCard.gd")
const ShopCardCtl := preload("res://ui/Shop/ShopCardCtl.gd")
const SetBarScript := preload("res://ui/Shop/SetBar.gd")

const PANEL_W := 496.0
const PANEL_H := 762.0
const CARD_H := 100.0
const CARD_GAP := 8.0
const CARD_MAX_H := 132.0      # 卡少时不要撑成巨无霸，剩下的空间居中留白
const INV_H := 96.0            # 我的武器：6 个固定方格（含标题行；上方留 18px 给提示行）
const CARDS_Y := 224.0
const CARDS_BOTTOM := 674.0    # 底部按钮上沿：卡片区总高度 = 674 - 224
const MAX_CARDS := 6           # 大商店最多 6 张（卡片会变矮）
const BTN_Y := 674.0

const GOLD := Color(0.99, 0.87, 0.40)
const GOLD_DK := Color(0.80, 0.60, 0.26)

var gold_lbl: Label
var stats_lbl: Label
var hint_lbl: Label
var cards: Array = []
var inv: Control
var sets_bar: Control
var merge_btn: Button
var reroll_btn: Button
var next_btn: Button

func build() -> void:
	set_size(Vector2(PANEL_W, PANEL_H))
	set_position(Vector2((540 - PANEL_W) * 0.5, (900 - PANEL_H) * 0.5))
	add_theme_stylebox_override("panel", flat_box(Color(0.14, 0.10, 0.07, 0.985), GOLD_DK, 18))
	_build_header()
	_build_stats()
	_build_inventory()
	_build_cards()
	_build_buttons()
	_build_sets()

# 套装条：面板最底一条（按钮下方还剩 30px），常驻显示五套的件数进度
func _build_sets() -> void:
	sets_bar = SetBarScript.new()
	sets_bar.set_size(Vector2(PANEL_W - 28, 24)); sets_bar.set_position(Vector2(14, 736))
	add_child(sets_bar)

func _build_header() -> void:
	add_child(coin_rect(Vector2(18, 16), 30))
	var title := Label.new()
	title.text = I18n.t("shop_title")
	title.set_position(Vector2(58, 17))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", GOLD)
	add_child(title)
	var pill := Panel.new()
	pill.set_size(Vector2(152, 38)); pill.set_position(Vector2(PANEL_W - 166, 12))
	pill.add_theme_stylebox_override("panel", flat_box(Color(0.30, 0.21, 0.06, 0.95), Color(0.85, 0.66, 0.22), 19))
	add_child(pill)
	pill.add_child(coin_rect(Vector2(7, 6), 26))
	gold_lbl = Label.new(); gold_lbl.set_position(Vector2(40, 5))
	gold_lbl.add_theme_font_size_override("font_size", 19)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50))
	pill.add_child(gold_lbl)

func _build_stats() -> void:
	var bg := Panel.new()
	bg.set_size(Vector2(PANEL_W - 28, 48)); bg.set_position(Vector2(14, 60))
	bg.add_theme_stylebox_override("panel", flat_box(Color(0.20, 0.16, 0.09, 0.92), Color(0.42, 0.34, 0.18, 0.9), 10))
	add_child(bg)
	stats_lbl = Label.new(); stats_lbl.set_size(Vector2(PANEL_W - 40, 44)); stats_lbl.set_position(Vector2(22, 64))
	stats_lbl.add_theme_font_size_override("font_size", 13)
	stats_lbl.add_theme_color_override("font_color", Color(0.62, 0.90, 0.63))
	add_child(stats_lbl)
	# 满槽提示条：只在"槽位满了还刷不出新武器"时亮，否则玩家只会以为商店坏了。
	# ⚠️ 位置压着"我的武器"最后一排往下 8px：以前放在 y=200，正好盖住格子里的
	#    "售 N"按钮（按钮占 195~212），提示一出来售出就点不到了。
	hint_lbl = Label.new()
	hint_lbl.set_size(Vector2(PANEL_W - 40, 18)); hint_lbl.set_position(Vector2(22, 206))
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.40))
	add_child(hint_lbl)

func _build_inventory() -> void:
	inv = InventoryPanelScript.new()
	inv.set_size(Vector2(PANEL_W - 28, INV_H)); inv.set_position(Vector2(14, 112))
	add_child(inv)

# 一次建满 MAX_CARDS 张，实际显示几张由本场节奏决定（高度随之自适应）
func _build_cards() -> void:
	var y := CARDS_Y
	for _i in MAX_CARDS:
		var c = ShopCardScript.new()
		c.set_size(Vector2(PANEL_W - 28, CARD_H)); c.set_position(Vector2(14, y))
		add_child(c); cards.append(c)
		y += CARD_H + CARD_GAP

func _build_buttons() -> void:
	merge_btn = Button.new(); merge_btn.set_size(Vector2(126, 58)); merge_btn.set_position(Vector2(14, BTN_Y))
	merge_btn.add_theme_font_size_override("font_size", 17)
	style_btn(merge_btn, Color(0.95, 0.62, 0.16), Color(0.22, 0.13, 0.03), Color(0.86, 0.56, 0.14))
	add_child(merge_btn)
	reroll_btn = Button.new(); reroll_btn.set_size(Vector2(144, 58)); reroll_btn.set_position(Vector2(146, BTN_Y))
	reroll_btn.add_theme_font_size_override("font_size", 17)
	style_btn(reroll_btn, Color(0.24, 0.33, 0.18), Color(0.74, 0.91, 0.54), Color(0.48, 0.64, 0.32))
	add_child(reroll_btn)
	next_btn = Button.new(); next_btn.set_size(Vector2(180, 58)); next_btn.set_position(Vector2(296, BTN_Y))
	next_btn.text = I18n.t("shop_next"); next_btn.add_theme_font_size_override("font_size", 19)
	style_btn(next_btn, Color(0.98, 0.80, 0.22), Color(0.24, 0.15, 0.04), Color(0.88, 0.66, 0.16))
	add_child(next_btn)

# 卡片区总高度固定（224~674）；网格 3 列、行数随卡数变、区内垂直居中。
# 每波固定 6 张 = 3 列 × 2 行，正好铺满（不留空格 —— 以前小商店只开 4 张，
# 第 2 行就剩 1 张卡 + 2 个空格，玩家以为商店坏了）。小卡只留图标+名+价，点开看详情。
func layout_cards(n: int) -> void:
	var cols := 3
	var ax := 14.0
	var aw := PANEL_W - 28.0
	var ay := CARDS_Y
	var ah := CARDS_BOTTOM - CARDS_Y
	var gap := CARD_GAP
	var rows := maxi(1, int(ceil(float(n) / float(cols))))
	var tw := (aw - float(cols - 1) * gap) / float(cols)
	var th := minf((ah - float(rows - 1) * gap) / float(rows), CARD_MAX_H)
	var used := th * float(rows) + float(rows - 1) * gap
	var sy := ay + maxf(0.0, (ah - used) * 0.5)
	for i in cards.size():
		var c: ShopCardScript = cards[i]
		var col := i % cols
		var row := i / cols
		c.set_size(Vector2(tw, th))
		c.set_position(Vector2(ax + float(col) * (tw + gap), sy + float(row) * (th + gap)))

static func flat_box(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.set_corner_radius_all(int(radius)); sb.border_color = border; sb.set_border_width_all(2)
	return sb

static func coin_rect(pos: Vector2, sz: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Art.coin_icon(); tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.set_size(Vector2(sz, sz)); tr.set_position(pos)
	return tr

static func style_btn(b: Button, bg: Color, fg: Color, border: Color) -> void:
	var n := flat_box(bg, border, 14); n.shadow_color = Color(0, 0, 0, 0.35); n.shadow_size = 4; n.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat; hov.bg_color = bg.lightened(0.12); b.add_theme_stylebox_override("hover", hov)
	var pre := n.duplicate() as StyleBoxFlat; pre.bg_color = bg.darkened(0.15); b.add_theme_stylebox_override("pressed", pre)
	var dis := n.duplicate() as StyleBoxFlat; dis.bg_color = bg.darkened(0.45); b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg); b.add_theme_color_override("font_disabled_color", Color(fg, 0.45))
