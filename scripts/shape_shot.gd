extends SceneTree

# 临时目检脚本（用完即删）：把所有敌人的手绘造型摆一屏截图，检查 rim light / 落地阴影 / 表情。
# 跑法：xvfb-run -s "-screen 0 540x900x24" godot --path . --script res://scripts/shape_shot.gd

const Shape := preload("res://entities/Enemy/EnemyShape.gd")
# [类型, 配色] —— 与任务给定的各类型色板一致
const TYPES := [
	["grunt", "#e0605f"], ["fast", "#ef9a4a"], ["tank", "#9a7ad0"],
	["fly", "#56cfe0"], ["boss", "#e0507a"], ["swarm", "#c8e06a"],
	["brute", "#7a5ac0"], ["shambler", "#5a8a4a"], ["shooter", "#b06bff"],
	["charger", "#ff7a4d"], ["splitter", "#c58aff"], ["bomber", "#ff5b6e"],
	["splitling", "#d9a8ff"],
]

func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.22, 0.18)
	bg.size = Vector2(540, 900)
	root.add_child(bg)
	var board := ShapeBoard.new()
	root.add_child(board)
	for _i in 4:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/shapes.png")
	print("SHOT /tmp/shapes.png")
	quit(0)

class ShapeBoard extends Node2D:
	func _draw() -> void:
		var cols := 4
		for i in TYPES.size():
			var x := 75.0 + float(i % cols) * 135.0
			var y := 90.0 + float(i / cols) * 160.0
			draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
			Shape.body(self, TYPES[i][0], 26.0, Color(TYPES[i][1]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
