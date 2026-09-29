#!/usr/bin/env python3
"""去背处理：边缘泛洪去背景 → 只留最大连通域(顺带去掉水印等碎片) → 裁剪到内容bbox → 缩放到256。

用法: python3 _bgremove.py 输入.png 输出.png [bg_threshold]
背景色取四角中位数；只从图像边缘开始泛洪， sprite 内部的白色高光/牙齿不会被误删。
"""
import sys
from collections import deque
import numpy as np
from PIL import Image

def process(src, dst, thr=42.0, out_size=256):
    im = Image.open(src).convert("RGBA")
    arr = np.array(im).astype(np.int16)
    h, w = arr.shape[:2]
    rgb = arr[..., :3]

    # 背景色 = 四角 12x12 区域中位数
    corners = np.concatenate([
        rgb[:12, :12].reshape(-1, 3), rgb[:12, -12:].reshape(-1, 3),
        rgb[-12:, :12].reshape(-1, 3), rgb[-12:, -12:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)

    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    is_bg = dist < thr

    # 从边缘泛洪（只删与边缘连通的背景，保护 sprite 内部同色区域）
    bgflood = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg[y, x] and not bgflood[y, x]:
                bgflood[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg[y, x] and not bgflood[y, x]:
                bgflood[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
            if 0 <= ny < h and 0 <= nx < w and is_bg[ny, nx] and not bgflood[ny, nx]:
                bgflood[ny, nx] = True; q.append((ny, nx))

    alpha = arr[..., 3].copy()
    alpha[bgflood] = 0

    # 连通域：只保留最大的一块（水印/游离碎片全清掉）
    solid = alpha > 0
    label = np.zeros((h, w), dtype=np.int32)
    cur = 0
    best, best_size = 0, 0
    for y0 in range(h):
        for x0 in range(w):
            if solid[y0, x0] and label[y0, x0] == 0:
                cur += 1
                size = 0
                q = deque([(y0, x0)])
                label[y0, x0] = cur
                while q:
                    y, x = q.popleft()
                    size += 1
                    for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
                        if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and label[ny, nx] == 0:
                            label[ny, nx] = cur
                            q.append((ny, nx))
                if size > best_size:
                    best, best_size = cur, size
    keep = (label == best)
    alpha[~keep] = 0

    # 裁到内容 bbox（留 2px 边）再缩放
    ys, xs = np.nonzero(alpha)
    pad = 2
    y0, y1 = max(0, ys.min()-pad), min(h, ys.max()+1+pad)
    x0, x1 = max(0, xs.min()-pad), min(w, xs.max()+1+pad)
    out = np.dstack([rgb, alpha]).astype(np.uint8)[y0:y1, x0:x1]
    img = Image.fromarray(out, "RGBA")
    img = img.resize((out_size, out_size), Image.LANCZOS)
    img.save(dst)
    kept = best_size / (h * w) * 100
    print(f"OK {dst}  bbox=({x0},{y0},{x1},{y1}) 主体占比 {kept:.0f}%  尺寸 {w}x{h} -> {out_size}")

if __name__ == "__main__":
    process(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 42.0)
