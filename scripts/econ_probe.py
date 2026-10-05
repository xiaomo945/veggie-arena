#!/usr/bin/env python3
# =====================================================================
# 金币经济长线诊断（一次性分析脚本，不是发版流程的一部分）
# =====================================================================
#
# 为什么需要它：
#   balance_model.py 的表 C 只跑到玩家死亡那波就停了（典型第 2~5 波），
#   所以"金币花不完"这个问题它天生看不见 —— 表 C 最后一行是
#   "第 5 波 收入 907 / 花费 217 / 持有 3055"，盈余已经 14 倍，但脚本就停这儿了。
#   而玩家抱怨的是第 10~20 波：武器全 6 级、道具买不动了。
#
#   所以这里换一个打法：不管死不死，假设玩家"能活到第 N 波"，
#   把每一波能赚多少金币、当前商店里所有东西一共多少钱都算出来，
#   直接看"购买力总量"这条曲线。三个数：
#     income      本波收入（击杀掉金 + 波次奖励）
#     wallet      假设玩家从不花钱，累积到本波有多少钱
#     catalog     本波商店若把所有商品各买一件，要多少钱（购买力上限）
#   真正的健康线是 income 与 catalog 同阶 —— wallet 疯涨就是"钱多到没处花"。
#
# 公式全部镜像 core/ 与 data/，与 balance_model.py 保持一致的口径。
#
# 用法：python3 scripts/econ_probe.py [--max 30] [--greedy] [--wavelen 60] [--waves 12]
#   --greedy   模拟"贪心玩家"：每波先进账，再把商店按价格从低到高买光为止，
#              看真实花掉多少、还剩多少、武器推到几级 —— 这才是判断"钱有没有去处"的主判据
#   --wavelen  覆盖每波时长（配合 balance.json 的 wave.length 做改前/改后对比）
#   --waves    贪心模式跑多少波（默认跟 balance.json 的 wave.total）
#
# =====================================================================
# 为什么加 --greedy（2026-10-05 经济改造）：
#   上面那张表里第 20 波"收入/购买力 = 21.8x"看着吓人，但它有两个盲区：
#     1) 购买力那列**没乘波次通胀**（漏了 Economy.price_of），实际价格是它的 10 倍；
#     2) 它假设玩家"能 100% 清场"，从不看玩家到底钱花得掉花不掉。
#   所以真正的判据是：一个什么都想买的玩家，跑到第 N 波时**兜里还剩多少**。
#   剩得下两波以上的收入 → 钱确实没去处；剩不到半波 → 经济健康。
# =====================================================================

import json
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)


BAL = load("balance.json")
WPN = load("weapons.json")
ENM = load("enemies.json")
TIERS = load("shop_tiers.json")
UPG = load("upgrades.json")

WEAPONS = WPN.get("weapons", WPN)
ENEMIES = ENM.get("enemies", ENM)
UPGRADES = UPG.get("upgrades", UPG)

WAVE_LEN = float(BAL["wave"]["length"])
WAVE_TOTAL = int(BAL["wave"]["total"])
SPAWN = BAL["spawn"]
ENDLESS = BAL["endless"]
SHOPD = BAL["shop"]
WOK = BAL["wok"]

MAX_SLOT = int(SHOPD["max_slot"])
MAX_LV = int(SHOPD["max_lv"])
BIG_EVERY = int(SHOPD["big_every"])
BIG_N = int(SHOPD["big_offer_count"])
SMALL_N = int(SHOPD["small_offer_count"])
TIER_MULT = float(TIERS["tier_price_mult"])
TIER_FLOOR = TIERS["tier_price_floor"]
MAX_TIER_FOR_WAVE = {int(k): int(v) for k, v in TIERS["weapon_tier_from_wave"].items()}


def price_for_tier(base_cost, lv):
    raw = int(round(float(base_cost) * (TIER_MULT ** (max(1, lv) - 1))))
    return max(raw, int(TIER_FLOOR.get(str(lv), 0)))


