extends RefCounted

# 技能槽位计算（四元素联动的第二环）：武器/道具【产出】技能。
#
# 旧结构：每个角色只有 1 个技能（角色表 skill 字段），武器/道具只改技能的数值
# （variants + skill_power）—— 玩家原话"没有任何道具/武器会产生技能，
# 技能和道具武器完全脱节"。
# 新结构：技能有三个来源，凑成最多 3 个槽位：
#   1) 角色本命技（characters.json 的 skill）：永远在槽 0，威力 100%
#   2) 武器赠送（weapons.json 的 skill 字段）：拿到这把武器就多一个技能
#   3) 道具赠送（upgrades.json 的 skill 字段）：同理
# 赠送技基础值打 0.8 折（GIFT_MUL）：本命技是角色的招牌，不能白送一样强；
# 但赠送技【照样吃 variants】—— 灼烧法师拿喷火枪送灼烧，再堆 4 件元素武器，
# 灼烧一样触发他的强化路线。这就是联动的意义：武器给招，构筑仍然决定招的强弱。
#
# 上限 3 的理由：HUD 扇面（wok + 3 技能 + 攻击键 + 冲刺）在 540x900 下排得开，
# 右手拇指从 245° 扫到 155° 一共三下；再多就按"先武器后道具"截断，
# 货架与详情页仍看得到全部赠送信息（买了不进槽 ≠ 信息被藏起来）。
#
# 纯函数、不碰 autoload（架构守卫 R2）：全部数据由调用方注入，便于单测。

const SkillDef := preload("res://core/SkillDef.gd")

# 同时生效的技能上限（含本命技）
const MAX_SLOTS := 3
# 赠送技的基础值折扣。冷却不打折——白送一个技能已经够好，再送更快冷却就过头了。
const GIFT_MUL := 0.8

# 当前生效的技能槽位（顺序即 HUD 扇面顺序：槽 0 是攻击键 + 最顺手的技能位）。
# 每项 {id, source, key, mul}：
#   source = "char"（本命技，key = 角色 key，mul = 1.0）
#   source = "weapon"（key = 武器 id）/ "item"（key = 道具 id），mul = GIFT_MUL
static func slots_of(char_entry: Dictionary, weapons: Array, weapon_defs: Dictionary,
		item_keys: Array, item_defs: Dictionary, skills_cfg: Dictionary) -> Array:
	var arr: Array = skills_cfg.get("skills", []) as Array
	var out: Array = []
	var seen: Dictionary = {}
	# 1) 本命技：角色表写了 id；没写或写错 → 退回 primary，绝不留空槽
	var cid := SkillDef.skill_id_of(char_entry, str(skills_cfg.get("primary", "frost")))
	if SkillDef.base_of(cid, arr).is_empty():
		cid = str(skills_cfg.get("primary", "frost"))
	if not cid.is_empty():
		out.append({"id": cid, "source": "char",
			"key": str(char_entry.get("_key", "")), "mul": 1.0})
		seen[cid] = true
	# 2) 武器赠送（按持有顺序；同一技能只占一槽，先到先得）
	for w in weapons:
		if not (w is Dictionary):
			continue
		var wkey := str((w as Dictionary).get("key", ""))
		var wd: Dictionary = weapon_defs.get(wkey, {}) as Dictionary
		var sid := str(wd.get("skill", ""))
		if sid.is_empty() or seen.has(sid) or SkillDef.base_of(sid, arr).is_empty():
			continue
		out.append({"id": sid, "source": "weapon", "key": wkey, "mul": GIFT_MUL})
		seen[sid] = true
	# 3) 道具赠送（持有即送，与数量无关）
	for k in item_keys:
		var ud: Dictionary = item_defs.get(str(k), {}) as Dictionary
		var sid2 := str(ud.get("skill", ""))
		if sid2.is_empty() or seen.has(sid2) or SkillDef.base_of(sid2, arr).is_empty():
			continue
		out.append({"id": sid2, "source": "item", "key": str(k), "mul": GIFT_MUL})
		seen[sid2] = true
	# 4) 截断到上限（保前面的：本命 > 武器 > 道具）
	while out.size() > MAX_SLOTS:
		out.pop_back()
	return out

# 槽位 id 列表（信号广播 / HUD 重建比对用）
static func ids_of(slots: Array) -> Array:
	var out: Array = []
	for s in slots:
		out.append(str((s as Dictionary).get("id", "")))
	return out

# 两组槽位是不是同一回事（id 序列完全相同）—— HUD 只在真的变了时重建按钮，
# 否则每帧 prune+add_child，按钮会不停闪。
static func same_slots(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str((a[i] as Dictionary).get("id", "")) != str((b[i] as Dictionary).get("id", "")):
			return false
	return true
