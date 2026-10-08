extends Node

# BGM 管理器：三段可无缝循环的背景乐，按游戏阶段切换，并做交叉淡入淡出。
#   menu  主菜单/结算页   —— 轻松诙谐，带中式五声音阶味
#   battle 战斗波次        —— 舒缓中速，96 BPM
#   boss   Boss 波         —— 稍稳明亮，104 BPM
# 三段都是程序化合成、可商用、单声道 Ogg，详见 art/audio/。
#
# WebAudio 在用户手势（点 START）后才解锁，标题页若还没点过就没声，
# 属于浏览器策略，正常 —— 真正常听得到的是开跑后的战斗乐。

const TRACKS := {
	"menu": "res://art/audio/bgm_menu.ogg",
	"battle": "res://art/audio/bgm_battle.ogg",
	"boss": "res://art/audio/bgm_boss.ogg",
}
const VOL_DB := -10.0     # BGM 比音效低一档，不盖过开火/命中/击杀；用户嫌"催命"再压一档
const FADE := 0.7         # 交叉淡入淡出秒数

# 音乐总开关：用户仍不满意、要求先关掉，故暂置 false（静音）。
# 「最后再做」时改回 true 即可恢复；届时若仍不满意可同步调 gen_bgm.py 的 BPM/增益。
const ENABLED := false

var _players := {}
var _current := ""

# 当前曲目的目标音量（含用户音乐音量设置）；关音乐时直接静音
func _target_db() -> float:
	if Settings == null:
		return VOL_DB
	var db: float = Settings.music_player_db()
	return -80.0 if db <= -79.0 else db + VOL_DB

func _ready() -> void:
	for k in TRACKS.keys():
		var p := AudioStreamPlayer.new()
		var s := load(TRACKS[k]) as AudioStreamOggVorbis
		if s != null:
			s.loop = true
		p.stream = s
		p.bus = "Master"
		p.volume_db = -60.0
		add_child(p)
		_players[k] = p
	Events.run_started.connect(_on_run_started)
	Events.wave_started.connect(_on_wave_started)
	Events.boss_wave.connect(_on_boss_wave)
	Events.final_boss_wave.connect(_on_boss_wave)
	Events.player_died.connect(_on_died)
	Events.run_won.connect(_on_won)
	# 标题页菜单乐：桌面端立即响；Web 端等首次手势解锁后才响（正常）
	# call_deferred：避免 _ready 阶段 Settings 全局名尚未注册（为 Nil）
	if ENABLED:
		call_deferred("play", "menu")

# 切到指定曲；同曲已在播则忽略（不切断循环），避免重复触发时一顿一顿。
func play(track: String) -> void:
	if not ENABLED:
		return
	if not _players.has(track):
		return
	# 音乐关：只把该曲压静音、不实际播放（省资源）
	if Settings == null or not Settings.music_enabled():
		var silent := _players[track] as AudioStreamPlayer
		if silent != null:
			silent.volume_db = -80.0
		return
	if _current == track:
		var cur := _players[track] as AudioStreamPlayer
		if cur != null and not cur.playing:
			cur.volume_db = -60.0
			cur.play()
			_fade_in(track)
		return
	if _current != "" and _players.has(_current):
		_fade_out(_current)
	_current = track
	var p := _players[track] as AudioStreamPlayer
	if p == null:
		return
	p.volume_db = -60.0
	p.play()
	_fade_in(track)

func _fade_in(track: String) -> void:
	var p := _players[track] as AudioStreamPlayer
	if p == null:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", _target_db(), FADE)

func _fade_out(track: String) -> void:
	var p := _players[track] as AudioStreamPlayer
	if p == null:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, FADE)
	tw.tween_callback(p.stop)

func _on_run_started() -> void:
	play("battle")

func _on_wave_started(_w: int) -> void:
	play("battle")

func _on_boss_wave(_w: int) -> void:
	play("boss")

func _on_died() -> void:
	play("menu")

func _on_won() -> void:
	play("menu")

# 设置改变后重读音乐开关：当前曲恢复音量/重播，非当前曲压静音
func refresh() -> void:
	var on := true
	if Settings != null:
		on = Settings.music_enabled()
	for k in _players.keys():
		var p := _players[k] as AudioStreamPlayer
		if p == null:
			continue
		if k == _current and on:
			if not p.playing:
				p.volume_db = -60.0
				p.play()
			_fade_in(k)
		else:
			p.volume_db = -80.0
