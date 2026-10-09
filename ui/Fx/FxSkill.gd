extends Node2D

# 主动技能施放特效（纯表现）。
# 五种形态各有**一整套独立的运动语言** —— 不是"同一种圆圈换装饰"：
#   冰 shards  冻结：六棱尖刺从中心"定型"般刺出并停住，雪絮缓慢外飘（慢、脆、静态感）
#   毒 bubbles 蠕动：边界不断起伏的黏泡团 + 向上翻涌的泡（慢、沉、脏萌感）
#   火 sparks  爆燃：卡通"噗"的三层扇贝爆开 + 火舌向上窜 + 起手白闪（快、有爆发力）
#   电 arcs    放电：枝状闪电抽打 + 一瞬全白 + 折点余辉（极快、间歇性抖动）
#   风 blades  旋切：三把镰刃旋转 + 中心漩涡向内吸 + 花瓣外抛（持续旋转感）
# 差异体现在【轮廓】和【速度曲线】，不只是颜色 —— 玩家看一眼剪影就认得出是第几招。
#
# 只订阅 Events.skill_cast，不认识 Player/Game/Enemy，删掉也不影响玩法。
# ⚠️ 位置/相位一律由 index 推导，不用随机源 —— 保持 headless 模拟可复现。

const Shake := preload("res://entities/effects/Shake.gd")
const SkillLook := preload("res://ui/SkillLook.gd")

# 滞留场时长（秒）：控制类留久一点看得清，爆发类短促收尾
const CLOUD_OF := {"shards": 1.2, "bubbles": 1.9, "sparks": 0.9, "arcs": 1.0, "blades": 0.8}
# 每种形态的高光色（与 SkillLook 主色搭配，做描边/点缀）
const ACCENT_OF := {
	"shards": Color(0.86, 0.98, 1.0),
	"bubbles": Color(0.72, 1.0, 0.62),
	"sparks": Color(1.0, 0.88, 0.40),
	"arcs": Color(0.92, 0.97, 1.0),
	"blades": Color(0.86, 1.0, 0.92),
}

var _fx: Array = []

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
	# 没有特效在播就完全不重绘（旧写法每帧 queue_redraw，白刷一层画布）
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
	var cloud: float = float(d.get("cloud", 1.2))
	var p: Vector2 = d.get("pos", Vector2.ZERO)
	var acc: Color = ACCENT_OF.get(style, Color(1, 1, 1)) as Color
	# 滞留阶段进度 0→1（1 = 完全消散）
	var proc: float = clampf((t - life) / maxf(0.001, cloud), 0.0, 1.0)
	var fade: float = 1.0 - proc
	match style:
		"shards":
			_draw_freeze(p, radius, col, acc, t, life, proc, fade)
		"bubbles":
			_draw_poison(p, radius, col, acc, t, proc, fade)
		"sparks":
			_draw_fire(p, radius, col, acc, t, life, proc, fade)
		"arcs":
			_draw_bolt(p, radius, col, acc, t, life, proc, fade)
		_:
			_draw_wind(p, radius, col, acc, t, proc, fade)

# 带波浪/扇贝边的环点集：让轮廓不是死圆（所有形态复用）
func _wobble(c: Vector2, r: float, n: int, amp: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var rr: float = r * (1.0 + amp * sin(float(n) * a * 0.5 + phase))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts

# 卡通 ease-out：起手窜得猛、收尾慢（爆燃/刺出的手感来源）
func _out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)

