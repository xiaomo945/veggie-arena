extends CanvasLayer

# HUD：血条、波次进度、金币、击杀、武器槽。
# 只订阅 Events 信号更新自己 —— 不认识 Player、也不认识 Game。
# 布局约束：手机竖屏 540x900，顶部 74px 是 HUD 区（竞技场从 y=74 开始），
# 拇指会挡住下半屏，所以所有信息都放顶部。

const HudBarsScene := preload("res://ui/HUD/HudBars.gd")

var _bars: Node2D
var _wave: Label
var _gold: Label
var _kill: Label
var _wave_time := 0.0
var _wave_len := 20.0

func _ready() -> void:
	layer = 20
	_bars = Node2D.new()
	_bars.set_script(HudBarsScene)
	add_child(_bars)

	_wave = _mk_label(Vector2(14, 34), 17, Color(0.95, 0.95, 0.95))
	_gold = _mk_label(Vector2(14, 54), 15, Color(0.98, 0.84, 0.35))
	_kill = _mk_label(Vector2(150, 54), 13, Color(0.75, 0.75, 0.78))

	Events.player_hp_changed.connect(_on_hp)
	Events.gold_changed.connect(_on_gold)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_progress.connect(_on_wave_progress)
	Events.weapons_changed.connect(_on_weapons)
	Events.run_started.connect(_on_weapons)

	_wave_len = float(Data.wave_cfg().get("length", 20))
	_on_weapons()
	_refresh()

func _mk_label(pos: Vector2, size: int, c: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	add_child(l)
	return l

func _on_hp(hp: int, max_hp: int) -> void:
	_bars.set("hp_ratio", float(hp) / maxf(1.0, float(max_hp)))
	_bars.queue_redraw()

func _on_gold(gold: int) -> void:
	_gold.text = "金币 %d" % gold

func _on_wave_started(wave: int) -> void:
	_refresh()

func _on_wave_progress(elapsed: float, length: float) -> void:
	_bars.set("wave_progress", elapsed / maxf(0.001, length))
	_bars.queue_redraw()
	# 击杀数每帧跟着刷新（省一个信号，反正波次进度也是每帧发）
	_kill.text = "击杀 %d" % GameState.kills
	_wave.text = "第 %d 波" % GameState.wave

func _on_weapons() -> void:
	var slots: Array = []
	for w in GameState.weapons:
		if not (w is Dictionary):
			continue
		var def := Data.weapon(str(w.get("key", "")))
		if def.is_empty():
			continue
		slots.append({
			"key": str(w.get("key", "")),
			"lv": int(w.get("lv", 1)),
			"color": Color(str(def.get("color", "#ffffff"))),
			"zh": str(def.get("zh", "")),
		})
	_bars.set("slots", slots)
	_bars.queue_redraw()

func _refresh() -> void:
	_wave.text = "第 %d 波" % GameState.wave
	_kill.text = "击杀 %d" % GameState.kills
