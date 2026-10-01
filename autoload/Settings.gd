extends Node

# 音频设置持久化（音效/音乐开关 + 总静音），存 user://turnip_settings.json。
# 独立于存档 SaveMgr：设置是设备级偏好，不该随存档回退/清洗。
# headless 下写文件可能失败，save() 容错（只 push_warning），不影响游戏运行。

const PATH := "user://turnip_settings.json"

var sfx_on := true
var music_on := true
var muted := false

func _ready() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		sfx_on = bool(d.get("sfx_on", true))
		music_on = bool(d.get("music_on", true))
		muted = bool(d.get("muted", false))

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: 无法写入 %s（无痕模式/headless）" % PATH)
		return
	f.store_string(JSON.stringify({"sfx_on": sfx_on, "music_on": music_on, "muted": muted}))
	f.close()

# 音效此刻是否该响（受总静音影响）
func sfx_enabled() -> bool:
	return sfx_on and not muted

# 音乐此刻是否该响（受总静音影响）
func music_enabled() -> bool:
	return music_on and not muted

func toggle_sfx() -> bool:
	sfx_on = !sfx_on
	_save()
	return sfx_on

func toggle_music() -> bool:
	music_on = !music_on
	_save()
	return music_on

func toggle_muted() -> bool:
	muted = !muted
	_save()
	return muted
