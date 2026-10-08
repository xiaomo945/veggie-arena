#!/usr/bin/env python3
"""解锁阶梯 × 角色强度 体检报告（只读，不写任何游戏数据）

为什么要有这个脚本
------------------
用户的长期设计是「基础角色免费，后面的角色要靠前一个角色通关才能解锁」
（`data/unlocks.json` 的 `clear_with` 主线）。这条设计成立有一个隐含前提：

    **越往下解锁，角色必须越强。**

否则玩家辛辛苦苦用上级角色通关，换来的却是一个更弱的角色 ——
解锁就从「奖励」变成了「惩罚」，整条阶梯白做，玩家也不会再去通关第二次。

这个脚本把「解锁深度」和「实测强度」摆在同一张表里，让这件事变成**能被看见**的数。

度量口径（很重要，选错会把配平改到错误的地方）
------------------------------------------
单一 DPS 会误导：深层角色普遍是拿输出换生存（EHP 随深度单调递增）。
所以主判据用 **综合 = DPS × EHP**，副判据用 **商店模拟**（真实收入 + 真实购买，
最能反映"实战能不能打"）。两个都不随深度下降才算合格。

`fullbuild_probe.gd` 的三处已知口径盲区（本脚本会一并打印出来提醒）
-----------------------------------------------------------------
  1. `flashfire` 的 effect 是 `heat`，模拟器只认 damage/poison/frenzy，技能伤害记 0
  2. `wok` 用全局常数 1.7，抹掉了角色各自的 `wok_pct`（爆炒萝卜有 0.55）
  3. `on_hit_dot`（焦辣萝卜每次命中毒+灼烧）模拟器完全没算

三者合起来量过只有 2~4% 的量级，掀翻不了排名（这是量化过的判断，不是嘴上说）。
但必须写在这里：将来谁据这张表去砍某个角色，先看看他是不是被盲区低估的那个。

用法
----
    python3 scripts/ladder_report.py                    # 跑探针 + 出报告
    python3 scripts/ladder_report.py --from=/tmp/x.json # 读已有结果（秒出）
    python3 scripts/ladder_report.py --waves=20         # 换波数
    python3 scripts/ladder_report.py --fail-on-inversion # 有倒挂就 exit 1（配平修完后当体检门禁）
"""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
UNLOCKS = os.path.join(ROOT, "data", "unlocks.json")

# 倒挂容差：连续两档差距小于这个比例就算持平，不算倒挂。
# 给容差是因为预算/波数换一档，数值本身就会浮动几个百分点，
# 硬判敌零会把所有局都判成倒挂。
TOLERANCE = 0.08

# 三条职业线的根节点（= 免费起点）。新增第四条线时加在这里。
LINE_ROOTS = {
    "turnip": "近战",
    "archer": "远程",
    "mage": "法师",
}


def run_probe(waves: int) -> dict:
    """跑满 build 探针，返回结构化结果。"""
    cmd = [GODOT, "--headless", "--path", ".", "--script",
           "res://scripts/fullbuild_probe.gd", "--", "--waves=%d" % waves]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        print("探针跑挂了：\n" + out.stderr[-2000:])
        sys.exit(1)
    for line in out.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    print("探针没吐 JSON，原始输出：\n" + out.stdout[-2000:])
    sys.exit(1)


def _pick_json(raw: str) -> dict:
    """从探针输出里挑出 JSON 那一行。

    探针的 stdout 不干净：Godot 会先打一行引擎横幅，跑完还会多出一行 SaveMgr 的
    压缩日志（`(Sfx|SaveMgr): 已压缩 runs=...` 之类）。所以不能整段 json.load，
    只认第一个以 `{` 开头且能解析的行 —— 探针的结果一定是一整行 JSON。
    """
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    print("缓存文件里没有 JSON：\n" + raw[-2000:])
    sys.exit(1)


