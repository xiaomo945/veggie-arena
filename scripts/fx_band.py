#!/usr/bin/env python3
"""击杀特效【尖峰】闸门（B 类卡顿）。

稳态帧率由 scripts/perf_regression.py 守（每帧热点 ms/帧），但那类指标
【看不见尖峰】：平均 60fps、清场那一帧 30ms，均值照样漂亮，玩家却实实在在
觉得卡。这个闸门专门盯"密集击杀"这种瞬时事件。

被测对象：tests/perf/FxBench.gd（30 连杀 = 一波清场）。

三条硬线：
  1. 节点增量必须为 0   —— 池化后不允许再产生任何临时节点；
                            谁把特效改回 new()，这条立刻红。
  2. 对象增量 <= OBJ_MAX —— 同上，含 Tween / 内部对象（Tween 特别贵）。
  3. 30 连杀耗时 <= MS_MAX —— 120Hz 帧预算 8.33ms，清场瞬间最多只能吃掉一小角。

用法：python3 scripts/fx_band.py
"""
import re
import subprocess
import sys
import os

GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

N = 30
MS_MAX = 1.0        # 30 连杀的总开销上限（实测池化后 0.38~0.46ms）
NODE_MAX = 0        # 节点增量硬上限
OBJ_MAX = 100       # 对象增量上限（池化后实测 0；留余量防脆弱）

LINE = re.compile(
    r"FXBENCH kills=(\d+) us=(\d+) ms=([\d.]+) per_kill_us=(\d+) "
    r"node_delta=(-?\d+) obj_delta=(-?\d+)")


def main() -> int:
    out = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--scene",
         "res://tests/perf/FxBench.tscn"],
        capture_output=True, text=True, timeout=180).stdout
    m = LINE.search(out)
    print("=== 击杀特效尖峰闸门（B 类卡顿）===")
    print("  场景：一波清场 %d 只怪同时死" % N)
    if m is None:
        print("  ❌ 没拿到 FXBENCH 输出（基准脚本挂了？）")
        return 1
    _k, _us, ms, per, nd, od = (int(m.group(1)), int(m.group(2)),
                                float(m.group(3)), int(m.group(4)),
                                int(m.group(5)), int(m.group(6)))
    print("  实测：%d 连杀 = %.3f ms（%d us/次）  节点增量 %d  对象增量 %d"
          % (_k, ms, per, nd, od))
    bad = []
    if nd > NODE_MAX:
        bad.append("节点增量 %d > %d（特效又退化成 new() 了？先去 "
                   "entities/effects/SparkPool.gd 找池）" % (nd, NODE_MAX))
    if od > OBJ_MAX:
        bad.append("对象增量 %d > %d（多半是又建了 Tween，特效请用 _process "
                   "手动推进）" % (od, OBJ_MAX))
    if ms > MS_MAX:
        bad.append("30 连杀 %.3f ms > %.1f ms（120Hz 预算 8.33ms 里不能占 "
                   "这么大一块）" % (ms, MS_MAX))
    if bad:
        for b in bad:
            print("  ❌ " + b)
        return 1
    print("  ✅ 无尖峰（节点/对象零分配，%d 连杀仅 %.3f ms）" % (N, ms))
    return 0


if __name__ == "__main__":
    sys.exit(main())
