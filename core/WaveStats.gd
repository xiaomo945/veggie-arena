extends RefCounted

# 每波统计（D3-3 结算页用）：纯数据 + 快照逻辑，从 GameState 拆出避免它超 300 行。
# 只记录"本波"的金币/击杀/连击，所有字段公开（测试可直接构造，不碰私有字段）。

const COMBO_WINDOW := 2.5   # 连击有效窗口（秒，与 HUD 一致）

var gold_start: int = 0      # 本波开局持有金币
var kills_start: int = 0      # 本波开局累计击杀
var combo: int = 0           # 本波连击计数（每次击杀 +1，超时归零）
var best_combo: int = 0      # 本波最高连击
var _combo_t: float = 0.0     # 连击有效剩余时间

# 每波开局快照一次（商店内的购买/花费不影响本波金币统计）
func snapshot(gold: int, kills: int) -> void:
	gold_start = gold
	kills_start = kills
	combo = 0
	best_combo = 0
	_combo_t = 0.0

func add_kill() -> void:
	combo += 1
	if combo > best_combo:
		best_combo = combo
	_combo_t = COMBO_WINDOW

# 连击衰减：超过 COMBO_WINDOW 秒没击杀则归零（结算页读 best_combo）
func tick(delta: float) -> void:
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			combo = 0

func gold_earned(gold: int) -> int:
	return maxi(0, gold - gold_start)

func kills_this_wave(kills: int) -> int:
	return maxi(0, kills - kills_start)
