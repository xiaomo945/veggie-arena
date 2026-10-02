extends Node2D

# 金币掉落物：对象池复用（跟子弹/敌人一个套路），不在战斗中 instantiate。
#
# 掉在地上 → 玩家进磁吸圈 → "啪"地飞过去 → 吃到加钱。
# 移动与判定全交给 core/Pickup（纯函数），本文件只管节点状态和外观。
#
# 性能：外观只在 spawn 时画一次（queue_redraw 一次），
# 之后靠 position/scale 做飘动，70 枚金币同屏零重绘。

const Pickup := preload("res://core/Pickup.gd")

var active := false
var value := 1

var _magnet := 92.0
var _pull := 430.0
var _collect := 18.0
var _spread := 26.0
var _life := 0.0
var _age := 0.0
var _phase := 0.0
var _spin := 0.0
var _pulled := false
var _r := 5.5

const GOLD := Color(1.0, 0.82, 0.28)
const GOLD_D := Color(0.85, 0.60, 0.10)
const GOLD_L := Color(1.0, 0.95, 0.72)

func spawn(pos: Vector2, v: int, cfg: Dictionary) -> void:
	global_position = pos
	value = maxi(1, v)
	var c := Pickup.cfg(cfg)
	_magnet = float(c["magnet"])
	_pull = float(c["pull_speed"])
	_collect = float(c["collect_radius"])
	_spread = float(c["spread"])
	_life = float(c["life"])
	_age = 0.0
	_phase = randf() * TAU
	_spin = randf() * TAU
	_pulled = false
	# 面额越大画得越大：一眼能看出"这坨钱值"（下限提到 6.5，萝卜印才读得出来）
	_r = 6.5 if value <= 2 else (8.0 if value <= 5 else 9.5)
	scale = Vector2.ONE
	active = true
	visible = true
	queue_redraw()

func recycle() -> void:
	active = false
	visible = false
	value = 1
	_pulled = false

# 每帧推进。返回本帧吃到的价值（0 = 没吃到）。
# ⚠️ 回收会把 value 清零，所以必须在 recycle 之前把价值存下来再返回。
# magnet 是真实磁吸半径(px)，由调用方算好（含自动拾取/拾取范围等强化）；
# force 为 true 时无视距离全吸（波末清场用）。
func advance(delta: float, player_pos: Vector2, magnet: float, force := false) -> int:
	if not active:
		return 0
	_age += delta
	if _life > 0.0 and _age >= _life:
		recycle()
		return 0
	var m := magnet
	if force:
		m = 100000.0
	var res := Pickup.step(global_position, player_pos, m,
		_pull, _collect, delta)
	global_position = res["pos"] as Vector2
	_pulled = bool(res.get("pulled", false))
	# 飘动全靠 transform（零重绘）：地上时 x 轻微挤压=硬币翻面自旋、
	# y 一伸一缩=上下浮动；被吸时整体放大一点（"吸住了"的反馈）
	if _pulled:
		scale = Vector2(1.25, 1.25)
	else:
		_spin += delta * 3.0
		_phase += delta * 3.4
		scale = Vector2(0.74 + 0.26 * absf(cos(_spin)), 1.0 + 0.10 * sin(_phase))
	if bool(res.get("collected", false)):
		var v := value      # 先存，recycle 会把 value 清零
		recycle()
		return v
	return 0

# 波末清场：不飞过去，直接结算（避免玩家看着一堆金币慢慢飞回来等半天）
func value_and_recycle() -> int:
	var v := value
	recycle()
	return v

func _ready() -> void:
	# 金币是"512 大图缩到十几 px"画的：默认 nearest 过滤会把采样点打歪，
	# 看起来就是一颗小黄点 —— 缩小绘制一律走线性 + mipmap（配合 Art.coin_icon）
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _draw() -> void:
	if not active:
		return
	# 静态微光 + 落影：一次画好，之后零重绘
	draw_circle(Vector2.ZERO, _r * 1.9, Color(1.0, 0.85, 0.3, 0.06))
	draw_set_transform(Vector2(0, _r * 0.9), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _r * 1.05, Color(0.0, 0.0, 0.0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 卡通金币（萝卜印金饼，运行时缩好+mipmap，见 Art.coin_icon）
	var tex := Art.coin_icon()
	if tex != null:
		var s := _r * 2.6
		draw_texture_rect_region(tex, Rect2(-s * 0.5, -s * 0.5, s, s),
			Rect2(Vector2.ZERO, tex.get_size()))
		return
	# 手绘兜底：深色描边 + 金色本体 + 内圈 + 左上高光
	draw_circle(Vector2.ZERO, _r + 1.2, GOLD_D)
	draw_circle(Vector2.ZERO, _r, GOLD)
	draw_arc(Vector2.ZERO, _r * 0.62, 0, TAU, 24, GOLD_D, 1.4, true)
	draw_circle(Vector2(-_r * 0.3, -_r * 0.32), _r * 0.34, GOLD_L)
