extends Node2D

# 战场环境氛围粒子（纯代码绘制，无外部资源）：厨房的蒸汽/火星/油星缓缓上浮淡出。
# 垫在战斗层之下（show_behind_parent），不挡战斗；只取"少量"以免满屏割草时糊成一片。
#
# 三种质点：
#   steam  半透明白雾，边升边膨胀边淡出（灶台热气）
#   spark  细小亮橙火星，窜得稍快、寿命短、带微闪（爆炒溅起的火星）
#   oil    暗金小油滴，缓缓上浮、偶尔左右晃（锅里溅出的油星）

const MAX := 26
const SPAWN_DT := 0.10          # 每 0.1s 试着冒一颗，控制密度
const INK := Color(0.06, 0.05, 0.09, 1.0)

var _arena := Rect2(0, 0, 540, 900)
var _parts: Array = []
var _acc := 0.0
var _rng := RandomNumberGenerator.new()

func setup(rect: Rect2) -> void:
	_arena = rect
	_rng.randomize()

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_acc += delta
	while _acc >= SPAWN_DT:
		_acc -= SPAWN_DT
		_spawn_one()
	var had := not _parts.is_empty()
	var i := 0
	while i < _parts.size():
		var p: Dictionary = _parts[i]
		p["t"] = float(p.get("t", 0.0)) + delta
		p["pos"] = (p.get("pos") as Vector2) + (p.get("vel") as Vector2) * delta
		# 油星左右轻晃
		if str(p.get("kind")) == "oil":
			var s := float(p.get("sway", 0.0)) + delta * 2.0
			p["sway"] = s
			var sx := sin(s) * 6.0 * delta
			p["pos"] = Vector2((p.get("pos") as Vector2).x + sx, (p.get("pos") as Vector2).y)
		var life := float(p.get("life", 1.0))
		if float(p.get("t", 0.0)) >= life:
			_parts.remove_at(i)
			continue
		# 出界就回收（向上飘出竞技场顶）
		if (p.get("pos") as Vector2).y < _arena.position.y - 30.0:
			_parts.remove_at(i)
			continue
		i += 1
	var now := not _parts.is_empty()
	if now or had:
		queue_redraw()

func _spawn_one() -> void:
	if _parts.size() >= MAX:
		return
	var r := _rng.randf()
	var kind := "steam" if r < 0.5 else ("spark" if r < 0.78 else "oil")
	var x := _arena.position.x + _rng.randf_range(0.04, 0.96) * _arena.size.x
	var y := _arena.position.y + _rng.randf_range(0.55, 0.98) * _arena.size.y
	var vel := Vector2(_rng.randf_range(-6.0, 6.0), -_rng.randf_range(14.0, 30.0))
	var life := _rng.randf_range(1.6, 3.0)
	var size := _rng.randf_range(6.0, 12.0)
	if kind == "spark":
		vel = Vector2(_rng.randf_range(-10.0, 10.0), -_rng.randf_range(40.0, 80.0))
		life = _rng.randf_range(0.4, 0.8)
		size = _rng.randf_range(1.6, 3.0)
	elif kind == "oil":
		vel = Vector2(_rng.randf_range(-4.0, 4.0), -_rng.randf_range(10.0, 20.0))
		life = _rng.randf_range(1.4, 2.6)
		size = _rng.randf_range(2.4, 4.2)
	_parts.append({"pos": Vector2(x, y), "vel": vel, "t": 0.0, "life": life,
		"kind": kind, "size": size, "sway": _rng.randf_range(0.0, 6.28),
		"hue": _rng.randf_range(0.0, 1.0)})

func _draw() -> void:
	for p in _parts:
		var d := p as Dictionary
		var k := clampf(float(d.get("t", 0.0)) / float(d.get("life", 1.0)), 0.0, 1.0)
		var pos: Vector2 = d.get("pos")
		var sz := float(d.get("size", 8.0))
		var kind := str(d.get("kind"))
		if kind == "steam":
			_draw_steam(pos, sz, k)
		elif kind == "spark":
			_draw_spark(pos, sz, k, float(d.get("hue", 0.0)))
		else:
			_draw_oil(pos, sz, k)

func _draw_steam(pos: Vector2, sz: float, k: float) -> void:
	var a := sin(k * PI) * 0.16
	if a <= 0.01:
		return
	var r := sz * (0.7 + k * 1.1)
	draw_circle(pos, r + 2.0, Color(0.9, 0.92, 0.95, a * 0.4))
	draw_circle(pos, r, Color(1.0, 1.0, 1.0, a))

func _draw_spark(pos: Vector2, sz: float, k: float, hue: float) -> void:
	var a := (1.0 - k)
	var flick := 0.7 + 0.3 * sin(k * 40.0 + hue * 6.28)
	var c := Color(1.0, 0.6 + 0.25 * flick, 0.2, a * flick)
	draw_circle(pos, sz + 1.2, Color(INK.r, INK.g, INK.b, a * 0.5))
	draw_circle(pos, sz, c)
	draw_circle(pos, sz * 0.5, Color(1.0, 0.95, 0.7, a))

func _draw_oil(pos: Vector2, sz: float, k: float) -> void:
	var a := sin(k * PI) * 0.7
	if a <= 0.02:
		return
	draw_circle(pos, sz + 1.0, Color(INK.r, INK.g, INK.b, a * 0.5))
	draw_circle(pos, sz, Color(0.78, 0.58, 0.18, a))
	draw_circle(pos - Vector2(sz * 0.3, sz * 0.3), sz * 0.4, Color(1.0, 0.9, 0.55, a))
