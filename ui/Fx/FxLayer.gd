extends CanvasLayer

# 打击感特效层（Juice）：只订阅 Events 做表现，不认识 Player/Game/Enemy，也不写回玩法状态。
# 删掉这个文件游戏照样能玩（验收标准）。四件事：飘字 / 爆环 / 全屏晕染 / 过关彩纸

# 飘字/爆环/迸溅的并发上限不再写死：掉帧时由画质档位自动收紧
#（见 core/PerfGuard.gd）。它们是"看得见的开销"，降档先砍这些，最后才动同屏敌人。
const MAX_CRACKS := 24

const FLOAT_LIFE := 0.62
const FLOAT_RISE := 46.0

var _rings: Array = []
var _arcs: Array = []
var _cracks: Array = []
var _pops: Array = []
var _floats: Array = []
var _pool: Array = []
var _ring_view: Node2D
var _arc_view: Node2D
var _crack_view: Node2D
var _pop_view: Node2D
var _hurt: Control
var _gold: Control
var _hurt_t := 0.0
var _gold_t := 0.0
var _last_hp := -1
var _celeb_layer: CanvasLayer  # 过关庆祝画在独立高层 CanvasLayer（商店 30 层之上），否则彩纸被面板挡住
var _celeb_view: Node2D
var _celeb: Array = []
var _blast = null          # 颠勺全屏爆炸（屏幕空间，恒定居中于玩家）

const MELEE_LIFE := 0.16
const Shake := preload("res://entities/effects/Shake.gd")
const HitStop := preload("res://entities/effects/HitStop.gd")
const BossIntroScene := preload("res://ui/Fx/FxBossIntro.gd")
const SpawnHaloScene := preload("res://ui/Fx/FxSpawnHalo.gd")

func _ready() -> void:
	layer = 15          # 在世界之上、HUD(20) 之下；特效层跟着镜头走，否则飘字/爆环钉死在屏幕
	follow_viewport_enabled = true
	name = "FxLayer"

	# CanvasLayer 自己不能 _draw，爆环用独立 Node2D 画
	_ring_view = Node2D.new()
	_ring_view.set_script(preload("res://ui/Fx/FxRings.gd"))
	_ring_view.set("rings", _rings)   # Array 是引用类型：直接给，双方同份，无需同步
	_ring_view.name = "Rings"
	add_child(_ring_view)

	# 近战挥砍扇形：同样的套路，独立数组 + 独立 Node2D
	_arc_view = Node2D.new()
	_arc_view.set_script(preload("res://ui/Fx/MeleeArc.gd"))
	_arc_view.set("arcs", _arcs)
	_arc_view.name = "MeleeArcs"
	add_child(_arc_view)

	# 地面裂痕（菜刀等近战砍地）：独立数组 + 独立 Node2D
	_crack_view = Node2D.new()
	_crack_view.set_script(preload("res://ui/Fx/FxCracks.gd"))
	_crack_view.set("cracks", _cracks)
	_crack_view.name = "Cracks"
	add_child(_crack_view)

	# 命中迸溅 + 枪口火光：独立数组 + 独立 Node2D
	_pop_view = Node2D.new()
	_pop_view.set_script(preload("res://ui/Fx/FxPops.gd"))
	_pop_view.set("pops", _pops)
	_pop_view.name = "Pops"
	add_child(_pop_view)

	# 过关庆祝层（画在商店之上）
	_celeb_layer = CanvasLayer.new()
	_celeb_layer.layer = 40
	_celeb_layer.name = "Celebrate"
	add_child(_celeb_layer)
	_celeb_view = Node2D.new()
	_celeb_view.set_script(preload("res://ui/Fx/FxPops.gd"))
	_celeb_view.set("pops", _celeb)
	_celeb_view.name = "Celeb"
	_celeb_layer.add_child(_celeb_view)

	# 颠勺全屏爆炸（放在晕染之下，金色晕染仍盖在最上层）
	_blast = Control.new()
	_blast.set_script(preload("res://ui/Fx/FxBlast.gd"))
	_blast.name = "Blast"
	add_child(_blast)

	# Boss 登场演出（全屏压暗 + 地缝 + 横幅，屏幕空间，自己订阅 boss_wave）
	var intro := Control.new()
	intro.set_script(BossIntroScene)
	intro.name = "BossIntro"
	add_child(intro)
	# 精英/Boss 出场光环（世界空间，自己订阅 enemy_spawned）
	var halo := Node2D.new()
	halo.set_script(SpawnHaloScene)
	halo.name = "SpawnHalo"
	add_child(halo)
	# 主动技能施放特效（世界空间，自己订阅 skill_cast）
	var skill_fx := Node2D.new()
	skill_fx.set_script(preload("res://ui/Fx/FxSkill.gd"))
	skill_fx.name = "SkillFx"
	add_child(skill_fx)

	_hurt = _mk_flash(Color(1.0, 0.12, 0.18))
	_gold = _mk_flash(Color(1.0, 0.78, 0.32))

	Events.damage_dealt.connect(_on_damage)
	Events.enemy_killed.connect(_on_killed)
	Events.enemy_exploded.connect(_on_enemy_exploded)
	Events.player_hp_changed.connect(_on_hp)
	Events.wok_tossed.connect(_on_toss)
	Events.melee_visual.connect(_on_melee)
	Events.weapon_fired.connect(_on_fired)
	Events.wave_ended.connect(_on_wave_ended)

