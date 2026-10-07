#!/usr/bin/env python3
# =====================================================================
# 每波强度规划守门（Power Band）
# =====================================================================
#
# 回答用户的一串问题：
#   "第一波预计要把武器升到多少级？他的金币是不是超标？
#    第二波应该达到什么样的水平才能比怪稍微厉害一些？
#    第三波要达到什么水平，金币要在什么样的范围，然后每一波都要有一个规划，
#    使这个角色的强度不能超标太多，也不能太弱。"
#
# 做法：把上面这些问句翻译成**每一波都要过的五条硬线**，出线就是设计事故。
# 数值全部来自 scripts/power_probe.gd（它直调真实 core/ 代码，不另造公式），
# 本文件只负责"读数据 + 判线 + 出表"，不碰任何公式。
#
# 五条线（每一波都要过）：
#   ① 战力比 ratio = 打这一波时的输出 ÷ 全清这一波需要的输出，落在分段带内
#   ② 成长不停滞：不许倒退，且每 4 波至少要涨一截
#   ③ 金币不超标：波末余钱 ≤ 本波收入 × GOLD_HI_K
#   ④ 等级不落后：等效等级（含道具、锅气）不能落后需求等级太多
#   ⑤ 清场率 ≥ CLEAR_MIN：这一波刷出来的怪至少要打得掉九成
#
# 边界说明（别拿它当生存判据）：
#   本守门只管"输出与经济"这一侧。玩家"活不活得下来"由 balance_model.py
#   的 CONTACT_K 模型负责，两侧分工，不要混着改。
#
# 用法：
#   python3 scripts/power_band.py                # 出表 + 判线（check.sh 用这个）
#   python3 scripts/power_band.py --waves 20     # 判到第 20 波
#   python3 scripts/power_band.py --json         # 只吐 JSON，给别的脚本消费
#
# 退出码：0 = 每一波都在带内；1 = 有出带
# =====================================================================

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
PROBE = "res://scripts/power_probe.gd"

# ---- 五条线的阈值（设计目标，改这里等于改难度，必须写理由）----
#
# ① ratio：为什么下界不是 1.0？
#    探针里的 DPS 是"理论满命中"输出，实战有走位、射程、怪分散的损耗，
#    有效输出大约只有理论的 6~7 成。ratio 1.5 ≈ 实战刚好清场；
#    2.0~2.5 ≈ 稳清场还有余裕；再往上就是闭眼割草。
RATIO_LO = 1.50
RATIO_HI = 3.00
# 第 1 波单独放宽下界：开局只有 2 把 Lv1 武器，必然吃力，只要求"打得完"。
WAVE1_LO = 1.00
# 第 2~3 波单独放宽上界：用户点名"第二波要比怪稍微厉害一些，
#   不会被打不过去，没有打不过去的可能" —— 教学波就是要爽。
TUTORIAL_HI = 5.50
TUTORIAL_WAVES = 3

# ② 成长：逐波卡 3% 太苛刻（后期武器等级本来就推得慢，卡死只会逼人造假数据），
#    改成"不许倒退 + 每 4 波至少涨 12%"，既抓得住停滞又不会误伤正常的平台期。
GROW_BACK = 0.99
GROW_WINDOW = 4
GROW_WINDOW_MIN = 0.12

# ③ 金币：余钱超过本波收入的 1.5 倍，说明这一波的产出没处花 ——
#    玩家会觉得"攒钱没意义"，这是 roguelite 最伤节奏的毛病。
GOLD_HI_K = 1.50

# ④ 等级：等效等级（把道具、锅气都折算成"相当于武器升到几级"）落后需求 1 级以内。
EQ_LAG = 1.00

# ⑤ 清场率
CLEAR_MIN = 0.90


def ratio_band(w):
    lo = WAVE1_LO if w == 1 else RATIO_LO
    hi = TUTORIAL_HI if w <= TUTORIAL_WAVES else RATIO_HI
    return lo, hi


def run_probe(waves, targets=3):
    cmd = [GODOT, "--headless", "--path", ROOT, "--script", PROBE, "--",
           "--waves=%d" % waves, "--targets=%d" % targets]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    for line in p.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise RuntimeError("探针没吐出 JSON（godot 退出码 %d）\n%s"
                       % (p.returncode, p.stderr[-800:]))


