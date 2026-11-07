#!/usr/bin/env python3
"""把 camera-snapshot.sh 抓的 RG10 原始帧转成能看的 PNG。

    python cam-raw2png.py snap.raw snap.png [宽] [高]

帧的布局（A733 + imx219 实测）：1920x1080 的图按 1920x1088 存，
每像素 16-bit 小端、低 10 位有效（RGGB Bayer）。默认参数就是这套。

只做「能看清是什么」这件事：按 0.5/99.5 分位拉伸、不做 gamma、不做 AWB，
所以颜色会偏；要看准颜色得走 ISP（本板暂时没通）。依赖 numpy + Pillow。
"""
import sys

import numpy as np
from PIL import Image


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    raw, out = sys.argv[1], sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
    height = int(sys.argv[4]) if len(sys.argv) > 4 else 1080

    stride_h = (height + 7) // 8 * 8  # 驱动按 8 行对齐
    data = np.fromfile(raw, dtype="<u2")
    need = width * stride_h
    if data.size < need:
        print(f"{raw}: {data.size} px, expected at least {need}", file=sys.stderr)
        return 1
    plane = data[:need].reshape(stride_h, width)[:height, :]

    v = plane.astype(np.float64)
    lo, hi = np.percentile(v, 0.5), np.percentile(v, 99.5)
    v = np.clip((v - lo) / max(hi - lo, 1.0) * 255.0, 0, 255)

    # RGGB: (0,0)=R (0,1)=Gb (1,0)=Gr (1,1)=B
    r = v[0::2, 0::2]
    g = (v[0::2, 1::2] + v[1::2, 0::2]) / 2.0
    b = v[1::2, 1::2]

    def up(x):
        return np.repeat(np.repeat(x, 2, axis=0), 2, axis=1)[:height, :width]

    rgb = np.clip(np.dstack([up(r), up(g), up(b)]), 0, 255).astype(np.uint8)
    Image.fromarray(rgb).save(out)
    print(f"{out}  ({width}x{height})  plane range {plane.min()}..{plane.max()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