# ── 冰：六棱尖刺"定型"刺出 + 雪絮外飘 ────────────────────────────────
func _draw_freeze(p: Vector2, radius: float, col: Color, acc: Color,
		t: float, life: float, proc: float, fade: float) -> void:
	var grow: float = _out(clampf(t / life, 0.0, 1.0)) * (1.0 - 0.22 * proc)
	var n := 6
	for i in n:
		var ang: float = TAU * float(i) / float(n) + 0.3
		var u := Vector2(cos(ang), sin(ang))
		var tip: Vector2 = p + u * radius * 0.95 * grow
		var w: Vector2 = u.rotated(PI * 0.5) * radius * 0.10 * grow
		var mid: Vector2 = p + u * radius * 0.52 * grow
		# 主尖刺（带白尖的高光，一看就是冰棱）
		draw_colored_polygon(PackedVector2Array([p + w, tip, p - w]),
			Color(col.r, col.g, col.b, fade * 0.68))
		draw_line(mid, tip, Color(acc.r, acc.g, acc.b, fade * 0.95), 3.0, true)
		# 侧向小倒钩（雪花感：主干 + 两对小分支）
		for s in [-1.0, 1.0]:
			var bp: Vector2 = p + u * radius * 0.45 * grow
			var bw: Vector2 = u * radius * 0.20 * grow
			draw_line(bp, bp + bw + u.rotated(PI * 0.5) * radius * 0.16 * s * grow,
				Color(acc.r, acc.g, acc.b, fade * 0.7), 2.5, true)
	# 外框：六边形硬边（不是圆 —— 冰就该有折角）
	var hex := _wobble(p, radius * 0.30 * grow, 6, 0.0, 0.0)
	draw_polyline(hex, Color(acc.r, acc.g, acc.b, fade * 0.5), 3.0, true)
	# 雪絮：缓慢外飘的小点（慢、静态感来自它们几乎不动）
	for i in 7:
		var a: float = TAU * float(i) / 7.0 + 0.5
		var rr: float = radius * (0.55 + 0.18 * proc) * grow
		var sp: Vector2 = p + Vector2(cos(a), sin(a)) * rr
		draw_circle(sp, radius * 0.045, Color(acc.r, acc.g, acc.b, fade * 0.6))

# ── 毒：边界蠕动的黏泡团 + 向上翻涌的泡 ──────────────────────────────
func _draw_poison(p: Vector2, radius: float, col: Color, acc: Color,
		t: float, proc: float, fade: float) -> void:
	var rr: float = radius * (0.62 + 0.14 * proc)
	# 黏泡团：lobes=3 且相位随时间变 → 边界一直在"蠕动"
	var blob := _wobble(p, rr, 22, 0.13, t * 1.9)
	draw_colored_polygon(blob, Color(col.r, col.g, col.b, fade * 0.26))
	draw_polyline(blob, Color(acc.r, acc.g, acc.b, fade * 0.62), 4.0, true)
	# 内层小泡壑（让"黏"有层次）
	var inner := _wobble(p, rr * 0.55, 16, 0.18, -t * 2.6)
	draw_polyline(inner, Color(acc.r, acc.g, acc.b, fade * 0.35), 2.5, true)
	# 翻涌的泡：一路往上顶（慢、沉）
	for i in 8:
		var phase: float = t * 0.85 + float(i) * 0.9
		var u := Vector2(cos(float(i) * 2.1), -1.0).normalized()
		var rise: float = (phase - floor(phase))
		var bp: Vector2 = p + Vector2(u.x * radius * 0.34,
			-radius * 0.15 + u.y * radius * 0.55 * rise)
		var br: float = radius * (0.10 + 0.06 * sin(float(i))) * (0.5 + 0.5 * rise)
		draw_circle(bp, br, Color(col.r, col.g, col.b, fade * 0.42))
		draw_arc(bp, br, 0.0, TAU, 12, Color(acc.r, acc.g, acc.b, fade * 0.5), 2.0, true)

# ── 火：卡通爆燃（扇贝三层）+ 火舌上窜 + 起手白闪 ────────────────────
func _draw_fire(p: Vector2, radius: float, col: Color, acc: Color,
		t: float, life: float, proc: float, fade: float) -> void:
	var k: float = _out(clampf(t / life, 0.0, 1.0))
	# 起手白闪：让"炸出去了"这一下有实感
	if t < 0.14:
		var f: float = 1.0 - t / 0.14
		draw_circle(p, radius * 0.42 * (0.6 + 0.6 * f), Color(1.0, 0.97, 0.85, f * 0.85))
	# 三层扇贝爆开（lobes=5，是"卡通烟团"的关键：边必须是圆的鼓包而不是光环）
	for l in 3:
		var base: float = radius * (0.30 + 0.26 * float(l)) * (0.45 + 0.75 * k + 0.25 * proc)
		var puff := _wobble(p, base, 18, 0.16, float(l) * 1.7 + t * 2.2)
		var alpha: float = fade * (0.50 - 0.13 * float(l))
		draw_colored_polygon(puff, Color(col.r, col.g, col.b, alpha * 0.7))
		draw_polyline(puff, Color(acc.r, acc.g, acc.b, alpha * 0.8), 4.0 - float(l), true)
	# 火舌：向上舔的三条（方向感让火和电彻底区分开）
	for i in 3:
		var sway: float = sin(t * 5.0 + float(i)) * radius * 0.12
		var tip: Vector2 = p + Vector2(sway, -radius * (0.75 + 0.35 * k))
		var half: Vector2 = Vector2(radius * 0.17, radius * 0.0)
		draw_colored_polygon(PackedVector2Array([p - half, p + half, tip]),
			Color(acc.r, acc.g, acc.b, fade * 0.5))
		draw_circle(tip, radius * 0.07, Color(1.0, 0.95, 0.7, fade * 0.7))

