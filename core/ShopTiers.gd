extends RefCounted

# 武器分级 / 商店难度门禁（纯逻辑，无渲染依赖）
#
# 解决用户反馈："商店只刷 1 级武器，2~5 级刷不出来，所以合不了" —— 现在商店会
# 直接给出 1..N 级的武器成品，价格按 tier_price_mult 逐级复利；同时按波次门禁，
# 前几波只出低档武器 / 低稀有度道具，避免"一上来就刷出厉害东西"破坏难度曲线。
#
# 分级配色（用户指定）：白1 / 绿2 / 蓝3 / 紫4 / 红5 / 传说6。
# 全部数值集中在 data/shop_tiers.json，方便配平，不写死在代码里。

const PATH := "res://data/shop_tiers.json"

var _cfg: Dictionary = {}

func _load() -> void:
	if not _cfg.is_empty():
		return
	_cfg = {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_cfg = parsed as Dictionary

# 价格倍率：每升一级 ×N（N 默认 2，即 2 级=1 级的 2 倍，3 级=2 级的 2 倍…）
# 用户硬约束：高级武器绝不比低级便宜（2级≥40、3级≥80…），所以倍率必须 ≥2。
func tier_price_mult() -> float:
	_load()
	return float(_cfg.get("tier_price_mult", 2.0))

func max_tier() -> int:
	_load()
	return int(_cfg.get("max_tier", 6))

# 某档位的最低底价（不管武器自身 cost 多低，都不能低于这条线，保证"高级更贵"）
func tier_floor(lv: int) -> int:
	_load()
	var map: Dictionary = _cfg.get("tier_price_floor", {})
	return int(map.get(str(clampi(lv, 1, max_tier())), 0))

# 档位底价 = max(武器1级价 × 倍率^(lv-1), 该档底价)。再叠打折/通胀在 build_pool 里结算。
func price_for_tier(base_cost: int, lv: int) -> int:
	_load()
	var mult := tier_price_mult()
	var raw := int(round(float(base_cost) * pow(mult, float(maxi(1, lv) - 1))))
	return maxi(raw, tier_floor(lv))

# 售出回收比例（买入价的 N%，绝不高于买入价）
func sell_ratio() -> float:
	_load()
	return clampf(float(_cfg.get("sell_ratio", 0.8)), 0.0, 1.0)

# 售出价 = floor(买入价 × 比例)，永远 ≤ 买入价（用户硬约束：不能 40 买的卖到 40 以上）
func sell_price(buy_cost: int) -> int:
	return int(floor(float(buy_cost) * sell_ratio()))

# 当前波次允许出现的最高武器档位（1..max_tier）。
# weapon_tier_from_wave 形如 {"1":1,"2":2,"3":5,...}：档位 L 从第 from_wave 波起出现。
func max_tier_for_wave(wave: int, cap_tier: int = 99) -> int:
	_load()
	var map: Dictionary = _cfg.get("weapon_tier_from_wave", {})
	var top := 1
	var hard := mini(max_tier(), cap_tier)
	for L in range(1, hard + 1):
		var from := int(map.get(str(L), 999))
		if wave >= from:
			top = L
	return top

# 某档位在商店池里的相对权重（高档更稀有）
func tier_weight(lv: int) -> float:
	_load()
	var map: Dictionary = _cfg.get("weapon_tier_weight", {})
	return float(map.get(str(lv), 1.0))

# 该给某把武器刷出哪些档位：跟着玩家"已持有的等级"走（用户核心诉求）。
#   - 未持有 → 只刷 1 级（先买初级起家）
#   - 已持有 L 级 → 刷 [L-1, L]（买一把 L 级即可再合成到 L+1；L-1 是卖错/丢了的兜底）
# 已持有的等级永远可买，波次上限不会压它（否则"持有 4 级却买不到 4 级去合 5 级"）。
func offer_tiers(owned_lv: int, _wave_top_tier: int, max_lv: int) -> Array:
	var hi := 1
	if owned_lv > 0:
		hi = mini(owned_lv, max_lv)
	var lo := maxi(1, owned_lv - 1)
	var out: Array = []
	for L in range(lo, hi + 1):
		out.append(L)
	return out

# 当前波次允许出现的最高道具稀有度（前几波不出高阶道具 = 难度控制）
func max_rarity_for_wave(wave: int) -> int:
	_load()
	var map: Dictionary = _cfg.get("upgrade_rarity_from_wave", {})
	var top := 1
	for r in range(1, 4):
		var from := int(map.get(str(r), 999))
		if wave >= from:
			top = r
	return top

# 分级配色（用户指定：白/绿/蓝/紫/红/传说）
func tier_color(lv: int) -> Color:
	_load()
	var map: Dictionary = _cfg.get("tier_colors", {})
	var key := str(clampi(lv, 1, max_tier()))
	var hex := str(map.get(key, "#ffffff"))
	return Color(hex)

func tier_name_zh(lv: int) -> String:
	_load()
	var map: Dictionary = _cfg.get("tier_names_zh", {})
	return str(map.get(str(clampi(lv, 1, max_tier())), "Lv%d" % lv))
