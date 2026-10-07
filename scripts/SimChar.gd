extends RefCounted

# =====================================================================
# 模拟里的"角色侧"建模：属性合并 / 技能折算 / 等效血量
#
# 为什么单独一个文件：scripts/SimCore.gd（商店与经济推演）加上这一坨会超 300 行，
# 撞上架构守卫 R1。而且这两件事确实该分开 —— 商店是"玩家怎么买"，这里是
# "买了之后这角色有多强"，前者所有角色共用，后者每个角色一套。
#
# 这三条是"满 build 强度对比"能不能成立的关键：少了任何一条，13 个角色都会
# 跑出同一个数，比较就没有意义了。
# =====================================================================

const Synergy := preload("res://core/Synergy.gd")
const SkillDef := preload("res://core/SkillDef.gd")
const Character := preload("res://core/Character.gd")

const FRENZY_RATE := 0.5     # 疾风/连击狂潮的攻速加成量级（保守取值）
const LIFESTEAL_CHANCE := 0.08   # 与 scenes/EnemySystem.gd 保持一致
const BASE_HP := 100.0           # data/balance.json 的 player.max_hp
const CTRL_SLOW := 0.35          # 减速折算成生存加成（刻意保守）
const CTRL_FREEZE := 0.5         # 冻结折算成生存加成


# 生效属性 = 道具累计 + 角色自带 + 羁绊档位。三者并列，谁都不能漏。
func eff_st(weapons: Array, st: Dictionary, char_entry: Dictionary,
		defs: Dictionary) -> Dictionary:
	var es: Dictionary = st.duplicate()
	_merge_add(es, Character.stats_of(char_entry))
	if not char_entry.is_empty():
		_merge_add(es, Synergy.bonuses(weapons, char_entry, defs))
	return es


# 技能的等效输出 / 控制价值。只认真实字段，不替技能吹牛：
#   damage → 范围命中数 × 伤害 / 冷却（有 burn_dps 再叠加持续段）
#   poison → 敌人最大血量占比 × 持续 / 冷却（另加 burn_dps）
#   frenzy → 攻速窗口折算成平均倍率（乘在武器输出上）
#   slow/freeze/heat → 不算输出，折算成生存系数（ctrl）
func skill_parts(weapons: Array, es: Dictionary, char_key: String,
		char_entry: Dictionary, defs: Dictionary, skills: Array,
		targets: int, avg_hp: float) -> Dictionary:
	var out := {"dps": 0.0, "rate": 0.0, "ctrl": 1.0}
	if char_entry.is_empty() or skills.is_empty():
		return out
	var base := SkillDef.base_of(SkillDef.skill_id_of(char_entry), skills)
	if base.is_empty():
		return out
	var stat_of := func(k: String) -> float: return float(es.get(k, 0.0))
	var c := SkillDef.resolve(base, char_key, weapons, defs, stat_of)
	var cd := maxf(1.0, float(c.get("cooldown", 6.0)))
	var n := float(targets)
	match str(c.get("effect", "")):
		"damage":
			var per := float(c.get("dmg", 0.0))
			per += float(c.get("burn_dps", 0.0)) * float(c.get("dur", 0.0))
			out["dps"] = per * n / cd
		"poison":
			var dur := float(c.get("dur", 0.0))
			var per := float(c.get("poison_dps_pct", 0.0)) * avg_hp
			per += float(c.get("burn_dps", 0.0))
			out["dps"] = per * dur * n / cd
		"frenzy":
			out["rate"] = FRENZY_RATE * float(c.get("dur", 0.0)) / cd
		_:
			pass
	# 减速 / 冻结 = 敌人靠近变慢 = 挨打变少。折算保守：宁可低估控制技，
	# 也不要让"数值技永远赢控制技"这种假结论影响配平。
	var slow_v := float(c.get("slow_v", 0.0))
	var slow_d := float(c.get("slow_dur", 0.0))
	var frz := float(c.get("freeze_dur", 0.0))
	if slow_v > 0.0 or frz > 0.0:
		out["ctrl"] = 1.0 + CTRL_SLOW * slow_v * slow_d / cd + CTRL_FREEZE * frz / cd
	return out


# 等效血量：把"血条 + 护甲 + 闪避 + 回复 + 吸血"压成一个可比的数。
# 护甲是【减法】减伤（Combat.damage_after_armor），所以等效血量放大倍数是
# avg_hit / (avg_hit - armor) —— 怪越弱护甲越值钱，这正是真实手感。
func ehp(es: Dictionary, w: int, length: float, kills: float,
		enemies: Dictionary) -> float:
	var hp := BASE_HP + float(es.get("max_hp", 0.0))
	var armor := float(es.get("armor", 0.0))
	var dodge := clampf(float(es.get("dodge", 0.0)), 0.0, 0.6)
	var avg_hit := 0.0
	for k in enemies:
		var e: Dictionary = enemies[k]
		avg_hit = maxf(avg_hit, float(e.get("dmg_base", 4.0))
			+ float(e.get("dmg_per_wave", 0.0)) * float(w))
	var mult := avg_hit / maxf(1.0, avg_hit - armor)
	var regen := float(es.get("regen", 0.0)) * length
	var ls := float(es.get("lifesteal", 0.0)) * LIFESTEAL_CHANCE * kills
	return (hp + regen + ls) * mult / (1.0 - dodge)


func avg_enemy_hp(enemies: Dictionary) -> float:
	var t := 0.0
	var n := 0
	for k in enemies:
		var e: Dictionary = enemies[k]
		t += float(e.get("hp_base", 10.0))
		n += 1
	return t / maxf(1.0, float(n))


static func _merge_add(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		dst[str(k)] = float(dst.get(str(k), 0.0)) + float(src[k])
