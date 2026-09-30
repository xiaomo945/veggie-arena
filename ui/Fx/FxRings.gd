extends Node2D

# 击杀爆环的纯绘制层：把 FxLayer 传来的环数组画出来。
# 不处理输入、不认识任何玩法对象 —— 删掉不影响游戏逻辑。
#
# rings 由 FxLayer 在 _ready 里直接把数组引用塞进来（Array 是引用类型），
# 所以 FxLayer 每帧的增删这里立刻可见，不用再同步。

var rings: Array = []

func _draw() -> void:
	if rings.is_empty():
		return
	for r in rings:
		var d: Dictionary = r as Dictionary
		if d.is_empty():
			continue
		var t: float = float(d.get("t", 0.0))
		var life: float = float(d.get("life", 0.34))
		var k: float = clampf(t / life, 0.0, 1.0)
		var big: bool = bool(d.get("big", false))
		var maxr: float = 78.0 if big else 34.0
		var rad: float = lerpf(6.0, maxr, k)
		var a: float = (1.0 - k) * 0.85
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		if big:
			draw_arc(pos, rad, 0.0, TAU, 24, Color(1.0, 0.62, 0.30, a), 4.0, true)
		else:
			draw_arc(pos, rad, 0.0, TAU, 20, Color(1.0, 0.88, 0.55, a), 2.5, true)
