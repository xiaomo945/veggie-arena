extends CharacterBody2D

# 玩家：跑位手感（core/Movement）+ 武器环绕与自动开火（core/Weapon）
# 本文件不含任何平衡数值 —— 速度、冷却、伤害全读 balance.json / weapons.json
#
# 外观（手绘/贴图）已抽到 entities/Player/PlayerVisual.gd，本脚本只负责物理与战斗。

const Movement := preload("res://core/Movement.gd")
const Weapon := preload("res://core/Weapon.gd")
const Dash := preload("res://core/Dash.gd")

const MOUNT_RADIUS := 42.0

var _dir := Vector2.ZERO
var _vx := 0.0
var _vy := 0.0
var _radius := 16.0
var _speed := 180.0
var _k_forward := 90.0
var _k_reverse := 110.0
var _arena := Rect2()
var _bob := 0.0

var _weapons: Array = []          # [{key, level, stats, timer}]
var _rng := RandomNumberGenerator.new()
var _hp := 100
var _max_hp := 100
var _ifr := 0.0
# 冲刺闪避状态（core/Dash 的字典，纯函数推进）
var _dash: Dictionary = {}
var _dash_cfg: Dictionary = {}
var _face := Vector2(0, -1)      # 面朝方向：没推摇杆时冲刺默认朝这边
var _dash_trail: Array = []      # 冲刺残影 [{pos, t}]
var dash_count := 0            # 本局冲刺次数（诊断/HUD 用）
var hits_taken := 0            # 本局挨打次数（诊断：确认伤害系统真的在打人）
var damage_taken := 0          # 本局累计受到的伤害

var visual: Node2D = null         # 外观层（PlayerVisual），_ready 里注入

func _ready() -> void:
	var pc := Data.player_cfg()
	_radius = float(pc.get("radius", 16))
	_speed = float(pc.get("speed", 180))
	_max_hp = int(pc.get("max_hp", 100))
	_hp = _max_hp
	var f := Movement.feel(Data.feel_cfg())
	_k_forward = float(f["k_forward"])
	_k_reverse = float(f["k_reverse"])
	var a := Data.arena()
	_arena = Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900)))
	_rng.randomize()
	_dash_cfg = Dash.cfg(Data.dash_cfg())
	_dash = Dash.make()
	# 外观层：承接全部绘制，与物理解耦
	visual = preload("res://entities/Player/PlayerVisual.gd").new()
	add_child(visual)
	Events.stick_dir_changed.connect(_on_dir)
	Events.stick_released.connect(_on_release)
	Events.dash_requested.connect(_on_dash_requested)
	Events.character_changed.connect(_on_character_changed)
	Events.weapons_changed.connect(_rebuild_weapons)
	_rebuild_weapons()

func _on_dir(d: Vector2) -> void:
	_dir = d
	if d.length_squared() > 0.0001:
		_face = d.normalized()

func _on_release() -> void:
	_dir = Vector2.ZERO

# 冲刺按钮：有摇杆方向就朝那边冲，没推摇杆就朝面朝方向冲
func _on_dash_requested() -> void:
	var d := _dir
	if d.length_squared() < 0.0001:
		d = _face
	if not Dash.can_start(_dash, _dash_cfg):
		return
	if Dash.start(_dash, d, _dash_cfg):
		dash_count += 1
		Events.dash_started.emit(global_position, d)
		Events.dash_state_changed.emit(0.0, false)
		visual.queue_redraw()

# 给模拟/AI 用：直接下移动指令（等价于手指推摇杆）
func set_move_dir(d: Vector2) -> void:
	_dir = d.normalized() if d.length() > 1.0 else d

# 武器列表变化（买了/合成）时重建缓存，避免每帧读 JSON
# 参数来自 weapons_changed 信号，本函数直接读 GameState，故忽略它（命名避开成员 _weapons）
func _rebuild_weapons(_ignored: Array = []) -> void:
	_weapons = []
	var cfg := Data.combat_cfg()
	# 强化加成在这里一次性算进武器属性，开火时不再重复计算
	var dmg_pct := GameState.stat_value("dmg_pct")
	var rate_pct := GameState.stat_value("rate_pct")
	# 血量上限以 GameState 为准（角色加成 + 强化加成都已并进去，这里不要再加一遍）
	_max_hp = GameState.max_hp
	_speed = float(Data.player_cfg().get("speed", 180)) * (1.0 + GameState.stat_value("speed_pct"))
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
		_weapons.append({
			"key": key,
			"level": lv,
			"stats": st,
			"color": Color(str(def.get("color", "#ffffff"))),
			# ⚠️ timer 初值必须是 cd（表示"冷却已满，可立即开火"）。
			#    填成很大的数会导致 timer-cd 永远为正 → 每帧都开火（实测 876 发/17 秒）
			"timer": float(st.get("cd", 1.0)),
		})
	visual.queue_redraw()

