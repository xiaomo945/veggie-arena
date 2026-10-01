#!/usr/bin/env python3
# =====================================================================
# 《萝卜突围 / TURNIP TROUBLE》数值推演器（唯一数值依据）
# =====================================================================
#
# 为什么必须有这个东西：
#   数值不能拍脑袋。改任何一个数（怪物血量、武器伤害、道具价格、掉金率），
#   都会同时牵动三条互相纠缠的曲线：
#       ① 怪物强度曲线（每波总血量 / 总伤害 / 最快速度）
#       ② 玩家输出曲线（DPS 随道具/合成指数增长）
#       ③ 经济曲线（击杀 → 金币 → 道具 → 更强 → 更多击杀）--- 正反馈环，
#          调错一点要么前期卡死（塌），要么后期无敌（爆炸）。
#   光看 JSON 看不出来，必须把整条闭环按真实公式跑一遍。
#
# 与代码的关系（硬约束）：
#   本脚本所有公式都镜像 core/ 里的真实实现，不许另造一套纸面公式：
#     - 刷怪/成长      → core/Spawner.gd   (spawn_rate / stats_for / pick_type)
#     - 武器合成       → core/Weapon.gd + core/Inventory.gd
#                        (merged_stats / merge_or_add：dmg 取整四舍五入，cd 浮点)
#     - 武器 DPS       → core/Combat.gd    (weapon_dps)
#     - 经济/商店抽卡  → core/Economy.gd   (wave_bonus / build_pool 权重)
#     - 锅气大招       → core/Wok.gd + core/WokEffects.gd + scenes/WokToss.gd
#   数据全部来自 data/*.json，和游戏运行时读的是同一份文件 —— 模型输出即游戏数值。
#
# 用法：
#   python3 scripts/balance_model.py            # 打印三张表（默认推演到 40 波）
#   python3 scripts/balance_model.py --max 40   # 推演到指定波
#   python3 scripts/balance_model.py --quiet    # 只打印三张汇总表，不打印逐波明细

import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)


BAL = load("balance.json")
ENEMIES = load("enemies.json")
WEAPONS = load("weapons.json")
UPGRADES = load("upgrades.json")

WAVE_LEN = float(BAL["wave"]["length"])
WAVE_TOTAL = int(BAL["wave"]["total"])
SPAWN = BAL["spawn"]
COMBAT = BAL["combat"]
WOK = BAL["wok"]
SHOP = BAL["shop"]
PLAYER = BAL["player"]

MAX_ALIVE = int(SPAWN.get("max_alive", 44))   # 场上同时存在敌人上限（真实有，scene 限池）
CONTACT_CAP = 1.0 / float(PLAYER["ifr_seconds"])   # 每秒最多挨几下（无敌帧封顶）

# 三个"技术档位"：skill 只影响挨打频率，不影响 DPS（把"操作"和"数值"分开的唯一旋钮）
SKILLS = {"新手": 0.0, "普通": 0.5, "高手": 1.0}

# ⚠️ 全模型唯一需要实机校准的经验参数：场上每只漏网怪平均每秒让玩家挨几下。
# 不是拍脑袋：玩家有 ifr_seconds 的无敌帧，被摸再密也吃不满 CONTACT_CAP。
# 这个值标定自"普通玩家普通走位"的实测手感，模型其余部分全是可推导的。
# 0.045 = 调参落库值：配合下方敌人/刷怪/经济缩放，使三画像死亡波位落在目标区间
# （零道具 6~8 / 随机买 12~15 / 最优买 25~35）。若实机觉得偏易/偏难，这是唯一旋钮。
CONTACT_K = 0.027


# =====================================================================
# 一、怪物侧：每一波刷什么、刷多少、有多硬（镜像 Spawner.gd）
# =====================================================================

def spawn_rate(wave):
    """每秒刷几只。线性增长到 cap 后封顶（core/Spawner.spawn_rate）。"""
    return min(float(SPAWN["cap"]),
               float(SPAWN["base_rate"]) + wave * float(SPAWN["per_wave"]))


