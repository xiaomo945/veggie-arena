extends CharacterBody2D

# 玩家：跑位手感（core/Movement）+ 武器环绕与自动开火（core/Weapon）
# 本文件不含任何平衡数值 —— 速度、冷却、伤害全读 balance.json / weapons.json

const Movement := preload("res://core/Movement.gd")
const Weapon := preload("res://core/Weapon.gd")

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

const SKIN := Color(0.97, 0.96, 0.92)
const SHADE := Color(0.86, 0.85, 0.80)
const LEAF := Color(0.35, 0.68, 0.30)
const LEAF2 := Color(0.27, 0.56, 0.24)
const EYE := Color(0.16, 0.14, 0.12)

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
	Events.stick_dir_changed.connect(_on_dir)
	Events.stick_released.connect(_on_release)
	Events.weapons_changed.connect(_rebuild_weapons)
	_rebuild_weapons()

func _on_dir(d: Vector2) -> void:
	_dir = d

func _on_release() -> void:
	_dir = Vector2.ZERO

# 武器列表变化（买了/合成）时重建缓存，避免每帧读 JSON
func _rebuild_weapons() -> void:
	_weapons = []
	var cfg := Data.combat_cfg()
	# 强化加成在这里一次性算进武器属性，开火时不再重复计算
	var dmg_pct := GameState.stat_value("dmg_pct")
	var rate_pct := GameState.stat_value("rate_pct")
	_max_hp = int(Data.player_cfg().get("max_hp", 100)) + int(GameState.stat_value("max_hp"))
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
			"timer": 999.0,
		})
	queue_redraw()

func _physics_process(delta: float) -> void:
	var nv := Movement.step(_vx, _vy, _dir.x, _dir.y,
		_speed, delta, _k_forward, _k_reverse)
	_vx = nv.x
	_vy = nv.y
	global_position = Movement.clamp_to_arena(
		global_position + Vector2(_vx, _vy) * delta, _arena, _radius)
	if _ifr > 0.0:
		_ifr -= delta
	_bob += delta * 6.0 * (Movement.speed_of(_vx, _vy) / maxf(_speed, 1.0))
	queue_redraw()

# 由 Game 每帧调用：传入敌人列表（含 pos），自动瞄准最近目标开火
func auto_fire(enemies: Array, delta: float) -> void:
	for i in _weapons.size():
		var w: Dictionary = _weapons[i]
		var st: Dictionary = w["stats"]
		w["timer"] = float(w["timer"]) + delta
		var cd := float(st.get("cd", 1.0))
		if not Weapon.can_fire(float(w["timer"]), cd):
			continue
		var ti := Weapon.nearest_target(global_position, enemies, float(st.get("range", 300)))
		if ti < 0:
			continue
		var e: Dictionary = enemies[ti]
		var base_dir: Vector2 = (e.get("pos", global_position) - global_position).normalized()
		var dirs := Weapon.pellet_directions(base_dir,
			int(st.get("pellets", 1)), float(st.get("spread", 0.0)), _rng)
		var mpos := Weapon.mount_position(global_position, i, _weapons.size(), MOUNT_RADIUS)
		for d in dirs:
			Events.weapon_fired.emit(mpos, d, st, w["color"] as Color)
		w["timer"] = Weapon.next_cooldown(float(w["timer"]), cd)

# 血量只存在 GameState 一处，Player 只负责无敌帧与受击表现
func take_hit(amount: float) -> void:
	if _ifr > 0.0:
		return
	_ifr = float(Data.player_cfg().get("ifr_seconds", 0.38))
	GameState.take_damage(int(amount))

func _draw() -> void:
	var squash := 1.0 + 0.05 * sin(_bob)
	var stretch := 1.0 / squash
	# 受伤闪烁：无敌帧内半透明，让玩家知道"刚才挨打了"
	var alpha := 1.0 if _ifr <= 0.0 else 0.55
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, -12), Vector2(-3, -30), Vector2(0, -11)]), Color(LEAF.r, LEAF.g, LEAF.b, alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(9, -12), Vector2(3, -30), Vector2(0, -11)]), Color(LEAF2.r, LEAF2.g, LEAF2.b, alpha))
	var body := PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(10 * stretch, 6 * squash),
		Vector2(0, 18 * squash),
		Vector2(-10 * stretch, 6 * squash),
	])
	draw_colored_polygon(body, Color(SKIN.r, SKIN.g, SKIN.b, alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-13 * stretch, -10 * squash),
		Vector2(13 * stretch, -10 * squash),
		Vector2(13 * stretch, -4 * squash),
		Vector2(-13 * stretch, -4 * squash)]), Color(SHADE.r, SHADE.g, SHADE.b, alpha))
	var look := _dir
	if look == Vector2.ZERO:
		look = Vector2(0, -1)
	else:
		look = look.limit_length(1.0)
	draw_circle(Vector2(-4.6 + look.x * 2.2, -2 + look.y * 1.6), 2.3,
		Color(EYE.r, EYE.g, EYE.b, alpha))
	draw_circle(Vector2(4.6 + look.x * 2.2, -2 + look.y * 1.6), 2.3,
		Color(EYE.r, EYE.g, EYE.b, alpha))

# 武器图标画在角色身上（跟着一起移动）
func draw_mounts() -> void:
	pass
