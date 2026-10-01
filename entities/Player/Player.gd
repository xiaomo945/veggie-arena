extends CharacterBody2D

# 玩家：跑位手感（core/Movement）+ 武器环绕与自动开火（core/Weapon）
# 本文件不含任何平衡数值 —— 速度、冷却、伤害全读 balance.json / weapons.json
#
# 外观（手绘/贴图）已抽到 entities/Player/PlayerVisual.gd，本脚本只负责物理与战斗。

const Movement := preload("res://core/Movement.gd")
const Weapon := preload("res://core/Weapon.gd")
const Dash := preload("res://core/Dash.gd")
const Shake := preload("res://entities/effects/Shake.gd")
const PlayerWeapons := preload("res://entities/Player/PlayerWeapons.gd")

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

var arms: PlayerWeapons = null    # 武器组（缓存/冷却/开火，见 PlayerWeapons.gd）
var _rng := RandomNumberGenerator.new()
var _hp := 100
var _max_hp := 100
var _ifr := 0.0
# 冲刺闪避状态（core/Dash 的字典，纯函数推进）
var _dash: Dictionary = {}
var _dash_cfg: Dictionary = {}
# 由道具驱动的派生属性（每次重建武器时刷新一次，别在每帧里重复读升级表）
var _regen := 0.0          # 每秒回血（被动道具 regen）
var _regen_acc := 0.0
var _dodge := 0.0          # 闪避率（被动道具 dodge）
var _ifr_pct := 0.0        # 无敌帧时长加成
var _boost_left := 0.0     # 受击后的短暂加速剩余秒数（被动道具 hit_boost）
var _face := Vector2(0, -1)      # 面朝方向：没推摇杆时冲刺默认朝这边
var _dash_trail: Array = []      # 冲刺残影 [{pos, t}]
var dash_count := 0            # 本局冲刺次数（诊断/HUD 用）
var hits_taken := 0            # 本局挨打次数（诊断：确认伤害系统真的在打人）
var damage_taken := 0          # 本局累计受到的伤害

var visual: Node2D = null         # 外观层（PlayerVisual），_ready 里注入

var _hurt_rect: ColorRect = null   # 受击红屏蒙版（屏幕空间，不随世界抖动）
var _hurt_tween: Tween = null

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
	# 冲刺类道具：冷却按"减少比例"叠（最多减 80%，否则无限冲刺会破坏节奏）
	_dash_cfg["cooldown"] = float(_dash_cfg.get("cooldown", 1.8)) \
		* (1.0 - clampf(GameState.stat_value("dash_cd_pct"), 0.0, 0.8))
	_dash_cfg["distance"] = float(_dash_cfg.get("distance", 96)) \
		* (1.0 + GameState.stat_value("dash_dist_pct"))
	_dash = Dash.make()
	# 外观层：承接全部绘制，与物理解耦
	visual = preload("res://entities/Player/PlayerVisual.gd").new()
	add_child(visual)
	# 受击红屏：独立的屏幕空间蒙版（CanvasLayer），不随世界抖动
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_hurt_rect = ColorRect.new()
	_hurt_rect.color = Color(1, 0, 0, 0)
	# ⚠️ 必须忽略鼠标：ColorRect 默认 STOP，这条全屏透明红屏在 layer=128（比标题/商店都高），
	#    会吞掉整个屏幕的 GUI 点击 —— 之前"标题/结算页怎么点都关不掉"就是它挡的
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_hurt_rect)
	Events.stick_dir_changed.connect(_on_dir)
	Events.stick_released.connect(_on_release)
	Events.dash_requested.connect(_on_dash_requested)
	Events.character_changed.connect(_on_character_changed)
	Events.weapons_changed.connect(_rebuild_weapons)
	arms = PlayerWeapons.new(self)
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
# 属性/道具变了就重建：武器缓存交给武器组，这里只刷玩家自己的派生属性
func _rebuild_weapons(_ignored: Array = []) -> void:
	_regen = GameState.stat_value("regen")
	_dodge = clampf(GameState.stat_value("dodge"), 0.0, 0.6)
	_ifr_pct = GameState.stat_value("ifr_pct")
	# 血量上限以 GameState 为准（角色加成 + 强化加成都已并进去，这里不要再加一遍）
	_max_hp = GameState.max_hp
	_refresh_speed()
	arms.rebuild()
	visual.queue_redraw()

