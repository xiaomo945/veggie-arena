extends SceneTree

# 项目配置"读回"探针：把 project.godot 里的关键设置【运行时实际值】打出来。
#
# 为什么要读回而不是看文件：Godot 的 ConfigFile 解析器会把一段非 ASCII 注释
# 并进紧邻的下一个键名（实测过两次），于是文件里明明写着
#   window/dpi/allow_hidpi=false
# 运行时读回来却是引擎默认的 true —— 文件看着对、实际没生效，而且没有任何报错。
# 那次事故让我们"以为关掉了 HiDPI"，手机上一直在按 DPR 2~3 渲染
# （1179x2619 像素/帧，填充率直接吃掉帧率），是"怪一多就卡"的 A 类真凶之一。
#
# 这个探针只负责输出，判定在 scripts/cfg_guard.py。

const KEYS := [
	"physics/common/physics_interpolation",
	"physics/common/physics_ticks_per_second",
	"display/window/dpi/allow_hidpi",
	"display/window/size/viewport_width",
	"display/window/size/viewport_height",
	"input_devices/pointing/emulate_mouse_from_touch",
	"rendering/renderer/rendering_method",
]

func _initialize() -> void:
	for k in KEYS:
		print("CFG %s=%s" % [k, str(ProjectSettings.get_setting(k, "MISSING"))])
	quit()
