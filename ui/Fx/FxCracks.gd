extends Node2D

# 地面裂痕特效（菜刀等近战武器砍地）：沿挥砍方向裂开，再"愈合"（绿光收拢）。
# 长度 / 分叉随武器等级变大。纯表现，不写任何玩法状态。

const LIFE := 0.85
var cracks: Array = []   # 由 FxLayer 注入同一份数组

func _draw() -> void:
	for cr in cracks:
		var t: float = float(cr.get("t", 0.0))
		var pos: Vector2 = cr.get("pos", Vector2.ZERO)
		var dir: Vector2 = cr.get("dir", Vector2.RIGHT)
		var lvl: int = int(cr.get("level", 1))
		var len: float = 18.0 + lvl * 14.0
		var ang: float = dir.angle()
		var grow: float = clampf(t / 0.14, 0.0, 1.0)
		var heal: float = clampf((t - 0.5) / (LIFE - 0.5), 0.0, 1.0)
		var cur_len: float = len * grow
		var dark_a: float = (1.0 - heal) * 0.9
		if dark_a > 0.02:
			_draw_crack(pos, ang, cur_len, lvl,
				Color(0.20, 0.11, 0.13, dark_a), Color(0.42, 0.26, 0.28, dark_a))
		if heal > 0.0:
			var ga: float = sin(heal * PI) * 0.85
			_draw_crack(pos, ang, cur_len, lvl,
				Color(0.0, 0.0, 0.0, 0.0), Color(0.5, 0.95, 0.5, ga * 0.7))

func _draw_crack(pos: Vector2, ang: float, len: float, lvl: int, out_c: Color, in_c: Color) -> void:
	var segs := 5
	var pts := PackedVector2Array([pos])
	for i in range(1, segs + 1):
		var f: float = float(i) / float(segs)
		var jitter: float = sin(f * 9.0 + ang * 3.0) * 6.0 * (1.0 - f * 0.3)
		pts.append(pos + Vector2(cos(ang), sin(ang)) * len * f
			+ Vector2(-sin(ang), cos(ang)) * jitter)
	_draw_path(pts, out_c, 5.0)
	_draw_path(pts, in_c, 2.6)
	if lvl >= 3:
		for b in range(1, mini(lvl - 1, 3) + 1):
			var at: Vector2 = pts[mini(b * 2, pts.size() - 1)]
			var ba: float = ang + (1.0 if b % 2 == 0 else -1.0) * 0.6
			var bp: Vector2 = at + Vector2(cos(ba), sin(ba)) * len * 0.4
			_draw_path(PackedVector2Array([at, bp]), out_c, 3.5)
			_draw_path(PackedVector2Array([at, bp]), in_c, 1.8)

func _draw_path(pts: PackedVector2Array, c: Color, wdt: float) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], c, wdt, true)
