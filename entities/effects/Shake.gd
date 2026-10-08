extends RefCounted

# 轻量震屏：项目无 Camera2D，故直接抖动世界根节点（game）的 position。
# 整个 world 子树一起抖动，相对几何不变 → 不影响玩法，只抖画面。
# 玩家受击 / Boss 出现 / 单次大伤害时由调用方触发，受 Settings.screenshake_enabled 控制。

static var _root: Node2D = null
static var _tween: Tween = null

static func register(root: Node2D) -> void:
	_root = root

static func kick(strength: float, duration: float) -> void:
	if _root == null:
		return
	if not Settings.get_setting("screenshake_enabled", true):
		return
	var base: Vector2 = _root.position
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = _root.create_tween()
	# ⚠️ 必须跑在物理步：Tween 默认在渲染帧（idle）更新，而 game 是战斗世界根节点、
	# 开了物理插值（120Hz 上两个渲染帧插值同一个物理步）。在渲染帧改它的 position
	# 会和插值打架，表现为整个世界"抽一下"。放进物理步后震屏跟着插值一起平滑。
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var n := 6
	var dt: float = duration / float(n + 1)
	for i in n:
		var k: float = 1.0 - float(i) / float(n)
		var s: float = strength * k
		var off: Vector2 = Vector2(randf_range(-s, s), randf_range(-s, s))
		_tween.tween_property(_root, "position", base + off, dt)
	_tween.tween_property(_root, "position", base, dt)
