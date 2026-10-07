extends Control

# 角色解锁关系树：一屏看清"用谁通关 → 解开谁"。
#
# 为什么要这一页：解锁规则散在 data/unlocks.json 里，玩家看规则表才知道下一个目标是谁。
# 玩家的原话是"做一个角色的关系树，一看就明白" —— 规则表是给代码读的，树是给人读的。
#
# 结构完全由 data/unlocks.json 推导（core/Unlocks.lanes / standalone），
# 以后加 60 个角色、改任何一条线，这张图自动跟着变，不用维护第二份"路线表"。
#
# ⚠️ 与 WeaponPicker 同一个坑：_ready 里 anchors 已失效，**必须配显式 size**。

const Unlocks := preload("res://core/Unlocks.gd")
const UnlockText := preload("res://ui/UnlockText.gd")

# 点某个节点 → 让外边弹该角色的详情页（复用 CharDetail，layer 55 盖在本页之上）
signal char_detail_requested(key: String)
# 点空白 / 点标题以外的任何地方 → 收起本页（这么大的浮层必须有"一戳就关"的退路）
signal close_requested

const MARGIN := 16.0
const NODE_H := 58.0
const NODE_GAP := 30.0      # 上下两节点之间留给箭头的位置
const LANE_GAP := 12.0
const HEAD_Y := 96.0        # 标题区占位
const HEAD_LBL := 24.0      # 每列小标题占位
const FOOT := 56.0          # 底部进度条占位
const MIN_ROW_H := 40.0     # 角色再多也不许把方块压到不可读

var _lanes: Array = []      # 主线：每条一串 key（从免费起点到最深的后代）
var _side: Array = []       # 旁路：只能靠累计数据解锁的角色
var _boxes: Dictionary = {} # key → Rect2（屏幕坐标）
var _arrows: Array = []     # [{from, to, done}] 主线箭头
var _owned := 0
var _hover := ""
var _node_h := NODE_H

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(540.0, 900.0)
	Events.character_unlocked.connect(_on_char_unlocked)
	I18n.locale_changed.connect(_on_locale_changed)
	queue_redraw()
	ScreenMode.fit_overlay(self)

func show_page() -> void:
	_refresh()

func hide_page() -> void:
	_hover = ""
	queue_redraw()

# 每次打开都重算：存档在局与局之间会变，节点状态不能停在上一次。
# ⚠️ 状态变了必须显式 queue_redraw：自绘节点不会因为数据变了自动重画
#   （露过一次丑：换完存档截图，画面还停在上一份存档的"全部已拥有"）。
func _refresh() -> void:
	var all: Array = Data.characters.keys()
	var cfg: Dictionary = Data.unlocks_cfg()
	_lanes = Unlocks.lanes(cfg, all)
	_side = Unlocks.standalone(cfg, all)
	_boxes = {}
	_arrows = []
	_owned = 0
	for k in all:
		if Unlocks.is_unlocked(SaveMgr.data, cfg, str(k)):
			_owned += 1
	_layout()
	queue_redraw()

# 布局：几条主线各一列，旁路易一列。角色变多时整体等比压扁，绝不溢出屏幕。
func _layout() -> void:
	var ncols: int = _lanes.size() + (1 if not _side.is_empty() else 0)
	if ncols <= 0:
		return
	var grid_w := 540.0 - 2.0 * MARGIN
	var col_w := (grid_w - float(ncols - 1) * LANE_GAP) / float(ncols)
	var rows := 1
	for lane in _lanes:
		rows = maxi(rows, (lane as Array).size())
	rows = maxi(rows, _side.size())
	var avail := 900.0 - HEAD_Y - FOOT - HEAD_LBL
	var row_h := avail / float(rows)
	if row_h < MIN_ROW_H:
		row_h = MIN_ROW_H
	_node_h = minf(NODE_H, row_h * 0.68)
	var gap := maxf(6.0, row_h - _node_h)
	var top := HEAD_Y + HEAD_LBL + maxf(0.0, (avail - row_h * float(rows)) * 0.5)
	for i in ncols:
		var keys: Array = (_lanes[i] as Array) if i < _lanes.size() else _side
		var x := MARGIN + float(i) * (col_w + LANE_GAP)
		for j in keys.size():
			var y := top + float(j) * (row_h)
			_boxes[str(keys[j])] = Rect2(x, y, col_w, _node_h)
		# 箭头只属于主线：旁路角色之间没有"谁解开谁"，不能画出误导性的连线
		if i >= _lanes.size():
			continue
		for j in keys.size() - 1:
			var cx := x + col_w * 0.5
			_arrows.append({
				"from": Vector2(cx, top + float(j) * row_h + _node_h + gap * 0.25),
				"to": Vector2(cx, top + float(j + 1) * row_h - gap * 0.35),
				"child": str(keys[j + 1]),
			})

