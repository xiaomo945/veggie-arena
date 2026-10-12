extends RefCounted

# =====================================================================
# 模拟侧的 DPS 数学：对群折算 / 武器汇总 / 锅气档位倍率。
#
# 为什么从 SimCore 拆出来（2026-10-12）：SimCore 本来就贴在 300 行红线上，
# 而这一轮要加两项口径（锅气按角色 wok_pct 浮动、角色自带命中 DoT），
# 没地方长了。拆完两边都留有余量，且"DPS 怎么算"和"一局怎么推演"，
# 本来就是两件事。
#
# 口径原则不变：一律直调真实 core/ 公式（Combat.weapon_dps /
# WeaponSets.damage_mult），不重造第二套。
# =====================================================================

const Combat := preload("res://core/Combat.gd")
const Weapon := preload("res://core/Weapon.gd")
const WeaponSets := preload("res://core/WeaponSets.gd")
const SP := preload("res://tests/SrcParse.gd")

var targets := 3
var defs := {}
var wok_cfg := {}


# 对群折算：单把武器打 N 个目标时输出是单体的几倍。口径与 tests/test_weapon.gd
# 的 _multiplier 一致 —— 按单体 DPS 排会让 AOE/连锁武器显得很弱，逼着配平去堆
# 单体数值，正是用户嫌的"武器只是数值堆叠"。链式衰减现读源码，不抄常数。
func group_mult(def: Dictionary) -> float:
	var beh := Weapon.behavior_of(def)
	if float(def.get("aoe", 0)) > 0.0 or beh == "pulse" or beh == "beam":
		return float(targets)
	if beh == "chain":
		var m := 1.0
		var hop := 1.0
		for _i in range(int(def.get("chain", 0))):
			hop *= SP.const_val(SP.read("res://scenes/BulletSystem.gd"), "CHAIN_FALLOFF")
			m += hop
		return m
	return 1.6 if beh == "boomerang" else (1.15 if beh == "homing" else 1.0)


func eff_dps(w: Dictionary, dmg_pct: float, rate_pct: float) -> float:
	var d: Dictionary = defs.get(str(w.get("key", "")), {})
	return Combat.weapon_dps(w, dmg_pct, rate_pct) * group_mult(d)


# 锅气档位倍率。基础 = tier1/tier2 的中点（保守假设两种档各占一半战斗时间）；
# wok_pct（角色自带 + 道具 + heat 技能当量，见 SimChar）把实际档位往 tier2 推
# —— 攒热越快，爆炒档停留越久。clamp 到 tier2 封顶：再高的充能速率也不会
# 超过"全程爆炒"这个物理上限。
# ⚠️ 这里只建模档位停留比例，不建模颠勺伤害本身（对所有角色一致，
#    不影响横向比较；颠勺是手动大招，模拟器从来不猜玩家按键时机）。
func wok_mult(wok_pct_eff: float) -> float:
	var t1 := 1.0 + float(wok_cfg.get("tier1_fire", 0.3))
	var t2 := (1.0 + float(wok_cfg.get("tier2_fire", 0.65))) \
		* (1.0 + float(wok_cfg.get("tier2_dmg", 0.3)))
	var mid := (t1 + t2) * 0.5
	return mid + (t2 - mid) * clampf(wok_pct_eff, 0.0, 1.0)


# 当前这堆武器若全停在 Lv1 会有多少输出 —— need_lv / eq_lv 的分母，
# 让"该到几级"这句话有一个和玩家手上武器同口径的尺子。
# dot 一起传进来：它是角色被动、与武器等级无关，两边都带才公平。
func sum_lv1(weapons: Array, ccfg: Dictionary, dot: float = 0.0) -> float:
	var t := 0.0
	var gsum := 0.0
	for w in weapons:
		var d: Dictionary = defs.get(str(w.get("key", "")), {})
		var g := group_mult(d)
		t += Combat.weapon_dps(Weapon.merged_stats(d, 1, ccfg)) * g
		gsum += g
	return t + dot * gsum


# 当前总输出。pierce / aoe 只给保守折算（穿透要怪排队才吃得到、范围要够大才多打
# 到一个），完全不计会让探针只认 dmg/rate/crit 三类道具，把玩家算弱、把敌人配软。
func total(weapons: Array, st: Dictionary, dot: float, wok_pct_eff: float) -> float:
	var rp := float(st.get("rate_pct", 0.0))
	var pa := float(st.get("pellets_add", 0.0))
	var t := 0.0
	var gsum := 0.0
	for w in weapons:
		var key := str(w.get("key", ""))
		var d: Dictionary = defs.get(key, {})
		var ww: Dictionary = w.duplicate()
		ww["pellets"] = float(w.get("pellets", 1)) + pa
		# ⚠️ 伤害必须走 WeaponSets.damage_mult，不能只套 dmg_pct：实战里
		#    近战吃 melee_pct、远程吃 ranged_pct、元素额外吃 elem_pct
		#    （entities/Player/PlayerWeapons.gd 就这么算的）。只套 dmg_pct
		#    会把所有"元素流 / 近战流"角色的羁绊收益算成 0，排名彻底失真。
		var g := group_mult(d)
		t += Combat.weapon_dps(ww, 0.0, rp) * WeaponSets.damage_mult(d, st) * g
		gsum += g
	# 角色自带命中 DoT：每把武器碰到的怪都挂一份，所以跟着对群折算一起放大；
	# 但它不吃暴击/穿透/范围/锅气档位（固定值 + 只吃 elem_pct，见 scenes/InnateDot.gd）。
	var dot_total := dot * gsum
	var cc := clampf(float(st.get("crit_chance", 0.0)), 0.0, 1.0)
	var pierce := 1.0 + 0.10 * minf(float(st.get("pierce_add", 0.0)), 4.0)
	var aoe := 1.0 + 0.08 * minf(float(st.get("aoe_add", 0.0)) / 20.0, 4.0)
	return t * (1.0 + cc * float(st.get("crit_mult", 0.0))) * pierce * aoe \
		* wok_mult(wok_pct_eff) + dot_total
