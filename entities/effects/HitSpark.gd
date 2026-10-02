extends Node2D

# 击杀爆点（卡通"噗叽"）：敌人死亡时由 EnemySystem 生成（init 后 add_child 到 game）。
# big=true 用于 Boss，碎屑更多、环更大。纯表现，约 0.5s 后自毁。
# 形状：圆润小团子四散 + 中心一团膨胀的"气" + 一圈胖环，读起来像卡通爆开。

const _OCT := 9   # 八边形近似圆

func _oct_poly(r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in _OCT:
		var a := TAU * float(i) / float(_OCT)
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

func init(pos: Vector2, big: bool) -> void:
	global_position = pos
	var count: int = 7
	var base: float = 72.0
	var s: float = 5.0
	var blob_c := Color(1.0, 0.92, 0.66)
	if big:
		count = 13
		base = 132.0
		s = 8.0
		blob_c = Color(1.0, 0.6, 0.42)
	# 中心"气团"：快速膨胀后淡出（卡通噗叽的核心）
	var puff := Polygon2D.new()
	puff.polygon = _oct_poly(s * 1.6)
	puff.color = blob_c
	add_child(puff)
	var tp := puff.create_tween()
	tp.tween_property(puff, "scale", Vector2.ONE * 2.2, 0.22).set_ease(Tween.EASE_OUT)
	tp.parallel().tween_property(puff, "modulate:a", 0.0, 0.34)
	tp.chain().tween_callback(puff.queue_free)
	# 四散小团子
	for i in count:
		var a: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var spd: float = base * randf_range(0.6, 1.2)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var blob := Polygon2D.new()
		blob.polygon = _oct_poly(s)
		blob.color = blob_c
		add_child(blob)
		var t := blob.create_tween()
		t.tween_property(blob, "position", dir * spd, 0.34).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(blob, "scale", Vector2.ONE * 0.3, 0.34)
		t.parallel().tween_property(blob, "modulate:a", 0.0, 0.34)
		t.chain().tween_callback(blob.queue_free)
	# 胖环
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	var rn := 20
	for k in rn:
		var ra: float = TAU * float(k) / float(rn)
		pts.append(Vector2(cos(ra), sin(ra)) * 8.0)
	ring.points = pts
	ring.closed = true
	ring.width = 5.0 if big else 4.0
	ring.default_color = Color(1.0, 0.78, 0.42, 0.95)
	add_child(ring)
	var tr := ring.create_tween()
	tr.tween_property(ring, "scale", Vector2.ONE * (3.6 if big else 2.6), 0.32).set_ease(Tween.EASE_OUT)
	tr.parallel().tween_property(ring, "modulate:a", 0.0, 0.32)
	tr.chain().tween_callback(ring.queue_free)
	var tc := create_tween()
	tc.tween_callback(queue_free).set_delay(0.5)