func _physics_process(delta: float) -> void:
	_refresh_speed()
	if _boost_left > 0.0:
		_boost_left = maxf(0.0, _boost_left - delta)
	_tick_regen(delta)
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
# 由 Game 每帧调用：武器冷却 + 自动瞄准开火全部在武器组里
func auto_fire(enemies: Array, delta: float) -> void:
	arms.tick(enemies, delta)

func take_hit(amount: float) -> void:
	if _ifr > 0.0:
		return
	# 闪避：整次伤害免掉（不是减伤）。命中判定在这里做，玩家能直观感到"这下没掉血"
	if _dodge > 0.0 and _rng.randf() < _dodge:
		Events.player_dodged.emit(global_position)
		return
	_ifr = float(Data.player_cfg().get("ifr_seconds", 0.38)) * (1.0 + _ifr_pct)
	# 挨打先扣护盾（颠勺"护盾"道具给的），扣完才掉血 —— 让大招也能当保命手段
	var remain := int(amount)
	if GameState.shield > 0:
		var absorbed: int = mini(GameState.shield, remain)
		GameState.shield -= absorbed
		remain -= absorbed
		Events.shield_changed.emit(GameState.shield)
	# 受击加速（hit_boost）：被摸一下就窜出去一截，给"被打后拉开距离"的操作空间
	if remain > 0:
		_boost_left = float(Data.player_cfg().get("hit_boost_sec", 1.2))
	hits_taken += 1
	damage_taken += remain
	GameState.take_damage(remain)
	# 受击红屏闪烁
	if _hurt_rect != null:
		_hurt_rect.color = Color(1, 0, 0, 0.35)
		if _hurt_tween != null and _hurt_tween.is_valid():
			_hurt_tween.kill()
		_hurt_tween = create_tween()
		_hurt_tween.tween_property(_hurt_rect, "color:a", 0.0, 0.35)
	# 受击轻微震屏
	Shake.kick(7.0, 0.18)

func _on_character_changed(_key: String) -> void:
	# 属性加成变了（生命上限 / 移速 / 伤害 / 攻速都读 stat_value），重建缓存即可
	_rebuild_weapons()

# 手动推进一帧（模拟 / 调试用；正常游戏由引擎调 _physics_process）
func step(delta: float) -> void:
	_physics_process(delta)

# 每秒回血：不足 1 点的零头要攒着（_regen_acc），否则 1.5/s 会被砍成 1/s
func _tick_regen(delta: float) -> void:
	if _regen <= 0.0:
		return
	_regen_acc += _regen * delta
	if _regen_acc >= 1.0:
		var n := int(_regen_acc)
		_regen_acc -= float(n)
		GameState.heal(n)

# 速度 = 基准 × 道具加成(Speed%) × 玩家自调手感倍率(Settings.move_scale)。
# 每帧重算而不是只在 rebuild 时算一次：设置里拧滑块要立刻生效，
# 而 stat_value 只是遍历十几个升级项，每帧算一次的开销可以忽略。
func _refresh_speed() -> void:
	var mult := 1.0
	# 颠勺"狂暴"期间攻速移速一起涨（GameState 统一倒计时，武器端读同一个值）
	if GameState.frenzy_left > 0.0:
		mult *= GameState.frenzy_mult()
	# 刚挨过打：短暂加速，好让玩家有机会拉开距离而不是被黏着磨死
	if _boost_left > 0.0:
		mult *= 1.0 + GameState.stat_value("hit_boost")
	_speed = float(Data.player_cfg().get("speed", 180)) \
		* (1.0 + GameState.stat_value("speed_pct")) \
		* (float(Settings.move_scale) / 100.0) * mult

# ---- 给外观层（PlayerVisual）的只读接口 ----
# PlayerVisual 是 Player 自己的绘制层，每帧要读这些状态。走访问器而不是让它直接
# 摸 player._xxx：谁能改仍然收口在 Player 内部，外部只有读权限。
func bob_phase() -> float:
	return _bob

func ifr_left() -> float:
	return _ifr

func dash_state() -> Dictionary:
	return _dash

func radius() -> float:
	return _radius

func move_dir() -> Vector2:
	return _dir

func dash_trail() -> Array:
	return _dash_trail

func weapon_caches() -> Array:
	return arms.caches()
