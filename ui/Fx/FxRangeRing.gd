extends Node2D

# 金币拾取范围预览环：买完"金币拾取范围"类强化时，从玩家位置扩散到当前磁吸半径的金色环，
# 0.6 秒淡出。让"拾取范围 +N"这种纯数值变化一眼可见（否则玩家根本看不到自己变强了）。
# 纯表现层，订阅 Events.player_range_preview；玩家世界坐标从 main scene 的 player 节点取。

var rings: Array = []

const GOLD := Color(1.0, 0.82, 0.29)
const LIFE := 0.6

func _ready() -> void:
	Events.player_range_preview.connect(_on_preview)

func _on_preview(radius: float) -> void:
	var pos := Vector2.ZERO
	var cs = get_tree().current_scene
	if cs != null:
		var p = cs.get("player")
		if p != null and p is Node2D:
			pos = (p as Node2D).global_position
	if rings.size() < 8:
		rings.append({"pos": pos, "t": 0.0, "radius": maxf(radius, 1.0)})

func _process(delta: float) -> void:
	var had := not rings.is_empty()
	var i := 0
	while i < rings.size():
		var d: Dictionary = rings[i]
		d["t"] = float(d.get("t", 0.0)) + delta
		if float(d.get("t", 0.0)) >= LIFE:
			rings.remove_at(i)
		else:
			i += 1
	if had:
		queue_redraw()

func _draw() -> void:
	if rings.is_empty():
		return
	for r in rings:
		var d: Dictionary = r as Dictionary
		var k: float = clampf(float(d.get("t", 0.0)) / LIFE, 0.0, 1.0)
		var a := 1.0 - k
		var rad := lerpf(float(d.get("radius", 1.0)) * 0.15, float(d.get("radius", 1.0)), k)
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		# 外环：从内向外扩散并淡出
		draw_arc(pos, rad, 0.0, TAU, 40, Color(GOLD.r, GOLD.g, GOLD.b, a * 0.9), 4.0, true)
		# 内环：增强"范围"体感
		draw_arc(pos, rad * 0.7, 0.0, TAU, 32, Color(GOLD.r, GOLD.g, GOLD.b, a * 0.35), 2.0, true)
