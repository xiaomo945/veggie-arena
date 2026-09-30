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
	_make("shoot", _synth(900, 240, 0.07, 0.22, 0.55))
	_make("hit",   _synth(1300, 620, 0.045, 0.28, 0.0))
	_make("kill",  _synth(420, 940, 0.10, 0.30, 0.0))
	_make("pickup",_synth(880, 1340, 0.12, 0.34, 0.0))
	_make("wave",  _synth(300, 760, 0.35, 0.30, 0.0))
	_make("hurt",  _synth(220, 80, 0.16, 0.42, 0.4))
	_make("over",  _synth(520, 110, 0.7, 0.42, 0.2))
	_make("wok",   _synth(180, 760, 0.30, 0.46, 0.25))

	Events.weapon_fired.connect(_on_shoot)
	Events.damage_dealt.connect(_on_hit)
	Events.enemy_killed.connect(_on_kill)
	# 吃钱时才响（掉落不响）：一地金币掉下来若逐个发声会很吵
	Events.pickup_collected.connect(_on_pickup)
	Events.wave_started.connect(_on_wave)
	Events.player_hp_changed.connect(_on_hp)
	Events.player_died.connect(_on_died)
	Events.wok_tossed.connect(_on_wok)

# 合成一段单声道 16bit PCM 的 AudioStreamWAV
# f0->f1 频率滑音，dur 秒，vol 音量，noise 噪声占比（0=纯音）
func _synth(f0: float, f1: float, dur: float, vol: float, noise: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * dur)
	var data := PackedByteArray()
	for i in n:
		var t := float(i) / float(rate)
		var p := t / dur
		var freq := f0 + (f1 - f0) * p
		var env := (1.0 - p)
		env = env * env              # 更陡的衰减，听感更"短促"
		var s := sin(2.0 * PI * freq * t)
		if noise > 0.0:
			s = s * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise
		var v := s * env * vol
		var pcm := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.append(pcm & 0xFF)
		data.append((pcm >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

func _make(key: String, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
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
		p.play()

func _on_shoot(_a: Vector2, _b: Vector2, _c: Dictionary, _d: Color) -> void:
	_play("shoot", 55)

func _on_hit(_amount: int, _pos: Vector2, _crit: bool) -> void:
	_play("hit", 45)

func _on_kill(_type: String, _pos: Vector2) -> void:
	_play("kill", 35)

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
