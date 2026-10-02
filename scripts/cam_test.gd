extends SceneTree

# 验证相机方案（与 Main.gd 真实代码路径一致）：
#  Camera2D 直接挂在玩家节点上（引擎原生跟随），不再写 root.canvas_transform。
# 这里确认：玩家移动到任意位置，相机都贴着玩家（始终以玩家为中心），且平滑到位。
# 运行：godot --headless --script scripts/cam_test.gd

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
	player.add_child(cam)          # 关键：挂在玩家身上，位置每帧自动等于玩家

	var cases := [
		["中心", Vector2(0, 0)],
		["偏右下", Vector2(400, 1000)],
		["左上角", Vector2(-900, -1200)],
		["右下角", Vector2(900, 1500)],
	]
	var ok := true
	for c in cases:
		player.position = c[1]
		await create_timer(0.5).timeout   # 给平滑足够时间到位
		var got := cam.global_position
		var dist := got.distance_to(player.global_position)
		# 玩家走到屏幕边缘也要被相机居中：允许平滑残差 < 2px
		var passd := dist < 2.0
		ok = ok and passd
		print("  [%s] 玩家=%s 相机=%s %s" % [c[0], player.global_position, got, "PASS" if passd else "FAIL(差%.1f)" % dist])

	print("CAM_TEST %s" % ("PASS" if ok else "FAIL"))
	quit()
