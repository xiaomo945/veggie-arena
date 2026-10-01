extends Node2D

# 击杀碎屑 + 冲击波环。敌人死亡时由 EnemySystem 生成（init 后 add_child 到 game）。
# big=true 用于 Boss，碎屑更多、环更大。纯表现，约 0.45s 后自毁。

func init(pos: Vector2, big: bool) -> void:
	global_position = pos
	var count: int = 7
	var base: float = 70.0
	var s: float = 3.0
	if big:
		count = 14
		base = 140.0
		s = 5.0
	for i in count:
		var a: float = TAU * float(i) / float(count) + randf_range(-0.25, 0.25)
		var spd: float = base * randf_range(0.6, 1.25)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var shard := Node2D.new()
		add_child(shard)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-s, -s * 0.4), Vector2(s, -s * 0.4), Vector2(0, s)])
		if big:
			poly.color = Color(1.0, 0.55, 0.4)
		else:
			poly.color = Color(1.0, 0.9, 0.65)
		shard.add_child(poly)
		var t := shard.create_tween()
		t.tween_property(shard, "position", dir * spd, 0.35).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(poly, "modulate:a", 0.0, 0.35)
		t.chain().tween_callback(shard.queue_free)
	# 冲击波环
	var ring := Line2D.new()
	var r: float = 8.0
	var pts := PackedVector2Array()
	for k in 18:
		var ra: float = TAU * float(k) / 18.0
		pts.append(Vector2(cos(ra), sin(ra)) * r)
	ring.points = pts
	ring.closed = true
	if big:
		ring.width = 5.0
	else:
		ring.width = 3.0
	ring.default_color = Color(1.0, 0.9, 0.6, 0.9)
	add_child(ring)
	var ring_scale: float = 2.4
	if big:
		ring_scale = 3.6
	var tr := ring.create_tween()
	tr.tween_property(ring, "scale", Vector2.ONE * ring_scale, 0.3).set_ease(Tween.EASE_OUT)
	tr.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	tr.chain().tween_callback(ring.queue_free)
	# 自毁（子节点已各自 queue_free，这里清掉容器）
	var tc := create_tween()
	tc.tween_callback(queue_free).set_delay(0.45)
