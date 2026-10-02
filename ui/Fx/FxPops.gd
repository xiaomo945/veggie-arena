extends Node2D

# 命中迸溅 + 枪口火光：短命的世界空间小特效，由 FxLayer 喂数组、本层只画。
# 和 rings/arcs/cracks 同一套路 —— FxLayer 把数组引用直接塞进来，双方看同一份。
#
# 两种 kind：
#   "impact"  敌人挨打时的卡通星芒爆点（随命中颜色上色，暴击更亮）
#   "muzzle"  远程武器枪口的小火光（手枪这类开局武器最该有手感）

var pops: Array = []   # [{pos, t, life, kind, color, scale}]

const INK := Color(0.06, 0.05, 0.09, 1.0)

func _draw() -> void:
	if pops.is_empty():
		return
	for p in pops:
		var d := p as Dictionary
		if d.is_empty():
			continue
		var t: float = float(d.get("t", 0.0))
		var life: float = float(d.get("life", 0.18))
		var k: float = clampf(t / life, 0.0, 1.0)
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		var col: Color = d.get("color", Color(1, 1, 1))
		if str(d.get("kind", "impact")) == "muzzle":
			_draw_muzzle(pos, k, col)
		else:
			_draw_impact(pos, k, col)

# 命中迸溅：中心亮点 + 5 道卡通星芒，快速扩张后淡出
func _draw_impact(pos: Vector2, k: float, col: Color) -> void:
	var a: float = 1.0 - k
	var r: float = lerpf(3.0, 14.0, k)
	draw_circle(pos, r * 0.42, Color(1, 1, 1, a))
	var n: int = 5
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var p0: Vector2 = pos + Vector2(cos(ang), sin(ang)) * r * 0.3
		var p1: Vector2 = pos + Vector2(cos(ang), sin(ang)) * r * 1.5
		draw_line(p0, p1, col, 2.6)
	# 暗描边的小圈，让爆点在亮背景上也立得住
	draw_arc(pos, r * 0.42, 0.0, TAU, 12, INK, 1.4, true)

# 枪口火光：亮核 + 武器色 + 4 道短星芒，瞬间亮起再缩没
func _draw_muzzle(pos: Vector2, k: float, col: Color) -> void:
	var a: float = 1.0 - k
	var r: float = lerpf(10.0, 3.0, k)
	draw_circle(pos, r, Color(1, 1, 1, a))
	draw_circle(pos, r * 0.62, Color(col.r, col.g, col.b, a))
	var n: int = 4
	for i in n:
		var ang: float = TAU * float(i) / float(n) + k * 0.6
		var d: float = r * (1.5 + k)
		var tip: Vector2 = pos + Vector2(cos(ang), sin(ang)) * d
		draw_line(pos, tip, Color(1, 1, 1, a * 0.85), 2.0)
