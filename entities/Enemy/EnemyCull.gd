extends RefCounted

# 屏幕外的敌人不重绘（性能优化，2026-10-04 晚）。
#
# 为什么有效：竞技场 1080x1620，视口只有 540x900 —— 屏幕上同一时刻只能看到约 28%
# 的敌人。而敌人每次挨打都会 squash → queue_redraw()，密集战斗里几乎每帧都有十几只
# 在重绘；这十几个 _draw() 里大部分是屏幕外的，画了也看不见。
#
# 做法：请求重绘时先看在不在镜头里；不在就只记一个 _dirty 标记，等它进屏幕再补画。
# 绘制内容是局部坐标（变换在引擎侧），所以"跳过重绘"不会让画面错位，只是沿用上一帧
# 缓存的绘制命令 —— 等它进入视野时补一次即可。
#
# 抽成独立文件而不是塞进 Enemy.gd：Enemy.gd 顶着 300 行架构红线，放不下了。

const MARGIN := 96.0     # 视口外再多留一点，避免刚进屏幕那一帧还没画出来

static func in_view(n: Node2D) -> bool:
	var vp := n.get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_2d()
	var c := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var half := vp.get_visible_rect().size * 0.5
	return Rect2(c - half, half * 2.0).grow(MARGIN).has_point(n.global_position)

# 可见就立刻重绘并返回 true；不可见返回 false（调用方把 _dirty 置上，进屏幕时补画）
static func redraw_if_visible(n: Node2D) -> bool:
	if not in_view(n):
		return false
	n.queue_redraw()
	return true