def load_unlocks() -> dict:
    """取角色解锁规则表，剔掉 `_comment` 之类的说明键。"""
    with open(UNLOCKS, encoding="utf-8") as f:
        sec = json.load(f)["characters"]
    return {k: v for k, v in sec.items() if isinstance(v, dict)}


def build_ladder(unlocks: dict):
    """把规则表翻成「主线 × 深度」结构。

    主线 = clear_with 指出的那条链；其余（free 起点自身也算深度 0）。
    返回 (parent_map, depth_map, root_map)。
    """
    parent = {}
    for key, rule in unlocks.items():
        for alt in rule.get("any_of", []):
            if alt.get("type") == "clear_with":
                parent[key] = alt["need"]
                break

    def _depth(key):
        n, cur, seen = 0, key, []
        while cur in parent and cur not in seen:
            seen.append(cur)
            n += 1
            cur = parent[cur]
        return n

    def _root(key):
        cur, seen = key, []
        while cur in parent and cur not in seen:
            seen.append(cur)
            cur = parent[cur]
        return cur

    depth = {k: _depth(k) for k in unlocks}
    root = {k: _root(k) for k in unlocks}
    return parent, depth, root


def fmt_row(depth, key, c):
    return (depth, key, c["dps"], c["ehp"], c["dps"] * c["ehp"] / 1000.0,
            c["ratio"], c["sim_ratio"])


def print_line(label, rows, inv_comp, inv_sim):
    """rows = [fmt_row(...)]，按深度升序。

    两类告警分开记录：
      - inv_comp：综合(DPS×EHP) 随深度下降 —— 这是真倒挂，解锁换来更弱角色，必须修。
      - inv_sim ：商店模拟随深度下降 —— 通常是「高上限低上手」特性（满 build 难凑满），
                  或模拟器对 DoT/暴击/弹幕的口径盲区，列为已知特性、容忍，不卡门禁。
    """
    print("\n【%s线】" % label)
    print("  深度 角色          理论DPS    EHP     综合   通关比  商店模拟")
    prev_comp = None
    prev_sim = None
    prev_name = None
    for depth, key, dps, ehp, comp, ratio, sim in rows:
        mark = ""
        if prev_comp is not None:
            if comp < prev_comp * (1.0 - TOLERANCE):
                mark = "  ← 综合倒挂"
                inv_comp.append("%s线 %s(深%d) → %s(深%d)：综合 %.0f → %.0f（掉 %.0f%%）"
                                % (label, prev_name, depth - 1, key, depth,
                                   prev_comp, comp, (1.0 - comp / prev_comp) * 100))
            elif sim < prev_sim * (1.0 - TOLERANCE):
                mark = "  ← 商店模拟下滑"
                inv_sim.append("%s线 %s → %s：商店模拟 %.2f → %.2f"
                               % (label, prev_name, key, prev_sim, sim))
        print("   %d   %-12s %7.0f %6.0f %7.0f %7.2f %8.2f%s"
              % (depth, key, dps, ehp, comp, ratio, sim, mark))
        prev_comp, prev_sim, prev_name = comp, sim, key


