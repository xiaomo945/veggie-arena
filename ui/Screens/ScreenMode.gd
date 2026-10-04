extends Node

# 横竖屏双布局（docs/07 §5.6）：
#   竖屏 540x900 = 默认，沙箱 / 单测 / headless 走原路径零改动；
#   宽屏（真实窗口宽高比 > 1.3）自动把设计分辨率切到 960x540 + 放大竞技场到 1620x1080。
# 所有逻辑集中在此，避免把 Main 顶过 300 行红线。作为 autoload 全局可用（保证被加载）。
#
# ⚠️ 测试用：环境变量 VA_FORCE_LANDSCAPE=1 强制横屏（沙箱 xvfb 只能给竖屏窗口）。

const LANDSCAPE_AR := 1.3
const LANDSCAPE_SIZE := Vector2i(960, 540)

func _win_size() -> Vector2:
	return Vector2(DisplayServer.window_get_size())

func is_widescreen() -> bool:
	var w := _win_size()
	if w.x <= 0 or w.y <= 0:
		return false
	return float(w.x) / float(w.y) > LANDSCAPE_AR

func should_landscape() -> bool:
	return OS.has_environment("VA_FORCE_LANDSCAPE") or is_widescreen()

# 设计分辨率（content_scale_size）：横屏 960x540，竖屏 540x900。
func _design_size() -> Vector2:
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		var v: Vector2i = (ml as SceneTree).root.content_scale_size
		return Vector2(float(v.x), float(v.y))
	return Vector2(540.0, 900.0)

# 在读取 arena 之前调用（Main._ready 顶部）：设定横竖屏标志 + 翻转设计分辨率。
# 竖屏时本函数完全不动作（Data 标志保持 false，arena 走原值）。
func apply() -> void:
	var land := should_landscape()
	Data.set_landscape(land)
	if land:
		var ml = Engine.get_main_loop()
		if ml is SceneTree:
			(ml as SceneTree).root.content_scale_size = LANDSCAPE_SIZE

# 相机限位：把"视野矩形"钳在竞技场边界内，玩家靠近边缘时镜头停跟、屏幕边贴竞技场边，无黑框。
# ⚠️ 关键坑（已实测验证）：Godot 4.3 的 Camera2D limit_* 钳的是【相机中心点】，不是视野。
#    若直接把 limit 设成竞技场边界，中心点被钳到边界、视野仍会探出半屏到黑区 —— 黑框照旧。
#    所以限位必须【内缩半个视口】：center ± 半视口 这个视野矩形才留得住竞技场内。
#    视口尺寸用当前设计分辨率（竖屏 540x900 / 横屏 960x540，由 content_scale_size 决定）。
func clamp_camera(cam: Camera2D, a: Dictionary) -> void:
	var v := _design_size()              # 当前视口（世界单位，zoom=1）：竖屏 540x900 / 横屏 960x540
	var hw: float = v.x * 0.5
	var hh: float = v.y * 0.5
	var ax: float = float(a.get("x", 0))
	var ay: float = float(a.get("y", 0))
	var aw: float = float(a.get("w", 540))
	var ah: float = float(a.get("h", 900))
	# 竞技场比视口小（极端情况）时无法把视野留在场内：相机锁定到竞技场中心，避免 limit 反转出错。
	if aw <= v.x or ah <= v.y:
		var cx: float = ax + aw * 0.5
		var cy: float = ay + ah * 0.5
		cam.limit_left = int(cx)
		cam.limit_right = int(cx)
		cam.limit_top = int(cy)
		cam.limit_bottom = int(cy)
		cam.limit_smoothed = false
		return
	cam.limit_left = int(ax + hw)
	cam.limit_right = int(ax + aw - hw)
	cam.limit_top = int(ay + hh)
	cam.limit_bottom = int(ay + ah - hh)
	cam.limit_smoothed = false   # 硬限位：贴边瞬间即停，避免 smoothing 把视野甩进黑区一帧

# 把"按 540x900 竖屏设计"的整屏菜单（CanvasLayer 下的 _root Control）缩放到当前视口内。
# 竖屏：dst=540x900，scale=1 原样。横屏：dst=960x540 比竖屏设计矮，按高度 fit
# （scale = 540/900 = 0.6），内容变 324x540 水平居中、左右留边——菜单功能完全可用，
# 只是两侧留白。横屏菜单的视觉精修（如把商店网格铺宽）属真机迭代项。
# 先把节点固定成 540x900 设计尺寸（竖屏整屏菜单的本意），再缩放/居中：这样节点的
# 整屏子节点（shade 暗底等）也跟着 540x900 走，横屏下与内容边界一致，不会"暗底比内容宽"。
func fit_overlay(node: Control) -> void:
	if node == null:
		return
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.size = Vector2(540.0, 900.0)
	var dst := _design_size()
	var src := Vector2(540.0, 900.0)
	var s := minf(dst.x / src.x, dst.y / src.y)
	node.scale = Vector2(s, s)
	node.position = Vector2((dst.x - src.x * s) * 0.5, (dst.y - src.y * s) * 0.5)

func landscape() -> bool:
	return Data.is_landscape()