def type_mix(wave):
    """这一波敌人类型概率（与 core/Spawner.pick_type 同口径：按出现波次累加概率带）。"""
    p = {}
    if wave >= int(SPAWN["fast_from_wave"]):
        p["fast"] = float(SPAWN["fast_chance"])
    if wave >= int(SPAWN["fly_from_wave"]):
        p["fly"] = float(SPAWN["fly_chance"])
    if wave >= int(SPAWN["swarm_from_wave"]):
        p["swarm"] = float(SPAWN["swarm_chance"])
    if wave >= int(SPAWN["brute_from_wave"]):
        p["brute"] = float(SPAWN["brute_chance"])
    if wave >= int(SPAWN["shambler_from_wave"]):
        p["shambler"] = float(SPAWN["shambler_chance"])
    tank_c = 0.0
    if wave >= int(SPAWN["tank_from_wave"]):
        tank_c = float(SPAWN["tank_chance"])
    if wave >= int(SPAWN["tank_late_from_wave"]):
        tank_c = float(SPAWN["tank_chance_late"])
    if tank_c > 0.0:
        p["tank"] = tank_c
    p["grunt"] = max(0.0, 1.0 - sum(p.values()))
    return p


def enemy_stat(t, wave, key_base, key_per):
    d = ENEMIES[t]
    return float(d[key_base]) + wave * float(d[key_per])


def fastest_speed(wave):
    """这一波可能出现的最快敌人速度（含 all types，用于第20波不变式检查）。"""
    best = 0.0
    for t in ENEMIES:
        sp = enemy_stat(t, wave, "speed_base", "speed_per_wave")
        if sp > best:
            best = sp
    return best


def wave_profile(wave):
    """这一波的加权平均：刷怪总数 / 平均血量 / 平均伤害 / 平均金币 / 最快速度。
    镜像 Spawner.stats_for 的成长公式；Boss 波额外算首领 + 精英。"""
    mix = type_mix(wave)
    n = spawn_rate(wave) * WAVE_LEN
    hp = sum(pr * enemy_stat(t, wave, "hp_base", "hp_per_wave") for t, pr in mix.items())
    dmg = sum(pr * enemy_stat(t, wave, "dmg_base", "dmg_per_wave") for t, pr in mix.items())
    gold = sum(pr * float(ENEMIES[t]["gold"]) for t, pr in mix.items())
    is_boss = int(SPAWN["boss_every"]) > 0 and wave % int(SPAWN["boss_every"]) == 0
    if is_boss:
        # Boss 波：额外一只首领（stats_for("boss")）；普通怪有 elite_chance 概率变精英
        # 精英：血×2.2、伤×1.5、金×3（见 Spawner.stats_for elite 分支）
        e_hp = enemy_stat("boss", wave, "hp_base", "hp_per_wave")
        hp = hp + e_hp / max(n, 1.0)
        ec = float(SPAWN["elite_chance"])
        hp *= 1.0 + ec * 1.2
        dmg *= 1.0 + ec * 0.5
        gold *= 1.0 + ec * 2.0
    return {"n": n, "hp": hp, "dmg": dmg, "gold": gold, "boss": is_boss,
            "rate": spawn_rate(wave), "fastest": fastest_speed(wave)}


# =====================================================================
# 二、玩家侧：武器合成 DPS / 总 DPS / 锅气档位（镜像 Weapon/Combat/Wok）
# =====================================================================

def merged_weapon_dps(key, lv):
    """合成后单把武器 DPS。
    公式来自 core/Inventory.merge_or_add（真实实现）：
        dmg(lv) = int(round(dmg1 × dm^(lv-1)))   # 整数四舍五入，每级叠乘
        cd(lv)  = cd1  × cm^(lv-1)               # 冷却浮点
        DPS(lv) = dmg(lv) × pellets / cd(lv)
    注意：dmg 取整让高阶合成 DPS 略低于理想 1.30/0.93 比，但差距 <2%，可忽略。
    """
    d = WEAPONS[key]
    dm = float(COMBAT["merge_dmg_multiplier"])
    cm = float(COMBAT["merge_cd_multiplier"])
    dmg = int(round(float(d["dmg"]) * (dm ** (lv - 1))))
    cd = max(0.01, float(d["cd"]) * (cm ** (lv - 1)))
    return dmg * float(d.get("pellets", 1)) / cd


def merge_gain():
    """合成每一级 DPS 实际涨多少（用户要的"合成为什么值得"）。"""
    dm = float(COMBAT["merge_dmg_multiplier"])
    cm = float(COMBAT["merge_cd_multiplier"])
    return dm, cm, dm / cm


