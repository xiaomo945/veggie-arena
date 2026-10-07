#!/usr/bin/env python3
# =====================================================================
# 多用户画像角色评审（每个角色做完都要过这一关）
# =====================================================================
#
# 用户诉求（原话）：
#   "用户画像就是轻度用户、中度用户、重度用户啊，还有啊，男生女生的喜好
#    这样来评分儿…他使用的武器，他的名字，他的玩法，爽感，它的特效美术，
#    每一个环节都要模仿用户画像给这个角色打分儿…都满意了，或者是打到过
#    一个比较高的分儿，这个角色才能做。"
#
# 所以做成：**3 档投入度 × 2 性别 = 6 个画像**，每人一眼 7 个维度打分，
# 六个画像**全部过线**这个角色才算做完。不是取平均 —— 取平均会让
# "重度玩家爱死、轻度玩家看不懂"的角色蒙混过关，而后者恰恰是大多数流失。
#
# 两个闸门，缺一不可：
#   ① 每个画像的加权分 ≥ pass（满分 5.0）。权重见 data/char_review.json，
#      轻度重"上手门槛 + 特效美术"，重度重"构筑深度"，女性画像重"美术 + 名字"。
#   ② 任何一项原始分 ≤ hard_floor 就是硬伤，直接不过。
#      没有这条，就能靠"名字 5 分"把"玩法 2 分"的角色抬过线。
#
# 用法：
#   python3 scripts/char_review.py            # 出表 + 判定
#   python3 scripts/char_review.py --json     # 只吐 JSON
#   python3 scripts/char_review.py --only scorch
#
# 退出码：0 = 全部角色过线；1 = 有角色不过线（check.sh 会拦下）
# =====================================================================

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REVIEW = os.path.join(ROOT, "data", "char_review.json")
CHARS = os.path.join(ROOT, "data", "characters.json")


def load():
    r = json.load(open(REVIEW, encoding="utf-8"))
    c = json.load(open(CHARS, encoding="utf-8"))
    dims = [k for k in r["dims"] if k != "_doc"]
    personas = {k: v for k, v in r["personas"].items() if k != "_doc"}
    scores = {k: v for k, v in r["scores"].items() if k != "_doc"}
    # 角色以 characters.json 为准：新角色忘了打分就必须在表里补，不能悄悄跳过
    chars = {k: v for k, v in c.items()
             if isinstance(v, dict) and "en" in v}
    return r, dims, personas, scores, chars


def weighted(sc, persona):
    w = persona["weight"]
    return sum(float(sc[d]) * float(w.get(d, 0.0)) for d in w)


def main():
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        only = args[args.index("--only") + 1]

    r, dims, personas, scores, chars = load()
    pkeys = list(personas.keys())
    fails = []
    table = []

    for key in chars:
        if only and key != only:
            continue
        if key not in scores:
            fails.append("角色 %s 没打分（在 data/char_review.json 的 scores 里补）" % key)
            table.append((key, chars[key], None, None, ["缺分"]))
            continue
        sc = scores[key]
        marks = []
        per = {}
        for pk in pkeys:
            w = weighted(sc, personas[pk])
            per[pk] = w
            if w < float(r["pass"]):
                marks.append("%s %.2f" % (personas[pk]["zh"], w))
                fails.append("角色 %s：%s 画像只有 %.2f 分 < %.2f"
                             % (key, personas[pk]["zh"], w, float(r["pass"])))
        hard = [d for d in dims
                if int(sc.get(d, 0)) <= int(r["hard_floor"])]
        if hard:
            marks.append("硬伤：" + "/".join(hard))
            fails.append("角色 %s：%s 得分 ≤ %d（硬伤，靠别的项抬不过来）"
                         % (key, "/".join(hard), int(r["hard_floor"])))
        table.append((key, chars[key], per, sc, marks))

    if "--json" in args:
        print(json.dumps({"fails": fails,
                          "rows": [{"key": k, "en": c.get("en"), "zh": c.get("zh"),
                                    "per": p, "raw": s, "marks": m}
                                   for k, c, p, s, m in table]},
                         ensure_ascii=False))
        return 1 if fails else 0

    print("=" * 108)
    print("多用户画像角色评审：6 个画像全部过线，这个角色才算做完")
    print("  画像 = 3 档投入度（轻/中/重）× 2 性别偏好；维度 = 用户点名的 5 项 + 深度 + 上手")
    print("  过线：每个画像加权分 ≥ %.2f，且没有任何一项 ≤ %d（硬伤）"
          % (float(r["pass"]), int(r["hard_floor"])))
    print("=" * 108)
    head = "%-12s %-10s %-8s" % ("角色", "EN", "中文")
    for pk in pkeys:
        head += " %6s" % personas[pk]["zh"]
    head += "  %s" % "判定"
    print(head)
    print("  " + "-" * 104)
    for key, c, per, sc, marks in table:
        line = "%-12s %-10s %-8s" % (key, c.get("en", ""), c.get("zh", ""))
        if per is None:
            line += " " + " " * 6 * len(pkeys) + "  缺分"
            print(line)
            continue
        for pk in pkeys:
            line += " %6.2f" % per[pk]
        line += "  %s" % ("✅" if not marks else "❌ " + "、".join(marks))
        print(line)

    print()
    print("=" * 108)
    print("原始分（1~5，打分时扮演那个人，不打平均）")
    print("=" * 108)
    print("%-12s %s" % ("角色", " ".join("%6s" % d[:6] for d in dims)))
    print("  " + "-" * 60)
    for key, c, per, sc, marks in table:
        if sc is None:
            continue
        print("%-12s %s" % (key, " ".join("%6d" % int(sc.get(d, 0)) for d in dims)))

    print()
    if fails:
        print("  ❌ 不过线 %d 处（按用户要求：不过线的角色要打回重做）" % len(fails))
        for f in fails[:24]:
            print("     - " + f)
        if len(fails) > 24:
            print("     … 还有 %d 条" % (len(fails) - 24))
        return 1
    print("  ✅ 六个画像全部满意")
    return 0


if __name__ == "__main__":
    sys.exit(main())
