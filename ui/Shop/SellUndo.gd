extends RefCounted

# 售出撤销：记住"上一次卖出的那把武器"，提供一键恢复（点错了不丢武器、不白亏钱）。
#
# 为什么独立成文件：Shop.gd 已逼近架构守卫 R1 的 300 行上限，把撤销的状态与逻辑
# 抽到这里，Shop.gd 只做"接线 + 在合适时机 reset"，不超行。
#
# 行为：每次卖出都会覆盖上一次快照（所以撤销永远 = 最近一次卖出）；
# 买武器 / 整店刷新 / 重新开商店时 reset，避免撤销出"超出槽位 / 状态错乱"。

const Inventory := preload("res://core/Inventory.gd")
# GameState / Events 是 autoload 单例，直接用全局名访问（不要 preload 成类，
# 否则会把同名的全局单例遮蔽掉，解析期就报"对非静态类调用"，本脚本编译失败→SellUndo.new() 返回 Nil）。
# 参考 Shop.gd：它也是直接用 GameState.gold / Events.xxx 的全局名。

var _snap: Dictionary = {}      # {"w": 武器副本, "gold": 回收金币}；空 = 无可撤销
var _btn: Button = null
var _refresh: Callable = Callable()

# 把撤销按钮接进来：默认隐藏，点按时恢复最近一次卖出
func wire(btn: Button, refresh_cb: Callable) -> void:
	_btn = btn
	_refresh = refresh_cb
	_btn.visible = false
	_btn.pressed.connect(_on_undo)

# 执行卖出并记录快照；返回 {"gain":int, "kept":bool}
#   kept=true  —— 最后一把不让卖（Inventory 已保护"至少留 1 把"），由调用方弹红字提示
#   gain=0     —— 白送武器（买入价 0），卖了不退钱，无需撤销
func sell(weapons: Array, idx: int, ratio: float) -> Dictionary:
	if idx < 0 or idx >= weapons.size() or weapons.size() <= 1:
		_show(false)
		return {"gain": 0, "kept": true}
	_snap = {"w": (weapons[idx] as Dictionary).duplicate(true), "gold": 0}
	var gain := Inventory.sell_weapon(weapons, idx, ratio)
	_snap["gold"] = gain
	if gain > 0:
		GameState.add_gold(gain)
		Events.weapons_changed.emit(weapons)
		_show(true)
	else:
		_snap = {}          # 没退钱，撤销没意义
		_show(false)
	return {"gain": gain, "kept": false}

func _on_undo() -> void:
	if _snap.is_empty():
		return
	GameState.weapons.append((_snap["w"] as Dictionary).duplicate(true))
	GameState.add_gold(-int(_snap.get("gold", 0)))
	Events.weapons_changed.emit(GameState.weapons)
	_snap = {}
	_show(false)
	if _refresh.is_valid():
		_refresh.call()

# 商店重开 / 买了东西 / 整店刷新时清掉快照，撤销按钮隐藏
func reset() -> void:
	_snap = {}
	_show(false)

func _show(on: bool) -> void:
	if _btn != null:
		_btn.visible = on
