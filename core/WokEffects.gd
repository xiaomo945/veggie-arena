extends RefCounted

# 锅气大招（颠勺）的效果组装 —— 纯逻辑，不碰任何 Node。
#
# 设计意图：锅气是这游戏的核心差异化玩法 —— 靠击杀攒火候，攒满放一个全屏大招，
# 而**道具决定这个大招是什么**：减速、冻结、中毒、灼烧、破甲、连锁爆炸、吸血、掉金……
# 所以效果组合必须是数据驱动的：加一个新道具 = 加一个 stat，不改这里的结构。
#
# 为什么放在 core/ 而不是 EnemySystem 里：
#   1. 效果组合全是数值，放 core 才能被 headless 单测直接覆盖
#   2. EnemySystem 已经顶到 300 行红线，再往里塞效果就守不住了

# 所有锅气相关的 stat 名。EnemySystem 按这个名字列表一次性取值再传进来。
const STAT_KEYS := [
	"wok_dmg_pct",    # 大招伤害 +%（比例）
	"wok_knock_pct",  # 击退 +%（比例）
	"wok_slow",       # >0 开启减速，数值 = 持续秒数（强度用 cfg toss_slow_pct）
	"wok_freeze",     # 冻结秒数（0 = 没有）
	"wok_poison",     # 中毒：每秒扣最大生命的比例（0.03 = 每秒 3%）
	"wok_burn",       # 灼烧：每秒固定伤害
	"wok_shred",      # 破甲：受到伤害加深的比例（0.25 = 多挨 25%）
	"wok_explode",    # 连锁爆炸：被大招打死的怪会炸周围，数值 = 爆炸伤害
	"wok_lifesteal",  # 吸血：每命中一个敌人回多少血
	"wok_gold",       # 掉金：每命中一个敌人额外掉多少金币
	"wok_refund",     # 返火：释放后按比例把火候条还回来（连发流）
	"wok_execute",    # 斩杀：血量低于这个比例的敌人直接被大招秒掉（0.2 = 20%）
	"wok_vortex",     # 聚怪：>0 时改为把敌人**吸向**玩家（而不是甩飞）
	"wok_chain",      # 连锁：大招伤害在敌人之间弹跳的次数
	"wok_shield",     # 护盾：大招后获得多少点护盾（挨打先扣它）
	"wok_frenzy",     # 狂暴：大招后多少秒内攻速 + 移速暴涨
	"wok_magnet",     # 吸金：>0 就把场上金币全部吸到脚下
	"wok_elite_pct",  # 精英特攻：对 Boss / 精英怪的额外伤害比例
	"wok_double",     # 双重施放：一次消耗，连放两发
]

# 从 stat 表 + balance 配置，算出这一发大招的全部参数。
# stat: {stat_key: 数值}，来自 GameState.stat_value 快照。
static func build(stat: Dictionary, cfg: Dictionary) -> Dictionary:
	var dmg_mult := float(cfg.get("toss_dmg_mult", 0.6)) \
		* (1.0 + _v(stat, "wok_dmg_pct"))
	return {
		"dmg_mult": dmg_mult,
		"flat": float(cfg.get("toss_flat", 25.0)) * (1.0 + _v(stat, "wok_dmg_pct")),
		"knock": float(cfg.get("toss_knock", 130)) * (1.0 + _v(stat, "wok_knock_pct")),
		# 以下各项为 0 表示"没买对应道具"，EnemySystem 会跳过
		"slow_v": _flag(_v(stat, "wok_slow"), float(cfg.get("toss_slow_pct", 0.5))),
		"slow_dur": _v(stat, "wok_slow"),
		"freeze_dur": _v(stat, "wok_freeze"),
		"poison_dps_pct": _v(stat, "wok_poison"),
		"poison_dur": _flag(_v(stat, "wok_poison"), float(cfg.get("toss_poison_dur", 3.0))),
		"burn_dps": _v(stat, "wok_burn"),
		"burn_dur": _flag(_v(stat, "wok_burn"), float(cfg.get("toss_burn_dur", 2.5))),
		"shred_v": _v(stat, "wok_shred"),
		"shred_dur": _flag(_v(stat, "wok_shred"), float(cfg.get("toss_shred_dur", 3.0))),
		"explode": _v(stat, "wok_explode"),
		"explode_radius": float(cfg.get("toss_explode_radius", 70.0)),
		"lifesteal": _v(stat, "wok_lifesteal"),
		"gold": _v(stat, "wok_gold"),
		"refund": _v(stat, "wok_refund"),
		"execute": _v(stat, "wok_execute"),
		"vortex": _v(stat, "wok_vortex"),
		"chain": int(_v(stat, "wok_chain")),
		"shield": int(_v(stat, "wok_shield")),
		"frenzy": _v(stat, "wok_frenzy"),
		"magnet": _v(stat, "wok_magnet"),
		"elite_pct": _v(stat, "wok_elite_pct"),
		"double": int(_v(stat, "wok_double")),
		"chain_dmg": float(cfg.get("toss_chain_dmg", 12.0)),
	}

# 这一发大招带了几种附加效果（用于 HUD 提示 / 测试断言）
static func effect_count(fx: Dictionary) -> int:
	var n := 0
	for k in ["slow_v", "freeze_dur", "poison_dps_pct", "burn_dps", "shred_v",
			"explode", "lifesteal", "gold", "refund", "execute", "vortex",
			"chain", "shield", "frenzy", "magnet"]:
		if float(fx.get(k, 0.0)) > 0.0:
			n += 1
	return n

# 读一个 stat，缺省 0
static func _v(stat: Dictionary, key: String) -> float:
	return float(stat.get(key, 0.0))

# 开关型：主数值 >0 时才启用配套的时长/强度，否则给 0
static func _flag(on: float, value: float) -> float:
	return value if on > 0.0 else 0.0
