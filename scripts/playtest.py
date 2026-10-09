#!/usr/bin/env python3
# 角色游玩路线"能不能玩到最后"验收。
#
# 背景：用户多次问"这个游戏能不能通关"。单元测试答不了 —— 它跑在 --script 模式，
# 那里不注册 autoload，战斗链路根本起不来。只有真跑一整局（headless + 固定种子）
# 才能回答"路线是否走得通"。
#
# 两档 AI 夹逼，缺一不可：
#   default = 会玩的玩家（宽视野、每帧决策、会冲刺会放技能）→ 必须通关，否则路线不成立
#   human   = 普通玩家（视野窄、0.2s 才重判、12% 失误）→ 观察下限，不该过早团灭
# 只看 default 会高估"普通玩家能不能玩"，只看 human 会误以为游戏劝退。
#
# 用法：python3 scripts/playtest.py              # 跑默认档 + 普通玩家档
#       python3 scripts/playtest.py --char=mage  # 换角色（默认 turnip）
# 退出码：default 档必须通关，否则 1（硬门禁）。

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
# ⚠️ 单种子的"死在第几波"对刷怪成分极度敏感（实测：同一份配置换一个种子，
#    普通玩家档能在第 7 波和第 8 波之间跳）。所以默认跑多个种子看分布，
#    只在【多数种子都活不过某波】时才判定需要调平衡 —— 否则就是在拟合噪声。
BASE_SEED = 0x51A32B1E
SEEDS = [BASE_SEED, 0x2F19A7C3, 0x7C4E11B5, 0x1A93D46F, 0x63B0E8D2]

CHAR = "turnip"
ONLY = None      # 只跑某一档（快速迭代用）
N_SEED = None    # 只用前 N 个种子
for a in sys.argv[1:]:
    if a.startswith("--char="):
        CHAR = a.split("=", 1)[1]
    elif a.startswith("--only="):
        ONLY = a.split("=", 1)[1]
    elif a.startswith("--seeds="):
        N_SEED = int(a.split("=", 1)[1])

# 跑满 12 波需要 ~540s 模拟时间，给足余量让它在"通关/阵亡"时自然退出
SECONDS = "900"

PROFILES = [
    ("会玩档", []),
    ("普通玩家档", ["--human"]),
]


SEEDS_USED = SEEDS[:N_SEED] if N_SEED else SEEDS
PROFILES_USED = [x for x in PROFILES if ONLY is None or x[0] == ONLY]


def run(flags, seed):
    cmd = [GODOT, "--headless", "--path", ROOT, "--",
           "--sim=" + SECONDS, "--char=" + CHAR] + flags
    env = dict(os.environ)
    env["SIM_SEED"] = str(seed)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900, env=env)
    out = p.stdout + p.stderr
    if re.search(r"SCRIPT ERROR|Parse Error|Invalid call", out):
        return None, out
    ending = re.search(r"结局\s*:\s*(.+)", out)
    wave = re.search(r"波次\s*:\s*(\d+)", out)
    hp = re.search(r"玩家血量\s*:\s*(\d+)\s*/\s*(\d+)", out)
    kills = re.search(r"累计击杀\s*:\s*(\d+)", out)
    return (
        str(ending.group(1)).strip() if ending else "?",
        int(wave.group(1)) if wave else 0,
        "%s/%s" % (hp.group(1), hp.group(2)) if hp else "?",
        int(kills.group(1)) if kills else 0,
    ), out


def main() -> int:
    print("=== 路线验收：%s / %d 个种子（衡量'能不能玩到最后'）===" % (CHAR, len(SEEDS_USED)))
    res = {}
    for name, flags in PROFILES_USED:
        waves, wins, bloode = [], 0, []
        for i, seed in enumerate(SEEDS_USED):
            r, out = run(flags, seed)
            if r is None:
                print("  ❌ %s 运行期报错：" % name)
                for line in out.strip().split("\n")[-8:]:
                    print("     " + line)
                return 1
            ending, wave, hp, kills = r
            won = "通关" in ending
            if won:
                wins += 1
            waves.append(wave)
            bloode.append(hp)
            print("   种子%d 第%2d 波 %s | 血 %s | 击杀 %d"
                  % (i + 1, wave, "通关" if won else "阵亡", hp, kills))
        waves_sorted = sorted(waves)
        median = waves_sorted[len(waves_sorted) // 2]
        res[name] = (wins, median, waves)
        print("  %s：通关 %d/%d，到达波次 %s（中位 %d）"
              % (name, wins, len(SEEDS_USED), waves, median))
    ok_default = res["会玩档"][0] == len(SEEDS)
    if not ok_default:
        print("  ❌ 会玩的玩家存在跑不到终点的种子 —— 路线不成立，必须先调平衡")
        return 1
    print("  ✅ 路线可完成（会玩档 %d/%d 通关）；普通玩家档中位第 %d 波"
          % (res["会玩档"][0], len(SEEDS_USED), res["普通玩家档"][1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
