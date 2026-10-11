extends RefCounted

# 输入缓冲（纯逻辑）：动作按下那一刻如果不可用（冲刺还在冷却、技能没转好），
# 把这一下记下来；在窗口内一旦可用就自动补发。
#
# 为什么必须有："跟不跟手"的分水岭就在这里。冲刺冷却 1.8s，玩家凭手感会在
# 还差 0.1 秒时按下去 —— 没缓冲就是按了没反应，玩家读成"这游戏不听我的"，
# 而实际上他按对了，只是早了 100ms。动作游戏普遍给 0.1~0.2s 的缓冲窗口。
#
# ⚠️ 窗口不能太长：超过 0.2s 就变成"我早按了半秒它自己放了"，玩家会觉得失控。
#   0.15s 是"刚好覆盖人类提前量"的量级。

const WINDOW := 0.15

# 记一次按下（同一个 key 重复按下会刷新窗口，不会叠加）
static func arm(buf: Dictionary, key: String, win: float = WINDOW) -> void:
	buf[key] = win

# 每帧推进；窗口归零就丢弃（过期的输入不该补发）
static func tick(buf: Dictionary, delta: float) -> void:
	var dead: Array = []
	for k in buf.keys():
		var t: float = float(buf[k]) - delta
		if t <= 0.0:
			dead.append(k)
		else:
			buf[k] = t
	for k in dead:
		buf.erase(k)

# 这一下还在窗口内吗（调用方还要自己判动作此刻是否真的可用）
static func pending(buf: Dictionary, key: String) -> bool:
	return float(buf.get(key, 0.0)) > 0.0

# 已经补发了，消费掉（避免重复触发）
static func consume(buf: Dictionary, key: String) -> void:
	buf.erase(key)
