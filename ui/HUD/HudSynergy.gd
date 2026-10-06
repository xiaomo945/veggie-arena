extends Control

# HUD 羁绊进度条（阶段 B1）：战斗中常驻显示"本命·手枪 3/6，还差 1 件"。
#
# 为什么必须在【战斗中】常驻可见：
#   羁绊（角色 × 武器）是"再买一把同样的"的动力来源，而商店每一波才开一次。
#   玩家打怪时看不见自己的进度，进商店就不会带着目标 —— 于是又回到
#   "刷出什么买什么"。这一条把"研究 build"从商店里拉回战斗中：
#   每时每刻都看得见"我还差几件"，跨档还会弹横幅庆祝。
#
# 模块化：自己每 0.25s 拉一次 Synergy.progress（纯函数），不接一串信号；
#   换角色/买武器/合成/卖掉，它都会自己跟上。跨档时只发一个 tier_up 信号，
#   由 HUD.gd 转发给横幅 —— HUD.gd 因此不用懂任何羁绊规则。
#
# ⚠️ 位置走 HudLayout.synergy_pos()：它挂在 HUD CanvasLayer 下，用的是屏幕
#    绝对坐标，而相机按 HudLayout.hud_block_h() 在上边让位。改 Y 必须同步
#    HudLayout.TOP_CONTENT_H，否则玩家贴场地最上沿时会被这条压住（真踩过同类 bug）。

const Synergy := preload("res://core/Synergy.gd")
const Stats := preload("res://core/Stats.gd")

# 跨档通知：HUD.gd 收到后弹横幅（和套装跨档同一条反馈通道）
signal tier_up(text: String, color: Color)

const REFRESH := 0.25          # 拉数据的间隔（秒）：够快，又不是每帧算
const FONT_SIZE := 11
const CHIP_H := 14.0
const CHIP_GAP := 12.0
const KINDS := ["signature", "bond"]

var _t := 0.0
var _prog: Dictionary = {}
var _tiers: Dictionary = {}
var _char := ""

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	position = HudLayout.synergy_pos()
	size = Vector2(HudLayout.synergy_w(), HudLayout.synergy_h())
	I18n.locale_changed.connect(queue_redraw)
	_refresh()

func _process(delta: float) -> void:
	_t += delta
	if _t < REFRESH:
		return
	_t = 0.0
	_refresh()

func _refresh() -> void:
	var ck := GameState.character
	if ck != _char:
		_char = ck
		_tiers = {}       # 换角色 = 换一整套羁绊，别把上个角色的档位带过来
	var ce := Data.character(ck)
	_prog = Synergy.progress(GameState.weapons, ce, Data.weapons)
	for kind in KINDS:
		if not _prog.has(kind):
			continue
		var d := _prog[kind] as Dictionary
		var t := int(d.get("tier", 0))
		var old := int(_tiers.get(kind, 0))
		_tiers[kind] = t
		if t > old and old > 0:
			_pop_tier_up(kind, d)
	queue_redraw()

# 跨档横幅：和套装跨档走同一条通道（"我凑齐了一档"是件大事，不能只在面板里变个数字）
func _pop_tier_up(kind: String, d: Dictionary) -> void:
	var txt := I18n.t("set_tier_up") % [_title(kind, d), int(d.get("count", 0))] + _gain(d)
	tier_up.emit(txt, _color(kind))

# ---- 文案 ----

func _title(kind: String, d: Dictionary) -> String:
	if kind == "signature":
		return I18n.t("syn_signature") + "·" + I18n.pick(Data.weapon(str(d.get("key", ""))))
	return I18n.t("syn_bond") + "·" + I18n.t("set_" + str(d.get("tag", "")))

# 这一档给了什么（取第一条加成写进横幅，全写会太长）
func _gain(d: Dictionary) -> String:
	var st := d.get("stats_now", {}) as Dictionary
	for k in st:
		var e := Stats.entry(str(k))
		return "  " + I18n.t(str(e.get("name", ""))) + " " + Stats.fmt_value(
			str(e.get("fmt", "")), float(st[k]))
	return ""

func _color(kind: String) -> Color:
	# 本命金、羁绊蓝 —— 与商店卡片的描边同色，玩家好把两处对上号
	return Color(1.0, 0.84, 0.32) if kind == "signature" else Color(0.45, 0.75, 1.0)

# ---- 绘制 ----

func _draw() -> void:
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var x := 0.0
	for kind in KINDS:
		if not _prog.has(kind):
			continue
		x = _chip(fs, x, kind, _prog[kind] as Dictionary)
		if x >= size.x:
			return     # 后面画不下了就停手，绝不糊到别的控件上

func _chip(fs: Font, x: float, kind: String, d: Dictionary) -> float:
	var col := _color(kind)
	var cnt := int(d.get("count", 0))
	var mx := int(d.get("max_need", 0))
	var main := "%s %d/%d" % [_title(kind, d), cnt, mx]
	var nextn := int(d.get("need_next", 0))
	var sub := I18n.t("syn_max") if nextn <= 0 else I18n.t("syn_next") % nextn
	var w := fs.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var w2 := fs.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	# 进度条：满档整条实心，未达成按 count/max 填（一眼看出"还差多少"）
	var bar_w := 26.0
	var frac := 0.0 if mx <= 0 else clampf(float(cnt) / float(mx), 0.0, 1.0)
	draw_rect(Rect2(x, 4.0, bar_w, CHIP_H - 8.0), Color(1, 1, 1, 0.16))
	draw_rect(Rect2(x, 4.0, bar_w * frac, CHIP_H - 8.0), col)
	var tx := x + bar_w + 5.0
	draw_string(fs, Vector2(tx, CHIP_H - 3.0), main,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 0.92))
	var sx := tx + w + 6.0
	draw_string(fs, Vector2(sx, CHIP_H - 3.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
	return sx + w2 + CHIP_GAP
