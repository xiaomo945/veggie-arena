#!/usr/bin/env python3
"""道具定价不变式审计：同属性道具不得存在"严格劣势"（死卡）。

背景（2026-10-15 专家会诊 P1）：upgrades.json 的道具可跨波重复购买、且
GameState.stat_value 按购买份数 n 线性倍乘（无封顶、无每件限购）。因此一件
道具"永远不该被买"有两条判定路径：

  路径 1 同属性单件劣势： A、B 同 stat，A 的 cost <= B 且 value >= B，
         且至少一边严格更优 → B 在任何情况下都不如上 A。
  路径 2 基础档重复购买优势： B 的 cost >= k×基础档cost 且 value <= k×基础档
         value（k >= 2，至少一边严格）→ 直接买 k 次基础档更优。
         例：旧 spd2b 26 金 +14% vs 两件 spd 20 金 +20%，同效更贵 = 死卡。

硬规则之外还有一条项目自选口径：消费类的每金币效率不得超过永久血量线的顶配
（hp4 类），否则"救命稻草"会挤掉所有永久投资（heal 8 金 40 血 = 5.0 HP/金，
曾是该线顶配的 2.7 倍）。

带负面词条的嵌套 stats 道具（pellets / pellets2 / *_focus）天然豁免：
它们的价值在取舍上，不在纯数字上，本审计不认文案只认数字。

用法：python3 scripts/upgrade_audit.py [--data data/upgrades.json]
退出码：0 = 无严格劣势；1 = 有（供 check.sh / CI 拦截）。
"""
import argparse
import json
import os
import sys
from collections import defaultdict

# 消费类软规则：瞬时回复每金币效率不得高于永久血量线顶配。
# 键 = 消费类 stat，值 = 对应的永久属性线 stat。
CONSUMABLE_VS_PERMANENT = {"heal_now": "max_hp"}

# 重复购买检测时最多叠几件基础档（够用即可：k 超过性价比就没意义了）
MAX_STACK = 8


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def flat_items(defs):
    """只取扁平 stat/value 道具（嵌套 stats 的带负面词条，豁免）。"""
    out = {}
    for k, v in defs.items():
        if not isinstance(v, dict):
            continue
        st = v.get("stat")
        val = v.get("value")
        if not st or val is None:
            continue
        cost = v.get("cost", 0)
        if not isinstance(cost, (int, float)) or cost <= 0:
            continue
        out[k] = (str(st), float(cost), float(val))
    return out


def find_single_domination(groups):
    """路径 1：同属性单件严格劣势。返回 (dead, dominator, reason) 列表。"""
    bad = []
    for stat, items in groups.items():
        for kb in items:
            sb, cb, vb = items[kb]
            for ka in items:
                if ka == kb:
                    continue
                sa, ca, va = items[ka]
                if ca <= cb and va >= vb and (ca < cb or va > vb):
                    bad.append((kb, ka, "%s: %s %.4g 金换 %.4g，被 %s %.4g 金换 %.4g 严格压制"
                                % (stat, kb, cb, vb, ka, ca, va)))
                    break
    return bad


def find_repeat_domination(groups):
    """路径 2：基础档重复购买严格优势。基础档 = 该属性线 cost 最低（并列取 value 最高）。"""
    bad = []
    for stat, items in groups.items():
        if len(items) < 2:
            continue
        base_key = min(items, key=lambda k: (items[k][1], -items[k][2]))
        bs, bc, bv = items[base_key]
        if bv <= 0:
            continue  # 负值/零值线（如技能冷却缩减）不适用线性叠加口径
        for kb in items:
            if kb == base_key:
                continue
            sb, cb, vb = items[kb]
            # 候选 k 的闭区间：k 必须小到"总价不超过该件"（k*bc <= cb），
            # 又必须大到"价值追得上该件"（k*bv >= vb）。两个边界都随 k 单调，
            # 所以直接解区间，别用 break 猜（价值追不上就 break 会漏掉
            # "2 件不够、3 件刚好"的情况，spd4 曾被这样漏掉）。
            import math
            k_lo = max(2, math.ceil(vb / bv - 1e-9))
            k_hi = min(MAX_STACK, int(cb // bc))
            for k in range(k_lo, k_hi + 1):
                kc, kv = k * bc, k * bv
                if kc <= cb and kv >= vb and (kc < cb or kv > vb):
                    bad.append((kb, base_key, "%s: %s %.4g 金换 %.4g，不如买 %d 件 %s（%.4g 金换 %.4g）"
                                % (stat, kb, cb, vb, k, base_key, kc, kv)))
                    break
    return bad


def find_consumable_inversion(defs):
    """软规则的硬拦截：消费类每金币效率 > 永久线顶配 → 报错。"""
    bad = []
    perm = defaultdict(list)
    for k, v in defs.items():
        if isinstance(v, dict) and v.get("stat") and v.get("value") is not None:
            c = v.get("cost", 0)
            if isinstance(c, (int, float)) and c > 0:
                perm[str(v["stat"])].append((k, float(c), float(v["value"])))
    for consum, perm_stat in CONSUMABLE_VS_PERMANENT.items():
        for k, v in defs.items():
            if not (isinstance(v, dict) and v.get("stat") == consum):
                continue
            c = v.get("cost", 0)
            if not (isinstance(c, (int, float)) and c > 0):
                continue
            eff_c = float(v["value"]) / float(c)
            line = perm.get(perm_stat, [])
            if not line:
                continue
            best = max(val / c2 for _, c2, val in line)
            if eff_c > best:
                bad.append((k, "", "消费类 %s 每金币 %.3f 超过永久线 %s 顶配 %.3f —— 救命稻草会挤掉永久投资"
                            % (k, eff_c, perm_stat, best)))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "upgrades.json"))
    args = ap.parse_args()
    defs = load(args.data)
    items = flat_items(defs)
    groups = defaultdict(dict)
    for k, (st, c, v) in items.items():
        groups[st][k] = (st, c, v)

    single = find_single_domination(groups)
    repeat = find_repeat_domination(groups)
    consum = find_consumable_inversion(defs)

    print("=== 道具定价不变式审计 ===")
    print("  扁平数值道具 %d 个 / %d 条属性线" % (len(items), len(groups)))
    for label, bad in (("同属性单件劣势", single), ("基础档重复购买劣势", repeat), ("消费类效率倒挂", consum)):
        if bad:
            print("  ❌ %s %d 项：" % (label, len(bad)))
            for dead, dom, why in bad:
                print("     - %s" % why)
        else:
            print("  ✅ %s：无" % label)
    if single or repeat or consum:
        print("=== ❌ 存在严格劣势道具（死卡）===")
        return 1
    print("=== ✅ 全表无严格劣势 ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
