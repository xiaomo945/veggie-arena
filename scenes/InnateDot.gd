extends RefCounted

# 角色自带的"命中附加持续伤害"接线层（bullet / melee 两条命中管线共用）。
#
# 为什么单独一个文件：
#   1) 规则（给多少、给多久）在 core/Character.gd，是纯函数、可单测；
#      而"把它贴到敌人身上"必须碰 Enemy 实体和 GameState（autoload），
#      按架构守卫 R2 不能写进 core/。两边分开，规则和接线各自能独立验。
#   2) EnemySystem.gd 已经贴着 300 行红线，塞进去会立刻触发 R1。
#
# 为什么要这一层（真踩过的坑）：
#   焦辣萝卜 scorch 的人设是"毒 + 灼烧双 DoT"，但改造前 DoT 只挂在技能上 ——
#   玩家选它、开枪打了三秒，屏幕上一点火都没有，只看到自己普攻比别人低一截。
#   人设立在 tip 里、机制藏在技能冷却里，新手三秒看不懂，直接换角色。
#   现在：选中它 → 打中第一只怪 → 火烧起来。不需要读任何说明。

const Character := preload("res://core/Character.gd")

# 取本局角色自带的命中效果（每帧算一次，命中循环里复用；空表=这个角色没有）
static func of(character_key: String) -> Dictionary:
	return Character.on_hit_dot(_entry(character_key))

static func _entry(character_key: String) -> Dictionary:
	return Data.character(character_key) as Dictionary

# 命中时把效果贴到敌人身上。d 是 of() 的返回值；空表直接跳过（零开销）。
#
# ⚠️ 不叠层：Enemy.apply_fx 对同名效果取 max，所以一只怪最多同时吃一份，
#    它是"凡是被你碰过的怪都在慢慢掉血"，不是"每一发都追加伤害" ——
#    这条决定了它不会让高射速武器变成数值炸弹。
# ⚠️ 吃元素加成：elem_pct 是元素流的通用放大项，让本命喷火枪、
#    元素羁绊、元素道具都能一起放大这一层，四元素联动才闭环。
static func apply(e, d: Dictionary) -> void:
	if d.is_empty():
		return
	var scale := 1.0 + GameState.stat_value("elem_pct")
	var dur := float(d.get("dur", 2.0))
	var burn := float(d.get("burn", 0.0)) * scale
	var pct := float(d.get("poison_pct", 0.0)) * scale
	if burn > 0.0:
		e.apply_fx("burn", burn, dur)
	if pct > 0.0:
		e.apply_fx("poison", e.max_hp * pct, dur)
