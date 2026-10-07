extends RefCounted

# 刷怪逻辑 —— 纯逻辑，不引用任何 Node / 场景
# 输入 wave（第几波）与配置，输出"刷什么、刷多快、刷在哪、属性多少"

# 每秒刷怪数量：base + wave * per，不超过 cap。
# over>0 表示进入无尽段：允许突破常规 cap，在 cap 之上按 endless 段另加并封顶到 rate_cap。
static func spawn_rate(wave: int, cfg: Dictionary, over: int = 0, ecfg: Dictionary = {}) -> float:
	var base := float(cfg.get("base_rate", 0.5))
	var per := float(cfg.get("per_wave", 0.3))
	var cap := float(cfg.get("cap", 5.0))
	# ⚠️ 用 (wave - 1)：第 1 波不该已经吃到"波次成长"的加成。
	# 旧式 base + wave*per 让开局那 45 秒就刷 155 只，而玩家手上只有 2 把 Lv1 武器
	# （scripts/power_probe.gd 实测第 1 波清场率只有 86%）—— 新手第一波就被淹没，
	# 既拿不到那 14% 的金币，也直接劝退。改成 (wave-1) 后第 1 波 126 只、清场率过 100%，
	# 到第 20 波只比原来少 4%，后期强度不受影响。
	var r := minf(cap, base + float(wave - 1) * per)
	if over > 0:
		var ecap := float(ecfg.get("rate_cap", cap))
		r = minf(ecap, r + float(ecfg.get("rate_per_wave", 0.0)) * float(over))
	return r

# 精英出场概率：第 elite_from_wave 波起，每隔 elite_every 波来一轮；
# 轮内的概率 = elite_chance + elite_chance_per_wave * (wave - from)，封顶 elite_chance_cap。
# 不在精英轮 → 0（普通波完全不出精英，保证"变强版"是稀缺的、有节奏的惊喜）。
static func elite_chance(wave: int, cfg: Dictionary) -> float:
	var from := int(cfg.get("elite_from_wave", 1))
	if from <= 0 or wave < from:
		return 0.0
	var every := maxi(1, int(cfg.get("elite_every", 1)))
	if (wave - from) % every != 0:
		return 0.0
	var base := float(cfg.get("elite_chance", 0.0))
	var per := float(cfg.get("elite_chance_per_wave", 0.0))
	var cap := float(cfg.get("elite_chance_cap", 1.0))
	return clampf(base + per * float(wave - from), 0.0, cap)

# 一整波预计刷出多少只（用于配平估算）
static func wave_budget(wave: int, cfg: Dictionary, length: float) -> float:
	return spawn_rate(wave, cfg) * length

