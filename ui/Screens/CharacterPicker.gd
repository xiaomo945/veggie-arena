extends Control

# 角色选择卡片组：标题页里横排 4 张卡，点一下换人。
#
# 只做两件事：画自己（贴图 + 名字 + 属性摘要），以及把点击变成 GameState.set_character。
# 不认识 Player、不认识 Game —— 换人后由 Events.character_changed 通知它们。

const Character := preload("res://core/Character.gd")

const CARD_W := 96.0
const CARD_H := 118.0
const GAP := 10.0

var _keys: Array = []
var _selected := "turnip"
var _hover := -1

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_keys = Data.characters.keys()
	_keys.sort()
	_selected = GameState.character
	var n := float(_keys.size())
	var total := n * CARD_W + maxf(0.0, n - 1.0) * GAP
	size = Vector2(total, CARD_H)
	Events.character_changed.connect(_on_changed)
	queue_redraw()

func _on_changed(key: String) -> void:
	_selected = key
	queue_redraw()

func _key_at(p: Vector2) -> String:
	var i := int(p.x / (CARD_W + GAP))
	if i < 0 or i >= _keys.size():
		return ""
	# 落在间隙里不算
	var x0 := float(i) * (CARD_W + GAP)
	if p.x > x0 + CARD_W:
		return ""
	return str(_keys[i])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var k := _key_at(t.position)
			if not k.is_empty():
				GameState.set_character(k)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var k := _key_at(mb.position)
			if not k.is_empty():
				GameState.set_character(k)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var k := _key_at(mm.position)
		var idx := _keys.find(k) if not k.is_empty() else -1
		if idx != _hover:
			_hover = idx
			queue_redraw()

func _draw() -> void:
	for i in _keys.size():
		var key := str(_keys[i])
		var x := float(i) * (CARD_W + GAP)
		_draw_card(Rect2(x, 0.0, CARD_W, CARD_H), key, i == _hover, key == _selected)

func _draw_card(r: Rect2, key: String, hovered: bool, selected: bool) -> void:
	var entry: Dictionary = Data.character(key)
	var accent := Color(str(entry.get("color", "#ffffff")))
	# 底板：选中/悬停时更亮
	var bg := Color(0.13, 0.15, 0.20, 0.92)
	if selected:
		bg = Color(0.20, 0.24, 0.32, 0.98)
	elif hovered:
		bg = Color(0.17, 0.19, 0.25, 0.95)
	draw_rect(r, bg)
	# 选中用角色主色描边，未选中灰边
	var border := accent if selected else Color(0.35, 0.38, 0.45, 0.8)
	draw_rect(r, border, false, 3.0 if selected else 1.5)

	# 立绘：优先 char_<key>；缺图退化成一个主色圆点，玩家仍能分辨
	var tex := Art.sprite("char_" + key)
	var icon_r := 30.0
	var c := Vector2(r.position.x + CARD_W * 0.5, r.position.y + 38.0)
	if tex != null:
		var s := icon_r * 2.2
		draw_texture_rect_region(tex, Rect2(c.x - s * 0.5, c.y - s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
	else:
		draw_circle(c, icon_r * 0.8, accent)
		draw_arc(c, icon_r * 0.8, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 2.0, true)

	# 名字（英文，出海）
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var name := str(entry.get("en", key))
	var nw := fs.get_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(fs, Vector2(c.x - nw.x * 0.5, r.position.y + 78.0), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(1, 1, 1, 0.96) if selected else Color(0.78, 0.82, 0.88, 0.9))

	# 属性摘要：有加成才显示，纯基准角色显示 "BASE"
	var desc := Character.describe(entry)
	if desc.is_empty() or entry.get("stats", {}).is_empty():
		desc = "BASE"
	var dw := fs.get_string_size(desc, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	draw_string(fs, Vector2(c.x - dw.x * 0.5, r.position.y + 96.0), desc,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.95, 0.80, 0.40, 0.95) if selected else Color(0.62, 0.66, 0.72, 0.85))

	# 选中标记：右上角一个小三角
	if selected:
		var tp := Vector2(r.position.x + CARD_W - 14.0, r.position.y + 10.0)
		draw_colored_polygon(PackedVector2Array([
			tp, tp + Vector2(10.0, 0.0), tp + Vector2(5.0, 8.0)]), accent)
