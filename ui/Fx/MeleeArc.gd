extends Node2D

# 近战挥砍的短命扇形：只画，不认识任何玩法对象。
# 与 FxRings 同一个套路 —— FxLayer 把 arcs 数组引用直接塞进来（Array 是引用类型），
# 所以 FxLayer 每帧增删这里立刻可见，不用再同步。

var arcs: Array = []

const STEPS := 18

func _draw() -> void:
	if arcs.is_empty():
		return
	for a in arcs:
		var d: Dictionary = a as Dictionary
		if d.is_empty():
			continue
		var t: float = float(d.get("t", 0.0))
		var life: float = float(d.get("life", 0.16))
		var k: float = clampf(t / life, 0.0, 1.0)
		var origin: Vector2 = d.get("origin", Vector2.ZERO)
		var dir: Vector2 = d.get("dir", Vector2(1, 0))
		var reach: float = float(d.get("reach", 150.0))
		var half: float = float(d.get("half", 1.0))
		var col: Color = d.get("color", Color(1, 1, 1))
		var a0 := dir.angle() - half
		var a1 := dir.angle() + half
		var fade := 1.0 - k
		# 扇形填充（淡）
		var pts := PackedVector2Array()
		pts.append(origin)
		for i in range(STEPS + 1):
			var ang := a0 + (a1 - a0) * (float(i) / float(STEPS))
			pts.append(origin + Vector2(cos(ang), sin(ang)) * reach)
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, fade * 0.32))
		# 亮边弧（挥砍感）
		var edge := PackedVector2Array()
		for i in range(STEPS + 1):
			var ang := a0 + (a1 - a0) * (float(i) / float(STEPS))
			edge.append(origin + Vector2(cos(ang), sin(ang)) * reach)
		draw_polyline(edge, Color(col.r, col.g, col.b, fade * 0.85), 3.0, true)