# 按概率挑敌人类型，r ∈ [0,1)
# 概率带（按 r 从小到大）：fast → fly → swarm → brute → shambler → grunt(中段) → [tank 在尾部]
static func pick_type(wave: int, r: float, cfg: Dictionary) -> String:
	var fast_chance := 0.0
	var fly_chance := 0.0
	var tank_chance := 0.0
	var swarm_chance := 0.0
	var brute_chance := 0.0
	var shambler_chance := 0.0
	var shooter_chance := 0.0
	var charger_chance := 0.0
	var bomber_chance := 0.0
	var splitter_chance := 0.0
	if wave >= int(cfg.get("fast_from_wave", 2)):
		fast_chance = float(cfg.get("fast_chance", 0.28))
	if wave >= int(cfg.get("fly_from_wave", 4)):
		fly_chance = float(cfg.get("fly_chance", 0.20))
	if wave >= int(cfg.get("tank_from_wave", 3)):
		tank_chance = float(cfg.get("tank_chance", 0.12))
	if wave >= int(cfg.get("tank_late_from_wave", 6)):
		tank_chance = float(cfg.get("tank_chance_late", 0.18))
	# 新增敌人：到对应波次才进概率带，避免前期过载
	if wave >= int(cfg.get("swarm_from_wave", 5)):
		swarm_chance = float(cfg.get("swarm_chance", 0.10))
	if wave >= int(cfg.get("brute_from_wave", 4)):
		brute_chance = float(cfg.get("brute_chance", 0.10))
	if wave >= int(cfg.get("shambler_from_wave", 7)):
		shambler_chance = float(cfg.get("shambler_chance", 0.08))
	if wave >= int(cfg.get("charger_from_wave", 5)):
		charger_chance = float(cfg.get("charger_chance", 0.05))
	if wave >= int(cfg.get("shooter_from_wave", 6)):
		shooter_chance = float(cfg.get("shooter_chance", 0.05))
	if wave >= int(cfg.get("bomber_from_wave", 7)):
		bomber_chance = float(cfg.get("bomber_chance", 0.03))
	if wave >= int(cfg.get("splitter_from_wave", 8)):
		splitter_chance = float(cfg.get("splitter_chance", 0.03))
	if r < fast_chance:
		return "fast"
	if r < fast_chance + fly_chance:
		return "fly"
	if r < fast_chance + fly_chance + swarm_chance:
		return "swarm"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance:
		return "brute"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance + shambler_chance:
		return "shambler"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance + shambler_chance + charger_chance:
		return "charger"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance + shambler_chance + charger_chance + shooter_chance:
		return "shooter"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance + shambler_chance + charger_chance + shooter_chance + bomber_chance:
		return "bomber"
	if r < fast_chance + fly_chance + swarm_chance + brute_chance + shambler_chance + charger_chance + shooter_chance + bomber_chance + splitter_chance:
		return "splitter"
	if r > 1.0 - tank_chance:
		return "tank"
	return "grunt"

# 从四条边随机刷：side 0=上 1=下 2=左 3=右
# r1/r2 ∈ [0,1) 由调用方传入（保持可测试、可复现）
static func edge_position(side: int, arena: Dictionary, r1: float, r2: float) -> Vector2:
	var x := float(arena.get("x", 0))
	var y := float(arena.get("y", 0))
	var w := float(arena.get("w", 100))
	var h := float(arena.get("h", 100))
	var off := float(arena.get("edge_offset", 20))
	match side:
		0:
			return Vector2(x + r1 * w, y - off)
		1:
			return Vector2(x + r1 * w, y + h + off)
		2:
			return Vector2(x - off, y + r2 * h)
		_:
			return Vector2(x + w + off, y + r2 * h)

# 某一波某种敌人的完整属性
# elite=true 时把基础属性放大成"精英版"（血更厚、更大、更疼、金币更多）
# endless = {"hp":..,"dmg":..,"gold":..} 是 Run.endless_scales() 算好的无尽段倍率
static func stats_for(type: String, wave: int, defs: Dictionary, elite: bool = false,
		endless: Dictionary = {}) -> Dictionary:
	var d: Dictionary = defs.get(type, {})
	if d.is_empty():
		return {}
	var s := {
		"type": type,
		# 血量 = 基础 + 线性项 + 二次项。二次项（hp_accel）是"后期难度加速"旋钮：
		# 只有线性项时，想让第 20 波难 3 倍就得把斜率 ×3，第 1 波会跟着变难 3 倍
		# （开局 2 把武器直接打不动 = 劝退，实测第 1 波清场率掉到 86%）。
		# 二次项 wave² 让第 1 波只吃到 1 份、第 20 波吃到 400 份，
		# 于是"前几波温柔、后段陡起来"可以同时成立。默认 0 = 完全等价于旧行为。
		"hp": float(d.get("hp_base", 1)) + float(wave) * float(d.get("hp_per_wave", 0))
			+ float(wave) * float(wave) * float(d.get("hp_accel", 0.0)),
		"speed": float(d.get("speed_base", 0)) + float(wave) * float(d.get("speed_per_wave", 0)),
		"damage": float(d.get("dmg_base", 0)) + float(wave) * float(d.get("dmg_per_wave", 0)),
		"radius": float(d.get("radius", 12)),
		# 掉金也随波次成长（与 hp / damage 同构）。
		# 为什么必须加：之前 gold 是恒定值，而敌人血量线性涨、武器价格指数涨，
		# 于是后期"杀得越多越穷"，玩家成长在第 8 波前后彻底停滞 ——
		# scripts/power_probe.gd 实测 ratio（玩家DPS÷清场DPS）从第 8 波的 1.07
		# 一路掉到第 20 波的 0.25。不修这条，后期只能是"必然打不过"。
		"gold": int(d.get("gold", 1)) + int(round(
			float(wave) * float(d.get("gold_per_wave", 0)))),
		"color": d.get("color", "#ffffff"),
		"zh": d.get("zh", type),
		"flight": bool(d.get("flight", false)),
		"behavior": d.get("behavior", ""),
		"elite": false,
	}
	if elite:
		s["hp"] *= 2.2
		s["radius"] *= 1.4
		s["damage"] *= 1.5
		s["gold"] = int(s["gold"]) * 3
		s["color"] = "#ffd24a"
		s["elite"] = true
	s["hp"] *= float(endless.get("hp", 1.0))
	s["damage"] *= float(endless.get("dmg", 1.0))
	s["gold"] = maxi(1, int(round(float(s["gold"]) * float(endless.get("gold", 1.0)))))
	return s

