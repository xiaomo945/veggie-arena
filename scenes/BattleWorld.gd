extends RefCounted

# 一场战斗的全部可变状态：对象池、随机源、竞技场矩形、每帧复用的暂存数组、
# 颠勺冲击波、诊断计数器。
#
# 【为什么单独抽这一层】
# 之前 EnemySystem 通过 game._enemies / game._bullets / game._rng / game._arena /
# game._next_id ... 直接读写 Game 的私有字段，一共 64 处。后果是：
#   - Game 改个字段名，EnemySystem 就崩（编译期查不出来，跑起来才炸）；
#   - 想单独测敌人逻辑，得先造一个假的 Game；
#   - 谁在什么时候改了 _enemy_cursor，全项目没人说得清。
# 现在 Game（场景编排 / 波次生命周期）与 EnemySystem（战斗运算）只依赖这一个
# "世界状态"对象：字段是公开的显式契约，读写都收口在这里。
#
# 【为什么是 RefCounted 而不是 Node】
# 它只是数据 + 池引用，不进场景树，也不需要 _process。不进树 = 能被单测直接 new
# 出来，这是抽这一层的主要目的之一。

# 用 preload 引用本文件（const BattleWorld := preload("res://scenes/BattleWorld.gd")），
# 不用 class_name：check.sh 会清 .godot/editor 缓存，headless 跑起来时全局类表还没
# 重建，class_name 会报 "Identifier not declared"。preload 每次都稳。

const MAX_BULLETS := 90
const MAX_ENEMIES := 110

# ---- 对象池（由 Game 建好节点后交给 world 持有引用）----
var enemies: Array = []
var bullets: Array = []
var pickups: Node2D = null
var player: Node2D = null

var rng := RandomNumberGenerator.new()
var arena := Rect2()

# 每帧复用的暂存数组，避免每帧新建造成 GC 压力（手机端很明显）
var bdata: Array = []     # 子弹快照 [{pos,radius,active,ref}]
var edata: Array = []     # 敌人快照 [{pos,radius,vel,alive,ref}]
var neighbors: Array = [] # 分离用邻居 [{pos,radius}]

# 环形游标与自增 entity id
var enemy_cursor := 0
var bullet_cursor := 0
var next_id := 1

# 颠勺冲击波：shock_t < 0 表示没在播
var shock_t := -1.0
var shock_pos := Vector2.ZERO
var shock_max := 280.0
var shock_dur := 0.38

# 诊断计数器（模拟报告 / 调试面板读）
var shots_fired := 0
var hits_landed := 0
var gold_picked := 0

# 开新的一局：回收状态，但不碰对象池里的节点（池由 Game 管理生命周期）
func reset_run() -> void:
	enemy_cursor = 0
	bullet_cursor = 0
	next_id = 1
	shock_t = -1.0
	shock_pos = Vector2.ZERO
	shots_fired = 0
	hits_landed = 0
	gold_picked = 0

func kick_shock(pos: Vector2) -> void:
	shock_pos = pos
	shock_t = 0.0

func alive_enemy_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n

# 地上还没被捡走的金币面额（诊断 / HUD 用）
func ground_gold() -> int:
	return pickups.ground_value() if pickups != null else 0