# 全屏晕染：用 FxVignette（撑到视口 3 倍，把 letterbox 黑边也染上），
# 而不是 ColorRect——后者只盖 540x900，在手机上就是个"方块红框"，很割裂。
func _mk_flash(c: Color) -> Control:
	var v := Control.new()
	v.set_script(preload("res://ui/Fx/FxVignette.gd"))
	v.set("color", c)
	v.name = "Vignette"
	add_child(v)
	return v

# ---- 信号：飘伤害数字 ----
func _on_damage(amount: int, pos: Vector2, critical: bool) -> void:
	# 顿帧：重击每次都停；普通命中要节流，否则连射武器会顿成幻灯片
	if amount >= 30:
		HitStop.hit(0.045, 0.08)
	else:
		HitStop.hit_throttled(0.02, 0.5)
	if _floats.size() >= Perf.int_cap("floats", 24):
		return          # 高射速时宁可少飘几个，也不能拖帧
	var lab := _take_label()
	if lab == null:
		return
	lab.text = str(amount)
	lab.position = pos + Vector2(randf_range(-8.0, 8.0), -10.0)
	# 配色/字号与早期 DamageLabel 拉平（暴击=金、大数字≥30=橙、其余=白）；黑描边在 _take_label 统一加
	var big := amount >= 30
	var sc := 1.28 if (critical or big) else 1.0
	var col := Color(1.0, 1.0, 1.0)
	if critical: col = Color(1.0, 0.86, 0.35)
	elif big: col = Color(1.0, 0.55, 0.35)
	lab.scale = Vector2(sc, sc); lab.modulate = col
	lab.visible = true
	_floats.append({"label": lab, "t": 0.0})
	# 命中迸溅：和飘字一起冒，给每次打击一点卡通星芒
	if _pops.size() < Perf.int_cap("pops", 24):
		var pc := Color(1.0, 0.86, 0.35) if critical else Color(1.0, 1.0, 1.0)
		_pops.append({"pos": pos, "t": 0.0, "life": 0.18,
			"kind": "impact", "color": pc})

# ---- 信号：远程开火 → 枪口火光（按武器做专属） ----
func _on_fired(_pos: Vector2, _dir: Vector2, _stats: Dictionary, color: Color, key: String) -> void:
	if _pops.size() >= Perf.int_cap("pops", 24):
		return
	var pop := {"pos": _pos, "t": 0.0, "life": 0.12, "kind": "muzzle", "color": color}
	# 武器专属火光：火箭筒更大更橙、霰弹更宽
	if key == "rocket":
		pop["life"] = 0.22
		pop["scale"] = 1.8
		pop["color"] = Color(1.0, 0.55, 0.25)
	elif key == "shotgun":
		pop["scale"] = 1.3
		pop["wide"] = true
	_pops.append(pop)

# ---- 信号：击杀 → 三层迸溅（碎块/汁液/爆环，画在 FxRings）+ 击杀定帧 ----
func _on_killed(_type: String, pos: Vector2) -> void:
	HitStop.hit(0.05, 0.12)      # 击杀是最值得"顿一下"的时刻
	if _rings.size() >= Perf.int_cap("rings", 18):
		return
	_rings.append({"pos": pos, "t": 0.0, "life": 0.5, "big": (_type == "boss"),
		"color": Color(1.0, 0.88, 0.55)})

# 自爆怪贴脸爆炸：橙红冲击环 + 迸溅（复用击杀环/迸溅视图，删掉也不影响玩法）
func _on_enemy_exploded(pos: Vector2, _radius: float) -> void:
	if _rings.size() < Perf.int_cap("rings", 18):
		_rings.append({"pos": pos, "t": 0.0, "life": 0.45, "big": true,
			"color": Color(1.0, 0.45, 0.35)})
	if _pops.size() < Perf.int_cap("pops", 24):
		_pops.append({"pos": pos, "t": 0.0, "life": 0.22, "kind": "impact",
			"color": Color(1.0, 0.5, 0.4), "scale": 1.6})

# ---- 信号：挨打红闪 ----
func _on_hp(hp: int, _max_hp: int) -> void:
	if _last_hp >= 0 and hp < _last_hp:
		_hurt_t = 0.26
	_last_hp = hp

