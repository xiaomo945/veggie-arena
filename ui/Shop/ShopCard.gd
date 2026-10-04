extends Control

# 商店单卡组件（哑组件）：只负责"把一份报价画得好看"，不含任何购买逻辑。
# 购买逻辑全在 Shop.gd（调 GameState / Inventory / Economy）。
# data 字段由 Shop.gd 预计算后通过 setup() 灌入，保证本组件保持轻量（架构守卫 300 行红线）。
#
# 配色统一走数值总表 §8.4：
#   武器合成等级角标 Lv1 灰 / Lv2 绿 / Lv3 蓝 / Lv4 紫
#   道具稀有度边框 rarity1 灰 / rarity2 蓝 / rarity3 紫
#
# 卡通暖色规范：卡片圆角 14 / 小药丸圆角 8~14，描边统一 2px；
# 价格画成"金币药丸"（币图标 + 数字），主次：名称 > 图标/价格 > 标签 > 描述。

# ---- §8.4 配色（用户指定分级：白1/绿2/蓝3/紫4/红5/传说6）----
const LV_COLORS := [Color(0.85,0.86,0.90), Color(0.25,0.77,0.32), Color(0.18,0.55,1.0),
	Color(0.63,0.29,1.0), Color(1.0,0.30,0.24), Color(1.0,0.71,0.12)]
const RARITY_COLORS := [Color(0.60,0.63,0.65), Color(0.35,0.66,1.0), Color(0.78,0.49,1.0)]
const GOLD := Color(1.0, 0.82, 0.29)
const CARD_BG := Color(0.17, 0.13, 0.08, 0.97)
const CARD_BG_DIM := Color(0.11, 0.09, 0.06, 0.92)
const RED := Color(0.95, 0.42, 0.40)
const INFL := Color(1.0, 0.55, 0.25)   # 涨价角标：暖橙（卡通统一调）
const ICON_BOX := 60.0
const Ctl := preload("res://ui/Shop/ShopCardCtl.gd")

var _d: Dictionary = {}
var _hover := false
var _font: Font
var _sbs: Dictionary = {}   # StyleBoxFlat 缓存（按参数去重，避免每次重绘都 new）
var on_click: Callable = Callable()
# 单卡可控（Q6）：右上角两个小按钮 —— 锁定（整店刷新时保留）/ 单张刷新（只换这一张）
var on_lock: Callable = Callable()
var on_reroll_one: Callable = Callable()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	# 武器图标 256px / 金币 512px 都要缩到几十 px 画：线性 + mipmap，否则采样糊点
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	I18n.locale_changed.connect(_on_locale_changed)

func setup(data: Dictionary) -> void:
	_d = data
	queue_redraw()

