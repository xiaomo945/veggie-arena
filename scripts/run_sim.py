#!/usr/bin/env python3
# 整局集成验证（重构安全网）
#
# 单元测试跑在 `godot --script` 模式，那里**不注册 autoload**，所以 Game / Player /
# EnemySystem 这些真正依赖 Data / Events / GameState 的模块根本没法被单测实例化。
# 结论：跨模块的"整条链路还通不通"，只能靠真跑一局来验证。
#
# 做法：headless 跑主场景 + --sim，模拟 AI 自动跑位，然后断言战斗链路的关键事实。
# 只要刷怪 / 开火 / 命中 / 掉钱 / 波次推进（含商店与波末结算）任何一环断掉，
# 这里就会红 —— 这正是"拆大文件 / 抽中间层"这类重构最容易悄悄弄坏的地方。
#
# 用法：python3 scripts/run_sim.py [模拟秒数，默认 120]

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")

SECONDS = sys.argv[1] if len(sys.argv) > 1 else "120"

CRASH = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|"
                   r"Identifier not found|Invalid call|Attempt to call")

# 固定随机种子：自测跑的是"真实代码路径"，只是把所有随机源固定下来，
# 去掉"生存运气"噪声，让门禁可复现（真实玩家仍全随机）。
# 游戏侧各 RandomNumberGenerator 在检测到 SIM_SEED 环境变量时改用该种子。
SIM_SEED = 0x51A32B1E


def grab(pattern, text):
    m = re.search(pattern, text)
    return int(m.group(1)) if m else None


def main():
    cmd = [GODOT, "--headless", "--path", ROOT, "--", "--sim=" + SECONDS]
    env = dict(os.environ)
    env["SIM_SEED"] = str(SIM_SEED)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=env)
    out = p.stdout + p.stderr

    fails = []

    crash = CRASH.findall(out)
    if crash:
        fails.append("运行期报错: %s" % sorted(set(crash)))
    if p.returncode != 0:
        fails.append("进程退出码 %d（正常应为 0）" % p.returncode)

    peak = grab(r"场上敌人峰值:\s*(\d+)", out)
    kills = grab(r"累计击杀\s*:\s*(\d+)", out)
    m = re.search(r"开火/命中\s*:\s*(\d+)\s*/\s*(\d+)", out)
    shots, hits = (int(m.group(1)), int(m.group(2))) if m else (None, None)
    wave = grab(r"波次\s*:\s*(\d+)", out)
    m2 = re.search(r"金币\s*:\s*持有\s*(\d+)\s*/\s*累计捡到\s*(\d+)\s*/\s*地上待检\s*(\d+)",
                   out) or re.search(
        r"金币\s*:\s*持有\s*(\d+)\s*/\s*累计捡到\s*(\d+)\s*/\s*地上待捡\s*(\d+)", out)
    gold_picked, ground = (int(m2.group(2)), int(m2.group(3))) if m2 else (None, None)

    checks = [
        ("刷怪链路：场上出现过敌人", peak is not None and peak > 0, peak),
        ("武器链路：开过枪", shots is not None and shots > 0, shots),
        ("命中链路：子弹打中过敌人", hits is not None and hits > 0, hits),
        ("伤害链路：杀死过敌人", kills is not None and kills > 0, kills),
        ("掉落链路：地上有钱或已捡到钱",
         (gold_picked or 0) + (ground or 0) > 0, (gold_picked, ground)),
        ("波次链路：至少推进到第 2 波（含商店与波末结算）",
         wave is not None and wave >= 2, wave),
    ]
    for name, ok, val in checks:
        if not ok:
            fails.append("%s（实测 %s）" % (name, val))

    if fails:
        print("  ❌ 整局集成验证失败（%d 项）：" % len(fails))
        for f in fails:
            print("     - " + f)
        print("")
        print("  完整输出（最后 25 行）：")
        for line in out.strip().split("\n")[-25:]:
            print("     " + line)
        return 1

    print("  ✅ 整局集成验证通过（%s 秒模拟）：峰值敌人 %d / 击杀 %d / 开火命中 %d/%d / 第 %d 波"
          % (SECONDS, peak, kills, shots, hits, wave))
    return 0


if __name__ == "__main__":
    sys.exit(main())