func _physics_process(delta: float) -> void:
	Dash.step(_dash, delta)
	if Dash.active(_dash):
		# 冲刺中：直接以冲刺速度位移，不走加速度（这就是"窜出去"的爆发感来源）
		var dv: Vector2 = (_dash["dir"] as Vector2) * Dash.speed(_dash, _speed, _dash_cfg)
		_vx = dv.x
		_vy = dv.y
		_push_trail()
	else:
		var nv := Movement.step(_vx, _vy, _dir.x, _dir.y,
			_speed, delta, _k_forward, _k_reverse)
		_vx = nv.x
		_vy = nv.y
		global_position = Movement.clamp_to_arena(
			global_position + Vector2(_vx, _vy) * delta, _arena, _radius)
	if _ifr > 0.0:
		_ifr -= delta
	# 冲刺附带的无敌：比冲刺位移本身长一点，穿过怪堆不会刚落地就挨打
	var difr := Dash.ifr_left(_dash, _dash_cfg)
	if difr > 0.0 and difr > _ifr:
		_ifr = difr
	_age_trails(delta)
	_bob += delta * 6.0 * (Movement.speed_of(_vx, _vy) / maxf(_speed, 1.0))
	# 冷却进度给 HUD 画扇形（每帧一个信号，接收方只做一个赋值，开销可忽略）
	Events.dash_state_changed.emit(
		Dash.cooldown_ratio(_dash, _dash_cfg), Dash.can_start(_dash, _dash_cfg))
	visual.queue_redraw()

# ---- 冲刺残影 ----
func _push_trail() -> void:
	if _dash_trail.size() >= 6:
		_dash_trail.remove_at(0)
	_dash_trail.append({"w": global_position, "t": 0.22})

func _age_trails(delta: float) -> void:
	for i in range(_dash_trail.size() - 1, -1, -1):
		var t: Dictionary = _dash_trail[i] as Dictionary
		t["t"] = float(t.get("t", 0.0)) - delta
		if float(t.get("t", 0.0)) <= 0.0:
			_dash_trail.remove_at(i)

# 由 Game 每帧调用：传入敌人列表（含 pos），自动瞄准最近目标开火
func auto_fire(enemies: Array, delta: float) -> void:
	# 锅气档位加成：爆炒档攻速最快、还加伤害（"热锅炒菜更猛"）
	var fire_mult := GameState.wok_fire_mult()
	var dmg_mult := GameState.wok_dmg_mult()
	for i in _weapons.size():
		var w: Dictionary = _weapons[i]
		var st: Dictionary = w["stats"]
		w["timer"] = float(w["timer"]) + delta
		var cd := float(st.get("cd", 1.0)) / maxf(0.05, fire_mult)
		if not Weapon.can_fire(float(w["timer"]), cd):
			continue
		var ti := Weapon.nearest_target(global_position, enemies, float(st.get("range", 300)))
		if ti < 0:
			continue
		var e: Dictionary = enemies[ti]
		# 自动瞄准打提前量：按子弹飞行时间，预判敌人会移到哪
		var epos: Vector2 = e.get("pos", global_position)
		var vel: Vector2 = e.get("vel", Vector2.ZERO)
		var bs := float(st.get("bullet_speed", 600))
		var t := global_position.distance_to(epos) / maxf(bs, 1.0)
		var aim := epos + vel * t
		var base_dir: Vector2 = (aim - global_position).normalized()
		var dirs := Weapon.pellet_directions(base_dir,
			int(st.get("pellets", 1)), float(st.get("spread", 0.0)), _rng)
		var mpos := Weapon.mount_position(global_position, i, _weapons.size(), MOUNT_RADIUS)
		# 锅气伤害加成：复制一份 stats 改 dmg，不污染缓存（st 被多把武器共享引用）
		var est := st.duplicate()
		est["dmg"] = float(st.get("dmg", 0)) * dmg_mult
		for d in dirs:
			Events.weapon_fired.emit(mpos, d, est, w["color"] as Color)
		w["timer"] = Weapon.next_cooldown(float(w["timer"]), cd)

# 血量只存在 GameState 一处，Player 只负责无敌帧与受击表现
func take_hit(amount: float) -> void:
	if _ifr > 0.0:
		return
	_ifr = float(Data.player_cfg().get("ifr_seconds", 0.38))
	hits_taken += 1
	damage_taken += int(amount)
	GameState.take_damage(int(amount))

func _on_character_changed(_key: String) -> void:
	# 属性加成变了（生命上限 / 移速 / 伤害 / 攻速都读 stat_value），重建缓存即可
	_rebuild_weapons()
