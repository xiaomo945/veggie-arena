extends Control

# 颠勺大招的全屏卡通爆炸
#
# 爆炸中心 = 玩家实时世界坐标。FxLayer 是世界空间层（follow_viewport_enabled=true，
# 跟着相机走），所以它的子节点直接画"世界坐标"即可，相机变换已由整层统一施加。
#
# ⚠️ 历史 bug：这里曾用 get_canvas_transform() * _center_world 把相机变换又乘一遍，
#    等于对位置做了两次相机变换，再叠加 -1..2 锚点把 local(0,0) 推到 (-270,-450)，
#    结果圆环被甩到左上角屏幕外、白光爆闪留在场中央，看起来像"两个不相关的爆炸"。
#    现在直接画世界坐标、锚点改回 0..1，整发爆炸稳稳钉在玩家当前位置。
#
# 三段组成，边缘一律柔化（多层衰减而不是一根硬圆线），避免看到生硬的圆形边框：
#   1) 白光爆闪 —— 以玩家为中心向外多层同心圆铺开，半径远超半视口，铺满整屏
#   2) 扩散冲击波带 —— 以玩家为准由内向外多层衰减，一直扩到屏幕外才消失
#   3) 放射速度线 —— 卡通"咻"的爆开感（从玩家位置放射）

const LIFE := 0.55
const MAXR := 780.0     # 扩到屏幕外（540x900 半对角约 525），让环自然冲出画面
const FLASH_T := 0.18   # 爆闪占整段的比例
const BANDS := 8        # 冲击波层数（越多边缘越柔）

var t := 0.0
var playing := false
var _center_world := Vector2.ZERO   # 爆炸中心（玩家世界坐标），由 fire(pos) 传入

func fire(pos_world: Vector2 = Vector2.ZERO) -> void:
	_center_world = pos_world
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
	# 满屏控件：锚点 0..1 让 local(0,0) 对齐世界原点，画世界坐标时位置才准。
	# ⚠️ 之前用 -1..2 把 local(0,0) 推到 (-270,-450)，叠加世界层相机变换后圆环被甩到左上角。
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	# 全屏控件必须忽略触摸，否则吃掉摇杆点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)      # 只在 fire() 后的 0.55 秒里跑

func _draw() -> void:
	if not playing:
		return
	var k: float = clampf(t / LIFE, 0.0, 1.0)
	# FxLayer 是世界空间层（已统一施加相机变换），直接画玩家世界坐标即可，
	# 不要再用 get_canvas_transform() 二次投影，否则会被甩到屏幕外。
	var c: Vector2 = _center_world

	# 1) 白光爆闪：以玩家为中心的径向圆形爆闪（多层同心圆，中心最亮、边缘衰减）。
	if k < FLASH_T:
		var fa: float = 1.0 - k / FLASH_T
		var fr: float = lerpf(70.0, MAXR * 0.95, k / FLASH_T)
		for i in 7:
			var rr: float = fr * (1.0 - float(i) * 0.11)
			if rr <= 8.0:
				continue
			var a: float = fa * 0.20 * (1.0 - float(i) / 7.0)
			draw_circle(c, rr, Color(1.0, 0.96, 0.82, a))

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