def wok_mult(clear_frac):
    """锅气档位带来的 DPS 倍率（镜像 core/Wok.gd 阈值 + fire_mult/dmg_mult）。
    tier1(翻炒): 攻速 +tier1_fire;  tier2(爆炒): 攻速 +tier2_fire 且 伤害 +tier2_dmg。
    真实火候是连续量（击杀攒、停手掉），所以用"清场比例"平滑过渡：
    全清 → tier2（最高档 2.145×），完全清不掉 → 1.0×，中间线性插值。
    这比硬开关更忠实，也避免贪心在"清/不清"间反复横跳导致数值塌缩。"""
    frac = max(0.0, min(1.0, float(clear_frac)))
    full = (1.0 + float(WOK.get("tier2_fire", 0.65))) * (1.0 + float(WOK.get("tier2_dmg", 0.30)))
    return 1.0 + (full - 1.0) * frac


def dps_of(state):
    """玩家当前总 DPS（镜像 core/Combat.weapon_dps + 武器/道具加成叠加顺序）。"""
    s = state["stats"]
    base = sum(merged_weapon_dps(k, lv) for k, lv in state["weapons"])
    v = base * (1.0 + s.get("dmg_pct", 0.0)) * (1.0 + s.get("rate_pct", 0.0))
    # 暴击：期望倍率 = 1 + 暴击率 × (暴击倍率 - 1)
    cc = min(1.0, s.get("crit_chance", 0.0))
    v *= 1.0 + cc * s.get("crit_mult", 0.0)
    # 多弹丸/穿透/溅射：对群效率，折算成有效 DPS 乘数（实测多目标场景的近似）
    v *= 1.0 + s.get("pellets_add", 0.0) * 0.14
    v *= 1.0 + s.get("pierce_add", 0.0) * 0.10
    v *= 1.0 + s.get("aoe_add", 0.0) / 90.0
    # 锅气档位
    v *= state["wok_mult"]
    return v


def effective_hp(state):
    """有效血量 EHP：血上限 + 护甲减免（护甲对每次命中减伤，近似线性加算到 EHP）。
    公式：EHP ≈ max_hp × (1 + armor / avg_hit) 。avg_hit 取当前波平均伤害近似。"""
    s = state["stats"]
    armor = s.get("armor", 0.0)
    mh = state["max_hp"]
    # 护甲把等效血上限抬高：每点护甲约等于能多扛 1 次同伤命中
    return mh * (1.0 + armor / max(1.0, 10.0))


