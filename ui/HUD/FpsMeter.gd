extends Label

# 角上的 FPS 计数器（默认隐藏，Settings 里可开）。
#
# 为什么需要它：卡顿只能靠真机定位，而沙箱是 llvmpipe 软渲染，量不出 GPU 侧的真实
# 瓶颈。玩家能报的三个数是"多少 FPS / 屏幕上有几只怪 / 手机型号"，其中前两个必须
# 在游戏里看得见才报得出来 —— 这个计数器就是给那三个数准备的。
#
# 每秒只刷 4 次文本：Label 改 text 会触发重排，60 帧改 60 次纯粹是自己给自己找卡顿。

const UPDATE_EVERY := 0.25
# 敌人节点所在的 group（由 EnemySystem 在生成时挂上；没挂就只显示 FPS，不报错）
const ENEMY_GROUP := "enemies"

var _acc := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color(0.55, 0.95, 0.60))
	add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.05, 0.9))
	add_theme_constant_override("outline_size", 4)
	text = ""
	visible = bool(Settings.get_setting("show_fps", false))

func _process(delta: float) -> void:
	_acc += delta
	if _acc < UPDATE_EVERY:
		return
	_acc = 0.0
	# 每 0.25 秒同步一次可见性：在设置里开关后当场生效，不用重开一局才看见。
	# （Settings 没有变化信号，为它加一条全局广播不如这里顺手读一次便宜。）
	var on := bool(Settings.get_setting("show_fps", false))
	if on != visible:
		visible = on
	if not on:
		text = ""
		return
	# 顺带带上同屏敌人数：玩家一句话就能把"多少 FPS / 多少只怪"两个数都报全。
	# 数法 = 数场景里的 Enemy 节点（没有计数器就自己数，宁可多算一个 group 查询，
	# 也不要为了显示一个数字去给 EnemySystem 加一条每帧同步的耦合）。
	var n := 0
	for e in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if is_instance_valid(e) and e.get("alive"):
			n += 1
	text = "%d FPS · %d 怪" % [int(round(Engine.get_frames_per_second())), n]
