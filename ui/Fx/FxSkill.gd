extends Node2D

# 主动技能施放特效（纯表现）。
# 冰镇 = 青色扩张环 + 短暂震屏；毒雾 = 绿色扩张环 + 滞留毒云（半透明填充圆缓慢淡出）。
# 只订阅 Events.skill_cast，不认识 Player/Game/Enemy，删掉也不影响玩法
# （验收标准同 FxLayer：表现层与玩法层解耦）。

const Shake := preload("res://entities/effects/Shake.gd")

var _fx: Array = []      # [{id,pos,radius,t,life,cloud,frost,color}]

func _ready() -> void:
	Events.skill_cast.connect(_on_cast)

func _on_cast(id: String, pos: Vector2, radius: float) -> void:
	var is_frost: bool = (id == "frost")
	_fx.append({
		"id": id,
		"pos": pos,
		"radius": radius,
		"t": 0.0,
		"life": 0.55 if is_frost else 0.7,
		"cloud": 1.4 if not is_frost else 0.0,   # 毒雾滞留在场时间（秒）
		"frost": is_frost,
		"color": Color(0.5, 0.85, 1.0) if is_frost else Color(0.55, 0.85, 0.4),
	})
	if is_frost:
		Shake.kick(4.0, 0.14)

func _process(delta: float) -> void:
	var i := 0
	while i < _fx.size():
		var d: Dictionary = _fx[i]
		d["t"] = float(d.get("t", 0.0)) + delta
		var total: float = float(d.get("life", 0.7)) + float(d.get("cloud", 0.0))
		if float(d.get("t", 0.0)) > total:
			_fx.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	for d in _fx:
		var t: float = float(d.get("t", 0.0))
		var life: float = float(d.get("life", 0.7))
		var radius: float = float(d.get("radius", 150.0))
		var col: Color = d.get("color", Color(0.6, 0.85, 0.5))
		var frost: bool = bool(d.get("frost", false))
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		# 扩张环（前 life 秒）
		if t < life:
			var k := clampf(t / life, 0.0, 1.0)
			var a := 1.0 - k
			var rad := lerpf(radius * 0.3, radius, k)
			draw_arc(p, rad, 0.0, TAU, 32, Color(col.r, col.g, col.b, a * 0.9), 4.0, true)
			draw_arc(p, rad * 0.78, 0.0, TAU, 28, Color(col.r, col.g, col.b, a * 0.5), 2.5, true)
		# 毒雾：life 之后继续滞留一段，半透明填充圆缓慢淡出
		if not frost:
			var ct := t - life
			if ct >= 0.0:
				var ca := clampf(1.0 - ct / maxf(0.001, float(d.get("cloud", 1.4))), 0.0, 1.0)
				draw_circle(p, radius * 0.92, Color(col.r, col.g, col.b, ca * 0.18))
