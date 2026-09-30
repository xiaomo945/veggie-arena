extends RefCounted

# 刷怪逻辑 —— 纯逻辑，不引用任何 Node / 场景
# 输入 wave（第几波）与配置，输出"刷什么、刷多快、刷在哪、属性多少"

# 每秒刷怪数量：base + wave * per，不超过 cap
static func spawn_rate(wave: int, cfg: Dictionary) -> float:
	var base := float(cfg.get("base_rate", 0.5))
	var per := float(cfg.get("per_wave", 0.3))
	var cap := float(cfg.get("cap", 5.0))
	return minf(cap, base + float(wave) * per)

# 一整波预计刷出多少只（用于配平估算）
static func wave_budget(wave: int, cfg: Dictionary, length: float) -> float:
	return spawn_rate(wave, cfg) * length

# 按概率挑敌人类型，r ∈ [0,1)
# 概率带（按 r 从小到大）：fast → fly → grunt(中段) → [tank 在尾部]
static func pick_type(wave: int, r: float, cfg: Dictionary) -> String:
	var fast_chance := 0.0
	var fly_chance := 0.0
	var tank_chance := 0.0
	if wave >= int(cfg.get("fast_from_wave", 2)):
		fast_chance = float(cfg.get("fast_chance", 0.28))
	if wave >= int(cfg.get("fly_from_wave", 4)):
		fly_chance = float(cfg.get("fly_chance", 0.20))
	if wave >= int(cfg.get("tank_from_wave", 3)):
		tank_chance = float(cfg.get("tank_chance", 0.12))
	if wave >= int(cfg.get("tank_late_from_wave", 6)):
		tank_chance = float(cfg.get("tank_chance_late", 0.18))
	if r < fast_chance:
		return "fast"
	if r < fast_chance + fly_chance:
		return "fly"
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
static func stats_for(type: String, wave: int, defs: Dictionary, elite: bool = false) -> Dictionary:
	var d: Dictionary = defs.get(type, {})
	if d.is_empty():
		return {}
	var s := {
		"type": type,
		"hp": float(d.get("hp_base", 1)) + float(wave) * float(d.get("hp_per_wave", 0)),
		"speed": float(d.get("speed_base", 0)) + float(wave) * float(d.get("speed_per_wave", 0)),
		"damage": float(d.get("dmg_base", 0)) + float(wave) * float(d.get("dmg_per_wave", 0)),
		"radius": float(d.get("radius", 12)),
		"gold": int(d.get("gold", 1)),
		"color": d.get("color", "#ffffff"),
		"zh": d.get("zh", type),
		"flight": bool(d.get("flight", false)),
		"elite": false,
	}
	if elite:
		s["hp"] *= 2.2
		s["radius"] *= 1.4
		s["damage"] *= 1.5
		s["gold"] = int(s["gold"]) * 3
		s["color"] = "#ffd24a"
		s["elite"] = true
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
