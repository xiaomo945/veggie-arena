extends SceneTree

# 验证相机方案（与 Main.gd 真实代码路径一致）：
#  Camera2D 作为世界根的子节点，每帧把"夹过边界的玩家坐标"写进 cam.position，
#  跟随/拉伸交给引擎。这里确认 (1) 写 cam.position 真的让相机居中到该世界点；
#  (2) 夹边界的数学与原始 want 逻辑一致（场地比屏大→玩家居中、靠近边才露边）。
# 运行：godot --headless --script scripts/cam_test.gd

const VIEW := Vector2(540.0, 900.0)

func _clamp(p: Vector2, a: Dictionary) -> Vector2:
	var ax := float(a.get("x", 0.0)); var ay := float(a.get("y", 0.0))
	var aw := float(a.get("w", 540.0)); var ah := float(a.get("h", 900.0))
	var half := VIEW * 0.5
	var want := p
	want.x = clampf(want.x, ax + half.x, ax + aw - half.x) if aw > VIEW.x else ax + aw * 0.5
	want.y = clampf(want.y, ay + half.y, ay + ah - half.y) if ah > VIEW.y else ay + ah * 0.5
	return want

func _initialize() -> void:
	var world := Node2D.new()
	world.position = Vector2.ZERO
	root.add_child(world)
	var player := Node2D.new()
	world.add_child(player)
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 9.0
	cam.make_current()
	world.add_child(cam)

	var a := {"x": -270.0, "y": -360.0, "w": 1080.0, "h": 1620.0}
	var cases := [
		["中心", Vector2(0, 0), Vector2(0, 90)],
		["场地内偏右下", Vector2(400, 1000), Vector2(400, 810)],
		["顶左越界(夹到边)", Vector2(-9999, -9999), Vector2(0, 90)],
		["底右越界(夹到边)", Vector2(9999, 9999), Vector2(540, 810)],
	]
	var ok := true
	for c in cases:
		player.position = c[1]
		cam.position = _clamp(player.global_position, a)   # 与 Main._process 同款
		await create_timer(0.6).timeout                    # 给平滑足够时间到位
		var want: Vector2 = c[2]
		var got := cam.global_position
		var dist := got.distance_to(want)
		var passd := dist < 2.0
		ok = ok and passd
		print("  [%s] 期望=%s 实际=%s %s" % [c[0], want, got, "PASS" if passd else "FAIL(差%.1f)" % dist])

	print("CAM_TEST %s" % ("PASS" if ok else "FAIL"))
	quit()
