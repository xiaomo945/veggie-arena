#!/usr/bin/env python3
"""图集合并：art/icon_*.png + art/ui/icon_*.png → art/atlas.png + art/atlas.json

为什么合并：Web 端每张小图标都是一张独立纹理，商店/HUD 一帧要切换几十次
纹理绑定（draw call 前置开销），pck 里也是几十份零碎文件。合并成一张图集后
所有 UI 图标共享一次纹理绑定；Art.gd 运行时用 AtlasTexture 取区域。

空间：不裁边装不下 PoT 2048x2048（低端 GPU 纹理上限通常是 4096，8192 不保险）。
每个图标先裁掉透明边再装箱；裁掉的边距写进清单，运行时用 AtlasTexture.margin
贴回去 —— 画出来的结果和原图逐像素等价（只是显存里不再存那些透明像素）。

清单（atlas.json）按 Art.gd 的寻名规则存键：
  art/icon_<name>.png     → "icon_<name>"
  art/ui/icon_<name>.png  → "ui/icon_<name>"
每项 [x, y, w, h, ox, oy, w0, h0]：图集区域 + 裁边偏移 + 原始画布尺寸。
普通 .json 会随 pck 导出（data/balance.json 已验证同样机制在跑）。

用法：
  python3 scripts/build_atlas.py           # 重建图集 + 清单
  python3 scripts/build_atlas.py --verify  # 门禁：清单/图集一致性校验
"""
import glob
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
PAD = 2          # 图标间距：nearest 采样不串色
ROW_W = 2048     # 目标 PoT 宽；高按内容定，最终向上取 PoT
PREFIX = "icon_"


def norm(name: str) -> str:
    # 与 Art.normalize 同规则（小写 / 空格连字符转下划线 / 压缩连续下划线）
    s = name.strip().lower().replace(" ", "_").replace("-", "_")
    while "__" in s:
        s = s.replace("__", "_")
    return s


def collect() -> dict:
    """返回 {atlas键: 绝对路径}。两个目录的键不重叠（ui/ 前缀区分）。"""
    out = {}
    for p in sorted(glob.glob(os.path.join(ART, PREFIX + "*.png"))):
        out[norm(os.path.basename(p)[:-4])] = p
    for p in sorted(glob.glob(os.path.join(ART, "ui", PREFIX + "*.png"))):
        out["ui/" + norm(os.path.basename(p)[:-4])] = p
    return out


def build() -> int:
    imgs = {}
    for k, p in collect().items():
        im = Image.open(p).convert("RGBA")
        w0, h0 = im.size
        bbox = im.getbbox()   # 非透明内容范围（含 alpha）
        ox, oy = 0, 0
        if bbox is not None and bbox != (0, 0, w0, h0):
            ox, oy, x1, y1 = bbox
            im = im.crop(bbox)
        imgs[k] = (im, ox, oy, w0, h0)
    # 行排装箱：按高降序，行宽 ROW_W
    order = sorted(imgs, key=lambda k: -max(imgs[k][0].height, imgs[k][0].width))
    rect, x, y, row_h = {}, 0, 0, 0
    for k in order:
        w, h = imgs[k][0].size
        if x + w + PAD > ROW_W:
            x, y, row_h = 0, y + row_h + PAD, 0
        rect[k] = [x, y, w, h]
        x += w + PAD
        row_h = max(row_h, h)
    # 高度不强制 PoT：GLES3 / WebGL2 都支持 NPOT，按 8px 向上取整即可
    H = ((y + row_h) + 7) // 8 * 8
    if H > ROW_W * 2:
        print("❌ 图集高 %d 超过 2×%d，图标总量该瘦身了" % (H, ROW_W))
        return 1
    atlas = Image.new("RGBA", (ROW_W, H), (0, 0, 0, 0))
    for k, (px, py, w, h) in rect.items():
        atlas.paste(imgs[k][0], (px, py))
    # 清单补上裁边信息
    man_rects = {k: rect[k] + [imgs[k][1], imgs[k][2], imgs[k][3], imgs[k][4]] for k in rect}
    atlas.save(os.path.join(ART, "atlas.png"))
    with open(os.path.join(ART, "atlas.json"), "w", encoding="utf-8") as f:
        json.dump({"size": [ROW_W, H], "rects": man_rects}, f, ensure_ascii=False, indent=0, sort_keys=True)
    print("atlas: %d icons -> %dx%d (atlas.png + atlas.json)" % (len(rect), ROW_W, H))
    return 0


def verify() -> int:
    errs = []
    man_path = os.path.join(ART, "atlas.json")
    if not os.path.exists(man_path):
        print("  ❌ 缺少 art/atlas.json（跑 python3 scripts/build_atlas.py 重建）")
        return 1
    man = json.load(open(man_path, encoding="utf-8"))
    atlas = Image.open(os.path.join(ART, "atlas.png")).convert("RGBA")
    if list(atlas.size) != man["size"]:
        errs.append("atlas.png 尺寸 %s ≠ 清单 %s" % (atlas.size, man["size"]))
    for k, v in man["rects"].items():
        x, y, w, h = v[0], v[1], v[2], v[3]
        if atlas.crop((x, y, x + w, y + h)).getbbox() is None:
            errs.append("区域为空: %s" % k)
    # 现存的 icon 源文件必须都在清单里（新增图标忘了重建图集 → 这里红）
    for k in collect():
        if k not in man["rects"]:
            errs.append("图标 %s 不在图集里（重建：python3 scripts/build_atlas.py）" % k)
    # 武器表里的每个 key 必须有 icon_weapon_<key>（漏美术直接红）
    weapons = json.load(open(os.path.join(ROOT, "data", "weapons.json"), encoding="utf-8"))
    for k in weapons:
        if k.startswith("_"):
            continue
        if norm("icon_weapon_" + str(k)) not in man["rects"]:
            errs.append("武器 %s 缺图标 icon_weapon_%s" % (k, k))
    if errs:
        print("  ❌ 图集校验失败：")
        for e in errs:
            print("     - " + e)
        return 1
    print("  ✅ 图集一致：%d 个图标 / %dx%d / 武器表全覆盖" % (len(man["rects"]), *man["size"]))
    return 0


if __name__ == "__main__":
    sys.exit(verify() if "--verify" in sys.argv else build())