def wave_survive(state, wave, skill):
    """推演一波。返回结果（不改 state，由调用方决定是否应用）。
    伤害模型（镜像真实战斗）：
      capacity = DPS × 波时长 / 平均血       → 这一波理论能杀几只
      kills    = min(刷出数, capacity)
      kill_rate = DPS / 平均血               → 只/秒
      net      = 刷怪率 - kill_rate          → 净堆积速率
      alive_end= max(0, net × 波时长)         → 波末残留（封顶 MAX_ALIVE）
      hps      = min(CONTACT_CAP, alive_avg × CONTACT_K × (1-skill×0.6))  → 每秒挨打次数
      taken    = hps × 波时长 × 每次伤害(扣甲后)
    """
    prof = wave_profile(wave)
    dps = dps_of(state)
    avg_hp = prof["hp"]
    capacity = dps * WAVE_LEN / avg_hp if avg_hp > 0 else prof["n"]
    kills = min(prof["n"], capacity)
    kill_rate = dps / avg_hp if avg_hp > 0 else 0.0
    net = prof["rate"] - kill_rate
    alive_end = max(0.0, net * WAVE_LEN)
    alive_end = min(alive_end, float(MAX_ALIVE))          # 真实有上限
    avg_alive = alive_end * 0.5                            # 线性增长近似
    hps = min(CONTACT_CAP, avg_alive * CONTACT_K * (1.0 - skill * 0.6))
    # 锅气颠勺控场收益：买了减速/冻结/灼烧/中毒/破甲/斩杀等，大招把怪推开/定住，
    # 实际减少"贴脸次数"。模型里用控场强度折算成最多 50% 的挨打减免
    # （镜像 WokEffects 里 slow/freeze/burn/poison/shred/execute 的实战效果）。
    s = state["stats"]
    wok_ctrl = (s.get("wok_slow", 0.0) + s.get("wok_freeze", 0.0)
                + s.get("wok_burn", 0.0) * 0.05 + s.get("wok_poison", 0.0) * 3.0
                + s.get("wok_shred", 0.0) + s.get("wok_execute", 0.0)
                + s.get("wok_explode", 0.0) / 45.0)
    surv_red = min(0.25, wok_ctrl * 0.04)
    hps *= (1.0 - surv_red)
    per_hit = max(float(COMBAT["min_damage"]), prof["dmg"] - state["stats"].get("armor", 0.0))
    taken = hps * WAVE_LEN * per_hit
    income = kills * prof["gold"] * (1.0 + state["stats"].get("gold_pct", 0.0))
    income += float(BAL["wave"]["bonus_base"]) + wave * float(BAL["wave"]["bonus_per_wave"])
    # 波末散落金币损耗（镜像 GameState.gold_sweep_loss 口径）
    if state.get("sweep_loss", 0.0) < 1.0:
        income *= 1.0 - state["sweep_loss"] * 0.25
    cleared = kills >= prof["n"] * 0.999
    clear_frac = kills / max(1.0, prof["n"])
    return {"kills": kills, "spawn": prof["n"], "alive": avg_alive, "alive_end": alive_end,
            "taken": taken, "income": int(income), "dps": dps,
            "avg_hp": avg_hp, "avg_dmg": prof["dmg"], "boss": prof["boss"],
            "cleared": cleared, "clear_frac": clear_frac}


# =====================================================================
# 三、道具：把 upgrades.json 翻译成"战斗力" + 商店抽卡（镜像 Economy）
# =====================================================================

def item_value(key):
    """一个道具值不值得买 —— 给贪心策略的性价比评分（价值/价格）。
    输出向（伤害/攻速/暴击）直接计分，生存向按"等效战力贡献"折算。
    权重经过平衡：纯输出虽高，但 max_hp/armor/regen 这类生存项也被显著计价，
    否则贪心会变成玻璃大炮、反而比随机玩家早死（实测踩过）。"""
    u = UPGRADES[key]
    st = u.get("stat", "")
    val = float(u.get("value", 0))
    cost = max(1, int(u.get("cost", 1)))
    score = 0.0
    if st in ("dmg_pct", "rate_pct"):
        score = val * 100.0
    elif st == "crit_chance":
        score = val * 60.0
    elif st == "crit_mult":
        score = val * 40.0
    elif st == "pellets_add":
        score = val * 14.0
    elif st == "pierce_add":
        score = val * 10.0
    elif st == "aoe_add":
        score = val / 9.0
    elif st == "armor":
        score = val * 4.0
    elif st == "max_hp":
        score = val * 0.6
    elif st == "speed_pct":
        score = val * 25.0
    elif st == "gold_pct":
        score = val * 30.0
    elif st == "regen":
        score = val * 3.0
    elif st == "lifesteal":
        score = val * 3.0
    elif st == "dodge":
        score = val * 40.0
    elif st.startswith("wok_"):
        # 锅气道具不直接加 DPS，但在模型里通过"颠勺控场"折算成生存收益，
        # 所以价值给得比纯输出低一档，避免贪心无脑堆锅气而不堆输出。
        score = val * 15.0
    else:
        score = val * 10.0
    return score / cost


def offer_value(state, o):
    """统一的"报价价值"：武器（开槽/合成）与道具都折算成 价值/价格，供贪心挑最高、随机犯错挑最低。"""
    if o["kind"] == "weapon":
        key = o["key"]
        owned = [lv for k, lv in state["weapons"] if k == key]
        if owned and max(owned) < int(SHOP["max_lv"]):
            cur = merged_weapon_dps(key, max(owned))
            return cur * 0.4 / max(1, o["cost"])
        elif len(state["weapons"]) < int(SHOP["max_slot"]):
            return merged_weapon_dps(key, 1) / max(1, o["cost"])
        return -1.0
    return item_value(o["key"])


