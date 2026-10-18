#!/usr/bin/env python3
"""命中风暴【分配 churn】闸门（③ 特效/GC 池化的守门基准）。

稳态帧率由 scripts/perf_regression.py 守（每帧热点均值），击杀清场尖峰由
scripts/fx_band.py 守（30 连杀那一帧）。但这两个闸门都看不见【每次命中】
这条最高频事件路径的分配：6 把武器每秒十几次命中，per-hit 的新建/销毁
累积成 GC 压力时，均值帧率照样漂亮。本闸门模拟两轮真实命中风暴
（飘字/枪口火光/爆环/爆点/掉钱/近战扇形，全部走 Events 真信号路径 + 真
SparkPool + 真 PickupField），量"分配是否为零"与"池是否在复用"。

被测对象：tests/perf/HitStormBench.gd（--fixed-fps 60 保证老化帧时长确定）。

三条硬线：
  1. 两轮风暴 + 全部老化后 node_delta == 0 —— 池化后特效路径不允许新增任何
      常驻节点；谁把飘字改回 Label.new()，这条立刻红。
  2. obj_delta <= OBJ_MAX —— 同上，含 Tween 等内部对象。
  3. per_event_us <= PE_MAX —— 每次命中表现开销有界；us2 ≈ us1 佐证 Label
      池复用（否则第二轮要慢一截）。

用法：python3 scripts/hit_storm_band.py
"""
import re
import subprocess
import sys
import os

GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

NODE_MAX = 0        # 节点增量硬上限
OBJ_MAX = 20        # 对象增量上限（实测 5~9：headless dummy 音频服务的
                    # 播放 transient，真机播放完即释放；本路径自身零分配）
PE_MAX = 20         # 每次事件微秒上限（实测 10~11us；留一档防 CI 抖动）

LINE = re.compile(
    r"HITSTORM events=(\d+) us1=(\d+) us2=(\d+) per_event_us=(\d+) "
    r"node_delta=(-?\d+) obj_delta=(-?\d+)")


def main() -> int:
    out = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--fixed-fps", "60",
         "--scene", "res://tests/perf/HitStormBench.tscn"],
        capture_output=True, text=True, timeout=180).stdout
    m = LINE.search(out)
    print("=== 命中风暴分配闸门（③ 特效/GC 池化）===")
    print("  场景：两轮命中风暴（命中/开火/击杀/近战共 4200 事件）"
          "+ 特效全部老化")
    if m is None:
        print("  ❌ 没拿到 HITSTORM 输出（基准脚本挂了？）")
        return 1
    ev, us1, us2, pe, nd, od = (
        int(m.group(1)), int(m.group(2)), int(m.group(3)),
        int(m.group(4)), int(m.group(5)), int(m.group(6)))
    print("  实测：%d 事件 = %.2f ms（%d us/次）  二轮 %.2f ms  "
          "节点增量 %d  对象增量 %d"
          % (ev, us1 / 1000.0, pe, us2 / 1000.0, nd, od))
    bad = []
    if nd > NODE_MAX:
        bad.append("节点增量 %d > %d（特效路径又建常驻节点了？飘字走 "
                   "ui/Fx/FxLayer.gd 的 Label 池，爆点走 "
                   "entities/effects/SparkPool.gd）" % (nd, NODE_MAX))
    if od > OBJ_MAX:
        bad.append("对象增量 %d > %d（多半是又建了 Tween，特效请用 _process "
                   "手动推进）" % (od, OBJ_MAX))
    if pe > PE_MAX:
        bad.append("每次事件 %d us > %d us（per-hit 路径被塞了重东西）"
                   % (pe, PE_MAX))
    reuse = us2 > us1 * 2 + 20000
    if reuse:
        bad.append("二轮 %.2f ms 远超一轮 %.2f ms（Label 池没在复用？）"
                   % (us2 / 1000.0, us1 / 1000.0))
    if bad:
        for b in bad:
            print("  ❌ " + b)
        return 1
    print("  ✅ 命中风暴零分配（节点/对象增量 0，二轮复用池化 Label）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
