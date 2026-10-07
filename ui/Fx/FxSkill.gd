extends Node2D

# 主动技能施放特效（纯表现）。
# 一套骨架（起手亮芯 + 三层扩张环 + 滞留场），样式按【当前形态】换：
# 冰=冰晶、毒=气泡、火/金=火星、电=电弧、风=风刃。形态变了特效跟着变 ——
# 玩家不用读字，看一眼颜色就知道"这一招换了个打法"。
# 只订阅 Events.skill_cast，不认识 Player/Game/Enemy，删掉也不影响玩法
# （验收标准同 FxLayer：表现层与玩法层解耦）。
#
# ⚠️ 之前太淡：环只有 4px/0.9alpha、滞留云 0.18alpha，玩家"根本没看到效果"。
#    现在改成：起手亮芯 + 三层粗环 + 明显滞留场。
# ⚠️ 位置一律由 index 推导，不用随机源——保持 headless 模拟可复现。

const Shake := preload("res://entities/effects/Shake.gd")
const SkillLook := preload("res://ui/SkillLook.gd")

# 各种滞留场的持续时间（秒）：控制类留久一点看得清，爆发类短促收尾
const CLOUD_OF := {"shards": 1.2, "bubbles": 1.9, "sparks": 0.9, "arcs": 1.0, "blades": 0.8}

var _fx: Array = []      # [{pos,radius,t,life,cloud,style,color}]

func _ready() -> void:
	Events.skill_cast.connect(_on_cast)

func _on_cast(id: String, pos: Vector2, radius: float, form: String) -> void:
	var style := SkillLook.style_of(id, form)
	_fx.append({
		"pos": pos,
		"radius": radius,
		"t": 0.0,
		"life": 0.75 if style == "shards" else 0.8,
		"cloud": float(CLOUD_OF.get(style, 1.2)),
		"style": style,
		"color": SkillLook.color_of(id, form),
	})
	if style == "shards":
		Shake.kick(4.0, 0.14)

func _process(delta: float) -> void:
	# 没有任何技能特效在播就完全不重绘（旧写法每帧都 queue_redraw，白刷一层画布）
	var had := not _fx.is_empty()
	var i := 0
	while i < _fx.size():
		var d: Dictionary = _fx[i]
		d["t"] = float(d.get("t", 0.0)) + delta
		var total: float = float(d.get("life", 0.75)) + float(d.get("cloud", 1.2))
		if float(d.get("t", 0.0)) > total:
			_fx.remove_at(i)
		else:
			i += 1
	if had:
		queue_redraw()

func _draw() -> void:
	for d in _fx:
		_draw_one(d)

func _draw_one(d: Dictionary) -> void:
	var t: float = float(d.get("t", 0.0))
	var life: float = float(d.get("life", 0.75))
	var radius: float = float(d.get("radius", 150.0))
	var col: Color = d.get("color", Color(0.6, 0.85, 0.5))
	var style: String = str(d.get("style", "sparks"))
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

	# 3) 滞留场：按形态换装饰。画成"甜甜圈"而不是整块实心圆 —— 技能是在脚下放的，
	#    实心圆会把主角整只糊住（Fx 层在 CanvasLayer，必然盖住主角）。
	var ct: float = t - life
	if ct < 0.0:
		return
	var ca: float = clampf(1.0 - ct / maxf(0.001, float(d.get("cloud", 1.2))), 0.0, 1.0)
	draw_arc(p, radius * 0.70, 0.0, TAU, 52,
		Color(col.r, col.g, col.b, ca * 0.36), radius * 0.58, true)
	draw_arc(p, radius * 0.95, 0.0, TAU, 44, Color(col.r, col.g, col.b, ca * 0.55), 3.0, true)
	match style:
		"shards":
			_draw_shards(p, radius, ca)
		"bubbles":
			_draw_bubbles(p, radius, ca, t, col)
		"arcs":
			_draw_arcs(p, radius, ca, t)
		"blades":
			_draw_blades(p, radius, ca, t)
		_:
			_draw_sparks(p, radius, ca, t, col)

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

# 火星（火/金/炭形态）：向外飘的小亮点，越远越淡
func _draw_sparks(p: Vector2, radius: float, a: float, t: float, col: Color) -> void:
	var n := 12
	for i in n:
		var ang: float = TAU * float(i) / float(n) + 0.15
		var k: float = float(i % 4) / 4.0
		var rr: float = radius * (0.35 + 0.55 * k) + sin(t * 3.0 + float(i)) * radius * 0.05
		var sp: Vector2 = p + Vector2(cos(ang), sin(ang)) * rr
		var sr: float = radius * (0.07 - 0.03 * k)
		draw_circle(sp, sr, Color(1.0, 0.92, 0.62, a * (0.85 - 0.4 * k)))
		draw_circle(sp, sr * 0.5, Color(col.r, col.g, col.b, a * 0.9))

# 电弧（电场形态）：从中心甩出去的锯齿线，每条折 4 段
func _draw_arcs(p: Vector2, radius: float, a: float, t: float) -> void:
	var n := 6
	for i in n:
		var ang: float = TAU * float(i) / float(n) + t * 1.6
		var u := Vector2(cos(ang), sin(ang))
		var side := u.rotated(PI * 0.5)
		var pts := PackedVector2Array([p + u * radius * 0.34])
		for s in 4:
			var rr: float = radius * (0.34 + 0.17 * float(s + 1))
			var off: float = radius * 0.09 * (1.0 if s % 2 == 0 else -1.0)
			pts.append(p + u * rr + side * off)
		draw_polyline(pts, Color(0.86, 0.94, 1.0, a * 0.85), 3.0, true)

# 风刃（风刃形态）：沿边缘切出去的弧线，一圈都在转
func _draw_blades(p: Vector2, radius: float, a: float, t: float) -> void:
	var n := 8
	for i in n:
		var ang: float = TAU * float(i) / float(n) + t * 2.4
		var a0: float = ang
		var a1: float = ang + 0.55
		draw_arc(p, radius * 0.62, a0, a1, 12, Color(0.92, 1.0, 0.96, a * 0.8), 6.0, true)
		draw_arc(p, radius * 0.90, a0 + 0.2, a1 + 0.2, 10,
			Color(0.72, 0.95, 0.86, a * 0.5), 4.0, true)