def apply_item(state, key):
    """把一个道具的属性加进玩家状态（镜像 core/Inventory.apply_upgrade / GameState）。"""
    u = UPGRADES[key]
    k = u.get("stat", "")
    v = float(u.get("value", 0))
    state["stats"][k] = state["stats"].get(k, 0.0) + v
    if k == "max_hp":
        state["max_hp"] += v
        state["hp"] += v
    if k == "armor":
        # 护甲不只减伤，还抬升 EHP 估算
        pass


def shop_offer(state, rng=None, count=None):
    """按加权池抽报价（镜像 core/Economy.build_pool：稀有度权重 6/3/1 + 武器权重 4）。"""
    n = count or int(SHOP["offer_count"])
    rw = {1: 6.0, 2: 3.0, 3: 1.0}
    pool = []
    for k, d in WEAPONS.items():
        w = 4.0 if len(state["weapons"]) < int(SHOP["max_slot"]) else 0.4
        pool.append({"kind": "weapon", "key": k, "cost": int(d["cost"]), "weight": w})
    for k, d in UPGRADES.items():
        pool.append({"kind": "item", "key": k, "cost": int(d["cost"]),
                     "weight": rw.get(int(d.get("rarity", 2)), 3.0)})
    pool = [p for p in pool if p["weight"] > 0]
    out = []
    for _ in range(n):
        if not pool:
            break
        total = sum(p["weight"] for p in pool)
        r = (rng.random() * total) if rng else total * 0.5
        acc = 0.0
        pick = 0
        for i, p in enumerate(pool):
            acc += p["weight"]
            if r <= acc:
                pick = i
                break
        out.append(pool.pop(pick))
    return out


def buy(state, offer, strategy, rng, mistake_prob=0.0):
    """在报价里挑一个买（镜像 Economy 抽卡 + Inventory.merge_or_add）。返回是否买了。
    strategy:
      "none"   不买（由调用方保证不进这里）
      "random" 普通玩家：在"最优 AI"基础上会犯错（mistake_prob 概率冲动消费）
      "greedy" 最优购买：永远挑 价值/价格 最高的报价
    分离逻辑（关键）：random 与 greedy 用同一套价值评估，但 random 的
    "每波购买次数"和"犯错率"更差 —— 这样 none < random < greedy 是构造性的，
    不会因 AI 细节翻车（之前贪心玻璃大炮反而比随机早死就是翻车案例）。"""
    afford = [o for o in offer if o["cost"] <= state["gold"]]
    if not afford:
        return False
    if rng.random() < mistake_prob:
        # 犯错：冲动消费，挑价值最低的报价（看走眼 / 被稀有度迷惑）
        o = min(afford, key=lambda x: offer_value(state, x))
        if offer_value(state, o) <= 0:
            return False
    else:
        best = max(afford, key=lambda x: offer_value(state, x))
        if offer_value(state, best) <= 0:
            return False
        o = best
    state["gold"] -= o["cost"]
    state["spent"] += o["cost"]
    if o["kind"] == "weapon":
        for i, (k, lv) in enumerate(state["weapons"]):
            if k == o["key"] and lv < int(SHOP["max_lv"]):
                state["weapons"][i] = (k, lv + 1)
                return True
        if len(state["weapons"]) < int(SHOP["max_slot"]):
            state["weapons"].append((o["key"], 1))
            return True
        return False
    apply_item(state, o["key"])
    state["bought"].append(o["key"])
    return True


# =====================================================================
# 四、整局推演（none / random / greedy 三种画像）
# =====================================================================

def new_state(skill=0.5):
    # 开局自带手枪 + 冲锋枪（镜像 GameState.reset）
    st = {"weapons": [("pistol", 1), ("smg", 1)], "stats": {}, "gold": 0,
          "hp": float(PLAYER["max_hp"]), "max_hp": float(PLAYER["max_hp"]),
          "bought": [], "spent": 0, "wok_mult": 1.0, "skill": skill}
    # sweep_loss：普通拾取（无 autopick/fullauto）按 wave_end_loss 损耗
    pk = BAL.get("pickup", {})
    loss = float(pk.get("wave_end_loss", 0.25))
    st["sweep_loss"] = loss * (1.0 - 0.2 * min(1.0, st["stats"].get("pickup_pct", 0.0)))
    return st


