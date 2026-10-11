extends RefCounted

# 打击反馈档位（爽感底层）：把"这一下该有多重"收在一处，要调手感只改这张表。
#
# 为什么单独一个文件：FxLayer 已经顶到 300 行红线，而"轻击 / 重击 / 暴击 / 击杀
# / Boss 倒下"各自该顿多久、震多重、闪什么颜色，本来就该是一张可以整体调的档位表，
# 而不是散在特效层各处的 if。调爽感时不用再翻绘制代码。
#
# 三档的设计意图：
#   轻击  只顿一下、不震 —— 连射武器一秒十几次命中，震了就成筛子
#   重击  顿 + 轻震      —— 大数字要"沉"，但不能抢戏
#   暴击  顿 + 明显短震  —— 玩家要能凭身体感觉"这下打实了"
#   击杀  顿 + 小震（节流）；Boss 倒下不节流，值得停下来看

const HitStop := preload("res://entities/effects/HitStop.gd")
const Shake := preload("res://entities/effects/Shake.gd")

const BIG_DMG := 30      # 飘字变橙、进"重击"档的门槛（与 FxLayer 的配色同一条线）

static func hit(amount: int, critical: bool) -> void:
	if critical:
		HitStop.hit(0.045, 0.08)
		Shake.tier("crit", 5.5, 0.14)
	elif amount >= BIG_DMG:
		HitStop.hit(0.045, 0.08)
		Shake.tier("big", 3.5, 0.12)
	else:
		# 轻击的顿帧必须节流，否则连射武器会顿成幻灯片（见 HitStop 注释）
		HitStop.hit_throttled(0.02, 0.5)

static func kill(type: String) -> void:
	HitStop.hit(0.05, 0.12)      # 击杀是最值得"顿一下"的时刻
	if type == "boss":
		Shake.kick(11.0, 0.45)
	else:
		Shake.tier("kill", 3.2, 0.12)
