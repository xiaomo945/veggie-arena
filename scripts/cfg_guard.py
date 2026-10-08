#!/usr/bin/env python3
"""项目配置守卫：防止 project.godot 里的设置【静默失效】。

两道检查：

1. 键名污染扫描
   Godot 的 ConfigFile 解析器会把一段非 ASCII 注释并进紧邻的下一个键名，
   于是键变成 "<中文注释>window/dpi/allow_hidpi"，该设置等于没写。
   文件看着对、运行时读回来是引擎默认值、全程无报错 —— 纯静默失效。
   已发生过两次（HiDPI 那条就因此一直是 true，等于手机按 DPR 2~3 渲染）。

2. 关键设置读回校验
   用 Godot 真正跑一遍把值读回来比对。只看文件不算数，必须看运行时。

用法：python3 scripts/cfg_guard.py
"""
import os
import re
import subprocess
import sys

GODOT = os.environ.get("GODOT", "/opt/godot/Godot_v4.3-stable_linux.x86_64")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 运行时必须等于的值（改这里的期望值前先想清楚为什么）
EXPECT = {
    "physics/common/physics_interpolation": "true",          # judder
    "physics/common/physics_ticks_per_second": "60",
    "display/window/dpi/allow_hidpi": "false",               # 手机填充率命门
    "display/window/size/viewport_width": "540",             # 竖屏
    "display/window/size/viewport_height": "900",
    "input_devices/pointing/emulate_mouse_from_touch": "true",  # 手机点不动
    "rendering/renderer/rendering_method": "gl_compatibility",  # Web 兼容
}

SECTION = re.compile(r"^\[([^\]]+)\]\s*$")
KV = re.compile(r"^([A-Za-z0-9_./]+)\s*=")


def scan_comment_pollution(path):
    """找出被非 ASCII 注释污染的键（键行本身正常，但上一行是中文注释时
    Godot 会把注释并进键名 —— 这里只在键名里出现非 ASCII 时才能发现，
    所以同时对"中文注释紧邻键"作预防性告警）。"""
    bad_keys, risky = [], []
    section = ""
    prev_cjk = False
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        s = line.strip()
        m = SECTION.match(s)
        if m:
            section = m.group(1)
            prev_cjk = False
            continue
        if not s or s.startswith(";") or s.startswith("#"):
            if any(ord(c) > 127 for c in s):
                prev_cjk = True
            continue
        m = KV.match(s)
        if m:
            key = m.group(1)
            if any(ord(c) > 127 for c in key):
                bad_keys.append((i, section, key[-50:]))
            elif prev_cjk:
                risky.append((i, section, key))
            prev_cjk = False
    return bad_keys, risky


def main() -> int:
    path = os.path.join(ROOT, "project.godot")
    print("=== 项目配置守卫（防静默失效）===")
    bad_keys, risky = scan_comment_pollution(path)
    if bad_keys:
        for i, sec, k in bad_keys:
            print("  ❌ 第 %d 行键名被注释污染：[%s] ...%s" % (i, sec, k))
        print("     修法：把那几行中文注释改成英文（或删掉），再跑一次。")
        return 1
    if risky:
        for i, sec, k in risky:
            print("  ⚠ 第 %d 行 [%s] %s 上方紧邻中文注释" % (i, sec, k))
            print("     （本次键名没被污染，但同样的写法污染过两次，建议改英文注释）")

    out = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--script", "res://tests/CfgProbe.gd"],
        capture_output=True, text=True, timeout=120).stdout
    got = dict(re.findall(r"^CFG (\S+)=(.*)$", out, re.M))
    if not got:
        print("  ❌ 探针没输出（tests/CfgProbe.gd 挂了？）")
        return 1
    bad = []
    for k, want in EXPECT.items():
        v = got.get(k, "MISSING")
        if v != want:
            bad.append("%s = %s（应为 %s）" % (k, v, want))
    if bad:
        for b in bad:
            print("  ❌ 运行时读回不符：" + b)
        print("     文件里写了但实际没生效 —— 多半又是注释污染，或键名拼错。")
        return 1
    print("  ✅ %d 个关键设置运行时读回全部正确（无注释污染）" % len(EXPECT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