# 圆角盒缓存：卡片/药丸/角标共用一套圆角语言
func _sb(bg: Color, border: Color, radius: float, bw: int) -> StyleBoxFlat:
	var k := "%s|%s|%s|%d" % [bg, border, radius, bw]
	if not _sbs.has(k):
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(int(radius))
		sb.border_color = border
		sb.set_border_width_all(bw)
		_sbs[k] = sb
	return _sbs[k]

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var touch := false
	if event is InputEventScreenTouch:
		touch = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		touch = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if touch:
		# 小按钮优先：点在锁/刷新上就不再触发购买（避免"想锁卡结果买下了"）
		var p := _event_pos(event)
		var hit := _hit_btn(p)
		if hit == 1 and on_lock.is_valid():
			on_lock.call(); accept_event(); return
		if hit == 2 and on_reroll_one.is_valid():
			on_reroll_one.call(); accept_event(); return
		_tap()
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var h := get_local_rect().has_point(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()

func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return Vector2.ZERO

# 命中哪个小按钮：1=锁定 2=单张刷新 0=都不是（走购买）
func _hit_btn(p: Vector2) -> int:
	if not bool(_d.get("can_lock", false)):
		return 0
	return Ctl.hit(size, p)

func _tap() -> void:
	if _d.get("disabled", false) or _d.get("sold", false):
		return
	if on_click.is_valid():
		on_click.call()

func get_local_rect() -> Rect2:
	return Rect2(0, 0, size.x, size.y)

func _draw() -> void:
	if _font == null or _d.is_empty():
		return
	var r := get_local_rect()
	var disabled := bool(_d.get("disabled", false))
	var sold := bool(_d.get("sold", false))
	var afford := bool(_d.get("affordable", true))
	var dim := disabled or (not afford) or sold
	# 边框：武器=自身主色（Lv 角标另算）；道具=稀有度色；买不起/槽满标红
	var accent: Color = _d.get("accent", GOLD)
	var border := accent
	if disabled:
		border = RED
	elif not afford:
		border = Color(0.6, 0.5, 0.5, 0.9)
	draw_style_box(_sb(CARD_BG if not dim else CARD_BG_DIM, border, 14.0, 4 if _hover else 2), r)

	# 矮卡（大商店 6 张）砍掉描述、缩小图标，否则文字会糊成一团
	var compact := Ctl.is_compact(r.size.y)
	var ib := Ctl.icon_box(r.size.y)

	# 左侧图标 / 稀有度宝石（底座染色呼应主色）
	_draw_icon(r, accent, ib)

	# 名称（为右上角 Lv/稀有度角标预留 84px，避免文字压到角标）
	var tx := 14.0 + ib + 10.0
	var name_c := Color(1,1,1,0.97) if not dim else Color(0.6,0.63,0.67,0.8)
	_center(_d.get("name", ""), tx + 8.0, 26, 18, name_c, r.size.x - tx - 92.0)

	# 类型 + 状态标签
	var tag := str(_d.get("tag", ""))
	var tag_c := accent if not dim else Color(0.55,0.58,0.62,0.8)
	_center(tag, tx + 8.0, 47, 12, tag_c, r.size.x - tx - 92.0)

	# 描述（按字符换行，最多 2 行；右侧留 96px 给价格药丸，避免文字钻到药丸底下）
	if not compact:
		var desc := str(_d.get("tip", ""))
		_draw_wrap(desc, tx, 66, 12, Color(0.76,0.72,0.64,0.95) if not dim else Color(0.5,0.47,0.43,0.7),
			r.size.x - tx - 96.0, 2)

	# 价格（"金币药丸"；买不起/槽满标红）—— 矮卡时挪到左下，给右上角的按钮让位
	_draw_price(str(_d.get("cost", 0)), afford and not disabled, compact, tx)

	# 通胀角标：本店比原价贵时画一个暖橙"涨 N%"圆角标（把物价上涨显式呈现）
	var infl_pct := int(_d.get("infl_pct", 0))
	if infl_pct > 0 and not sold:
		_draw_infl(infl_pct, afford, compact, tx)

	# Lv 角标（武器）或 稀有度 pips（道具）
	if str(_d.get("kind", "")) == "weapon":
		_draw_lv(compact)
	else:
		_draw_rarity(compact)

	# 单卡可控按钮（锁定 / 单张刷新）
	if bool(_d.get("can_lock", false)) and not sold:
		Ctl.draw(self, size, _d, _font)

	# 已售出遮罩
	if sold:
		draw_style_box(_sb(Color(0,0,0,0.5), Color(0,0,0,0), 14.0, 0), r)
		_center(I18n.t("shop_sold"), r.size.x * 0.5, r.size.y * 0.5 + 8, 22, Color(1,1,1,0.9))

func _draw_icon(r: Rect2, accent: Color, ib: float) -> void:
	var box := Rect2(14.0, (r.size.y - ib) * 0.5, ib, ib)
	draw_style_box(_sb(accent.darkened(0.62), Color(accent, 0.85), 12.0, 2), box)
	var tex: Texture2D = _d.get("icon", null)
	if tex != null and tex is Texture2D:
		var s := ib - 10.0
		draw_texture_rect_region(tex, Rect2(box.position.x + 5.0, box.position.y + 5.0, s, s),
			Rect2(Vector2.ZERO, (tex as Texture2D).get_size()))
	else:
		# 无图标（道具）：画一个稀有度/主色菱形宝石 + 高光
		var c := box.position + box.size * 0.5
		var rad := ib * 0.32
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)]),
			accent)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -rad*0.5), c + Vector2(rad*0.5, 0), c + Vector2(0, rad*0.5), c + Vector2(-rad*0.5, 0)]),
			Color(1,1,1,0.35))