def max_tier_for_wave(w):
    best = 1
    for tw, t in sorted(MAX_TIER_FOR_WAVE.items()):
        if w >= tw:
            best = t
    return max(1, min(int(TIERS["max_tier"]), best))


def wave_bonus(w):
    return int(BAL["wave"]["bonus_base"] + BAL["wave"]["bonus_per_wave"] * (w - 1))


def endless_gold_pct(w):
    if w <= WAVE_TOTAL:
        return 1.0
    d = w - WAVE_TOTAL
    return 1.0 + min(ENDLESS["gold_cap"] - 1.0, ENDLESS["gold_per_wave"] * d)


def spawn_rate(w):
    return min(SPAWN["cap"], SPAWN["base_rate"] + SPAWN["per_wave"] * (w - 1))


def pick_type(rng, w):
    """镜像 core/Spawner.pick_type 的权重结构（简化：只算普通怪构成）。"""
    pool = []
    for name, cfg in ENEMIES.items():
        pool.append((name, cfg, 1.0))
    return pool


def count_of_wave(w):
    r = spawn_rate(w)
    return int(r * WAVE_LEN)


def expected_gold_per_spawn(w, rng):
    """按当前波的怪种构成估算一次刷怪的期望金币。"""
    # 种类权重来自 spawn 配置里的 *_chance
    chances = {
        "fast": SPAWN["fast_chance"] if w >= SPAWN["fast_from_wave"] else 0.0,
        "tank": SPAWN["tank_chance"] if w >= SPAWN["tank_from_wave"] else 0.0,
        "fly": SPAWN["fly_chance"] if w >= SPAWN["fly_from_wave"] else 0.0,
        "swarm": SPAWN["swarm_chance"] if w >= SPAWN["swarm_from_wave"] else 0.0,
        "brute": SPAWN["brute_chance"] if w >= SPAWN["brute_from_wave"] else 0.0,
        "shambler": SPAWN["shambler_chance"] if w >= SPAWN["shambler_from_wave"] else 0.0,
        "shooter": SPAWN["shooter_chance"] if w >= SPAWN["shooter_from_wave"] else 0.0,
        "charger": SPAWN["charger_chance"] if w >= SPAWN["charger_from_wave"] else 0.0,
        "splitter": SPAWN["splitter_chance"] if w >= SPAWN["splitter_from_wave"] else 0.0,
        "bomber": SPAWN["bomber_chance"] if w >= SPAWN["bomber_from_wave"] else 0.0,
    }
    boss_every = int(SPAWN["boss_every"])
    boss_mult = float(SPAWN["boss_rate_mult"])
    total = 1.0 + sum(chances.values())
    exp = float(ENEMIES["grunt"].get("gold", 2))
    for k, c in chances.items():
        exp += c / total * (float(ENEMIES[k].get("gold", 2)) - float(ENEMIES["grunt"].get("gold", 2)))
    # boss：每 boss_every 波一次，频率再乘 boss_rate_mult
    if boss_every > 0 and w % boss_every == 0:
        exp += float(ENEMIES["boss"].get("gold", 40)) * boss_mult / max(1.0, total)
    return exp


