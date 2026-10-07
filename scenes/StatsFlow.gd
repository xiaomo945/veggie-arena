extends Node

# D3-2：属性页流程协调器。持有 StatsScreen 单例（layer=36），监听主界面「属性」键
# 的 stats_opened / stats_closed，仅暂停 / 恢复战斗世界（不弹暂停菜单）。
# 从 Game.gd 拆出，避免 Game 超 300 行架构红线（与 WaveDirector 同一思路）。

const StatsScreenScript := preload("res://ui/Screens/StatsScreen.gd")

var _screen: CanvasLayer = null
var _game = null

func setup(g: Node) -> void:
	_game = g

func _ready() -> void:
	_screen = StatsScreenScript.new()
	_screen.layer = 36
	add_child(_screen)
	Events.stats_opened.connect(_on_stats_opened)
	Events.stats_closed.connect(_on_stats_closed)

func screen() -> CanvasLayer:
	return _screen

func _on_stats_opened() -> void:
	if _game == null or not GameState.running or _game.is_paused():
		return
	_game.set_paused(true)
	GameState.paused = true
	Events.run_paused.emit(true)

func _on_stats_closed() -> void:
	if _game == null or not _game.is_paused():
		return
	_game.set_paused(false)
	GameState.paused = false
	Events.run_paused.emit(false)