# ── 电：枝状闪电抽打 + 一瞬全白 + 折点余辉 ───────────────────────────
func _draw_bolt(p: Vector2, radius: float, col: Color, acc: Color,
		t: float, life: float, proc: float, fade: float) -> void:
	# 一瞬全白（前 2 帧量级的闪）：unique signature of electric
	if t < 0.09:
		draw_circle(p, radius * 1.05, Color(1.0, 1.0, 1.0, 0.55 * (1.0 - t / 0.09)))
	# 只在"通断"半周期内显示 → 间歇抖动的观感（用电自身的时间节律，不用随机）
	var flicker: float = 0.55 + 0.45 * sin(t * 34.0)
	if flicker < 0.35 and proc > 0.15:
		return
	for i in 4:
		var ang: float = TAU * float(i) / 4.0 + t * 1.1
		var u := Vector2(cos(ang), sin(ang))
		var side := u.rotated(PI * 0.5)
		var pts := PackedVector2Array([p + u * radius * 0.20])
		for s in 5:
			var rr: float = radius * (0.20 + 0.17 * float(s + 1))
			var off: float = radius * 0.13 * sin(t * 11.0 + float(i) * 2.0 + float(s)) \
				* (1.0 if s % 2 == 0 else -1.0)
			pts.append(p + u * rr + side * off)
		draw_polyline(pts, Color(acc.r, acc.g, acc.b, fade * 0.9 * flicker), 3.5, true)
		# 折点余辉：炸开后的小亮点停在关节处
		if proc > 0.0:
			for j in range(1, pts.size()):
				draw_circle(pts[j], radius * 0.045,
					Color(col.r, col.g, col.b, fade * 0.55 * flicker))

# ── 风：三把旋转镰刃 + 中心漩涡 + 花瓣外抛 ───────────────────────────
func _draw_wind(p: Vector2, radius: float, col: Color, acc: Color,
		t: float, proc: float, fade: float) -> void:
	# 漩涡：半径递减、相位递增的一串短弧 → 眼睛看得出"在往里吸"
	for j in 5:
		var rr: float = radius * (0.88 - 0.15 * float(j))
		var a0: float = t * 3.2 + float(j) * 0.7
		draw_arc(p, rr, a0, a0 + 1.1, 14,
			Color(acc.r, acc.g, acc.b, fade * (0.55 - 0.08 * float(j))), 3.0, true)
	# 三把镰刃：长尾巴的月牙，整体旋转
	for i in 3:
		var a0: float = TAU * float(i) / 3.0 + t * 2.6
		draw_arc(p, radius * 0.72, a0, a0 + 0.95, 16,
			Color(col.r, col.g, col.b, fade * 0.85), 7.0, true)
		draw_arc(p, radius * 0.72, a0 + 0.55, a0 + 0.92, 10,
			Color(acc.r, acc.g, acc.b, fade * 0.5), 3.0, true)
	# 花瓣：被卷出来甩到外圈（越远越小越淡）
	for i in 5:
		var a: float = TAU * float(i) / 5.0 - t * 1.5
		var rr: float = radius * (0.55 + 0.45 * proc)
		var sp: Vector2 = p + Vector2(cos(a), sin(a)) * rr
		draw_circle(sp, radius * 0.05 * (1.0 - 0.5 * proc),
			Color(acc.r, acc.g, acc.b, fade * 0.6))
