extends Node2D

# 精英怪出场：地面光环扩散 + 出生瞬间的时间暂缓（limbo）+ 精英色描边。
# 订阅 Events.enemy_spawned（EnemySystem 刷出精英/Boss 时发），纯表现，删掉不影响玩法。
#
# 为什么是 Node2D（世界空间）：光环要"长在地上"，跟着镜头走；
# FxLayer 开了 follow_viewport_enabled，它的 Node2D 子节点就在世界坐标里。

const RING_LIFE := 0.55
const MAX_RINGS := 6
const LIMBO_SEC := 0.11

const HitStop := preload("res://entities/effects/HitStop.gd")

var _rings: Array = []   # [{pos, t, r0, r1, color, wide}]

func _ready() -> void:
	Events.enemy_spawned.connect(_on_spawn)

func _on_spawn(e: Node) -> void:
	if _rings.size() >= MAX_RINGS:
		return
	var elite := bool(e.get("elite"))
	var boss := str(e.get("etype")) == "boss"
	if not elite and not boss:
		return          # 普通小兵不值得给演出，怪海里全是环反而糊
	var col: Color = e.get("tint")
	# 精英：金色光环 + 一圈扩散的"词缀色"地面刻线
	var r0: float = float(e.get("radius")) * 1.2
	var r1: float = r0 + (150.0 if boss else 92.0)
	_rings.append({"pos": e.get("global_position"), "t": 0.0, "life": RING_LIFE,
		"r0": r0, "r1": r1, "color": col, "boss": boss})
	# 出生瞬间的时间暂缓：整个世界慢下来一瞬（精英 0.11s / Boss 0.2s）
	HitStop.hit(LIMBO_SEC if elite else 0.2, 0.18)

func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	var i := 0
	while i < _rings.size():
		var d: Dictionary = _rings[i]
		var t := float(d.get("t", 0.0)) + delta
		d["t"] = t
		if t >= float(d.get("life", RING_LIFE)):
			_rings.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	for r in _rings:
		var d := r as Dictionary
		var k := clampf(float(d.get("t", 0.0)) / float(d.get("life", RING_LIFE)), 0.0, 1.0)
		var pos: Vector2 = d.get("pos")
		var col: Color = d.get("color")
		var r0 := float(d.get("r0", 16.0))
		var r1 := float(d.get("r1", 90.0))
		# 前半段：实环扩散（地面上的能量圈）；后半段：越来越淡地消散
		var rad := lerpf(r0, r1, 1.0 - pow(1.0 - k, 2.2))
		var a := (1.0 - k)
		# 地面刻线：双圈 + 刻度线，比"一个圆"更像符文阵
		draw_arc(pos, rad, 0.0, TAU, 40, Color(col.r, col.g, col.b, a * 0.85), 4.0, true)
		draw_arc(pos, rad * 0.82, 0.0, TAU, 40, Color(col.r, col.g, col.b, a * 0.45), 2.0, true)
		var ticks := 10
		for i in ticks:
			var ang := TAU * float(i) / float(ticks) + k * 1.4
			var u := Vector2(cos(ang), sin(ang))
			draw_line(pos + u * rad * 0.86, pos + u * rad * 1.02,
				Color(1.0, 1.0, 1.0, a * 0.5), 2.0)
		if bool(d.get("boss", false)):
			# Boss 再加一道外圈光带，压迫感
			draw_arc(pos, rad * 1.14, 0.0, TAU, 40,
				Color(1.0, 0.35, 0.4, a * 0.4), 6.0, true)
