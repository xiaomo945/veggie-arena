#!/usr/bin/env python
"""A/B diff：合批前后敌人渲染逐像素比对（veggie-arena ②）。"""
import sys
import numpy as np
from PIL import Image

def regions(mask, min_area=40):
    """把差异掩码聚类成区域（简单 4 邻域连通），返回 [(x0,y0,x1,y1,area)]。"""
    from collections import deque
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    H, W = mask.shape
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        x1r = y1r = 0
        area = 0
        x_min, y_min, x_max, y_max = x0, y0, x0, y0
        while q:
            y, x = q.popleft()
            area += 1
            x_min, x_max = min(x_min, x), max(x_max, x)
            y_min, y_max = min(y_min, y), max(y_max, y)
            for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                ny, nx = y+dy, x+dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if area >= min_area:
            out.append((x_min, y_min, x_max, y_max, area))
    return sorted(out, key=lambda r: -r[4])

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int16)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.int16)
d = np.abs(a - b).max(axis=2)
mask = d > 12
n = int(mask.sum())
print(f"size={a.shape[1]}x{a.shape[0]}  diff_pixels={n}  ({100.0*n/mask.size:.3f}%)")
for r in regions(mask):
    print(f"  region x[{r[0]}..{r[2]}] y[{r[1]}..{r[3]}] area={r[4]}")
