#!/usr/bin/env python3
# 参数网格搜索：给 power_band 的五条线找一组可行参数。
#
# 为什么需要它：商店改成 6 张卡 + 修正了收入模型之后，玩家的钱和战力同时暴涨，
# ratio（输出 ÷ 清场需求）从第 6 波的 4.8 一路涨到第 20 波的 22.6（红线 3.0）。
# 单个旋钮调不动（动 inflation 会撞金币线、动 hp_accel 会把中期一起打硬），
# 只能网格搜索让守门脚本自己判。
#
# 可调三个旋钮：
#   gold_scale   敌人 gold_per_wave 的缩放（削掉金币的波次膨胀，钱才有意义）
#   inflation    商店价格通胀（每过一关涨多少）
#   hp_scale     敌人 hp_accel 的缩放（抬后期，二次项主要伤后段）
#
# 用法：python3 scripts/tune_band.py            # 搜索 + 打印排序结果（不落地）
#       python3 scripts/tune_band.py --apply    # 把最优组写回 data/*.json
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAL = os.path.join(ROOT, "data", "balance.json")
ENE = os.path.join(ROOT, "data", "enemies.json")

GOLD_SCALES = [float(x) for x in (os.environ.get("GOLD_SCALES") or "0.35,0.5,0.7,1.0").split(",")]
INFLATIONS = [float(x) for x in (os.environ.get("INFLATIONS") or "0.56,1.0,1.6,2.4").split(",")]
HP_SCALES = [float(x) for x in (os.environ.get("HP_SCALES") or "1.0,1.8,3.0").split(",")]


def load(p):
    with open(p) as f:
        return json.load(f)


def save(p, d):
    with open(p, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def apply_params(gold_scale, inflation, hp_scale):
    base = json.load(open(os.path.join(ROOT, ".tune_baseline.json")))
    bal = load(BAL)
    bal["shop"]["price_inflation"] = inflation
    save(BAL, bal)
    e = load(ENE)
    for k, v in e.items():
        if not isinstance(v, dict) or "gold_per_wave" not in v:
            continue
        v["gold_per_wave"] = round(float(base["enemies"][k]["gold_per_wave"]) * gold_scale, 4)
        v["hp_accel"] = round(float(base["enemies"][k]["hp_accel"]) * hp_scale, 4)
    save(ENE, e)


def run_band():
    p = subprocess.run([sys.executable, "scripts/power_band.py", "--waves", "20", "--json"],
                       cwd=ROOT, capture_output=True, text=True, timeout=600)
    try:
        return json.loads(p.stdout)
    except Exception:
        return None


def score(js):
    """越小越好：出带条数 ×100 + 累计超出幅度（倍率）"""
    if js is None:
        return 1e9, 999
    viol = js.get("fails") or []
    if not viol:
        return 0.0, 0
    over = 0.0
    for v in viol:
        m = re.search(r"ratio\s+([\d.]+)\s*>\s*([\d.]+)", v)
        if m:
            over += float(m.group(1)) / max(0.01, float(m.group(2))) - 1.0
        else:
            over += 1.0     # 非 ratio 类违规（成长/金币/等级/清场）各计 1
    return float(len(viol)) * 100.0 + over * 10.0, len(viol)


def main():
    if not os.path.exists(os.path.join(ROOT, ".tune_baseline.json")):
        json.dump({"balance": load(BAL), "enemies": load(ENE)},
                  open(os.path.join(ROOT, ".tune_baseline.json"), "w"), ensure_ascii=False)
    results = []
    for g in GOLD_SCALES:
        for inf in INFLATIONS:
            for h in HP_SCALES:
                apply_params(g, inf, h)
                js = run_band()
                s, n = score(js)
                results.append((s, n, g, inf, h))
                print("  gold×%.2f infl=%.2f hp×%.2f → 出带 %d，评分 %.1f" % (g, inf, h, n, s))
    results.sort()
    print("\n=== 最优 5 组 ===")
    for s, n, g, inf, h in results[:5]:
        print("  gold×%.2f  inflation=%.2f  hp_accel×%.2f  → 出带 %d（评分 %.1f）" % (g, inf, h, n, s))
    best = results[0]
    if "--apply" in sys.argv:
        apply_params(best[2], best[3], best[4])
        print("\n已落地：gold_per_wave×%.2f, inflation=%.2f, hp_accel×%.2f" % (best[2], best[3], best[4]))
    else:
        # 未指定 --apply 就恢复原状，避免把搜索过程留在工作区
        base = json.load(open(os.path.join(ROOT, ".tune_baseline.json")))
        save(BAL, base["balance"])
        save(ENE, base["enemies"])
        print("\n（未 --apply，数据已还原）")


if __name__ == "__main__":
    main()