def judge(d):
    """逐波判五条线。返回 (违规列表, 逐波明细)。"""
    rows = d["rows"]
    fails = []
    detail = []
    hist = []
    for r in rows:
        w = int(r["w"])
        ratio = float(r["ratio_fight"])
        dps = float(r["dps_reach"])
        gold = int(r["gold_left"])
        income = max(1, int(r["income"]))
        clear = float(r.get("clear_frac", 1.0))
        eq = float(r.get("eq_lv", 1.0))
        need = float(r.get("need_lv", 1.0))
        lo, hi = ratio_band(w)

        marks = []
        if ratio < lo:
            fails.append("第%d波：ratio %.2f < %.2f（杀不过刷怪速度，怪会堆积）"
                         % (w, ratio, lo))
            marks.append("太弱")
        elif ratio > hi:
            fails.append("第%d波：ratio %.2f > %.2f（碾压，强度超标）" % (w, ratio, hi))
            marks.append("超标")

        if hist:
            if dps < hist[-1] * GROW_BACK:
                fails.append("第%d波：出店战力 %.0f 比上一波 %.0f 还低（成长倒退）"
                             % (w, dps, hist[-1]))
                marks.append("倒退")
            if len(hist) >= GROW_WINDOW and dps < hist[-GROW_WINDOW] * (1.0 + GROW_WINDOW_MIN):
                fails.append("第%d波：出店战力 %.0f，比 %d 波前的 %.0f 涨不到 %.0f%%（成长停滞）"
                             % (w, dps, GROW_WINDOW, hist[-GROW_WINDOW], GROW_WINDOW_MIN * 100))
                marks.append("停滞")
        hist.append(dps)

        if gold > income * GOLD_HI_K:
            fails.append("第%d波：余钱 %d > 本波收入 %d × %.1f（钱没去处，金币超标）"
                         % (w, gold, income, GOLD_HI_K))
            marks.append("金币超标")

        if eq < need - EQ_LAG:
            fails.append("第%d波：等效等级 %.1f 落后需求 %.1f 超过 %.1f 级（被经济卡死）"
                         % (w, eq, need, EQ_LAG))
            marks.append("等级落后")

        if clear < CLEAR_MIN:
            fails.append("第%d波：清场率 %.0f%% < %.0f%%（打不完，会堆积）"
                         % (w, clear * 100, CLEAR_MIN * 100))
            marks.append("打不完")

        detail.append((w, r, "ok" if not marks else " ".join(marks)))
    return fails, detail


def main():
    args = sys.argv[1:]
    waves = 20
    if "--waves" in args:
        waves = int(args[args.index("--waves") + 1])

    d = run_probe(waves)
    fails, detail = judge(d)

    if "--json" in args:
        print(json.dumps({"rows": d["rows"], "fails": fails}, ensure_ascii=False))
        return 1 if fails else 0

    print("=" * 104)
    print("每波强度规划（数据源：scripts/power_probe.gd 直调真实 core/ 代码，商店 %d 局取中位数）"
          % d.get("runs", 1))
    print("  ratio = 打这一波时的输出 ÷ 全清这一波需要的输出；锅气倍率 %.2f" % d.get("wok", 1.0))
    print("=" * 104)
    print("%3s %8s %9s %6s %9s %5s %6s %6s %8s %7s  %s"
          % ("波", "清场DPS", "战斗DPS", "ratio", "带", "槽", "主力Lv", "需求Lv",
             "余钱", "本波收", "判定"))
    print("  " + "-" * 96)
    for w, r, mark in detail:
        lo, hi = ratio_band(w)
        print("%3d %8.0f %9.0f %6.2f %4.1f~%.1f %4d %6d %6.1f %8d %7d  %s"
              % (w, r["clear_dps"], r["dps_fight"], r["ratio_fight"], lo, hi,
                 r["slots"], r["top_lv"], r["need_lv"], r["gold_left"],
                 r["income"], mark))

    print()
    print("=" * 104)
    print("每一波的规划（用户问的《第 N 波该到几级、金币该多少》，答案在这里）")
    print("=" * 104)
    print("%3s %10s %12s %14s %10s" % ("波", "该到几级", "该有多少输出", "余钱上限", "打怪强度"))
    print("  " + "-" * 60)
    for w, r, mark in detail:
        print("%3d %8.1f 级 %10.0f DPS %12d 金 %10s"
              % (w, r["need_lv"], r["clear_dps"],
                 int(r["income"] * GOLD_HI_K),
                 "轻松" if r["ratio_fight"] > 2.6 else
                 ("吃紧" if r["ratio_fight"] < 1.6 else "相当")))

    print()
    print("=" * 104)
    print("带的含义（每一波都必须落在带内，出带 = 设计事故）")
    print("=" * 104)
    print("  ① ratio      第 1 波 %.2f~%.2f；第 2~%d 波教学放宽到 %.2f~%.2f；之后 %.2f~%.2f"
          % (WAVE1_LO, RATIO_HI, TUTORIAL_WAVES, RATIO_LO, TUTORIAL_HI, RATIO_LO, RATIO_HI))
    print("  ② 成长       出店战力不许倒退（×%.2f），且每 %d 波至少 +%.0f%%"
          % (GROW_BACK, GROW_WINDOW, GROW_WINDOW_MIN * 100))
    print("  ③ 金币       波末余钱 ≤ 本波收入 × %.1f" % GOLD_HI_K)
    print("  ④ 等级       等效等级（含道具、锅气）落后需求 ≤ %.1f 级" % EQ_LAG)
    print("  ⑤ 清场率     ≥ %.0f%%" % (CLEAR_MIN * 100))
    print()
    if fails:
        print("  ❌ 出带 %d 处：" % len(fails))
        for f in fails[:20]:
            print("     - " + f)
        if len(fails) > 20:
            print("     … 还有 %d 条" % (len(fails) - 20))
        return 1
    print("  ✅ 每一波都在带内：强度既不超标，也不过弱")
    return 0


if __name__ == "__main__":
    sys.exit(main())
