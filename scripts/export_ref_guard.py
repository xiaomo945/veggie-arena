#!/usr/bin/env python3
# 导出引用守卫：会进 pck 的运行时代码，不许引用导出排除清单里的路径，
# 也不许引用仓库里不存在的文件；main_scene / autoload 出事 = 100% 黑屏，单独盯。
#
# 事故背景（2026-10 线上黑屏，查了一整轮才定位）：
#   ui/Screens/Main.gd 顶部 const preload("res://scripts/SimArt.gd") ——
#   scripts/* 在 export_presets.cfg 的 exclude_filter 里。编辑器里文件在磁盘，
#   源码跑测（Xvfb/headless）天天全绿；web pck 里根本没有这文件 →
#   主场景脚本加载失败 → 加载完停在近黑底色，用户看到纯黑屏。
#   这类错误【本地全绿、线上黑屏】，没有任何现有门禁能抓到，故补此一道。
#
# 规则（对每个导出预设分别判定）：
#   R-x1 运行时代码不许引用该预设 exclude_filter 排除的路径
#        （preload/load/ext_resource 都算；const preload 缺文件 = 脚本直接加载失败）；
#   R-x2 运行时代码的 res:// 引用必须能在仓库里找到真实文件
#        （抓"文件挪了窝、引用没跟着改"—— 本 bug 的另一种形态）；
#   R-x3 run/main_scene 与全部 autoload 必须存在且不被任何预设排除
#        （这两样出事 = 100% 黑屏，且排查成本最高）。
#
# 用法：python3 scripts/export_ref_guard.py

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'scripts'))
from arch_guard import strip_code  # 复用：剥注释保留字符串（preload 路径在字符串里）

SCAN_EXTS = ('.gd', '.tscn', '.tres')
SKIP_DIRS = {'.git', '.godot', 'build', 'node_modules', '__pycache__'}
RES_RE = re.compile(r'res://[A-Za-z0-9_][A-Za-z0-9_./\-]*')


def read_presets():
    """解析 export_presets.cfg → [{name, exclude[], include[]}]"""
    path = os.path.join(ROOT, 'export_presets.cfg')
    if not os.path.exists(path):
        return []
    presets, cur = [], None
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if re.match(r'^\[preset\.\d+\]$', line):
                cur = {'name': '', 'exclude': [], 'include': []}
                presets.append(cur)
                continue
            if line.startswith('['):
                cur = None
                continue
            if cur is None or '=' not in line:
                continue
            k, _, v = line.partition('=')
            k, v = k.strip(), v.strip().strip('"')
            if k == 'name':
                cur['name'] = v
            elif k == 'exclude_filter':
                cur['exclude'] = [p.strip() for p in v.split(',') if p.strip()]
            elif k == 'include_filter':
                cur['include'] = [p.strip() for p in v.split(',') if p.strip()]
    return presets


def pattern_to_prefix(pat):
    """'scripts/*' → 'scripts/'；'foo.gd' → 'foo.gd'（精确文件）"""
    if pat.endswith('/*'):
        return pat[:-2] + '/'
    if pat.endswith('*'):
        return pat[:-1]
    return pat


def under_any(rel, prefixes):
    """rel 是去掉 res:// 后的仓库相对路径；命中返回前缀，否则 None"""
    for p in prefixes:
        if p.endswith('/'):
            if rel.startswith(p):
                return p
        elif rel == p:
            return p
    return None


def scan_files(excluded):
    """会进 pck 的文件：全仓 .gd/.tscn/.tres，剔除被排除目录整体与构建噪声目录"""
    res = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if not f.endswith(SCAN_EXTS):
                continue
            rel = os.path.relpath(os.path.join(base, f), ROOT).replace(os.sep, '/')
            if under_any(rel, excluded):
                continue
            res.append(rel)
    return sorted(res)


