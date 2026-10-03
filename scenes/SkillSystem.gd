extends RefCounted

# 主动技能系统（锅气之外的手动释放技能：冰镇 / 毒雾 …）。
#
# 为什么是独立组件、且挂在 Game 下：EnemySystem 已经顶到 300 行红线，再加技能
# 必然撞线；而"手动技能"和"颠勺"一样是差异化玩法，拆出来单独养最干净
# （参照 scenes/WokToss.gd 的拆法）。由 Game 持有并驱动，和 WaveDirector 同一级。
#
# 冷却与施放都在这；视觉交给 ui/Fx/FxSkill.gd（订阅 Events.skill_cast）。
# 效果全部复用 Enemy.apply_fx（slow/freeze/poison/burn），和颠勺走同一套状态系统，
# 所以持续伤害也会被 EnemySystem 走 damage_enemy 统一结算（毒死也算击杀/掉钱/涨锅气）。
#
# ⚠️ 只用公开 API：e.apply_fx / e.alive / e.global_position / e.max_hp / e.radius /
#    world.player / world.enemies。不碰任何 _ 私有字段（架构守卫 R3）。

const Shake := preload("res://entities/effects/Shake.gd")

var world = null                       # BattleWorld（注入）
var _skills: Dictionary = {}           # id -> 配置字典
var _cd: Dictionary = {}               # id -> 剩余冷却（秒）

# 由 Game 在 _ready 里调用：注入世界 + 读技能表
func setup(arr: Array, wld) -> void:
	world = wld
	_skills.clear()
	_cd.clear()
	for s in arr:
		var d: Dictionary = s
		var id: String = str(d.get("id", ""))
		if id == "":
			continue
		_skills[id] = d
		_cd[id] = 0.0

# 开新一局时清冷却（Game.start_run 调用），避免上一局残留的 CD 带到开局
func reset_cooldowns() -> void:
	for id in _skills.keys():
		_cd[id] = 0.0
		Events.skill_cooldown_changed.emit(id, 1.0, true)

# 手动释放：在冷却中返回 false（按钮按下但没放出去）；成功则进 CD 并发特效信号
func cast(id: String) -> bool:
	if not _skills.has(id):
		return false
	if float(_cd.get(id, 0.0)) > 0.0:
		return false
	var cfg: Dictionary = _skills[id]
	var pp: Vector2 = world.player.global_position
	var kind: String = str(cfg.get("effect", ""))
	if kind == "slow":
		_apply_slow(cfg, pp)
	elif kind == "poison":
		_apply_poison(cfg, pp)
	_cd[id] = float(cfg.get("cooldown", 6.0))
	Shake.kick(5.0, 0.18)
	Events.skill_cast.emit(id, pp, float(cfg.get("radius", 150.0)))
	_emit(id)
	return true

# 每物理帧推进冷却，并把（ratio, ready）广播给 HUD 画冷却扇形
func tick(delta: float) -> void:
	for id in _skills.keys():
		var c: float = float(_cd.get(id, 0.0))
		if c > 0.0:
			c = maxf(0.0, c - delta)
			_cd[id] = c
		_emit(id)

func _emit(id: String) -> void:
	var c: float = float(_cd.get(id, 0.0))
	var cdmax: float = float(_skills[id].get("cooldown", 6.0))
	var ratio: float = 1.0 - clampf(c / maxf(0.001, cdmax), 0.0, 1.0)
	Events.skill_cooldown_changed.emit(id, ratio, c <= 0.0)

# ---- 效果：冰镇 = 范围内减速 + 短暂冻结（站桩）----
func _apply_slow(cfg: Dictionary, pp: Vector2) -> void:
	var r: float = float(cfg.get("radius", 150.0))
	var sv: float = float(cfg.get("slow_v", 0.5))
	var sd: float = float(cfg.get("slow_dur", 3.0))
	var fd: float = float(cfg.get("freeze_dur", 0.0))
	for e in world.enemies:
		if not e.alive:
			continue
		if e.global_position.distance_to(pp) <= r + e.radius:
			e.apply_fx("slow", sv, sd)
			if fd > 0.0:
				e.apply_fx("freeze", 1.0, fd)

# ---- 效果：毒雾 = 范围内中毒（按最大生命%结算）+ 灼烧（固定 DPS）----
func _apply_poison(cfg: Dictionary, pp: Vector2) -> void:
	var r: float = float(cfg.get("radius", 150.0))
	var pct: float = float(cfg.get("poison_dps_pct", 0.05))
	var bd: float = float(cfg.get("burn_dps", 0.0))
	var dur: float = float(cfg.get("dur", 3.0))
	for e in world.enemies:
		if not e.alive:
			continue
		if e.global_position.distance_to(pp) <= r + e.radius:
			e.apply_fx("poison", e.max_hp * pct, dur)
			if bd > 0.0:
				e.apply_fx("burn", bd, dur)
