extends Node

# 音频 + 画质/性能设置持久化，存 user://turnip_settings.json。
# 独立于存档 SaveMgr：设置是设备级偏好，不该随存档回退/清洗。
# headless 下写文件可能失败，save() 容错（只 push_warning），不影响游戏运行。
#
# ⚠️ 共享契约：子 Agent A 的 EnemySystem/Player 用 Settings.get("particles_enabled", true)
# 这类两参数写法读取开关。Godot 4 的 Object.get 仅单参数，故这里自定义一个 get()
# （显式匹配键，避免递归 / super 调用风险），保证开关联动生效。

const PATH := "user://turnip_settings.json"

# ---- 既有音频开关 ----
var sfx_on := true
var music_on := true
var muted := false

# ---- 新增：画质 / 性能降级 ----
# quality: 0=低 / 1=中 / 2=高（默认 1 中画质）
var quality: int = 1
# 粒子 / 震屏总开关（默认开；低画质会被强制关）
var particles_enabled: bool = true
var screenshake_enabled: bool = true
# 帧率目标：0 = 引擎默认（不限制/默认）
var fps_target: int = 0
# 音量 0..100（默认满）
var music_volume: int = 100
var sfx_volume: int = 100
# 移动速度手感倍率（百分比，100 = 基准）。手感是主观的，与其反复改数值重新出包，
# 不如让玩家自己拧：范围 70%~180%，实时生效（下一帧重建速度）。
var move_scale: int = 100
# 语言偏好："en"（出海默认）/ "zh"（中文）。首次启动跟随系统语言自动选，
# 之后以 Settings 持久化值为准。开发者用中文设备测试时自动进中文，方便。
var language: String = "en"

func _ready() -> void:
	_load()
	apply_fps()
	# 音频总线重路由依赖 Sfx/Bgm 已创建播放器，延后一帧执行更稳妥
	call_deferred("apply_audio")

# 安全读取设置项：已知键直接返回；未知键回退引擎内置 Object.get；提供 default 时返回 default。
# ⚠️ 不能覆盖原生 Object.get（Godot 4.3 视为错误），故用独立方法名 get_setting。
func get_setting(key: String, default: Variant = null) -> Variant:
	match key:
		"sfx_on": return sfx_on
		"music_on": return music_on
		"muted": return muted
		"quality": return quality
		"particles_enabled": return particles_enabled
		"screenshake_enabled": return screenshake_enabled
		"fps_target": return fps_target
		"music_volume": return music_volume
		"sfx_volume": return sfx_volume
		"move_scale": return move_scale
		"language": return language
		_:
			var v = super.get(key)
			if v == null:
				return default
			return v

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		# 首次启动：跟随系统语言（中文设备→中文，方便国内玩家与开发者测试；其余→英文出海）
		language = _auto_locale()
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
		quality = int(d.get("quality", 1))
		particles_enabled = bool(d.get("particles_enabled", true))
		screenshake_enabled = bool(d.get("screenshake_enabled", true))
		fps_target = int(d.get("fps_target", 0))
		music_volume = int(d.get("music_volume", 100))
		sfx_volume = int(d.get("sfx_volume", 100))
		move_scale = clampi(int(d.get("move_scale", 100)), 70, 180)
		language = str(d.get("language", "en"))
		if language != "en" and language != "zh":
			language = "en"

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: 无法写入 %s（无痕模式/headless）" % PATH)
		return
	f.store_string(JSON.stringify({
		"sfx_on": sfx_on,
		"music_on": music_on,
		"muted": muted,
		"quality": quality,
		"particles_enabled": particles_enabled,
		"screenshake_enabled": screenshake_enabled,
		"fps_target": fps_target,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"move_scale": move_scale,
		"language": language,
	}))
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

# ---- 画质 / 性能 ----
func set_quality(v: int) -> void:
	quality = clampi(v, 0, 2)
	_save()

func set_particles(on: bool) -> void:
	particles_enabled = on
	_save()

func set_screenshake(on: bool) -> void:
	screenshake_enabled = on
	_save()

func set_fps_target(v: int) -> void:
	fps_target = maxi(0, v)
	apply_fps()
	_save()

# 音量：0..100，实时改对应音频总线，并持久化
func set_music_volume(v: int) -> void:
	music_volume = clampi(v, 0, 100)
	apply_audio()
	_save()

func set_sfx_volume(v: int) -> void:
	sfx_volume = clampi(v, 0, 100)
	apply_audio()
	_save()

# 移动速度手感：70%~180%。只存值，实际速度由 Player 每次重建时读取。
func set_move_scale(v: int) -> void:
	move_scale = clampi(v, 70, 180)
	_save()

# ---- 语言偏好 ----
# 跟随系统语言决定默认语言：中文（zh/zh-CN/zh-TW 等）→ 中文，其余 → 英文
func _auto_locale() -> String:
	var l := OS.get_locale_language()
	if l == "zh":
		return "zh"
	return "en"

func get_language() -> String:
	return language

func set_language(code: String) -> void:
	if code != "en" and code != "zh":
		return
	language = code
	_save()

# 帧率目标应用到引擎（0 = 引擎默认）
func apply_fps() -> void:
	Engine.max_fps = fps_target

# 建立 Music / Sfx 两条子总线，并把 Sfx/Bgm 的播放器重路由到对应总线，
# 从而实现音乐 / 音效独立音量。不改 Sfx.gd / Bgm.gd 源码。
func apply_audio() -> void:
	_ensure_bus("Music")
	_ensure_bus("Sfx")
	for p in Bgm.get_children():
		var ap := p as AudioStreamPlayer
		if ap != null and ap.bus != "Music":
			ap.bus = "Music"
	for p in Sfx.get_children():
		var ap := p as AudioStreamPlayer
		if ap != null and ap.bus != "Sfx":
			ap.bus = "Sfx"
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, _db(music_volume))
	var si := AudioServer.get_bus_index("Sfx")
	if si >= 0:
		AudioServer.set_bus_volume_db(si, _db(sfx_volume))

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) != -1:
		return
	AudioServer.add_bus(AudioServer.bus_count)
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")

# 0 音量视为静音（-80dB），否则按线性比例换算
func _db(v: int) -> float:
	if v <= 0:
		return -80.0
	return linear_to_db(float(v) / 100.0)
