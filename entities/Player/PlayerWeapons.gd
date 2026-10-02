extends RefCounted

# 玩家的武器组：缓存属性 / 冷却 / 自动瞄准开火。
#
# 为什么从 Player.gd 拆出来：Player 加了十几条武器类道具（暴击/穿透/溅射/弹速…）
# 之后顶到架构守卫的 300 行红线。武器是"一组有自己状态和冷却的东西"，
# 天然就该是一个独立部件 —— Player 只管移动和挨打。
#
# ⚠️ 不用 class_name：check.sh 会清 .godot/editor，headless 下全局类表不重建。

const Weapon := preload("res://core/Weapon.gd")

# 武器绕着角色转的站位半径（Brotato 式）
const MOUNT_RADIUS := 42.0

var host: Node2D = null              # 玩家节点：开火位置 / 面朝方向都从它取
var _weapons: Array = []             # [{key, level, stats, color, timer}]
var _rng := RandomNumberGenerator.new()
var _crit_chance := 0.0
var _crit_mult := 1.0

func _init(owner: Node2D) -> void:
	host = owner
	_rng.randomize()

# 属性缓存：所有道具加成（伤害/攻速/射程/弹速/穿透/溅射/弹丸数/暴击）
# 都在这里一次性叠进去，开火时不再重复计算 stat_value。
func rebuild() -> void:
	_weapons = []
	var cfg := Data.combat_cfg()
	var dmg_pct := GameState.stat_value("dmg_pct")
	var rate_pct := GameState.stat_value("rate_pct")
	var range_pct := GameState.stat_value("range_pct")
	var bspd_pct := GameState.stat_value("bullet_speed_pct")
	var pierce_add := int(GameState.stat_value("pierce_add"))
	var aoe_add := GameState.stat_value("aoe_add")
	var pellets_add := int(GameState.stat_value("pellets_add"))
	var ricochet_add := int(GameState.stat_value("ricochet"))
	_crit_chance = clampf(GameState.stat_value("crit_chance"), 0.0, 1.0)
	_crit_mult = 1.0 + GameState.stat_value("crit_mult")
	for w in GameState.weapons:
		if not (w is Dictionary):
			continue
		var key := str(w.get("key", ""))
		# 字段必须是 "lv"（与 core/Inventory 一致），写成 "level" 合成会静默失效
		var lv := int(w.get("lv", 1))
		var def := Data.weapon(key)
		if def.is_empty():
			continue
		var st := Weapon.merged_stats(def, lv, cfg)
		st["dmg"] = float(st.get("dmg", 0)) * (1.0 + dmg_pct)
		st["cd"] = float(st.get("cd", 1.0)) / maxf(0.05, 1.0 + rate_pct)
		st["range"] = float(st.get("range", 300)) * (1.0 + range_pct)
		st["bullet_speed"] = float(st.get("bullet_speed", 600)) * (1.0 + bspd_pct)
		st["pierce"] = int(st.get("pierce", 0)) + pierce_add
		st["aoe"] = float(st.get("aoe", 0)) + aoe_add
		# 弹丸数夹到 Weapon.MAX_PELLETS：不然"多一发"叠几层就能把手机卡死
		st["pellets"] = clampi(int(st.get("pellets", 1)) + pellets_add, 1, Weapon.MAX_PELLETS)
		st["bounce"] = int(st.get("bounce", 0)) + ricochet_add
		_weapons.append({
			"key": key,
			"level": lv,
			"stats": st,
			"color": Color(str(def.get("color", "#ffffff"))),
			# ⚠️ timer 初值必须是 cd（表示"冷却已满，可立即开火"）。
			#    填成很大的数会导致 timer-cd 永远为正 → 每帧都开火（实测 876 发/17 秒）
			"timer": float(st.get("cd", 1.0)),
		})

# 每帧推进冷却并自动开火。enemies 是 EnemySystem 收集好的 [{pos, vel, radius...}]
func tick(enemies: Array, delta: float) -> void:
	# 锅气档位加成：爆炒档攻速最快、还加伤害（"热锅炒菜更猛"）
	var fire_mult := GameState.wok_fire_mult() * GameState.frenzy_mult()
	var dmg_mult := GameState.wok_dmg_mult() * _desperation()
	var origin: Vector2 = host.global_position
	for i in _weapons.size():
		var w: Dictionary = _weapons[i]
		var st: Dictionary = w["stats"]
		w["timer"] = float(w["timer"]) + delta
		var cd := float(st.get("cd", 1.0)) / maxf(0.05, fire_mult)
		if not Weapon.can_fire(float(w["timer"]), cd):
			continue
		var ti := Weapon.nearest_target(origin, enemies, float(st.get("range", 300)))
		if ti < 0:
			continue
		var e: Dictionary = enemies[ti]
		# 自动瞄准打提前量：按子弹飞行时间，预判敌人会移到哪
		var epos: Vector2 = e.get("pos", origin)
		var vel: Vector2 = e.get("vel", Vector2.ZERO)
		var mpos := Weapon.mount_position(origin, i, _weapons.size(), MOUNT_RADIUS)
		# 复制一份 stats 再改 dmg，不污染缓存（st 被多把武器共享引用）
		var est := st.duplicate()
		est["dmg"] = float(st.get("dmg", 0)) * dmg_mult
		# 暴击按"每一发"独立 roll（近战每跳也可能暴击，手感更刺激）
		var crit := _crit_chance > 0.0 and _rng.randf() < _crit_chance
		if crit:
			est["dmg"] = float(est.get("dmg", 0)) * _crit_mult
		est["crit"] = crit
		# 近战：瞬时扇形挥砍，命中弧内全部敌人，无子弹。
		# 伤害走 EnemySystem.damage_enemy 漏斗（击杀/掉金/锅气/破甲都在那）。
		if Weapon.is_melee(st):
			var base_dir: Vector2 = (epos - origin).normalized()
			var kb := float(st.get("knockback", 0.0))
			Events.melee_swung.emit(mpos, base_dir, float(st.get("range", 150)),
				Weapon.melee_half_arc(st), float(est["dmg"]), crit, kb, w["color"] as Color,
				str(w["key"]), int(w["level"]))
			w["timer"] = Weapon.next_cooldown(float(w["timer"]), cd)
			continue
		var bs := float(st.get("bullet_speed", 600))
		var t := origin.distance_to(epos) / maxf(bs, 1.0)
		var aim := epos + vel * t
		var base_dir: Vector2 = (aim - origin).normalized()
		var dirs := Weapon.pellet_directions(base_dir,
			int(st.get("pellets", 1)), float(st.get("spread", 0.0)), _rng)
		for d in dirs:
			Events.weapon_fired.emit(mpos, d, est, w["color"] as Color)
		w["timer"] = Weapon.next_cooldown(float(w["timer"]), cd)

# 给外观层 / HUD 的只读快照
func caches() -> Array:
	return _weapons

# 背水一战（low_hp_dmg）：血越少打得越狠，满血时没有加成。
# 这是"高风险高回报"构筑的核心 —— 故意残血换输出。
func _desperation() -> float:
	var bonus := GameState.stat_value("low_hp_dmg")
	if bonus <= 0.0 or GameState.max_hp <= 0:
		return 1.0
	var ratio: float = clampf(float(GameState.hp) / float(GameState.max_hp), 0.0, 1.0)
	return 1.0 + bonus * (1.0 - ratio)
