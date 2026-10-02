extends Node2D

# 击杀迸溅（三层叠加）：碎块飞散 + 汁液飞溅 + 爆环。
# 之前只有一圈爆环，"啪"一下就没了；三层叠起来才像"切开的蔬菜炸开"。
#
# rings 由 FxLayer 在 _ready 里把数组引用塞进来（Array 是引用类型），
# FxLayer 每帧的增删这里立刻可见，不用再同步。
#
# 全部绘制无状态：同一帧里由 t 与序号决定形状（种子固定），不闪帧。

var rings: Array = []

const INK := Color(0.06, 0.05, 0.09, 1.0)

# 汁液颜色按敌人类型：切什么菜溅什么汁
const JUICE := {
	"grunt": Color(0.88, 0.38, 0.37), "fast": Color(0.94, 0.60, 0.29),
	"tank": Color(0.60, 0.48, 0.82), "fly": Color(0.34, 0.81, 0.88),
	"boss": Color(0.85, 0.25, 0.30), "swarm": Color(0.55, 0.80, 0.40),
	"brute": Color(0.78, 0.48, 0.30), "shambler": Color(0.62, 0.72, 0.38),
}

func _draw() -> void:
	if rings.is_empty():
		return
	for r in rings:
		var d: Dictionary = r as Dictionary
		if d.is_empty():
			continue
		var t: float = float(d.get("t", 0.0))
		var life: float = float(d.get("life", 0.5))
		var k: float = clampf(t / life, 0.0, 1.0)
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		var big: bool = bool(d.get("big", false))
		var col: Color = d.get("color", Color(1.0, 0.88, 0.55))
		_ring(pos, k, big, col)
		_chunks(pos, k, big, col)
		_juice(pos, k, big, col)

# 1) 爆环：快速扩张的白/金双环，前 0.34 秒内完成
func _ring(pos: Vector2, k: float, big: bool, col: Color) -> void:
	var kr := clampf(k / 0.68, 0.0, 1.0)
	if kr >= 1.0:
		return
	var a := 1.0 - kr
	var maxr := 96.0 if big else 42.0
	var rad := lerpf(6.0, maxr, kr)
	if big:
		draw_arc(pos, rad, 0.0, TAU, 26, Color(1.0, 0.62, 0.30, a * 0.85), 4.5, true)
	else:
		draw_arc(pos, rad, 0.0, TAU, 22, Color(1.0, 0.95, 0.75, a * 0.85), 2.6, true)
	draw_arc(pos, rad * 0.72, 0.0, TAU, 20, Color(col.r, col.g, col.b, a * 0.6), 2.0, true)

# 2) 碎块：4~7 块带暗描边的小多边形，边飞边转边淡出（皮/壳的碎片）
func _chunks(pos: Vector2, k: float, big: bool, col: Color) -> void:
	var n := 7 if big else 4
	for i in n:
		var rng_a := TAU * (float(i) / float(n)) + float(i * 37 % 13) * 0.11
		var dist := (52.0 if big else 30.0) * (0.7 + 0.3 * sin(float(i) * 2.7))
		var p := pos + Vector2(cos(rng_a), sin(rng_a)) * dist * k
		var sz := (7.5 if big else 5.0) * (1.0 - k * 0.55)
		var rot := rng_a + k * (5.0 + float(i % 3) * 2.0)
		var poly := PackedVector2Array()
		var sides := 3 + (i % 2)
		for s in sides:
			var a2 := rot + TAU * float(s) / float(sides)
			poly.append(p + Vector2(cos(a2), sin(a2)) * sz)
		draw_colored_polygon(poly, Color(INK.r, INK.g, INK.b, (1.0 - k) * 0.55))
		var inner := PackedVector2Array()
		for s in sides:
			var a3 := rot + TAU * float(s) / float(sides)
			inner.append(p + Vector2(cos(a3), sin(a3)) * sz * 0.62)
		draw_colored_polygon(inner, Color(col.r, col.g, col.b, 1.0 - k))

# 3) 汁液：一圈小圆点甩出去，先快后慢，最后淡出（湿漉漉的最后一笔）
func _juice(pos: Vector2, k: float, big: bool, col: Color) -> void:
	var n := 8 if big else 6
	for i in n:
		var ang := TAU * (float(i) / float(n)) + float(i) * 0.8
		var u := Vector2(cos(ang), sin(ang))
		# 抛物线感：距离 ease-out，纵向坠一点
		var dist := (64.0 if big else 38.0) * (1.0 - pow(1.0 - k, 1.8))
		var p := pos + u * dist + Vector2(0.0, k * k * 14.0)
		var r := (4.2 if big else 2.8) * (1.0 - k * 0.7)
		draw_circle(p, r + 1.2, Color(INK.r, INK.g, INK.b, (1.0 - k) * 0.5))
		draw_circle(p, r, Color(col.r, col.g, col.b, 1.0 - k * 0.9))
