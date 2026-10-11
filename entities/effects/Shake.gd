extends RefCounted

# 震屏（screen shake）—— 2026-10-12 起【全部取消】，本文件只留空壳。
#
# ⚠️ 用户拍板："爽感不是振频，把所有的振频震动取消掉"。
#   整屏抖动在这类小屏割草游戏里是负担：抖的那几十毫秒里正好看不清怪在哪，
#   而"看得清"才是这类游戏的手感底线。打击感改由顿帧 / 飘字 / 迸溅 / 音效承担
#   （档位见 entities/effects/Feel.gd，那些都不抖画面）。
#
# 为什么不删掉所有调用点：受伤 / 暴击 / 击杀 / Boss 出场 / 颠勺 / 技能，一共 6 处，
#   挨个删容易顺手改坏别的逻辑。收口成空操作一次性全部失效，更安全。
#   要恢复：把 git 历史里这一版实现贴回 kick() 即可（只此一处），调用点都不用动。

static var _root: Node2D = null

static func register(root_node: Node2D) -> void:
	_root = root_node

# 按"档位"震的入口（保留签名，行为为空）。节流表留着，将来恢复能直接用。
const TIER_GAP := {"crit": 0.22, "big": 0.22, "kill": 0.30}
static var _tier_at: Dictionary = {}

static func tier(_key: String, _strength: float, _duration: float) -> void:
	return

static func kick(_strength: float, _duration: float) -> void:
	return
