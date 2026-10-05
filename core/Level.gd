extends RefCounted

# 经验值 / 等级 —— 纯逻辑层，不碰任何节点，便于 headless 单测。
#
# 设计意图（对应"增加爽点"）：
#   击杀怪除了掉金币还掉经验，经验条实时上涨；升级时弹横幅 + 回血 + 短暂狂暴。
#   升级**不给永久属性** —— 属性仍走商店道具。等级只做"节奏推进器"，
#   避免"商店道具"和"等级奖励"两套数值互相盖、玩家不知道该先升什么。
#
# 曲线为什么是分段而不是纯指数（踩过的坑）：
#   纯指数 needed = base * growth^(lv-1) 实测 1500 杀就冲到 29 级 ——
#   前期狂升级、后期几乎不涨，手感等于"前 3 波把奖励吃光，后面全程空白"。
#   改成 needed(lv) = base + step*(lv-1) + quad*d*(d+1)，d = max(0, lv - span)：
#   前期线性（每波约升 1~2 级，反馈密集），过 span 级才二次加速（高等级仍有追求）。
#   实际量级：1500 杀≈Lv23、3000 杀≈Lv29、一整局 4700 杀≈Lv35；
#   60 级（"未来 60 个萝卜职业"的终局目标）要到无尽段才够得上。
#
# 参数全部走 data/balance.json 的 "level" 段，数值不写死在代码里。

const MAX_LEVEL := 60       # 等级上限（与"未来 60 个萝卜职业"的终局目标对齐）
const HEAL_PCT := 0.14      # 升级回复最大生命的比例（cfg 缺省值）
const FRENZY_SECONDS := 3.0 # 升级后的狂暴时长（cfg 缺省值）
const BASE := 20.0          # 1 级所需经验（cfg 缺省值）
const STEP := 14.0          # 每级线性增量（cfg 缺省值）
const QUAD := 1.0           # 超过 span 后每级的二次增量（cfg 缺省值）
const SPAN := 10            # 从这一级开始二次加速（cfg 缺省值）

# 参数取值：优先读 cfg，缺项回落到上面的常量（单测不传 cfg 也能跑）
static func _p(cfg: Dictionary, key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback)) if cfg.has(key) else fallback


# 从 lv 级升到 lv+1 级所需经验：
#   base + step*(lv-1) + quad*d*(d+1)，d = max(0, lv - span)
static func needed(lv: int, cfg: Dictionary = {}) -> int:
	var l := clampi(lv, 1, MAX_LEVEL)
	var d := maxi(0, l - int(_p(cfg, "span", float(SPAN))))
	var n := _p(cfg, "base", BASE) + _p(cfg, "step", STEP) * float(l - 1) \
		+ _p(cfg, "quad", QUAD) * float(d) * float(d + 1)
	return maxi(1, int(ceil(n)))


# 升到 lv 级所需的总经验
static func total_for(lv: int, cfg: Dictionary = {}) -> float:
	var l := clampi(lv, 1, MAX_LEVEL)
	var sum := 0.0
	for i in range(1, l):
		sum += float(needed(i, cfg))
	return sum


# 把总经验换算成等级 + 当前等级内的进度。
# 返回 {"level": int, "into": int, "need": int, "pct": float(0~1)}
static func breakdown(xp_total: int, cfg: Dictionary = {}) -> Dictionary:
	var xp := maxi(0, xp_total)
	var lv := 1
	var need := needed(lv, cfg)
	while lv < MAX_LEVEL and xp >= need:
		xp -= need
		lv += 1
		need = needed(lv, cfg)
	return {
		"level": lv,
		"into": xp,
		"need": need,
		"pct": clampf(float(xp) / float(maxi(1, need)), 0.0, 1.0),
	}


# 攒经验 -> 可能连升多级。返回 {"xp","level","gained"}，gained=0 表示没升级。
static func add(xp_total: int, amount: int, cfg: Dictionary = {}) -> Dictionary:
	var before: int = int(breakdown(xp_total, cfg)["level"])
	var after_total: int = maxi(0, xp_total + maxi(0, amount))
	var after: int = int(breakdown(after_total, cfg)["level"])
	return {"xp": after_total, "level": after, "gained": maxi(0, after - before)}


# 升级奖励的纯计算：返回 {"heal": int, "frenzy": float}
# 刻意不给永久属性（见文件头）。回血按上限百分比，连升多级时按倍数放大。
static func level_up_reward(gained: int, max_hp: int, cfg: Dictionary) -> Dictionary:
	var g := maxi(1, gained)
	var per := _p(cfg, "heal_pct", HEAL_PCT)
	var secs := _p(cfg, "frenzy_seconds", FRENZY_SECONDS)
	return {
		"heal": mini(max_hp, int(round(float(max_hp) * per * float(g)))),
		"frenzy": secs * float(g),
	}


# 击杀获得的经验：按敌人类型给不同权重。防"打小怪刷等级"，
# 所以精英/Boss 权重刻意拉高，让玩家有"优先打精英"的动机。
static func xp_for(etype: String, base_xp: int) -> int:
	var x := float(maxi(1, base_xp))
	match etype:
		"boss", "final_boss":
			x *= 14.0
		"elite":
			x *= 5.0
		"brute", "shambler", "tank":
			x *= 2.2
		"charger", "shooter", "bomber", "splitter":
			x *= 1.5
		"swarm":
			x *= 0.4    # 虫群给得少：不希望玩家靠刷小怪冲等级
	# 保底 1 点：base_xp 配成 0 或权重 <0.5 也不会出现"打了没经验"的挫败感
	return maxi(1, int(round(x)))