# ---- 信号：波次结束 → 过关庆祝（卡通彩纸从屏幕中央四散） ----
func _on_wave_ended(_wave: int, _pos: Vector2) -> void:
	if _celeb.size() >= 26:
		return
	var cx := Vector2(270.0, 450.0)
	var cols := [Color(1.0, 0.82, 0.29), Color(0.55, 0.85, 0.45),
		Color(1.0, 0.55, 0.45), Color(0.55, 0.78, 1.0)]
	var n := 16
	for i in n:
		_celeb.append({"pos": cx, "t": 0.0, "life": 0.85, "kind": "confetti",
			"color": cols[i % cols.size()], "ang": TAU * float(i) / float(n),
			"dist": randf_range(130.0, 270.0), "spin": randf_range(-7.0, 7.0)})

# ---- 信号：颠勺大招 → 全屏卡通爆炸 + 金闪 + 震屏 ----
# 爆炸中心跟随玩家实时位置（pos 是玩家世界坐标），不再钉屏幕中心。
func _on_toss(pos: Vector2) -> void:
	_gold_t = 0.42
	if _blast != null:
		_blast.fire(pos)
	# 震屏：颠勺是这游戏最重的一击
	Shake.kick(9.0, 0.32)

# ---- 信号：近战扇形 + 地面裂痕 ----
func _on_melee(origin: Vector2, dir: Vector2, reach: float, half_arc: float, color: Color, key: String, level: int) -> void:
	if _arcs.size() >= 12:
		return          # 多武器高频挥砍时宁可少画几刀，也不拖帧
	_arcs.append({"origin": origin, "dir": dir, "reach": reach,
		"half": half_arc, "color": color, "t": 0.0, "life": MELEE_LIFE})
	if _cracks.size() < MAX_CRACKS:  # 近战砍地裂痕：落点在挥砍中点，长度/分叉随武器等级变大
		_cracks.append({"pos": origin + dir * reach * 0.5, "dir": dir,
			"level": level, "color": color, "t": 0.0, "life": 0.85})

func _process(delta: float) -> void:
	var i := 0
	while i < _floats.size():
		var f: Dictionary = _floats[i]
		var t: float = float(f.get("t", 0.0)) + delta
		f["t"] = t
		var lab: Label = f.get("label") as Label
		lab.position.y -= FLOAT_RISE * delta
		var k: float = clampf(t / FLOAT_LIFE, 0.0, 1.0)
		lab.modulate.a = 1.0 - k * k
		if t >= FLOAT_LIFE:
			_give_label(lab)
			_floats.remove_at(i)
		else:
			i += 1
	# 其余数组都是同一套"推进 t / 到期剔除 / 重绘"，统一走一个函数
	_tick(_rings, _ring_view, delta)
	_tick(_arcs, _arc_view, delta)
	_tick(_cracks, _crack_view, delta)
	_tick(_pops, _pop_view, delta)
	_tick(_celeb, _celeb_view, delta)
	_tick_vignettes(delta)
	HitStop.tick()      # 定帧恢复（用真实时钟，见 HitStop 注释）

# 通用推进：t += delta；超 life 剔除；仅在"有特效在播或刚播完需清空"时重绘（避免空数组每帧白刷）
func _tick(arr: Array, view: Node2D, delta: float) -> void:
	var had := not arr.is_empty()
	var i := 0
	while i < arr.size():
		var d: Dictionary = arr[i]
		var t: float = float(d.get("t", 0.0)) + delta
		d["t"] = t
		if t >= float(d.get("life", 0.18)):
			arr.remove_at(i)
		else:
			i += 1
	if had:
		view.queue_redraw()

# 全屏晕染（受伤红 / 颠勺金）：撑满整块手机屏，含 letterbox 黑边
func _tick_vignettes(delta: float) -> void:
	if _hurt_t > 0.0:
		_hurt_t -= delta
		_hurt.set("strength", maxf(0.0, _hurt_t / 0.26))
		_hurt.queue_redraw()
	elif float(_hurt.get("strength")) > 0.0:
		_hurt.set("strength", 0.0)
		_hurt.queue_redraw()
	if _gold_t > 0.0:
		_gold_t -= delta
		_gold.set("strength", maxf(0.0, _gold_t / 0.42))
		_gold.queue_redraw()
	elif float(_gold.get("strength")) > 0.0:
		_gold.set("strength", 0.0)
		_gold.queue_redraw()

# ---- Label 对象池：飘字是最高频的特效，绝不能每次 instantiate ----
func _take_label() -> Label:
	if not _pool.is_empty():
		return _pool.pop_back() as Label
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 20)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	# 黑描边：和早期 DamageLabel 一致，密集怪海里也一眼看清数字
	lab.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.09, 1.0))
	lab.add_theme_constant_override("outline_size", 4)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.visible = false
	add_child(lab)
	return lab

func _give_label(lab: Label) -> void:
	lab.visible = false
	if _pool.size() < Perf.int_cap("floats", 24):
		_pool.append(lab)
