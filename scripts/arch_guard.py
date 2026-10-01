#!/usr/bin/env python3
# 架构守卫：把"架构规则"变成机器强制执行的硬失败，而不是写在文档里等人遵守。
#
# 三条规则：
#   R1 单文件 ≤ MAX_LINES 行
#   R2 core/ 纯逻辑层不得引用任何 autoload（保证可单测、无引擎依赖）
#   R3 不得读写"其他对象"的私有字段（X._yyy）—— 这是本项目最大的耦合源
#
# 迁移策略用行业通用的【棘轮 ratchet】：
#   存量违规写进 ALLOW 基线，规则立即硬生效 —— 存量不许变多（只降不升），
#   新增文件/新增违规一律失败。随着重构推进，把基线往下调，直到清零。
#   这样"守卫"第一天就有效，又不会逼你在一天内重构完历史代码。
#
# 用法：
#   python3 scripts/arch_guard.py            # 检查（违规则退出码 1）
#   python3 scripts/arch_guard.py --report   # 只打印当前违规与建议基线（不改文件）

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_LINES = 300

# 存量基线：{文件路径: 允许的违规数}。只允许下降，不允许上升。
# R1 已清零：HUD.gd 曾长到 389 行，拆成 HudTop / HudBanners / HudButtons
# 三个子组件 + 189 行的编排器后归零。此后单文件超 300 行一律硬失败。
ALLOW_LINES = {}
# core/ 纯度基线（当前实测 0，保持为空即"零容忍"）
ALLOW_CORE = {}
# 跨模块读私有字段基线（实测存量，只降不升）
ALLOW_PRIVATE = {
    "scenes/EnemySystem.gd": 64,              # game._* 池/状态 + e._phase/_kb/_slow_factor
    "entities/Player/PlayerVisual.gd": 12,    # player._bob/_ifr/_dash/_radius/_dir/_weapons
    "ui/Screens/Main.gd": 8,                  # 调试面板读 game._enemies/_bullets/_paused
    "tests/test_pickup.gd": 1,                # field._ready()：测试里手动建池，有注释说明
}

AUTOLOADS = ["Art", "Data", "Events", "GameState", "Settings", "Steam",
             "SaveMgr", "Sfx", "Bgm", "Gamepad", "I18n"]

REPORT = "--report" in sys.argv


def strip_code(text):
    """去掉 GDScript 注释（保留行结构），避免把注释里的文件名当成真引用。"""
    out = []
    i, n = 0, len(text)
    state = None  # None=代码, '"'=双引号, "'"=单引号, '3'=三引号
    while i < n:
        c = text[i]
        if state is None:
            if c == '#':                      # 行注释
                while i < n and text[i] != '\n':
                    i += 1
                continue
            if c == '"':
                if text.startswith('"""', i):
                    state, i = '3', i + 3
                    out.append('"""'); continue
                state = '"'
            elif c == "'":
                state = "'"
            out.append(c)
        else:
            if state == '3':
                if text.startswith('"""', i):
                    state, i = None, i + 3
                    out.append('"""'); continue
            elif c == state:
                state = None
            out.append(c if state else ' ')
        i += 1
    return ''.join(out)


def gd_files():
    res = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ('.godot', '.git', 'build')]
        if '.godot' in base or '.git' in base:
            continue
        for f in files:
            if f.endswith('.gd'):
                res.append(os.path.relpath(os.path.join(base, f), ROOT))
    return sorted(res)


def main():
    fails = []
    hints = []          # 存量已下降 → 提示把基线往下调（棘轮收紧）
    lines_bad, core_bad, priv_bad = {}, {}, {}

    for rel in gd_files():
        path = os.path.join(ROOT, rel)
        raw = open(path, encoding='utf-8', errors='ignore').read()
        code = strip_code(raw)

        # ---- R1 单文件行数 ----
        n = raw.count('\n') + (0 if raw.endswith('\n') or not raw else 1)
        if n > MAX_LINES:
            base = ALLOW_LINES.get(rel)
            if base is None:
                fails.append("R1 文件 %s 有 %d 行，超过 %d 行红线（且不在豁免基线里）"
                             % (rel, n, MAX_LINES))
            elif n > base:
                fails.append("R1 %s 从基线 %d 涨到 %d 行 —— 存量违规只许降不许升"
                             % (rel, base, n))
            elif n < base:
                hints.append("R1 %s 已降到 %d 行，基线可从 %d 下调" % (rel, n, base))
            lines_bad[rel] = n

        # ---- R2 core/ 纯度：不得引用 autoload ----
        if rel.startswith('core' + os.sep):
            hits = []
            for a in AUTOLOADS:
                if re.search(r'\b' + a + r'\.', code):
                    hits.append(a)
            if hits:
                base = ALLOW_CORE.get(rel, 0)
                if len(hits) > base:
                    fails.append("R2 core/ 纯逻辑层 %s 引用了 autoload %s（应为 0，"
                                 "否则无法单测）" % (rel, hits))
                core_bad[rel] = hits

        # ---- R3 不得读写其他对象的私有字段 X._yyy ----
        # 自身私有字段写作 _yyy 或 self._yyy，所以 "实例._yyy" 一定是越界。
        hits = re.findall(r'\b(?!self\b)[a-zA-Z_][a-zA-Z0-9_]*\._[a-zA-Z_]', code)
        if hits:
            base = ALLOW_PRIVATE.get(rel, 0)
            if len(hits) > base:
                fails.append("R3 %s 读写其他对象的私有字段 %d 处（基线 %d）—— "
                             "跨模块碰私有字段是本项目的头号耦合源"
                             % (rel, len(hits), base))
            elif len(hits) < base:
                hints.append("R3 %s 已降到 %d 处，基线可从 %d 下调"
                             % (rel, len(hits), base))
            priv_bad[rel] = len(hits)

    if REPORT:
        print("== 当前违规（用于写基线）==")
        print("R1 超 %d 行: %s" % (MAX_LINES, lines_bad or "无"))
        print("R2 core 引用 autoload: %s" % (core_bad or "无"))
        print("R3 读其他对象私有字段: %s" % (priv_bad or "无"))
        return 0

    if fails:
        print("❌ 架构守卫失败（%d 项）：" % len(fails))
        for f in fails:
            print("   - " + f)
        print("")
        print("  说明：存量违规已在 scripts/arch_guard.py 的 ALLOW_* 里登记基线，")
        print("        只许降不许升；修好后把对应基线往下调即可。")
        return 1

    print("  ✅ 架构守卫通过：单文件≤%d 行 / core 层零 autoload 依赖 / "
          "无新增跨模块私有字段访问" % MAX_LINES)
    for h in hints:
        print("  💡 " + h)
    return 0


if __name__ == '__main__':
    sys.exit(main())
