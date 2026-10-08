extends Node2D

# 击杀爆点对象池（配 entities/effects/HitSpark.gd 的池化版）。
#
# 为什么必须有池：见 HitSpark.gd 顶部注释 —— 击杀是【高频 × 密集】事件，
# 一波清场可能同一帧死十几只。旧版每次击杀 new 一整棵子树 + 十几个 Tween，
# 尖峰随击杀数线性增长；池化后每次击杀只做属性赋值。
#
# 池满策略：覆盖最老的一个，而不是丢弃新的 —— 玩家对"刚打死的那只炸没炸"
# 最敏感，截断 0.36 秒前的旧特效几乎无感，丢掉新特效则明显"打起来没反馈"。

const HitSpark := preload("res://entities/effects/HitSpark.gd")
const CAP := 16

var _sparks: Array = []
var _cursor := 0
var _active_n := 0

# 预建：调用一次，之后全程零 new
func build() -> void:
	for _i in CAP:
		var s := HitSpark.new()
		add_child(s)
		s.build()
		_sparks.append(s)

func active_count() -> int:
	return _active_n

func pop(pos: Vector2, big: bool) -> bool:
	if _sparks.is_empty():
		return false
	for i in CAP:
		var idx := (_cursor + i) % CAP
		var s := _sparks[idx] as HitSpark
		if s == null or s.is_playing():
			continue
		_cursor = (idx + 1) % CAP
		_active_n += 1
		s.reset(pos, big)
		return true
	# 全忙：覆盖最老的（见顶部"池满策略"）
	var s2 := _sparks[_cursor] as HitSpark
	_cursor = (_cursor + 1) % CAP
	s2.reset(pos, big)
	return true

# 由 HitSpark 播完时回调（公开 API，避免它反过来读池的私有字段）
func recycle(_s: Node) -> void:
	if _active_n > 0:
		_active_n -= 1
