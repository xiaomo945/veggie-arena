#!/usr/bin/env python3
"""把生成的萝卜贴图转成统一规格：抠背景 -> 归一化画布 -> 输出 art/sprite_char_<key>.png

AI 输出的图是 RGB 不透明图，背景可能是纯色、也可能是烤进图里的"透明棋盘格"。
这里不靠颜色猜背景，而是：
  1) 从四条边界像素出发做容差泛洪，标出所有"能从边缘连通到背景色"的像素；
  2) 剩余的前景再按连通域面积过滤，丢掉小于阈值的孤立碎块（AI 常见的边缘杂色）；
  3) 最后按内容 bbox 等比缩放、底部对齐到统一画布，保证 10 个萝卜视觉大小一致。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SRC = "/workspace/generated-images"
DST = "/workspace/veggie-arena/art"

CANVAS = 512
FILL = 0.82          # 内容高度占画布比例（与基准 turnip 图一致）
BOTTOM_PAD = 0.03    # 脚底留白
# 已是带透明通道的基准图，只需重新归一化，不做抠图
ALREADY_ALPHA = ("turnip",)

TOL = 34             # 泛洪容差（RGB 最大通道差）
MIN_BLOB = 260       # 小于此像素数的连通域视为杂点丢弃
FEATHER = 1.2        # 边缘羽化半径

ASSETS = {
    "skirmisher": "Same_cute_cartoon_daikon_turni_2026-10-04T22-43-16.png",
    "hoarder": "Same_cute_cartoon_daikon_turni_2026-10-04T22-43-19.png",
    "mage": "Same_cute_cartoon_daikon_turni_2026-10-04T22-43-20.png",
    "bruiser": "Same_cute_cartoon_daikon_turni_2026-10-04T22-43-43.png",
    "archer": "Archer_turnip_sprite__same_cut_2026-10-04T22-45-32.png",
    "hedgehog": "Hedgehog_turnip_sprite__same_c_2026-10-04T22-45-29.png",
    "commando": "Commando_turnip_sprite__same_c_2026-10-04T22-45-31.png",
    "martial": "Martial_artist_turnip_sprite___2026-10-04T22-45-31.png",
    "magnet": "Magnet_engineer_turnip_sprite__2026-10-04T22-45-31.png",
}


def flood_background(a: np.ndarray) -> np.ndarray:
    """从图像四边出发泛洪，返回 1=背景 的布尔数组。"""
    h, w, _ = a.shape
    # 背景色基准 = 四条边的中位色（多取样，避开角色伸出边缘的部分）
    edges = np.concatenate([
        a[0, :, :], a[h - 1, :, :], a[:, 0, :], a[:, w - 1, :],
        a[0:3, :, :].reshape(-1, 3), a[h - 3:, :, :].reshape(-1, 3),
    ])
    ref = np.median(edges.astype(float), axis=0)
    # 容差球：以 ref 为中心，半径随离边距离略微放宽（AI 图背景有轻微渐变/噪点）
    dist = np.abs(a.astype(float) - ref).max(axis=2)
    # 低饱和 + 极亮/极暗的一律当背景候选，棋盘格灰也能覆盖
    mx = a.max(axis=2).astype(float)
    mn = a.min(axis=2).astype(float)
    sat = mx - mn
    cand = (dist < TOL) | ((sat < 26) & ((mx > 190) | (mx < 90)))

    seed = np.zeros((h, w), bool)
    seed[0, :] = cand[0, :]
    seed[h - 1, :] = cand[h - 1, :]
    seed[:, 0] = cand[:, 0]
    seed[:, w - 1] = cand[:, w - 1]
    lab, _ = ndimage.label(cand)
    border = set(np.unique(np.concatenate([
        lab[0, :], lab[h - 1, :], lab[:, 0], lab[:, w - 1]])))
    border.discard(0)
    bg = np.isin(lab, list(border))
    return bg


def clean_foreground(fg: np.ndarray) -> np.ndarray:
    """丢掉小连通域碎块，并做闭运算补角色身上的浅色洞。"""
    lab, n = ndimage.label(fg)
    if n == 0:
        return fg
    sizes = ndimage.sum(fg, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= MIN_BLOB
    fg2 = keep[lab]
    # 闭运算：填补角色内部被误判为背景的区域
    m = Image.fromarray((fg2 * 255).astype(np.uint8), "L")
    m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    return np.asarray(m) > 127


def normalize(rgba: np.ndarray) -> Image.Image:
    alpha = np.ascontiguousarray(rgba[:, :, 3])
    # 羽化边缘，避免硬锯齿
    a_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(FEATHER))
    a = np.asarray(a_img).astype(float) / 255.0
    a[alpha < 8] = 0.0
    ys, xs = np.where(a > 0.06)
    if len(ys) == 0:
        return Image.fromarray(rgba, "RGBA")
    y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
    rgb = Image.fromarray(np.ascontiguousarray(rgba[:, :, :3]), "RGB").crop((x0, y0, x1, y1))
    alp = Image.fromarray((a[y0:y1, x0:x1] * 255).astype(np.uint8), "L")
    crop = rgb.convert("RGBA")
    crop.putalpha(alp)
    scale = min(target_h := int(CANVAS * FILL) / crop.height, CANVAS / crop.width)
    crop = crop.resize((max(1, int(round(crop.width * scale))),
                        max(1, int(round(crop.height * scale)))), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ox = (CANVAS - crop.width) // 2
    oy = max(0, CANVAS - crop.height - int(CANVAS * BOTTOM_PAD))
    canvas.alpha_composite(crop, (ox, oy))
    return canvas


def process(key: str, fname: str) -> bool:
    if key in ALREADY_ALPHA:
        src = os.path.join(DST, "sprite_char_%s.png" % key)
    else:
        src = os.path.join(SRC, fname)
    if not os.path.exists(src):
        print("MISSING %s <- %s" % (key, src))
        return False
    a = np.array(Image.open(src).convert("RGB"))
    if key in ALREADY_ALPHA:
        fg = np.array(Image.open(src).convert("RGBA"))[:, :, 3] > 127
    else:
        bg = flood_background(a)
        fg = clean_foreground(~bg)
    rgba = np.dstack([a, (fg * 255).astype(np.uint8)])
    out = normalize(rgba)
    out.save(os.path.join(DST, "sprite_char_%s.png" % key))
    arr = np.asarray(out)
    cov = arr[:, :, 3] > 24
    ys, xs = np.where(cov)
    print("%-11s content %3dx%-3d  cov %4.1f%%  kept %4.1f%%" % (
        key, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1,
        100.0 * cov.mean(), 100.0 * fg.mean()))
    return True


def main() -> int:
    try:
        import scipy  # noqa: F401
    except ImportError:
        print("需要 scipy，请先 pip3 install scipy")
        return 2
    ok = True
    for k in sorted(set(list(ASSETS.keys()) + list(ALREADY_ALPHA))):
        ok = process(k, ASSETS.get(k, "")) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
