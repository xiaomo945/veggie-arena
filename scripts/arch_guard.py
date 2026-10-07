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
# R3 已清零，零容忍：跨模块读私有字段一律硬失败（不再有任何存量豁免）。
# 清零路径（留给后来人看当时是怎么拆的）：
#   EnemySystem 64 处 game._* → 抽出 scenes/BattleWorld.gd 共享战斗状态；
#                  e._phase/_kb/_slow_factor → Enemy 加 wobble()/knockback()/slow_factor()
#   PlayerVisual 12 处 player._* → Player 加只读访问器 bob_phase()/ifr_left()/...
#   Main       8 处  game._*  → game.world.* / game.step() / game.is_paused()
#   test_pickup 1 处 field._ready() → PickupField 加公开 build_pool()
ALLOW_PRIVATE = {}

# 名单与 project.godot 的 autoload 段保持一致（漏了就等于放行）。
AUTOLOADS = ["Art", "Data", "Events", "GameState", "Settings", "Steam",
             "SaveMgr", "Sfx", "Bgm", "Gamepad", "I18n", "HudLayout", "ScreenMode",
             "Perf"]

REPORT = "--report" in sys.argv


def strip_code(text):
    """去掉 GDScript 注释（保留行结构），避免把注释里的文件名当成真引用。

    字符串**整体保留**（包括首尾引号）：只剥注释，不改字符串。
    ⚠️ 这里踩过坑：早期实现把字符串的"闭合引号"也替换成了空格，于是
       preload("res://core/Dash.gd") 被切成 preload("res://core/Dash.gd )，
       所有依赖引号配对的正则（比如抓 preload 路径）全部静默失效 —— 表现为
       "孤儿脚本"检测把整个 core/ 报成没人引用。字符串必须原样保留。
    """
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
                    state = '3'
                    out.append('"""')
                    i += 3
                    continue
                state = '"'
            elif c == "'":
                state = "'"
            out.append(c)
        else:
            out.append(c)                     # 字符串内容原样保留
            if state == '3':
                if text.startswith('"""', i):
                    out.append('""')
                    state = None
                    i += 3
                    continue
            elif c == state:
                state = None                  # 闭合引号已经 append 过了
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
        # ⚠️ 必须在【剥掉注释后】的代码上匹配：注释里写"复刻了 EnemyMind._collect_neighbors"
        #    这种解释性文字会被误判成越界读写（scripts/perf_bench.gd 就撞过一次）。
        # ⚠️ 已知边界：字符串**内部**提到 "Obj._field" 仍会被计数 —— 字符串必须
        #    原样保留（否则 R1 抓不到 preload 路径），只能规范书写：诊断打印里
        #    把它写成 "Obj 的 field"（perf_bench.gd 已改）。
        hits = re.findall(r'\b(?!self\b)[a-zA-Z_][a-zA-Z0-9_]*\._[a-zA-Z_]', strip_code(code))
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

    # ---- D3-2 单例守卫：StatsScreen 全仓恰好 new 一次 ----
    # HUD「属性」键与暂停菜单共用 Game 持有的同一份实例，new 第二次就是回归。
    stats_new = 0
    for rel in gd_files():
        if rel == 'scripts/arch_guard.py':
            continue
        raw = open(os.path.join(ROOT, rel), encoding='utf-8', errors='ignore').read()
        stats_new += raw.count('StatsScreenScript.new()')
    if stats_new != 1:
        fails.append("R-singleton StatsScreenScript.new() 出现 %d 次（必须恰好 1 次，单例化）"
                     % stats_new)

    # ---- D3-4 不变量：CharacterPicker.PICKER_MAX_H 不得改大 ----
    # 角色再多也必须整体等比缩，绝不能把 START 顶出 900 设计高（当前封顶 250）。
    picker_src = open(os.path.join(ROOT, 'ui/Screens/CharacterPicker.gd'),
                     encoding='utf-8', errors='ignore').read()
    m_maxh = re.search(r'PICKER_MAX_H\s*:?=\s*([0-9.]+)', picker_src)
    if m_maxh and float(m_maxh.group(1)) > 250.0:
        fails.append("R-picker CharacterPicker.PICKER_MAX_H=%s 超过 250（角色增多须整体等比缩）"
                     % m_maxh.group(1))
    # D3-4 不变量：选角主页只留"形象 + 名字"——详细的属性/亲和/本命文字不许塞回卡片，
    # 一律进每角色一页的 CharDetail（60 个角色也要放得下，不能靠缩小卡片塞信息）。
    if 'Character.describe' in picker_src or 'affinity_text' in picker_src:
        fails.append("R-picker CharacterPicker 又在卡片上画属性/亲和文字（应只留形象+名字，"
                     "详情一律走 ui/Screens/CharDetail.gd 独立页）")
    if not os.path.exists(os.path.join(ROOT, 'ui', 'Screens', 'CharDetail.gd')):
        fails.append("R-picker 缺少 ui/Screens/CharDetail.gd（每个角色必须有自己的详情独立页）")

    # ---- 选武器页不变量：候选池必须是"所有已解锁武器" ----
    # 回归背景：曾经是 list.slice(0, 6)，于是把 40 把武器全解锁了，开局也只能挑那 6 把，
    # 解锁系统一半的意义被这一行吃掉。因此这里既禁硬截断，也要求每把武器有独立详情页。
    wp_src = open(os.path.join(ROOT, 'ui', 'Screens', 'WeaponPicker.gd'),
                  encoding='utf-8', errors='ignore').read()
    if 'unlocked_weapons()' not in wp_src:
        fails.append("R-weaponpool WeaponPicker 候选池没走 SaveMgr.unlocked_weapons()"
                     "（必须 = 所有已解锁武器，不许写死列表）")
    if re.search(r'slice\(\s*0\s*,', wp_src):
        fails.append("R-weaponpool WeaponPicker 又对候选池硬截断（写死前 N 把 = 解锁白做）")
    if not os.path.exists(os.path.join(ROOT, 'ui', 'Screens', 'WeaponDetail.gd')):
        fails.append("R-weaponpool 缺少 ui/Screens/WeaponDetail.gd（每把武器必须有自己的详情独立页）")

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
