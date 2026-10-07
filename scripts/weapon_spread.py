#!/usr/bin/env python3
"""武器强度离散度：测量 + 收窄 + 闸门（阶段 D1）

为什么要有这个脚本
------------------
D1 量出过一个真问题：叉子 lv6 有效 DPS 315、滤网 64，**极差 4.9 倍**。
结果是 13 个角色里 11 个的最优 build 都是"6 把叉子"，角色羁绊的收益根本竞争不过
武器基础强度的差距 —— 玩家于是"刷出哪个买哪个"，角色的武器人设形同虚设。
这正是用户最早抱怨的那句："武器随便买哪个刷出来就买哪个，反正都没有额外加成"。

所以武器之间必须有差距（不然选武器没意义），但差距必须小到**能被羁绊扳回来**。

做法
----
只缩放 `dmg` 一个字段，不动 cd / pellets / behavior / range：
  * 射速、弹道、玩法手感全部保留 —— 每把武器还是"原来那把"；
  * 有效 DPS 与 dmg 成正比，所以缩放系数直接等于目标 DPS / 当前 DPS。

压缩公式（保中位数，避免打破已经调好的每波强度带 ratio）：
    target = median * (eff / median) ** P
P < 1 即压缩：P=0.5 把 4.9 倍极差收成 sqrt(4.9) ≈ 2.2 倍，中位数不动。

用法
----
    python3 scripts/weapon_spread.py            # 只测量，打印表 + 判定
    python3 scripts/weapon_spread.py --apply    # 收窄并写回 data/weapons.json
    python3 scripts/weapon_spread.py --check    # 只做闸门判定（供 check.sh 用）
"""

import json
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
WEAPONS = os.path.join(ROOT, "data", "weapons.json")

P = 0.48            # 压缩指数（1.0 = 不压缩；0.48 把 6.9× 极差收成约 2.5×）
TARGET_SPREAD = 2.6  # 闸门：极差上限（max/min），超过就是"一把通吃"
BOTTOM_SPREAD = 1.5  # 闸门：极差下限，低于就是"所有武器一个味"


def probe(lv: int = 1) -> dict:
    cmd = [GODOT, "--headless", "--path", ROOT, "--script",
           "res://scripts/wspread_probe.gd", "--", "--lv=%d" % lv]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise SystemExit("❌ 没拿到武器探针输出：\n" + out[-2000:])


def _med(v: list) -> float:
    s = sorted(v)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def main() -> int:
    args = sys.argv[1:]
    do_apply = "--apply" in args
    do_check = "--check" in args
    do_recost = "--recost" in args
    scale_f = 1.0
    do_scale = False
    for a in args:
        if a.startswith("--scale="):
            scale_f = float(a.split("=")[1])
            do_scale = True
    d = probe(1)
    w = d["weapons"]
    eff = {k: float(v["eff"]) for k, v in w.items()}
    m = _med(list(eff.values()))
    spread = max(eff.values()) / min(eff.values())

    if do_check:
        if spread > TARGET_SPREAD:
            print("❌ 武器有效 DPS 极差 %.2f× 超过上限 %.1f× —— 最强的那把会通吃，"
                  % (spread, TARGET_SPREAD))
            print("   修复：python3 scripts/weapon_spread.py --apply")
            return 1
        if spread < BOTTOM_SPREAD:
            print("❌ 武器有效 DPS 极差只有 %.2f×，低于下限 %.1f× —— 选武器变成没意义"
                  % (spread, BOTTOM_SPREAD))
            return 1
        print("  ✅ 武器有效 DPS 极差 %.2f×，在 %.1f~%.1f× 的带内"
              % (spread, BOTTOM_SPREAD, TARGET_SPREAD))
        return 0

    order = sorted(eff.items(), key=lambda kv: -kv[1])
    print("当前（lv%d）有效 DPS = 单体 DPS × 对群折算，中位数 %.1f，极差 %.2f×"
          % (d["lv"], m, spread))
    print("%-18s %8s %6s %8s %8s" % ("武器", "有效DPS", "折算", "压缩后", "系数"))
    for k, e in order:
        t = m * (e / m) ** P
        print("%-18s %8.1f %6.2f %8.1f %8.3f" % (k, e, w[k]["mult"], t, t / e))

    if not do_apply and not do_scale and not do_recost:
        print("\n（只测量。--apply 收窄 / --scale F 统一缩放 / --recost 重定价）")
        return 0

    raw = json.load(open(WEAPONS, encoding="utf-8"))
    if do_apply:
        if spread <= TARGET_SPREAD:
            print("❌ 当前极差 %.2f× 已经在带内，再压缩会变成'所有武器一个味'。\n"
                  "   真想继续动，请先确认目标（或改用 --scale 统一缩放）。" % spread)
            return 1
        for k, e in eff.items():
            t = m * (e / m) ** P
            f = t / e
            old = raw[k]["dmg"]
            new = old * f
            # 整数保持整数（绝大多数武器 dmg 是整数，改成浮点会破坏显示与测试）
            raw[k]["dmg"] = (int(round(new)) if isinstance(old, int) and new >= 1
                             else round(new, 2))
        print("  压缩后极差应为 %.2f× —— 重跑本脚本核对" % (spread ** P))

    if do_scale:
        for k in raw:
            old = raw[k]["dmg"]
            new = old * scale_f
            raw[k]["dmg"] = (int(round(new)) if isinstance(old, int) and new >= 1
                             else round(new, 2))
        print("  全部武器 dmg ×%.3f（极差不变，只是把整体强度抬/压回来）" % scale_f)

    if do_recost:
        med_cost = _med([float(v.get("cost", 20)) for v in raw.values()])
        for k, e in eff.items():
            # 价格 ∝ 战力^0.85：指数 <1 是故意的 —— 越强的武器"每金 DPS"要略高一点，
            # 这才有"攒钱买大件"的动力；严格成正比会让所有武器性价比一模一样，
            # 商店就退化成"买得起哪个买哪个"。
            c = med_cost * (e / m) ** 0.85
            raw[k]["cost"] = max(8, min(60, int(round(c))))
        print("  价格已按战力^0.85 重定（中位数保持在 %.0f）" % med_cost)

    json.dump(raw, open(WEAPONS, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    open(WEAPONS, "a", encoding="utf-8").write("\n")
    print("\n✅ 已写回 %s" % WEAPONS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
