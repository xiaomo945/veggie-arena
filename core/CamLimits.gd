extends RefCounted

# 相机限位计算（纯函数，不依赖任何 autoload / 场景树）—— 便于探针和单测直接验证。
#
# 【需求】玩家在场地中间时镜头正常跟随；只有玩家靠近场地边缘时镜头才停跟，
#         此时屏幕边正好贴住场地边，不露黑框（黑框会让"还没露面的怪"先打死你）。
#
# 【关键坑 1：Godot 4.3 的 Camera2D.limit_* 钳的是相机中心点，不是视野】
#   直接把 limit 设成场地边界 → 中心点被钳到边界、视野仍向外探出半屏 → 黑框照旧。
#   所以必须内缩半个视口：center ± 半视口 这个"视野矩形"才留得住场地内。
#
# 【关键坑 2：视口比场地还大时，内缩会让 left > right（限位反转）】
#   反转后相机中心被钳到一个死值 → 镜头彻底不动、玩家跑出屏幕（真机踩过）。
#   所以任何一维出现 min > max 时，该维退化为场地中心（锁死这一维，另一维仍可跟随）。
#
# 入参 a：场地矩形 {x,y,w,h}；view：相机可见的世界尺寸（宽, 高）；
#       margin：允许视野超出场地边界的宽度（把围栏露出来，默认 0=严格贴边）。
#         float = 四边统一；Dictionary {left,top,right,bottom} = 分边给（顶部要让开 HUD）。
# 返回：{left, right, top, bottom}，均为相机【中心点】的允许范围。

static func limits(a: Dictionary, view: Vector2, margin: Variant = 0.0) -> Dictionary:
	var ax := float(a.get("x", 0))
	var ay := float(a.get("y", 0))
	var aw := float(a.get("w", 540))
	var ah := float(a.get("h", 900))
	var hw := view.x * 0.5
	var hh := view.y * 0.5
	# margin：允许镜头再多往外让一点，把场地外的"围栏 + 一点灶台地面"露出来。
	# 露的是深色厨房地面（不是黑框），这样边界读起来是有围栏的战场，而不是画面被切断。
	var left := ax + hw - _mv(margin, "left", "right", 0.0)
	var right := ax + aw - hw + _mv(margin, "right", "left", 0.0)
	var top := ay + hh - _mv(margin, "top", "bottom", 0.0)
	var bottom := ay + ah - hh + _mv(margin, "bottom", "top", 0.0)
	# 视口比场地宽/高：内缩后区间反转，锁到该维的场地中心（而不是留下一个反转区间）
	if left > right:
		left = ax + aw * 0.5
		right = left
	if top > bottom:
		top = ay + ah * 0.5
		bottom = top
	return {"left": left, "right": right, "top": top, "bottom": bottom}

# margin 可以是 float（四边统一），也可以是 Dictionary {left,top,right,bottom} 分边给。
# ⚠️ 分边存在的理由：顶部要让开 HUD（ScreenMode.TOP_MARGIN 远大于其他三边），
# 底部/左右只需要露围栏。真机踩过：四边统一给大边距会让屏幕底部也露一大片场外。
# fallback 是"取了这一边就沿用另一边的值"，保证只写 {top=X} 时左右仍拿到 0 而不是 X。
static func _mv(margin: Variant, key: String, other: String, def: float) -> float:
	if margin is Dictionary:
		var d := margin as Dictionary
		if d.has(key):
			return float(d[key])
		if d.has(other):
			return float(d[other])
		return def
	return float(margin)

# 相机可见的世界尺寸（Vector2）：视口世界尺寸 ÷ zoom。
# 用 Viewport.get_visible_rect() 而不是 content_scale_size —— 前者就是"这一帧能画多少
# 世界单位"，随窗口/拉伸自动正确；拿不到时退回设计分辨率 540x900（竖屏）。
static func view_world_size(cam: Camera2D) -> Vector2:
	var vp := cam.get_viewport() if cam != null else null
	if vp == null:
		return Vector2(540.0, 900.0)
	var s := vp.get_visible_rect().size
	var z := cam.zoom
	if z.x > 0.0001 and z.y > 0.0001:
		s = Vector2(s.x / z.x, s.y / z.y)
	return s
