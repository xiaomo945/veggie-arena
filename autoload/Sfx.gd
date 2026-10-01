extends Node

# 程序化音效：不下载任何素材，用代码合成 PCM16 短音，接 Events 信号即播。
# 出海网页版在玩家点 START（用户手势）后才会解锁 WebAudio，音效随之生效。
# headless 模拟里 AudioServer 是 dummy，play() 安全无副作用。
#
# 信号高发的（开火/命中/击杀）都做了节流，避免一帧几十发把声音叠爆。

var _players: Dictionary = {}
var _last_hp := 999
var _last_at: Dictionary = {}   # 每种音效上次播放的毫秒时间，用于节流

func _ready() -> void:
	# 音效全部用子 Agent 合成的程序化 Ogg（art/sfx/），质量比内联 _synth 更好；
	# 缺文件时 push_warning 静默，不崩游戏。hurt 复用命中音（无专门受伤音）。
	_load("shoot", "res://art/sfx/sfx_shoot.ogg")
	_load("hit", "res://art/sfx/sfx_hit.ogg")
	_load("kill", "res://art/sfx/sfx_kill.ogg")
	_load("pickup", "res://art/sfx/sfx_coin.ogg")
	_load("wave", "res://art/sfx/sfx_levelup.ogg")
	_load("hurt", "res://art/sfx/sfx_hit.ogg")
	_load("over", "res://art/sfx/sfx_defeat.ogg")
	_load("wok", "res://art/sfx/sfx_wok.ogg")
	_load("button", "res://art/sfx/sfx_button.ogg")
	_load("dash", "res://art/sfx/sfx_dash.ogg")
	_load("unlock", "res://art/sfx/sfx_unlock.ogg")
	_load("victory", "res://art/sfx/sfx_victory.ogg")
	# 击杀/重击分层音（资源缺失则静默跳过，不影响既有调用方）
	_load("hit_heavy", "res://art/sfx/sfx_hit_heavy.ogg")
	_load("kill_boss", "res://art/sfx/sfx_kill_boss.ogg")

	Events.weapon_fired.connect(_on_shoot)
	Events.damage_dealt.connect(_on_hit)
	Events.enemy_killed.connect(_on_kill)
	# 吃钱时才响（掉落不响）：一地金币掉下来若逐个发声会很吵
	Events.pickup_collected.connect(_on_pickup)
	Events.wave_started.connect(_on_wave)
	Events.player_hp_changed.connect(_on_hp)
	Events.player_died.connect(_on_died)
	Events.wok_tossed.connect(_on_wok)
	Events.dash_started.connect(_on_dash)
	Events.unlocked.connect(_on_unlock)
	Events.run_won.connect(_on_victory)
	# 按设置应用音量（音效开关/总静音）；设置变了也由 PauseScreen 回调重调
	# call_deferred：autoload 全局名在所有 _ready 跑完后才注册，此处延迟避免 Settings 仍是 Nil
	call_deferred("apply_volume")

# 加载一个音效 Ogg（子 Agent 合成），放进播放器池；缺文件则静默跳过
func _load(key: String, path: String) -> void:
	var s := load(path) as AudioStream
	if s == null:
		push_warning("Sfx: 缺少音效资源 %s，该音效将静默" % path)
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "Master"
	add_child(p)
	_players[key] = p

# 节流：同音效距上次播放不足 gap_ms 就跳过（避免一帧几十发叠爆）
func _play(key: String, gap_ms: int) -> void:
	var now := Time.get_ticks_msec()
	if _last_at.has(key) and now - _last_at[key] < gap_ms:
		return
	_last_at[key] = now
	var p: AudioStreamPlayer = _players.get(key)
	if p != null:
		p.pitch_scale = 1.0
		p.play()

# 带音高的播放（用于按伤害/敌人类型调制音色，制造层次）
func _play_pitched(key: String, gap_ms: int, pitch: float) -> void:
	var now := Time.get_ticks_msec()
	if _last_at.has(key) and now - _last_at[key] < gap_ms:
		return
	_last_at[key] = now
	var p: AudioStreamPlayer = _players.get(key)
	if p != null:
		p.pitch_scale = pitch
		p.play()

func _on_shoot(_a: Vector2, _b: Vector2, _c: Dictionary, _d: Color) -> void:
	_play("shoot", 55)

func _on_hit(amount: int, _pos: Vector2, crit: bool) -> void:
	# 伤害越大音调越低 → 重击更有"分量"；暴击提亮
	var pitch: float = 1.0
	if crit:
		pitch = 1.3
	else:
		pitch = clampf(1.7 - float(amount) * 0.013, 0.7, 1.7)
	_play_pitched("hit", 45, pitch)
	# 大额伤害叠一层低频"闷响"（资源缺失则静默）
	if amount >= 30:
		_play_pitched("hit_heavy", 90, 0.8)

func _on_kill(type: String, _pos: Vector2) -> void:
	# 按敌人类型调制击杀音色：Boss 更沉、重甲略低
	var pitch: float = 1.0
	if type == "boss":
		pitch = 0.6
	elif type == "tank":
		pitch = 0.85
	_play_pitched("kill", 35, pitch)
	if type == "boss":
		_play_pitched("kill_boss", 120, 1.0)

func _on_pickup(_pos: Vector2, _value: int) -> void:
	_play("pickup", 60)

func _on_wave(_w: int) -> void:
	_play("wave", 200)

func _on_hp(hp: int, _max_hp: int) -> void:
	if hp < _last_hp:
		_play("hurt", 80)
	_last_hp = hp

func _on_died() -> void:
	_play("over", 500)

func _on_wok() -> void:
	_play("wok", 120)

# 按 Settings 把每个播放器压到静音或恢复（音效开关/总静音变化时由 PauseScreen 调）
func apply_volume() -> void:
	var on := true
	if Settings != null:
		on = Settings.sfx_enabled()
	for p in _players.values():
		var ap := p as AudioStreamPlayer
		if ap != null:
			if on:
				ap.volume_db = 0.0
			else:
				ap.volume_db = -80.0

# UI 按钮点击音（暂停菜单/通用按钮）
func ui_click() -> void:
	_play("button", 10)

func _on_dash() -> void:
	_play("dash", 50)

func _on_unlock(_key: String) -> void:
	_play("unlock", 0)

func _on_victory() -> void:
	_play("victory", 0)
