extends Control

# 全屏晕染（挨打红 / 颠勺金）
#
# 为什么把控件撑到视口的 3 倍：项目用 stretch=canvas_items + aspect=keep，
# 手机长屏时 540x900 的内容区上下会留黑边。若只按视口铺满，红闪就成了一块
# "方块"嵌在黑边里，割裂感很强（用户明确抱怨过）。
# 这里锚点取 -1..2（视口 3 倍），连黑边一起染上 —— 才是真正的全屏；
# 再叠一层由外向内逐层衰减的卡通框，读起来就是"挨打了"，中心视野不被糊住。

const BANDS := 6
const BAND_W := 26.0
const BASE_ALPHA := 0.20    # 铺满整屏（含黑边）的底色，消除方块硬边界
const FRAME_ALPHA := 0.55   # 内容区边缘卡通框的最外层强度

var color := Color(1.0, 0.15, 0.18)
var strength := 0.0         # 0..1，由 FxLayer 每帧写入

func _ready() -> void:
	# 撑到视口 3 倍，覆盖 letterbox 黑边
	anchor_left = -1.0
	anchor_top = -1.0
	anchor_right = 2.0
	anchor_bottom = 2.0
	# 全屏控件必须忽略触摸，否则会吃掉摇杆的所有点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if strength <= 0.002:
		return
	var s: float = clampf(strength, 0.0, 1.0)
	# 1) 整块屏（含黑边）铺一层淡色，消除"方块"硬边界
	draw_rect(Rect2(Vector2.ZERO, size), Color(color.r, color.g, color.b, s * BASE_ALPHA))
	# 2) 内容区边缘的卡通框：由外向内逐层衰减（只画边框，不糊住中心）
	var view: Vector2 = get_viewport_rect().size
	if view.x <= 0.0:
		view = Vector2(540.0, 900.0)
	# 锚点 -1..2 时，视口(0,0)在本控件局部坐标里位于 (view.x, view.y)
	var vp := Rect2(view.x, view.y, view.x, view.y)
	for i in BANDS:
		var inset: float = float(i) * BAND_W
		var rr := Rect2(vp.position + Vector2(inset, inset),
			vp.size - Vector2(inset * 2.0, inset * 2.0))
		if rr.size.x <= 0.0 or rr.size.y <= 0.0:
			break
		var a: float = s * FRAME_ALPHA * (1.0 - float(i) / float(BANDS))
		draw_rect(rr, Color(color.r, color.g, color.b, a), false, BAND_W)
