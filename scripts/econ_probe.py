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
# 用法：python3 scripts/econ_probe.py [--max 30] [--greedy]
#   --greedy  模拟"贪心玩家"：每波把钱花到买不了为止，看真实spent

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


def main():
    args = sys.argv[1:]
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