func _draw_lv(compact: bool) -> void:
	var lv := int(_d.get("lv", 1))
	var ci := clampi(lv, 1, LV_COLORS.size()) - 1
	var col: Color = LV_COLORS[ci]
	var txt := "Lv %d" % lv
	var fs := 13 if not compact else 12
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 7.0
	var h := 22.0 if not compact else 19.0
	var rr := Rect2(size.x - tw - pad * 2 - 12.0, 12.0 if not compact else 8.0, tw + pad * 2, h)
	draw_style_box(_sb(col, col.darkened(0.35), 8.0, 1), rr)
	_center(txt, rr.position.x + rr.size.x * 0.5, rr.position.y + h * 0.5 + fs * 0.35, fs, Color(0.06,0.07,0.09))

func _draw_rarity(compact: bool) -> void:
	var rar := clampi(int(_d.get("rarity", 1)), 1, 3)
	var col: Color = RARITY_COLORS[rar - 1]
	var pip := 9.0 if not compact else 7.0
	var gap := 4.0
	var total := float(rar) * pip + float(rar - 1) * gap
	var x0 := size.x - total - 12.0
	var y := 16.0 if not compact else 10.0
	for i in rar:
		draw_style_box(_sb(col, col.darkened(0.35), 3.0, 1),
			Rect2(x0 + float(i) * (pip + gap), y, pip, pip))

# 价格药丸：金底 + 币图标 + 数字；买不起/槽满换红底，一眼分清"买得起吗"
func _draw_price(text: String, ok: bool, compact: bool, tx: float) -> void:
	var fs := 16
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var coin := Art.coin_icon()
	var coin_s := 20.0
	var h := 28.0
	var w := coin_s + tw + 18.0
	var px := (size.x - 14.0 - w) if not compact else tx
	var py := (size.y - 42.0) if not compact else (size.y - 34.0)
	var rr := Rect2(px, py, w, h)
	draw_style_box(_sb(Color(0.30, 0.21, 0.06, 0.96) if ok else Color(0.28, 0.10, 0.08, 0.96),
		Color(0.85, 0.66, 0.22) if ok else RED, 14.0, 2), rr)
	if coin != null:
		draw_texture_rect_region(coin, Rect2(rr.position.x + 8.0, rr.position.y + 4.0, coin_s, coin_s),
			Rect2(Vector2.ZERO, coin.get_size()))
	_center(text, rr.position.x + 8.0 + coin_s + 4.0 + tw * 0.5,
		rr.position.y + h * 0.5 + fs * 0.35, fs, GOLD if ok else Color(1.0, 0.72, 0.66))

# 通胀角标："涨 N%" 暖橙圆角小标，呼应商店整体卡通暖色调
func _draw_infl(pct: int, afford: bool, compact: bool, tx: float) -> void:
	var txt := "涨 %d%%" % pct
	var fs := 12
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 6.0
	var w := tw + pad * 2
	var h := 18.0
	var x := (size.x - 14.0 - w) if not compact else tx
	var y := (size.y - 50.0) if not compact else (size.y - 60.0)
	var col := INFL if afford else Color(0.82, 0.48, 0.46)
	draw_style_box(_sb(Color(0.16, 0.10, 0.05, 0.9), col, 9.0, 2), Rect2(x, y, w, h))
	_center(txt, x + w * 0.5, y + h * 0.5 + fs * 0.32, fs, Color(1, 1, 1, 0.96))

func _draw_wrap(text: String, x0: float, y0: float, fs: int, c: Color, maxw: float, max_lines: int) -> void:
	var line := ""
	var lines := 0
	var i := 0
	while i < text.length() and lines < max_lines:
		var ch := text[i]
		var test := line + ch
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw and line != "":
			_center(line, x0 + maxw * 0.5, y0 + float(lines) * (fs + 4), fs, c)
			lines += 1
			line = ch
		else:
			line = test
		i += 1
	if line != "" and lines < max_lines:
		_center(line, x0 + maxw * 0.5, y0 + float(lines) * (fs + 4), fs, c)

func _center(text: String, cx: float, y: float, fs: int, c: Color, maxw := 9999.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > maxw and maxw < 9999.0:
		# 超宽截断，避免糊到邻区
		while w > maxw and text.length() > 1:
			text = text.substr(0, text.length() - 1)
			w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
