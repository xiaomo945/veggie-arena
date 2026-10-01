#!/usr/bin/env python3
# 重新生成中文子集字体 fonts/NotoSansSC-Subset.otf
#
# 作用：扫描项目里所有用到的中文（.gd/.json 等），从系统全量
# Noto Sans CJK SC 里子集化出一份只含"用到字符 + 常用标点/全角"的字体。
# 这样既保证当前中文 100% 显示（不豆腐块），体积又小（~2.7MB，gzip ~2.3MB），
# 远小于打包整个 CJK（~13MB）。
#
# 什么时候要跑：
#   1) 加了新中文文案 / 新武器名 / 新角色名后，scripts/check.sh 报"字体缺字"时；
#   2) 切换了系统全量字体路径时（见下方 FULL 变量）。
#
# 依赖：pip install fonttools
import os, re, sys
from fontTools.ttLib import TTFont
from fontTools import subset as ft_subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 系统全量 Noto Sans CJK（简体中文字面序号 2）。若路径不同请改这里。
FULL = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
SC_FACE = 2  # Noto Sans CJK SC
OUT = os.path.join(ROOT, "fonts", "NotoSansSC-Subset.otf")
CJK = re.compile(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3000-\u303F\uFF00-\uFFEF]')

def used_chars():
    s = set()
    for base, _, files in os.walk(ROOT):
        if '/.git' in base or '/.godot' in base:
            continue
        for f in files:
            if not f.endswith(('.gd', '.json', '.tres', '.cfg', '.md', '.csv', '.txt')):
                continue
            for ch in open(os.path.join(base, f), encoding='utf-8', errors='ignore').read():
                if CJK.match(ch):
                    s.add(ch)
    return s

def main():
    used = used_chars()
    # 用到字符 + ASCII + 常用标点/全角 + 扩展A（少量罕见字兜底）
    uni = set(ord(c) for c in used)
    for lo, hi in [(0x20, 0x7E), (0x2000, 0x206F), (0x3000, 0x303F),
                   (0x3400, 0x4DBF), (0xFF00, 0xFFEF)]:
        uni.update(range(lo, hi + 1))
    if not os.path.exists(FULL):
        sys.exit("找不到全量字体: %s\n请安装 fonts-noto-cjk 或修改脚本里的 FULL 路径" % FULL)
    font = TTFont(FULL, fontNumber=SC_FACE)
    ss = ft_subset.Subsetter()
    ss.options.glyph_names = False
    ss.options.name_IDs = ['*']
    ss.options.recalc_timestamp = False
    ss.options.drop_tables = []
    ss.populate(unicodes=uni)
    ss.subset(font)
    font.save(OUT)
    cm = TTFont(OUT).getBestCmap()
    miss = [c for c in used if ord(c) not in cm]
    print("写出 %s" % OUT)
    print("子集字符数: %d  仍缺失: %d" % (len(cm), len(miss)))
    if miss:
        print("警告：以下用到字符仍缺失 ->", ''.join(miss))
        sys.exit(1)

if __name__ == "__main__":
    main()
