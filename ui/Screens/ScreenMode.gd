extends Node

# 横竖屏双布局（docs/07 §5.6）：
#   竖屏 540x900 = 默认，沙箱 / 单测 / headless 走原路径零改动；
#   宽屏（真实窗口宽高比 > 1.3）自动把设计分辨率切到 960x540 + 放大竞技场到 1620x1080。
# 所有逻辑集中在此，避免把 Main 顶过 300 行红线。作为 autoload 全局可用（保证被加载）。
#
# ⚠️ 测试用：环境变量 VA_FORCE_LANDSCAPE=1 强制横屏（沙箱 xvfb 只能给竖屏窗口）。

const LANDSCAPE_AR := 1.3
const LANDSCAPE_SIZE := Vector2i(960, 540)
# 限位是纯计算，独立成文件（不依赖 autoload），探针与单测才能直接验证它
const CamLimits := preload("res://core/CamLimits.gd")
# 相机跟随平滑速度（等效原 Camera2D.position_smoothing_speed）
const CAM_FOLLOW_SPEED := 9.0
# 镜头允许越过场地边界的宽度：把钢边围栏（画在场地外 BAND≈18px）完整露出来。
# 露的是深色灶台地面而非黑框，玩家能看清"这里是战场边界"，又不会像之前那样
# 露出半屏黑区。改这个值只需动这里，CamLimits 已经把它做成参数。
const RIM_MARGIN := 24.0
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

# 相机跟随：跟玩家走；玩家靠近场地边缘时把镜头钳住，屏幕边正好贴住场地边（不露黑框）。
#
# ⚠️ 为什么不用 Camera2D.limit_*（实测踩过两次，见 docs/07 §5.6）：
#   相机若挂在玩家身上，limit 会被当成【父节点的局部坐标】来解释——内缩后的限位区间
#   不含 (0,0)，镜头直接被钉死在一点，玩家跑出屏幕（探针实测：视野恒为同一直角矩形）。
#   所以相机必须独立成节点，每帧手动钳制 global_position：坐标系明确、行为可验证。
#
# 平滑沿用 Camera2D.position_smoothing 的等效公式（原 speed=9.0）。
# 每帧重算限位，窗口尺寸变化/转屏自动适应，无需额外监听 resize。
func follow_camera(cam: Camera2D, target: Node2D, delta: float) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	if target == null or not is_instance_valid(target):
		return
	var m := CamLimits.limits(Data.arena(), CamLimits.view_world_size(cam), _cam_margin())
	var p := target.global_position
	var want := Vector2(clampf(p.x, m["left"], m["right"]), clampf(p.y, m["top"], m["bottom"]))
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-CAM_FOLLOW_SPEED * delta))

# 相机四边的越界余量：顶部按 HUD 实际高度让位，其余三边只露围栏。
#
# 【为什么顶部要让位 —— 用户报"玩家走到最上边时被 HUD 盖住"】
#   竖屏实测：场地 y −360~1260，视口 900 → 相机中心 Y 下限 = −360+450−24 = 66；
#   玩家世界 y 最小 = −360+22 = −338 → 屏幕 y = −338−(66−450) = 46，角色占 y 24~68。
#   而顶部 HUD 一路占到 y=112（还有刘海避让的 34px 下移），角色整个活在 HUD 底下。
#   顶部多让出 HUD 那一档高度后，玩家贴顶时角色中心落到 HUD 下沿之外，
#   镜头探出的那截场外地面正好被 HUD 盖住 —— 视觉上不损失任何战斗视野，
#   反而让 HUD 背后的深色灶台地面比花花绿绿的砧板地砖更好读。
#   ⚠️ 底部不能给大余量：底部是拇指操作区（HudButtons 技能簇 + 摇杆），
#   露太多等于把操作按钮推到屏幕外。
func _cam_margin() -> Dictionary:
	return {
		"left": RIM_MARGIN,
		"right": RIM_MARGIN,
		"top": RIM_MARGIN + HudLayout.hud_block_h(),
		"bottom": RIM_MARGIN,
	}

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
