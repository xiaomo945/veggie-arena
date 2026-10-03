extends Node2D

# 主动技能施放特效（纯表现）。
# 冰镇 = 青色扩张环 + 冰晶迸裂 + 滞留霜面；毒雾 = 绿色扩张环 + 翻涌气泡毒云。
# 只订阅 Events.skill_cast，不认识 Player/Game/Enemy，删掉也不影响玩法
# （验收标准同 FxLayer：表现层与玩法层解耦）。
#
# ⚠️ 之前太淡：环只有 4px/0.9alpha、滞留云 0.18alpha，玩家"根本没看到效果"。
#    现在改成：起手亮芯 + 三层粗环 + 明显滞留场（冰有冰晶、毒有气泡）。
# ⚠️ 位置一律由 index 推导，不用随机源——保持 headless 模拟可复现。

const Shake := preload("res://entities/effects/Shake.gd")

var _fx: Array = []      # [{pos,radius,t,life,cloud,frost,color}]

func _ready() -> void:
	Events.skill_cast.connect(_on_cast)

func _on_cast(id: String, pos: Vector2, radius: float) -> void:
	var is_frost: bool = (id == "frost")
	_fx.append({
		"pos": pos,
		"radius": radius,
		"t": 0.0,
		"life": 0.75 if is_frost else 0.8,
		"cloud": 1.2 if is_frost else 1.9,   # 滞留场时长（秒）
		"frost": is_frost,
		"color": Color(0.45, 0.85, 1.0) if is_frost else Color(0.45, 0.9, 0.35),
	})
	if is_frost:
		Shake.kick(4.0, 0.14)

func _process(delta: float) -> void:
	var i := 0
	while i < _fx.size():
		var d: Dictionary = _fx[i]
		d["t"] = float(d.get("t", 0.0)) + delta
		var total: float = float(d.get("life", 0.75)) + float(d.get("cloud", 1.2))
		if float(d.get("t", 0.0)) > total:
			_fx.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	for d in _fx:
		_draw_one(d)

func _draw_one(d: Dictionary) -> void:
	var t: float = float(d.get("t", 0.0))
	var life: float = float(d.get("life", 0.75))
	var radius: float = float(d.get("radius", 150.0))
	var col: Color = d.get("color", Color(0.6, 0.85, 0.5))
	var frost: bool = bool(d.get("frost", false))
	var p: Vector2 = d.get("pos", Vector2.ZERO)

	# 1) 起手亮芯：让"放出去了"这一下有实感
	if t < 0.2:
		var fa: float = 1.0 - t / 0.2
		draw_circle(p, radius * (0.16 + 0.55 * (t / 0.2)),
			Color(col.r, col.g, col.b, fa * 0.5))

	# 2) 扩张环：三层、粗、亮
	if t < life:
		var k: float = clampf(t / life, 0.0, 1.0)
		var a: float = 1.0 - k
		var rad: float = lerpf(radius * 0.25, radius, k)
		draw_arc(p, rad, 0.0, TAU, 48, Color(col.r, col.g, col.b, a * 0.95), 9.0, true)
		draw_arc(p, rad * 0.82, 0.0, TAU, 40, Color(col.r, col.g, col.b, a * 0.6), 5.0, true)
		draw_arc(p, rad * 0.6, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, a * 0.45), 3.0, true)

	# 3) 滞留场：冰=霜面+冰晶；毒=翻涌气泡云
	var ct: float = t - life
	if ct >= 0.0:
		var ca: float = clampf(1.0 - ct / maxf(0.001, float(d.get("cloud", 1.2))), 0.0, 1.0)
		if frost:
			draw_circle(p, radius * 0.95, Color(col.r, col.g, col.b, ca * 0.30))
			draw_arc(p, radius * 0.95, 0.0, TAU, 44,
				Color(0.85, 0.97, 1.0, ca * 0.6), 3.0, true)
			_draw_shards(p, radius, ca)
		else:
			draw_circle(p, radius * 0.95, Color(col.r, col.g, col.b, ca * 0.34))
			_draw_bubbles(p, radius, ca, t, col)

# 冰晶：沿边缘迸出的小尖刺（位置由 index 推导，不用随机）
func _draw_shards(p: Vector2, radius: float, a: float) -> void:
	var n := 10
	for i in n:
		var ang: float = TAU * float(i) / float(n) + 0.3
		var u := Vector2(cos(ang), sin(ang))
		var base: Vector2 = p + u * radius * 0.55
		var tip: Vector2 = p + u * radius * (0.80 + 0.12 * sin(float(i)))
		var w: Vector2 = u.rotated(PI * 0.5) * radius * 0.07
		draw_colored_polygon(PackedVector2Array([base - w, base + w, tip]),
			Color(0.88, 0.98, 1.0, a * 0.75))

# 毒气泡：场内翻涌的小泡（位置由 index 推导）
func _draw_bubbles(p: Vector2, radius: float, a: float, t: float, col: Color) -> void:
	var n := 9
	for i in n:
		var ang: float = TAU * float(i) / float(n) + 0.7
		var rr: float = radius * (0.30 + 0.42 * (float(i % 3) / 3.0))
		var rise: float = sin(t * 2.2 + float(i)) * radius * 0.06
		var bp: Vector2 = p + Vector2(cos(ang), sin(ang)) * rr + Vector2(0.0, rise)
		var br: float = radius * (0.10 + 0.05 * float(i % 2))
		draw_circle(bp, br, Color(col.r * 1.1, col.g * 1.1, col.b * 0.9, a * 0.5))
		draw_arc(bp, br, 0.0, TAU, 14, Color(0.9, 1.0, 0.85, a * 0.55), 2.0, true)
