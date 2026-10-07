extends RefCounted

# 锅气 Wok Heat 纯逻辑：不依赖任何 autoload / 渲染节点，便于 --script 单测。
# 状态是一个 Dictionary：{"heat", "tier", "ready", "stir", "hei", "max"}
# 所有数值都来自 data/balance.json 的 "wok" 段 —— 数值只改 JSON，不碰这里。

# 新建一份初始状态（火候 0、微温、无充能、不可颠勺）
static func make(cfg: Dictionary) -> Dictionary:
	return {
		"heat": 0.0,
		"tier": 0,
		"ready": false,
		"charges": 0,                       # 已银行(存住)的颠勺充能数
		"max_charges": int(cfg.get("max_charges", 3)),
		"stir": float(cfg.get("stir_from", 34)),
		"hei": float(cfg.get("wokhei_from", 68)),
		"max": float(cfg.get("max", 100)),
	}

static func heat_of(s: Dictionary) -> float:
	return float(s.get("heat", 0.0))

static func tier(s: Dictionary) -> int:
	return int(s.get("tier", 0))

static func ready(s: Dictionary) -> bool:
	return charges_of(s) > 0

static func charges_of(s: Dictionary) -> int:
	return int(s.get("charges", 0))

# 设火候并重新计算档位/就绪状态（阈值钳制都在这里）
static func _apply(s: Dictionary, cfg: Dictionary, v: float) -> void:
	v = clampf(v, 0.0, float(s.get("max", 100)))
	s["heat"] = v
	var t := 0
	if v >= float(s.get("hei", 68)):
		t = 2
	elif v >= float(s.get("stir", 34)):
		t = 1
	s["tier"] = t
	# 就绪 = 有充能可放（颠勺按钮因此常驻，不受火候衰减影响）
	s["ready"] = charges_of(s) > 0

static func add(s: Dictionary, cfg: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var v := heat_of(s) + amount
	var cap := float(s.get("max", 100))
	var thr := float(cfg.get("ready", 100)) - 0.001
	if v >= thr:
		# 火候攒满 → 自动银行一个颠勺充能，火候条归零（爆炒/翻炒临时增益随之结束）
		var maxc := int(s.get("max_charges", 3))
		var cur := int(s.get("charges", 0))
		if cur < maxc:
			s["charges"] = cur + 1
			v = 0.0
		else:
			# 充能已封顶：火候保留在满值，不浪费这段进度
			v = cap
	_apply(s, cfg, v)

# 白送充能（开局教学用）：爆炒萝卜一进局就有一个颠勺能按 —— 按一下就看见
# "输出全在颠勺"这件事，比任何 tip 文案都快。上限仍由 max_charges 卡住。
static func grant(s: Dictionary, n: int) -> void:
	if n <= 0:
		return
	var maxc := int(s.get("max_charges", 3))
	s["charges"] = mini(maxc, int(s.get("charges", 0)) + n)
	s["ready"] = charges_of(s) > 0

# 每帧自然衰减：停手不刷怪就凉下来，逼你保持进攻节奏
static func decay(s: Dictionary, cfg: Dictionary, delta: float) -> void:
	_apply(s, cfg, heat_of(s) - float(cfg.get("decay_per_sec", 7)) * delta)

# 挨打掉火候（被摸一下 = 锅被泼了冷水）
static func cool(s: Dictionary, cfg: Dictionary, amount: float) -> void:
	_apply(s, cfg, heat_of(s) - amount * float(cfg.get("cool_on_hit", 0.7)))

# 开火攻速倍率（爆炒档最猛）
static func fire_mult(s: Dictionary, cfg: Dictionary) -> float:
	var t := tier(s)
	if t >= 2:
		return 1.0 + float(cfg.get("tier2_fire", 0.55))
	if t >= 1:
		return 1.0 + float(cfg.get("tier1_fire", 0.25))
	return 1.0

# 开火伤害倍率（仅爆炒档加成）
static func dmg_mult(s: Dictionary, cfg: Dictionary) -> float:
	if tier(s) >= 2:
		return 1.0 + float(cfg.get("tier2_dmg", 0.30))
	return 1.0

# 颠勺：消耗一个已存充能（火候条不变；只要还有充能就能放，按钮因此常驻）
static func toss(s: Dictionary, cfg: Dictionary) -> bool:
	if charges_of(s) <= 0:
		return false
	s["charges"] = int(s.get("charges", 0)) - 1
	# 火候条按当前值保留（不回退到 toss_reset），stir/blazing 档位跟着火候走
	s["ready"] = charges_of(s) > 0
	return true
