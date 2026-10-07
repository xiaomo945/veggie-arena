#!/usr/bin/env python3
# D2 帧率回归闸门（确定性、CPU 侧，可进 CI）
#
# 为什么有这个脚本而不直接信 perf_probe.gd：
#   perf_probe 是 xvfb + llvmpipe 软渲染，量的是"沙箱软渲染帧时间"，
#   对手机 GPU 没有任何代表性（docs 已记：沙箱量不出 GPU 侧真瓶颈）。
#   它能给人"拐点大概在哪"的参考，但数值噪声大、不能当硬闸门。
#
#   这个脚本量的是【确定的 CPU 每帧热点】：perf_bench.gd 直调真实生产函数
#   （Hit.separation / EnemyMind 邻居收集同构 / Weapon.nearest_target / collect_enemy_data），
#   在固定怪数下统计 ms/帧。这些是"怪一多就卡"三类成因里 CPU 侧唯一可隔离、
#   可复现、可断言的部分（docs/08 诊断：O(n²) 分离是最可能的 CPU 主因）。
#
#   作用：谁把每帧热点改回 O(n²) 之外更糟的复杂度（或给每只怪加 O(n) 扫描），
#   这里立刻红——而且不依赖软渲染机时，可复现。
#
#   不覆盖的部分（必须靠真机 FpsMeter 角标，见 ui/HUD/FpsMeter.gd）：
#   GPU draw call 随敌人数线性涨的开销。PerfGuard 的 max_alive 档位（38/32/26/20）
#   是这一侧的唯一杠杆，由 tests/test_perf_guard.gd 守。
#
# 用法：python3 scripts/perf_regression.py
# 退出码 0 = 通过；非 0 = 存在帧率回归风险。

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")

# 同屏上限（与 data/balance.json max_alive / tests/test_perf_guard 一致）。
REAL_CAP = 38
STRESS_COUNT = 88  # 压力档：比真实上限高一截，给算法回归留检测窗口

# 每节每帧硬上限（ms）。当前实测：分离@88=0.35 / 瞄准@88=0.09 / 收集@88=0.07。
# 1.5ms 是约 4× 余量，能把"某节退化成更糟复杂度"挡在门外，又不至于误报。
SECTION_BUDGET_MS = 1.5
# 三节合计在压力档的硬上限。
TOTAL_BUDGET_MS = 3.0

# 只抓前两列（怪数 + ms/帧）。perf_bench 的 A 节是 4 列（多一个"距离检查次数"），
# B/C 节是 3 列——列数不同，统一按"行首数字 数字"匹配最稳。
SECTION_RE = re.compile(r"^\s*(\d+)\s+([\d.]+)")


def run_bench():
    cmd = [GODOT, "--headless", "--path", ROOT,
           "--script", "res://scripts/perf_bench.gd"]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return p.stdout + p.stderr


def parse(out):
    """返回 {section: {count: ms}}。"""
    tables = {}
    cur = None
    for line in out.splitlines():
        if line.startswith("【"):
            cur = line.strip()
            tables[cur] = {}
            continue
        if cur is None:
            continue
        m = SECTION_RE.match(line)
        if m:
            n = int(m.group(1))
            ms = float(m.group(2))
            tables[cur][n] = ms
    return tables


def _val_at(rows, n):
    """取 count=n 的 ms；缺失则用最近邻 count 的值（梯度是单调的，近似足够）。"""
    if n in rows:
        return rows[n]
    best = None
    for k in rows:
        if best is None or abs(k - n) < abs(best - n):
            best = k
    return rows[best] if best is not None else 0.0


def main():
    out = run_bench()
    tables = parse(out)
    if not tables:
        print("  ❌ perf_bench 没有产出可解析的表（Godot 报错？）")
        sys.stderr.write(out[-1500:])
        return 1

    fails = []
    print("=== D2 帧率回归闸门（CPU 每帧热点，确定性）===")
    print("  真实同屏上限 %d / 压力档 %d；单节硬上限 %.2fms、合计 %.2fms"
          % (REAL_CAP, STRESS_COUNT, SECTION_BUDGET_MS, TOTAL_BUDGET_MS))
    for sec, rows in tables.items():
        print("  %s" % sec)
        for n in sorted(rows):
            ms = rows[n]
            tag = ""
            if ms > SECTION_BUDGET_MS:
                tag = "  ❌ 超单节上限"
                fails.append("%s @%d = %.3fms > %.2fms" % (sec, n, ms, SECTION_BUDGET_MS))
            print("    %4d 怪: %.3f ms/帧%s" % (n, ms, tag))

    # 压力档合计
    total_stress = 0.0
    for sec, rows in tables.items():
        total_stress += _val_at(rows, STRESS_COUNT)
    ok = total_stress <= TOTAL_BUDGET_MS
    print("  压力档(%d)合计: %.3f ms/帧（上限 %.2f）%s"
          % (STRESS_COUNT, total_stress, TOTAL_BUDGET_MS, "✅" if ok else "❌"))
    if not ok:
        fails.append("压力档合计 %.3fms > %.2fms" % (total_stress, TOTAL_BUDGET_MS))

    # 真实上限档合计
    total_cap = 0.0
    for sec, rows in tables.items():
        total_cap += _val_at(rows, REAL_CAP)
    print("  真实上限档(%d)合计: %.3f ms/帧（占 60fps 预算 %.1f%%）"
          % (REAL_CAP, total_cap, total_cap / 16.67 * 100.0))

    if fails:
        print("  ❌ 帧率回归闸门失败：")
        for f in fails:
            print("     - " + f)
        return 1
    print("  ✅ CPU 每帧热点在阈值内（真实上限档 %.3fms，压力档 %.3fms）"
          % (total_cap, total_stress))
    return 0


if __name__ == "__main__":
    sys.exit(main())