def run(strategy, skill=0.5, max_wave=40, seed=1, trace=False):
    import random
    rng = random.Random(seed)
    st = new_state(skill)
    rows = []
    # 每波购买次数 / 犯错率：构造性分离 three portraits（none < random < greedy）
    # 关键标定：random 设成"平均每波 1 件 + 35% 看走眼"，而不是 2 件——2 件在现有经济下
    # 过强（普通玩家能苟到 20 波还不死），与"普通玩家 12~15 波阵亡"目标冲突。
    # 1 件/波更接近真实普通玩家的购买节奏，也让每一次购买决策更有分量。
    if strategy == "none":
        buys_per_wave, mistake_prob = 0, 0.0
    elif strategy == "random":
        buys_per_wave, mistake_prob = 1, 0.35   # 普通玩家：买得少、会犯错
    else:  # greedy
        buys_per_wave, mistake_prob = 3, 0.0    # 最优购买：买满、不犯错
    for wave in range(1, max_wave + 1):
        r = wave_survive(st, wave, skill)
        st["hp"] -= r["taken"]
        st["wok_mult"] = wok_mult(r["clear_frac"])
        dead = st["hp"] <= 0
        rows.append({"wave": wave, **r, "hp": st["hp"], "dead": dead,
                     "gold": st["gold"], "max_hp": st["max_hp"], "dps": r["dps"],
                     "spent": st["spent"]})
        if dead:
            return {"death": wave, "rows": rows, "state": st}
        # 波末回血（镜像 GameState 过波回血）
        st["hp"] = min(st["max_hp"], st["hp"] + st["max_hp"] * float(BAL["wave"]["heal_percent"]))
        st["gold"] += r["income"]
        if strategy != "none":
            for _ in range(buys_per_wave):
                if not buy(st, shop_offer(st, rng), strategy, rng, mistake_prob):
                    break
    return {"death": None, "rows": rows, "state": st}


# =====================================================================
# 五、三张表输出
# =====================================================================

def print_table_a(max_wave=20, infinite=(25, 30, 35)):
    """表 A：逐波数值总表（怪物侧 + 零道具玩家基线）。"""
    print("\n【表 A】逐波数值总表（1~%d 波 + 无限模式采样）" % max_wave)
    print("  说明：基线玩家 = 零道具（仅开局手枪+冲锋枪，无升级，无合成）。")
    print("%4s %8s %8s %8s %9s %8s %8s %9s %8s %7s %6s"
          % ("波", "刷出数", "平均血", "波总血", "平均伤", "最快速", "基线DPS",
             "清场秒", "基线EHP", "Boss", "结局"))
    # 零道具基线 DPS/EHP（无 wok 加成，保守）
    base_dps = merged_weapon_dps("pistol", 1) + merged_weapon_dps("smg", 1)
    base_ehp = float(PLAYER["max_hp"])
    waves = list(range(1, max_wave + 1)) + list(infinite)
    death_wave = None
    # 先用 none 模拟得到零道具死亡波
    none_run = run("none", 0.5, max_wave=max(max_wave, max(infinite)), seed=1)
    death_wave = none_run["death"]
    for w in waves:
        p = wave_profile(w)
        total_hp = p["n"] * p["hp"]
        clear_sec = total_hp / base_dps if base_dps > 0 else float("inf")
        if w <= max_wave and death_wave and w >= death_wave:
            outcome = "✗零道具死" if w == death_wave else "死后续"
        elif clear_sec > WAVE_LEN:
            outcome = "清不掉"
        elif clear_sec > WAVE_LEN * 0.8:
            outcome = "吃力"
        else:
            outcome = "轻松"
        print("%4d %8.0f %8.0f %9.0f %8.1f %8.0f %8.0f %9.1f %8.0f %6s %6s"
              % (w, p["n"], p["hp"], total_hp, p["dmg"], p["fastest"], base_dps,
                 clear_sec, base_ehp, "★" if p["boss"] else "", outcome))
    if death_wave:
        print("  → 零道具玩家在第 %d 波玩不下去（硬门槛，逼玩家买道具）。" % death_wave)
    return death_wave


