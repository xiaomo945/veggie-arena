extends Control

# 颠勺大招的全屏卡通爆炸
#
# 为什么画在屏幕空间而不是世界空间：爆炸环原本钉在世界坐标，但大招有 0.5 秒生命，
# 这半秒里玩家一直在跑，环就落在身后 —— 看上去"歪、不在正中间"（用户明确反馈）。
# 镜头恒定以玩家为中心，所以**屏幕中心永远等于玩家**，放这里既不会歪也不会脱节。
#
# 三段组成，边缘一律柔化（多层衰减而不是一根硬圆线），避免看到生硬的圆形边框：
#   1) 白光爆闪 —— 铺满整屏（含 letterbox 黑边），本来就没有边界
#   2) 扩散冲击波带 —— 由内向外多层衰减，一直扩到屏幕外才消失
#   3) 放射速度线 —— 卡通"咻"的爆开感

const LIFE := 0.55
const MAXR := 620.0     # 扩到屏幕外（540x900 半对角约 525），让环自然冲出画面
const FLASH_T := 0.18   # 爆闪占整段的比例
const BANDS := 8        # 冲击波层数（越多边缘越柔）

var t := 0.0
var playing := false

func fire() -> void:
	t = 0.0
	playing = true
	set_process(true)
	queue_redraw()

# 自己推进自己：FxLayer 只负责 fire()，不掺和播放细节
func _process(delta: float) -> void:
	if not playing:
		set_process(false)
		return
	t += delta
	if t >= LIFE:
		playing = false
		t = 0.0
	queue_redraw()

func _ready() -> void:
	# 撑到视口 3 倍，覆盖 letterbox 黑边，做到真·全屏
	anchor_left = -1.0
	anchor_top = -1.0
	anchor_right = 2.0
	anchor_bottom = 2.0
	# 全屏控件必须忽略触摸，否则吃掉摇杆点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)      # 只在 fire() 后的 0.55 秒里跑

func _draw() -> void:
	if not playing:
		return
	var k: float = clampf(t / LIFE, 0.0, 1.0)
	var view: Vector2 = get_viewport_rect().size
	if view.x <= 0.0:
		view = Vector2(540.0, 900.0)
	# 锚点 -1..2 时，视口中心在本控件局部坐标里位于 view + view*0.5
	var c: Vector2 = Vector2(view.x, view.y) + view * 0.5

	# 1) 白光爆闪：整块屏铺满，无边界所以不会割裂
	if k < FLASH_T:
		var fa: float = 1.0 - k / FLASH_T
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.96, 0.82, fa * 0.55))

	# 2) 扩散冲击波带：多层由内向外衰减，边缘柔化
	var r: float = k * MAXR
	var fade: float = 1.0 - k
	for i in BANDS:
		var rr: float = r - float(i) * 17.0
		if rr <= 6.0:
			continue
		var a: float = fade * (1.0 - float(i) / float(BANDS)) * 0.5
		draw_arc(c, rr, 0.0, TAU, 44, Color(1.0, 0.88, 0.5, a), 15.0 - float(i) * 1.5, true)
	if r > 12.0:
		draw_arc(c, maxf(r * 0.55, 8.0), 0.0, TAU, 36,
			Color(1.0, 0.72, 0.3, fade * 0.35), 10.0, true)

	# 3) 放射速度线：卡通爆开的"咻"感
	var rays := 12
	for i in rays:
		var ang: float = TAU * float(i) / float(rays) + 0.15
		var u := Vector2(cos(ang), sin(ang))
		draw_line(c + u * (r * 0.72), c + u * (r * 1.06 + 26.0),
			Color(1.0, 0.85, 0.45, fade * 0.4), 3.5)
