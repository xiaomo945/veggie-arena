extends RefCounted

# BGM 模块契约测试：
# 1) 三段 Ogg 文件存在且格式合法（防被误删 / 格式错）
# 2) 能被 Godot 真正 load 成 AudioStreamOggVorbis 且 loop=true
#    —— 防"OGG 没导入 → 游戏里静音"这种最隐蔽的回归
# 3) Bgm.gd 引用的三条路径与文件一一对应

const TRACKS := {
	"menu": "res://art/audio/bgm_menu.ogg",
	"battle": "res://art/audio/bgm_battle.ogg",
	"boss": "res://art/audio/bgm_boss.ogg",
}

var _p := 0
var _f := 0
var _failures: Array = []

func chk(cond: bool, msg: String) -> bool:
	if cond:
		_p += 1
		print("  OK: " + msg)
	else:
		_f += 1
		_failures.append(msg)
		print("  FAIL: " + msg)
	return cond

func run(_arg = null) -> Dictionary:
	var max_bytes := 3 * 1024 * 1024   # 单文件上限 3MB（网页加载预算）

	for k in TRACKS.keys():
		var path: String = TRACKS[k]
		var exists := FileAccess.file_exists(path)
		if not chk(exists, "BGM 文件存在: %s" % path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var len := f.get_length()
		var hdr := f.get_buffer(4)
		f.close()
		var is_ogg := hdr.size() == 4 and hdr[0] == 79 and hdr[1] == 103 and hdr[2] == 103 and hdr[3] == 83
		chk(is_ogg, "BGM 是合法 Ogg: %s" % path)
		chk(len > 1000 and len < max_bytes, "BGM 体积合理(%dKB): %s" % [len / 1024, path])

		var s = load(path)
		if not chk(s != null, "Godot 能 load: %s" % path):
			continue
		var ogg := s as AudioStreamOggVorbis
		if not chk(ogg != null, "是 AudioStreamOggVorbis: %s" % path):
			continue
		chk(ogg.loop == true, "loop=true 可循环: %s" % path)

	# Bgm.gd 是否引用了这三条路径（路径写错/漏接都会挂）
	var bgm_src := FileAccess.get_file_as_string("res://autoload/Bgm.gd")
	for k in TRACKS.keys():
		chk(bgm_src.contains(TRACKS[k]), "Bgm.gd 引用 %s" % TRACKS[k])

	return {"pass": _p, "fail": _f, "failures": _failures}