func _draw() -> void:
	var cfg: Dictionary = Data.unlocks_cfg()
	var save: Dictionary = SaveMgr.data
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(540.0, 900.0)), Color(0.03, 0.04, 0.07, 0.94), true)
	_draw_header(fs)
	# 每列小标题
	for i in _lanes.size():
		var lane: Array = _lanes[i]
		if lane.is_empty():
			continue
		var b: Rect2 = _boxes.get(str(lane[0]), Rect2())
		_draw_text(fs, UnlockText.route_lane_main(I18n.locale),
			Vector2(b.position.x, HEAD_Y + 6.0), 12, Color(0.99, 0.87, 0.40))
	var last: Array = _side if not _side.is_empty() else []
	if not last.is_empty():
		var b2: Rect2 = _boxes.get(str(last[0]), Rect2())
		_draw_text(fs, UnlockText.route_lane_side(I18n.locale),
			Vector2(b2.position.x, HEAD_Y + 6.0), 12, Color(0.62, 0.70, 0.82))
	# 箭头（先画线再画方块，线头藏在方块下面更好看）
	for a in _arrows:
		var done: bool = Unlocks.is_unlocked(save, cfg, str((a as Dictionary).get("child", "")))
		var col := Color(0.95, 0.82, 0.40, 0.95) if done else Color(0.42, 0.46, 0.52, 0.85)
		var p1: Vector2 = (a as Dictionary).get("from", Vector2.ZERO)
		var p2: Vector2 = (a as Dictionary).get("to", Vector2.ZERO)
		draw_line(p1, p2, col, 2.5, true)
		draw_colored_polygon(PackedVector2Array([
			p2, p2 + Vector2(-5.0, -8.0), p2 + Vector2(5.0, -8.0)]), col)
	# 节点
	for lane in _lanes:
		for key in lane:
			_draw_node(str(key), fs, true)
	for key in _side:
		_draw_node(str(key), fs, false)
	_draw_foot(fs)