def catalog_cost(w, rng, n_slots=MAX_SLOT):
    """本波商店若把 n 张卡全买下来要多少钱（按当前波能出的最高档位估）。"""
    mt = max_tier_for_wave(w)
    n = BIG_N if w % BIG_EVERY == 0 else SMALL_N
    costs = []
    for _ in range(n):
        # 档位按权重抽（简化：均匀取 1..mt，因为玩家想要的是"贵的那档"）
        lv = rng.randint(1, mt)
        # 底价取该档位下的中位武器价
        bases = sorted(float(v.get("cost", 20)) for v in WEAPONS.values())
        base = bases[min(len(bases) - 1, int(len(bases) * 0.5))]
        costs.append(price_for_tier(base, lv))
    # 道具（passive 类）价格区间
    ups = sorted(float(v.get("cost", 10)) for v in UPGRADES.values())
    med_up = ups[len(ups) // 2]
    return sum(costs) + med_up * n


# ---------------------------------------------------------------------
# 贪心模拟：真实 Implement=I Economy.price_of / ShopPlan.offer_count / Inventory 合成规则
# ---------------------------------------------------------------------

INFL = float(SHOPD["price_inflation"])
BIG_DISCOUNT = float(SHOPD["big_discount_pct"])
RARITY_WEIGHT = {1: 6.0, 2: 3.0, 3: 1.0}
WEAPON_WEIGHT = 4.0
TIER_WEIGHT = {int(k): float(v) for k, v in TIERS["weapon_tier_weight"].items()}
RARITY_FROM_WAVE = {int(k): int(v) for k, v in TIERS["upgrade_rarity_from_wave"].items()}


def inflation_mult(w):
    if INFL <= 0.0 or w <= 1:
        return 1.0
    return 1.0 + float(w - 1) * INFL


def shop_discount(w):
    return BIG_DISCOUNT if (w <= 1 or w % BIG_EVERY == 0) else 0.0


def price_of(base, w):
    """镜像 core/Economy.price_of：先叠波次通胀，再打折，最后取整（≥1）。"""
    p = float(base) * inflation_mult(w)
    d = shop_discount(w)
    if d > 0.0:
        p *= (1.0 - d)
    return max(1, int(round(p)))


def max_rarity_for_wave(w):
    top = 1
    for r in (1, 2, 3):
        if w >= int(RARITY_FROM_WAVE.get(r, 999)):
            top = r
    return top


def build_build(rng, n=MAX_SLOT):
    """挑 n 把代表武器（取成本中位数附近的，不吃极端贵/极端便宜的偏差）。"""
    items = sorted(WEAPONS.items(), key=lambda kv: float(kv[1].get("cost", 20)))
    mid = len(items) // 2
    lo = max(0, mid - n // 2)
    return [(k, v) for k, v in items[lo:lo + n]]


def offers_for_wave(state, w, rng, max_lv):
    """镜像 Economy.build_pool + Economy.roll_offers：
   武器按"持有等级"刷可买的档位，道具按稀有度门禁 + 权重抽，
   且保底塞 1 张最高等级的"合成搭档"（没有它玩家永远合不出下一档）。"""
    n = BIG_N if (w <= 1 or w % BIG_EVERY == 0) else SMALL_N
    max_rar = max_rarity_for_wave(w)

    # 武器候选：已持有 L 级 → 刷 L 级（买下即合成 L+1）；槽位没满时才给新武器
    wp = []
    for key, lv in state["weapons"].items():
        if lv >= max_lv:
            continue
        wp.append({"kind": "weapon", "key": key, "lv": lv,
                   "base": price_for_tier(float(WEAPONS[key].get("cost", 20)), lv),
                   "partner": True})
    if len(state["weapons"]) < MAX_SLOT:
        for key, cfg in WEAPONS.items():
            if key in state["weapons"]:
                continue
            wp.append({"kind": "weapon", "key": key, "lv": 1, "fresh": True,
                       "base": price_for_tier(float(cfg.get("cost", 20)), 1)})

    # 道具候选：按稀有度门禁 + 权重
    up = []
    for key, cfg in UPGRADES.items():
        rar = int(cfg.get("rarity", 1))
        if rar > max_rar:
            continue
        up.append({"kind": "upgrade", "key": key,
                   "base": float(cfg.get("cost", 10)),
                   "wt": RARITY_WEIGHT.get(rar, 3.0)})

    def card(o):
        c = dict(o)
        c["cost"] = price_of(c["base"], w)
        return c

    out = []
    # 保底 1 张"买得起的最高档"搭档：镜像 core/Economy.partner_score。
    #   旧行为是无脑给最高档，结果后期每张店都被一张几万的卡占着买不动 → 金币越攒越多。
    partners = [o for o in wp if o.get("partner")]
    if partners:
        gold = state["gold"]

        def score(o):
            c = price_of(o["base"], w)
            if c <= gold:
                return 1000000 + o["lv"] * 1000
            return -c

        best = max(partners, key=score)
        out.append(card(best))
        wp.remove(best)
    quota = max(0, min(2, len(wp) + 1) - 1)
    for _ in range(quota):
        if not wp:
            break
        pick = rng.choice(wp)
        out.append(card(pick))
        wp.remove(pick)
    # 其余名额：从"剩下的武器 + 全部道具"里按权重抽（镜像 Economy._weighted_pick）
    rest = wp + up

    def wt(o):
        if o["kind"] == "weapon":
            return WEAPON_WEIGHT * TIER_WEIGHT.get(int(o["lv"]), 1.0)
        return o.get("wt", 3.0)

    while len(out) < n and rest:
        total = sum(wt(o) for o in rest)
        r = rng.random() * total
        pick = rest[0]
        for idx, o in enumerate(rest):
            r -= wt(o)
            if r <= 0.0:
                pick = o
                break
        out.append(card(pick))
        rest.remove(pick)
    return out


def greedy_run(max_w, rng, wave_len, max_lv, verbose=True):
    state = {"weapons": {}, "gold": 0, "spent": 0, "upgrades": 0}
    rows = []
    total_income = 0
    for w in range(1, max_w + 1):
        n_spawn = int(spawn_rate(w) * wave_len)
        income = int(n_spawn * expected_gold_per_spawn(w, rng) * endless_gold_pct(w)) + wave_bonus(w)
        state["gold"] += income
        total_income += income

        offers = offers_for_wave(state, w, rng, max_lv)
        # 贪心：便宜的先买，买到买不动为止 —— 这代表"最能花钱"的玩家上限
        offers.sort(key=lambda o: o["cost"])
        bought = 0
        wave_spent = 0
        for o in offers:
            if state["gold"] < o["cost"]:
                continue
            state["gold"] -= o["cost"]
            wave_spent += o["cost"]
            bought += 1
            if o["kind"] == "weapon":
                if o["key"] in state["weapons"]:
                    state["weapons"][o["key"]] = o["lv"] + 1   # 合成 +1
                elif len(state["weapons"]) < MAX_SLOT:
                    state["weapons"][o["key"]] = 1
            else:
                state["upgrades"] += 1
        lvls = sorted(state["weapons"].values())
        top = lvls[-1] if lvls else 0
        rows.append((w, income, wave_spent, state["gold"], top, len(state["weapons"]), bought,
                     len(offers)))
        if verbose:
            print("  %2d  收入%6d   本波花%6d   结余%7d   武器 %d 把 最高Lv%-2d   买 %d/%d 张"
                  % (w, income, wave_spent, state["gold"], len(state["weapons"]), top,
                     bought, len(offers)))
    return rows, state, total_income


def main_greedy(args):
    max_w = WAVE_TOTAL
    if "--waves" in args:
        max_w = int(args[args.index("--waves") + 1])
    wave_len = WAVE_LEN
    if "--wavelen" in args:
        wave_len = float(args[args.index("--wavelen") + 1])
    max_lv = MAX_LV
    if "--maxlv" in args:
        max_lv = int(args[args.index("--maxlv") + 1])
    if "--infl" in args:
        globals()["INFL"] = float(args[args.index("--infl") + 1])
    rng = random.Random(11)

    print("=" * 78)
    print("贪心模拟：每波先把商店从便宜到贵买光（代表最能花钱的玩家）")
    print("  波数上限 %d   每波 %.0fs   武器等级上限 %d   通胀 %.2f/波"
          % (max_w, wave_len, max_lv, INFL))
    print("=" * 78)
    print("  波   本波收入   本波花销    结余金币   持有武器   买到几张")
    print("  " + "-" * 68)
    rows, st, total_income = greedy_run(max_w, rng, wave_len, max_lv)

    print()
    print("=" * 78)
    print("关键读数")
    print("=" * 78)
    print("  总进账 %d   总花销 %d   兜里还剩 %d（占 %.0f%%）"
          % (total_income, sum(r[2] for r in rows), st["gold"],
             100.0 * st["gold"] / max(1, total_income)))
    last = rows[-1]
    print("  终局：%d 把武器，最高 Lv%d，等级分布 %s" % (len(st["weapons"]), last[4],
                                                 sorted(st["weapons"].values(), reverse=True)))
    print("  最后 3 波平均能买几张（商店越到后期越买不动=挡位深）：%.1f/%d"
          % (sum(r[6] for r in rows[-3:]) / 3.0, rows[-1][7]))
    print()
    print("  → 结余占比 >40% ：钱明显没去处（玩家会感到金币过剩）")
    print("  → 结余占比 10~25%：健康 —— 花得掉，但每波仍有取舍")
    print("  → 结余占比 <10% 且武器已顶到等级上限：钱坑反倒卡住了成长")


def main():
    args = sys.argv[1:]
    if "--greedy" in args:
        main_greedy(args)
        return
    max_w = 30
    if "--max" in args:
        max_w = int(args[args.index("--max") + 1])
    rng = random.Random(7)

    print("=" * 78)
    print("金币经济长线诊断（假设玩家能活到第 N 波）")
    print("=" * 78)
    print()
    print("  波   刷出数  期望金/只   本波收入   商店全买要   纯攒钱    收入/购买力")
    print("  " + "-" * 72)

    wallet = 0
    rows = []
    for w in range(1, max_w + 1):
        n_spawn = count_of_wave(w)
        g_per = expected_gold_per_spawn(w, rng)
        gp = endless_gold_pct(w)
        # 玩家击杀率：假设能清掉大部分（真实清场率受 DPS 限制，这里放开上限）
        income = int(n_spawn * g_per * gp) + wave_bonus(w)
        wallet += income
        cat = catalog_cost(w, rng)
        ratio = income / cat if cat else 0
        rows.append((w, n_spawn, g_per, income, cat, wallet, ratio))
        print("  %2d   %5d   %7.1f   %8d   %9d   %8d   %8.1fx"
              % (w, n_spawn, g_per, income, cat, wallet, ratio))

    print()
    print("=" * 78)
    print("关键读数")
    print("=" * 78)
    w1, _, _, inc1, cat1, wal1, r1 = rows[0]
    w10 = rows[9] if len(rows) >= 10 else rows[-1]
    w20 = rows[19] if len(rows) >= 20 else rows[-1]
    print("  第 1 波：收入 %d，购买力 %d，比值 %.1fx" % (inc1, cat1, r1))
    print("  第 10 波：收入 %d，购买力 %d，比值 %.1fx，纯攒钱 %d" % (w10[3], w10[4], w10[6], w10[5]))
    print("  第 20 波：收入 %d，购买力 %d，比值 %.1fx，纯攒钱 %d" % (w20[3], w20[4], w20[6], w20[5]))
    print()
    print("  → 比值 <1 表示：这波赚的钱买不起本波商店的全部东西（购买力健康）")
    print("  → 比值 >1 表示：钱开始溢出，早晚花不完")
    print("  → 纯攒钱是上界：玩家就算什么都不买，钱也在滚雪球")
    print()

    # 满级武器的总花费
    print("  满级成本：6 把武器全 6 级")
    mid = sorted(float(v.get("cost", 20)) for v in WEAPONS.values())[len(WEAPONS) // 2]
    tot = sum(price_for_tier(mid, lv) for lv in range(1, MAX_LV + 1))
    print("    单把 1→6 级：%s = %d" % (" + ".join(str(price_for_tier(mid, lv)) for lv in range(1, 7)), tot))
    print("    6 把全满：%d 金币" % (tot * 6))
    print("    136 个道具单价区间：%d ~ %d" % (
        min(int(v.get("cost", 0)) for v in UPGRADES.values()),
        max(int(v.get("cost", 0)) for v in UPGRADES.values())))
    print("    道具全部买一遍：%d 金币" % sum(int(v.get("cost", 0)) for v in UPGRADES.values()))


if __name__ == "__main__":
    main()
