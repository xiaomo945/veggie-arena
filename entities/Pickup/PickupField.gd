extends Node2D

# 金币场地：管理金币对象池，负责掉落 / 磁吸推进 / 结算。
#
# 挂在主场景下的一个 Node2D。Game 只跟它打三个交道：
#   drop(pos, value)          —— 敌人死了掉钱
#   update(delta, pp, pct)    —— 每帧推进，返回本帧吃到的总额
#   collect_all()             —— 波末清场，把地上的钱一次性结算
#
# 池子满了不会崩：从头覆盖最老的一枚（宁可丢一枚金币，也不能让新钱刷不出来）。
#
# ⚠️ 本工程把 GDScript 警告当错误，所有来自无类型引用（_pool 元素、instantiate 结果）
#    的赋值都必须显式声明类型，用 := 会 Parse Error 并让整个文件加载失败。

const PickupScene := preload("res://entities/Pickup/Pickup.tscn")
const Pickup := preload("res://core/Pickup.gd")

var _pool: Array = []
var _cursor := 0
var _cfg: Dictionary = {}
var _max_pieces := 4
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	build_pool()

# 建池：公开方法而不是让调用方去调 _ready()。
# 单测里节点不进树、_ready 不会自动跑，以前测试只能手动 field._ready()；
# 现在测试（和任何想脱离场景树用这块逻辑的地方）直接调 build_pool()。
func build_pool() -> void:
	_rng.randomize()
	var raw: Dictionary = {}
	if Data.balance.has("pickup"):
		var got: Dictionary = Data.balance["pickup"] as Dictionary
		raw = got
	_cfg = Pickup.cfg(raw)
	_max_pieces = int(raw.get("max_pieces", 4))
	var n := int(raw.get("pool_size", 80))
	for _i in maxi(4, n):
		var p: Node2D = PickupScene.instantiate() as Node2D
		p.recycle()
		add_child(p)
		_pool.append(p)

# 掉钱：价值大的拆成几枚，散开落地（看起来像"爆出一地钱"）
# 返回"池满时被直接结算入账"的金额 —— 钱永远不会凭空消失：
# 池子满了就先把最老的一枚直接给玩家，再复用那个槽位。
func drop(pos: Vector2, value: int) -> int:
	var overflow := 0
	var v := maxi(1, value)
	var pieces := Pickup.split_count(v, _max_pieces)
	var vals := Pickup.split_values(v, pieces)
	var spread: float = float(_cfg.get("spread", 26.0))
	# 掉落点钳进竞技场（留 18px 余量），金币才不会散到地图外、看着割裂
	var a: Dictionary = Data.arena()
	var ar := Rect2(float(a.get("x", 0)), float(a.get("y", 0)),
		float(a.get("w", 540)), float(a.get("h", 900))).grow(-18.0)
	var anchor := _clamp_to(pos, ar)
	for i in vals.size():
		var p: Node2D = _next()
		if p == null:
			return overflow
		if p.active:
			# 池满：这枚最老的直接结算，不能让玩家白打
			var ov: int = p.value_and_recycle()
			overflow += ov
			Events.pickup_collected.emit(pos, ov)
		var at: Vector2 = _clamp_to(Pickup.drop_position(anchor, _rng.randf(), _rng.randf(), spread), ar)
		p.spawn(at, int(vals[i]), _cfg)
	return overflow

# 把点钳进矩形（金币掉地图外的根因：敌人死在边缘，掉落点漂出竞技场）
static func _clamp_to(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))

# 每帧推进所有金币。返回本帧被吃掉的总价值（0 表示没吃到）。
# magnet 是真实磁吸半径(px)，由 GameState.pickup_magnet() 算出（含自动拾取/拾取范围）。
# force=true 时无视磁吸半径全速回收（波末/清场）。
func update(delta: float, player_pos: Vector2, magnet: float, force := false) -> int:
	var got := 0
	for item in _pool:
		var p: Node2D = item as Node2D
		if p == null or not p.active:
			continue
		var v: int = p.advance(delta, player_pos, magnet, force)
		if v > 0:
			got += v
			Events.pickup_collected.emit(player_pos, v)
	return got

# 波末清场：不飞，直接结算，玩家不用干等一堆金币飘回来
func collect_all(player_pos: Vector2) -> int:
	var got := 0
	for item in _pool:
		var p: Node2D = item as Node2D
		if p == null or not p.active:
			continue
		var v: int = p.value_and_recycle()
		got += v
		Events.pickup_collected.emit(player_pos, v)
	return got

func clear() -> void:
	for item in _pool:
		var p: Node2D = item as Node2D
		if p != null:
			p.recycle()
	_cursor = 0

# 地上还没捡的钱的总面额（诊断用：模拟报告会打印它，方便看出"钱有没有掉出来"）
func ground_value() -> int:
	var total := 0
	for item in _pool:
		var p: Node2D = item as Node2D
		if p != null and p.active:
			total += int(p.value)
	return total

func alive_count() -> int:
	var n := 0
	for item in _pool:
		var p: Node2D = item as Node2D
		if p != null and p.active:
			n += 1
	return n

# 取一个槽位：优先空闲；全满就按顺序覆盖最老的一枚
func _next() -> Node2D:
	for i in _pool.size():
		var p: Node2D = _pool[(_cursor + i) % _pool.size()] as Node2D
		if p != null and not p.active:
			_cursor = (_cursor + i + 1) % _pool.size()
			return p
	var old: Node2D = _pool[_cursor] as Node2D
	_cursor = (_cursor + 1) % _pool.size()
	return old