def refs_of(rel, complete_only):
    """抽取文件里的 res:// 引用；.gd 先剥注释（复用架构守卫的实现）。
    complete_only=True 时只要"完整文件"形态（basename 带扩展名），
    动态拼接的 "res://art/" + name 不会被当成引用。"""
    with open(os.path.join(ROOT, rel), encoding='utf-8', errors='ignore') as fh:
        text = fh.read()
    if rel.endswith('.gd'):
        text = strip_code(text)
    out = []
    for m in RES_RE.finditer(text):
        r = m.group(0)
        if complete_only and '.' not in r.rsplit('/', 1)[-1]:
            continue
        out.append(r)
    return out


def project_entries():
    """project.godot 里的 main_scene 与 autoload 路径（res:// 形式）"""
    out = []
    path = os.path.join(ROOT, 'project.godot')
    if not os.path.exists(path):
        return out
    section = None
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            s = line.strip()
            if s.startswith('['):
                section = s
                continue
            if section == '[application]' and s.startswith('run/main_scene'):
                v = s.split('=', 1)[1].strip().strip('"')
                if v.startswith('res://'):
                    out.append(('main_scene', v))
            elif section == '[autoload]' and '=' in s:
                v = s.split('=', 1)[1].strip().strip('"')
                if v.startswith('*'):
                    v = v[1:]
                if v.startswith('res://'):
                    out.append((s.split('=', 1)[0].strip(), v))
    return out


def main():
    presets = read_presets()
    if not presets:
        print("  ⚠ 找不到 export_presets.cfg，跳过")
        return 0
    fails = []
    total_refs = 0

    for p in presets:
        excl = [pattern_to_prefix(x) for x in p['exclude']]
        incl = [pattern_to_prefix(x) for x in p['include']]
        files = scan_files(excl)
        # ---- R-x1 / R-x2 ----
        for rel in files:
            # R-x1 用全量匹配（含 "res://scripts/" 这种半截路径）：宁可误报也不漏
            for r in refs_of(rel, complete_only=False):
                total_refs += 1
                hit = under_any(r[len('res://'):], excl)
                if hit:
                    fails.append("R-x1 %s 引用了 %s —— 被预设「%s」的 exclude_filter "
                                 "排除（%s）。该预设的构建包里没这个文件：编辑器里能跑、"
                                 "发出去黑屏" % (rel, r, p['name'], hit))
            # R-x2 只查完整路径：文件必须真实存在
            for r in refs_of(rel, complete_only=True):
                if not os.path.exists(os.path.join(ROOT, r[len('res://'):])):
                    fails.append("R-x2 %s 引用了 %s，但仓库里没有这个文件"
                                 "（文件被挪走/删了？引用没跟着改）" % (rel, r))

    # ---- R-x3：main_scene / autoload 必须存在且不被任何预设排除 ----
    any_excl = []
    for p in presets:
        for pre in [pattern_to_prefix(x) for x in p['exclude']]:
            if pre not in any_excl:
                any_excl.append(pre)
    for key, r in project_entries():
        rel = r[len('res://'):]
        if not os.path.exists(os.path.join(ROOT, rel)):
            fails.append("R-x3 project.godot 的 %s = %s 不存在（主场景/autoload 缺失 "
                         "= 启动即黑屏）" % (key, r))
            continue
        for p in presets:
            hit = under_any(rel, [pattern_to_prefix(x) for x in p['exclude']])
            if hit:
                fails.append("R-x3 project.godot 的 %s = %s 被预设「%s」排除（%s）—— "
                             "该预设启动即黑屏" % (key, r, p['name'], hit))

    if fails:
        print("❌ 导出引用守卫失败（%d 项）：" % len(fails))
        for f in fails:
            print("   - " + f)
        print("")
        print("  说明：被 exclude_filter 排除的路径在 pck 里不存在，运行时 preload/")
        print("        load 会直接失败。修法：把文件移进会进包的目录（如 ui/sim/），")
        print("        或去掉无用的引用。")
        return 1

    print("  ✅ 导出引用守卫通过：%d 个预设 / %d 处 res:// 引用无排除项、无死链，"
          "main_scene 与 autoload 全部在位" % (len(presets), total_refs))
    return 0


if __name__ == '__main__':
    sys.exit(main())