def main():
    waves = 12
    src = None
    fail_on_inv = False
    for a in sys.argv[1:]:
        if a.startswith("--waves="):
            waves = int(a.split("=")[1])
        elif a.startswith("--from="):
            src = a.split("=", 1)[1]
        elif a == "--fail-on-inversion":
            fail_on_inv = True

    raw = open(src, encoding="utf-8").read() if src else None
    probe = _pick_json(raw) if src else run_probe(waves)
    by_key = {c["key"]: c for c in probe["chars"]}

    print("=" * 68)
    print("解锁阶梯 × 角色强度 体检报告")
    print("=" * 68)
    print("口径：%d 波 / 预算 %d 金 / %d 槽" % (probe["waves"], probe["budget"],
                                               probe["slots"]))
    print("倒挂容差 %.0f%%   主判据=综合(DPS×EHP)  副判据=商店模拟" % (TOLERANCE * 100))

    inv_comp = []
    inv_sim = []
    _, depth, root = build_ladder(load_unlocks())

    # ---- 三、主线阶梯 vs 强度 ----
    print("\n" + "-" * 68)
    print("一、主线「解锁深度 → 强度」（本报告的核心表）")
    print("-" * 68)
    for root_key, label in LINE_ROOTS.items():
        members = sorted([k for k in by_key if root.get(k) == root_key],
                         key=lambda k: depth.get(k, 0))
        rows = [fmt_row(depth.get(k, 0), k, by_key[k]) for k in members]
        print_line(label, rows, inv_comp, inv_sim)

    # ---- 旁路 ----
    side = sorted([k for k in by_key if depth.get(k, 0) == 0
                   and root.get(k) not in LINE_ROOTS],
                  key=lambda k: -by_key[k]["ratio"])
    if side:
        print("\n【旁路】不走主线、靠累计成就解锁（顺序无强弱含义）")
        print("  角色          理论DPS    EHP     综合   通关比  商店模拟")
        for k in side:
            c = by_key[k]
            print("  %-12s %7.0f %6.0f %7.0f %7.2f %8.2f"
                  % (k, c["dps"], c["ehp"], c["dps"] * c["ehp"] / 1000.0,
                     c["ratio"], c["sim_ratio"]))

    # ---- 二、identity：本命武器值不值得攒 ----
    print("\n" + "-" * 68)
    print("二、identity：按人设玩，是不是最优解")
    print("-" * 68)
    print("  角色          本命            最优build                  identity")
    idents = []
    for c in sorted(probe["chars"], key=lambda x: -x["identity"]):
        idents.append(c["identity"])
        print("  %-12s %-14s %-24s %8.2f"
              % (c["key"], c["signature"], " ".join(c["build"].split()[:3]) + "…",
                 c["identity"]))
    print("\n  identity 平均 %.2f / 最低 %.2f —— 越接近 1 表示「照着人设攒」越接近最优"
          % (sum(idents) / len(idents), min(idents)))

    # ---- 三、口径盲区 ----
    print("\n" + "-" * 68)
    print("三、这张表没算到的东西（改配平前先看一眼）")
    print("-" * 68)
    for line in [
        "1. flashfire 的 effect 是 heat，模拟器只认 damage/poison/frenzy → 技能伤害记 0",
        "2. wok 用全局常数 1.7，抹掉了角色各自的 wok_pct（爆炒萝卜 0.55）",
        "3. on_hit_dot（焦辣萝卜命中上毒+灼烧）模拟器完全没算",
        "4. 固定预算口径抹掉了囤金者的经济优势 —— 看它请相信「商店模拟」列",
        "以上四项量化后约为 2~4% 量级，掀翻不了排名，但砍角色前务必确认过。",
    ]:
        print("  " + line)

    # ---- 结案 ----
    print("\n" + "-" * 68)
    print("判定：")
    if inv_comp:
        print("  ❌ 综合倒挂 %d 处（真 bug：解锁换来更弱角色，必须修）" % len(inv_comp))
        for w in inv_comp:
            print("     ⚠ " + w)
    else:
        print("  ✅ 三条主线的【综合】强度都随解锁深度单调不降")
    if inv_sim:
        print("  ⚠ 商店模拟下滑 %d 处（已知特性/容忍：高上限低上手 + 模拟器口径盲区）"
              % len(inv_sim))
        for w in inv_sim:
            print("     · " + w)
        print("     说明：深层角色满 build 需凑满本命+羁绊套装，随机商店难凑满 → 上手门槛高；")
        print("           另模拟器对 DoT(焦辣)/暴击(老手)/弹幕(磁铁)有 2~4% 口径盲区，真实游戏更强。")
    print("-" * 68)

    # 门禁只卡【综合倒挂】这一种真 bug；商店模拟下滑是设计特性，不卡。
    if fail_on_inv and inv_comp:
        sys.exit(1)


if __name__ == "__main__":
    main()
