extends Node2D

# 命中迸溅 + 枪口火光 + 颠勺爆炒：短命的世界空间小特效，由 FxLayer 喂数组、本层只画。
# 和 rings/arcs/cracks 同一套路 —— FxLayer 把数组引用直接塞进来，双方看同一份。
#
# 三种 kind：
#   "impact"  敌人挨打时的卡通星芒爆点（随命中颜色上色，暴击更亮）
#   "muzzle"  远程武器枪口火光；scale 放大、wide=true 则星芒更宽（火箭筒/霰弹专属）
#   "boom"    颠勺大招的爆炒溅射：大团橙色火球膨胀后淡出

var pops: Array = []   # [{pos, t, life, kind, color, scale, wide}]

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
		var kind: String = str(d.get("kind", "impact"))
		if kind == "muzzle":
			_draw_muzzle(pos, k, col, float(d.get("scale", 1.0)), bool(d.get("wide", false)))
		elif kind == "boom":
			_draw_boom(pos, k, col)
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
	draw_arc(pos, r * 0.42, 0.0, TAU, 12, INK, 1.4, true)

# 枪口火光：亮核 + 武器色 + 星芒；scale 放大整体、wide 让星芒铺得更开
func _draw_muzzle(pos: Vector2, k: float, col: Color, sc: float, wide: bool) -> void:
	var a: float = 1.0 - k
	var r: float = lerpf(10.0, 3.0, k) * sc
	draw_circle(pos, r, Color(1, 1, 1, a))
	draw_circle(pos, r * 0.62, Color(col.r, col.g, col.b, a))
	var spread: float = 1.7 if wide else 1.2
	for i in 4:
		var ang: float = TAU * float(i) / 4.0 + k * 0.6
		var dlen: float = r * (spread + k)
		var tip: Vector2 = pos + Vector2(cos(ang), sin(ang)) * dlen
		draw_line(pos, tip, Color(1, 1, 1, a * 0.85), 2.0 * sc)

# 颠勺爆炒：大团橙红火球膨胀 + 白核 + 暗边，越扩越淡
func _draw_boom(pos: Vector2, k: float, col: Color) -> void:
	var a: float = 1.0 - k
	var r: float = lerpf(10.0, 92.0, k)
	draw_circle(pos, r + 3.0, Color(INK.r, INK.g, INK.b, a * 0.5))
	draw_circle(pos, r, Color(col.r, col.g, col.b, a * 0.85))
	draw_circle(pos, r * 0.5, Color(1, 0.92, 0.7, a))
	var n: int = 7
	for i in n:
		var ang: float = TAU * float(i) / float(n) + k * 0.8
		var d0: Vector2 = pos + Vector2(cos(ang), sin(ang)) * r * 0.7
		var d1: Vector2 = pos + Vector2(cos(ang), sin(ang)) * r * 1.25
		draw_line(d0, d1, Color(1, 0.85, 0.5, a * 0.9), 3.0)