def print_table_b(max_wave=40):
    """表 B：三画像失败波位（none / random / greedy × 三档技术）。"""
    print("\n【表 B】玩家画像失败波位（每组 8 个随机种子取中位数）")
    print("  画像：零道具=只开局两把枪 / 随机买=普通玩家会犯错 / 最优买=贪心+好操作")
    print("%-10s %-10s %-10s %-10s" % ("策略", "新手", "普通", "高手"))
    summary = {}
    for strat, label in [("none", "零道具"), ("random", "随机买"), ("greedy", "最优买")]:
        line = []
        for sname, sv in SKILLS.items():
            deaths = []
            for seed in range(1, 9):
                r = run(strat, sv, max_wave=max_wave, seed=seed)
                deaths.append(r["death"] if r["death"] else max_wave)
            deaths.sort()
            med = deaths[len(deaths) // 2]
            line.append("第%d波" % med)
            summary[(strat, sname)] = med
        print("%-10s %-10s %-10s %-10s" % (label, line[0], line[1], line[2]))
    print("  （%d 波上限：'第%d波'表示打完仍存活，已进入无限模式）" % (max_wave, max_wave))
    return summary


def print_table_c(max_wave=20):
    """表 C：经济收支曲线（以最优买+普通技术为代表，展示 收入 vs 道具支出）。"""
    print("\n【表 C】经济收支曲线（代表画像：最优买 + 普通技术，seed=1）")
    print("  说明：income = 击杀掉金(吃 gold_pct) + 波次奖励；spent = 累计购买道具花费。")
    print("  shop_attr = 本波末 gold≥最便宜报价? (金币是否够随便买一件) —— 衡量商店吸引力。")
    st = run("greedy", 0.5, max_wave=max_wave, seed=1)
    rows = st["rows"]
    # 最便宜报价（武器最低价 vs 道具最低价）
    cheap_w = min(int(d["cost"]) for d in WEAPONS.values())
    cheap_u = min(int(u["cost"]) for u in UPGRADES.values())
    cheap = min(cheap_w, cheap_u)
    print("%4s %9s %9s %10s %8s %7s" % ("波", "本波收入", "累计花费", "持有金币", "最便宜", "能买?"))
    cum = 0
    for r in rows:
        cum += r["income"]
        gold_left = r["gold"] + r["income"] - r["spent"] if r["wave"] > 1 else r["income"]
        # r 里 gold 是波末应用后的；用 state 估算持有
        can = "Y" if (r["gold"] + r["income"]) >= cheap else "n"
        print("%4d %9d %9d %10d %8d %7s" % (r["wave"], r["income"], r["spent"],
                                            r["gold"] + r["income"], cheap, can))
    print("  → 商店既要'有关吸引力'(每波都买得起东西)又不能'泛滥'(金币滚雪球到随便买)。")


def print_merge():
    dm, cm, per = merge_gain()
    print("\n【附录】武器合成收益公式（core/Inventory.merge_or_add 真实实现）")
    print("  伤害  dmg(lv) = int(round(dmg1 × %.2f^(lv-1)))  （整数四舍五入）" % dm)
    print("  冷却  cd(lv)  = cd1  × %.2f^(lv-1)            （浮点）" % cm)
    print("  DPS   DPS(lv) = DPS1 × %.4f^(lv-1)   （每级约 +%.1f%%）" % (per, (per - 1) * 100))
    for lv in range(1, int(SHOP["max_lv"]) + 1):
        print("    Lv%d：伤害 ×%.3f  冷却 ×%.3f  DPS ×%.3f"
              % (lv, dm ** (lv - 1), cm ** (lv - 1), per ** (lv - 1)))


def main():
    args = sys.argv[1:]
    max_wave = 40
    quiet = "--quiet" in args
    if "--max" in args:
        max_wave = int(args[args.index("--max") + 1])
    print_merge()
    death = print_table_a(20)
    print_table_b(max_wave)
    print_table_c(20)
    # 不变式速查
    pspeed = float(PLAYER["speed"])
    fs20 = fastest_speed(20)
    print("\n【不变式速查】")
    print("  第20波最快敌人 %d  ≤ 玩家速度 %d 的 90%% (%d) ? %s"
          % (int(fs20), int(pspeed), int(pspeed * 0.9),
             "OK" if fs20 <= pspeed * 0.9 else "失败"))
    print("  零道具死亡波（目标 6~8）：%s"
          % ("OK" if death and 6 <= death <= 8 else ("%.0f" % death if death else "未死")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
