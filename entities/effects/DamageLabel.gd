extends Node2D

# 伤害飘字：命中时在敌人位置生成，上浮并淡出，约 1.2s 后自毁。
# 纯表现层，由 EnemySystem.damage_enemy 调用 init() 后 add_child 到 game 节点。

var _lbl: Label = null

func _ready() -> void:
	_lbl = Label.new()
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_lbl)

# amount: 伤害值；crit: 是否暴击；pos: 世界坐标
func init(amount: int, crit: bool, pos: Vector2) -> void:
	_lbl.text = str(amount)
	var col := Color(1, 1, 1, 1)
	var sz := 20
	if crit:
		col = Color(1.0, 0.85, 0.2, 1.0)
		sz = 28
	elif amount >= 30:
		col = Color(1.0, 0.55, 0.35, 1.0)
		sz = 24
	_lbl.add_theme_font_size_override("font_size", sz)
	_lbl.modulate = col
	global_position = pos
	var t := create_tween()
	t.tween_property(self, "position", pos + Vector2(0, -44.0), 1.15).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_lbl, "modulate:a", 0.0, 1.15)
	t.parallel().tween_property(_lbl, "scale", Vector2.ONE * 1.25, 0.14).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(queue_free)