func _draw_header(fs: Font) -> void:
	_draw_text(fs, UnlockText.route_title(I18n.locale), Vector2(0.0, 34.0), 28,
		Color(0.98, 0.86, 0.32), 540.0, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(fs, UnlockText.route_hint(I18n.locale), Vector2(0.0, 68.0), 13,
		Color(0.78, 0.82, 0.88), 508.0, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_foot(fs: Font) -> void:
	_draw_text(fs, UnlockText.route_progress(_owned, Data.characters.size(), I18n.locale),
		Vector2(0.0, 852.0), 13, Color(0.66, 0.70, 0.78), 540.0, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(fs, UnlockText.route_close(I18n.locale), Vector2(0.0, 872.0), 12,
		Color(0.52, 0.56, 0.62), 540.0, HORIZONTAL_ALIGNMENT_CENTER)
	# 进度条：一眼看出解锁到几成（比数字更直观）
	var bw := 300.0
	var bx := (540.0 - bw) * 0.5
	draw_rect(Rect2(bx, 838.0, bw, 4.0), Color(0.20, 0.22, 0.27, 0.95), true)
	var r := float(_owned) / maxf(1.0, float(Data.characters.size()))
	draw_rect(Rect2(bx, 838.0, bw * r, 4.0), Color(0.98, 0.86, 0.32), true)

func _draw_node(key: String, fs: Font, mainline: bool) -> void:
	var b: Rect2 = _boxes.get(key, Rect2())
	if b.size.x <= 0.0:
		return
	var entry: Dictionary = Data.character(key)
	var cfg: Dictionary = Data.unlocks_cfg()
	var save: Dictionary = SaveMgr.data
	var opened := Unlocks.is_unlocked(save, cfg, key)
	var accent := Color(str(entry.get("color", "#ffffff")))
	var bg := Color(0.18, 0.13, 0.07, 0.95) if opened else Color(0.10, 0.11, 0.14, 0.92)
	if not opened:
		bg = Color(0.11, 0.12, 0.16, 0.92)
	var border := accent if opened else Color(0.38, 0.41, 0.47, 0.9)
	var bw := 2.5 if opened else 1.5
	if _hover == key:
		bw += 1.5
	Art.round_rect(self, b, bg, border, bw, 10.0)
	# 立绘：优先真人贴图，缺图退化成主色圆点
	var av := _node_h * 0.62
	var c := Vector2(b.position.x + 8.0 + av * 0.5, b.position.y + _node_h * 0.5)
	var tex := Art.sprite("char_" + key)
	if tex != null:
		draw_texture_rect_region(tex, Rect2(c.x - av * 0.5, c.y - av * 0.5, av, av),
			Rect2(Vector2.ZERO, tex.get_size()))
	else:
		draw_circle(c, av * 0.42, accent)
	var tx := b.position.x + 8.0 + av + 8.0
	var ty := b.position.y + _node_h * 0.5 - 6.0
	var nm := I18n.pick(entry)
	_draw_text(fs, nm, Vector2(tx, ty), 13,
		Color(0.98, 0.96, 0.92) if opened else Color(0.74, 0.77, 0.83), b.size.x - av - 20.0,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	# 状态行：已解锁写"已拥有"，否则写达成条件
	var sub := UnlockText.route_owned(I18n.locale)
	if opened:
		sub = UnlockText.route_owned(I18n.locale)
	elif mainline:
		var info: Dictionary = Unlocks.remaining(save,
			Unlocks.first_clear_with(Unlocks.rule_of(cfg, key)))
		sub = UnlockText.short(info, I18n.locale)
	else:
		sub = UnlockText.short(Unlocks.remaining(save, Unlocks.rule_of(cfg, key)), I18n.locale)
	_draw_text(fs, sub, Vector2(tx, ty + 16.0), 11,
		Color(0.55, 0.72, 0.48) if opened else Color(0.66, 0.70, 0.78),
		b.size.x - av - 20.0, HORIZONTAL_ALIGNMENT_LEFT, true)
	if not opened:
		_draw_lock(Vector2(b.position.x + b.size.x - 14.0, b.position.y + 13.0))

# 一把小挂锁（纯几何，不依赖美术素材）
func _draw_lock(c: Vector2) -> void:
	var w := 11.0
	var h := 9.0
	var body := Rect2(c.x - w * 0.5, c.y - h * 0.15, w, h)
	draw_rect(body, Color(0.92, 0.76, 0.30, 0.9), true)
	draw_rect(body, Color(0.32, 0.24, 0.08), false, 1.0)
	draw_arc(Vector2(c.x, c.y - h * 0.15), w * 0.38, PI, TAU, 12,
		Color(0.95, 0.82, 0.38), 1.8, true)

# 统一的行宽控制：超宽自动省略省略号，避免长名字顶出方块
func _draw_text(fs: Font, txt: String, at: Vector2, size: int, col: Color,
		width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		clip: bool = false) -> void:
	var out := txt
	if clip and width > 0.0:
		out = _ellipsis(fs, txt, width, size)
	draw_string(fs, at, out, align, width, size, col)

func _ellipsis(fs: Font, txt: String, width: float, size: int) -> String:
	if fs.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return txt
	var cut := txt
	while cut.length() > 1:
		cut = cut.substr(0, cut.length() - 1)
		if fs.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return cut + "…"
	return cut

func _key_at(p: Vector2) -> String:
	for k in _boxes:
		var b: Rect2 = _boxes[k]
		if Rect2(b.position, b.size).has_point(p):
			return str(k)
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var k := _key_at(mm.position)
		if k != _hover:
			_hover = k
			queue_redraw()
		return
	var pressed := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var key := _key_at(_tap_pos(event))
	if key.is_empty():
		close_requested.emit()
	else:
		Sfx.ui_click()
		char_detail_requested.emit(key)
	accept_event()

func _tap_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return (event as InputEventScreenTouch).position

func _on_char_unlocked(_key: String) -> void:
	_refresh()
	queue_redraw()

func _on_locale_changed(_l: String = "") -> void:
	queue_redraw()