# 终局 Boss：在普通 boss 属性上叠加 final_boss 段的倍率（血量/体型/伤害/金币/速度），
# 带 "final" 标记供 Enemy 换造型与阶段数。phases=false 时 phase_steps 为空 = 不分阶段。
static func final_boss_stats(wave: int, defs: Dictionary, fb: Dictionary,
		endless: Dictionary = {}) -> Dictionary:
	var s := stats_for("boss", wave, defs, false, endless)
	if s.is_empty() or not bool(fb.get("enabled", true)):
		return s
	s["hp"] *= float(fb.get("hp_mult", 1.0))
	s["radius"] *= float(fb.get("radius_mult", 1.0))
	s["damage"] *= float(fb.get("dmg_mult", 1.0))
	s["speed"] *= float(fb.get("speed_mult", 1.0))
	s["gold"] = maxi(1, int(round(float(s["gold"]) * float(fb.get("gold_mult", 1.0)))))
	s["color"] = str(fb.get("color", s.get("color", "#e0507a")))
	s["zh"] = str(fb.get("zh", s.get("zh", "boss")))
	s["en"] = str(fb.get("en", s.get("en", "Boss")))
	s["final"] = true
	s["phase_steps"] = (fb.get("phase_steps", [0.66, 0.33]) if
		bool(fb.get("phases", true)) else [])
	return s

# 一波的总血量（用于评估"这一波能不能打完"）
static func wave_total_hp(wave: int, cfg: Dictionary, defs: Dictionary, length: float) -> float:
	var n := wave_budget(wave, cfg, length)
	var total := 0.0
	# 按类型概率加权
	var fast_chance := 0.0
	var tank_chance := 0.0
	if wave >= int(cfg.get("fast_from_wave", 2)):
		fast_chance = float(cfg.get("fast_chance", 0.28))
	if wave >= int(cfg.get("tank_from_wave", 3)):
		tank_chance = float(cfg.get("tank_chance", 0.12))
	if wave >= int(cfg.get("tank_late_from_wave", 6)):
		tank_chance = float(cfg.get("tank_chance_late", 0.18))
	var grunt_chance := 1.0 - fast_chance - tank_chance
	var gs := stats_for("grunt", wave, defs)
	var fs := stats_for("fast", wave, defs)
	var ts := stats_for("tank", wave, defs)
	total += n * grunt_chance * float(gs.get("hp", 0))
	total += n * fast_chance * float(fs.get("hp", 0))
	total += n * tank_chance * float(ts.get("hp", 0))
	return total
