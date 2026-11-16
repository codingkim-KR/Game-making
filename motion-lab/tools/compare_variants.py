"""Side-by-side comparison of capture variants (sword 3-hit combo).

Expects these folders from tools/capture_motion.gd and tools/pixel_post.py:
  capture_raw/sword_combo_native  (soft toon, MSAA 2x, 112.5 px/m -> shrunk 2x)
  capture_raw/sword_combo_soft    (soft toon, no AA, 56.25 px/m)
  capture_raw/sword_combo_hard    (hard 3-band toon, no AA, 56.25 px/m)
  capture_raw/sword_combo_pixel   (hard + pixel_post.py)
Writes ../docs/pixel-pipeline/compare_sword_combo.png, zoom_frame20.png and
metrics.json (distinct opaque colours and share of semi-transparent pixels).
"""
import glob
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = "../docs/pixel-pipeline"
FONT = "assets/fonts/NotoSansKR.otf"
ROWS = [
    ("A  지금 방식: 크게 렌더링(MSAA) 후 축소", "sword_combo_native", 2),
    ("B  최종 크기로 직접 렌더링 (기존 부드러운 명암)", "sword_combo_soft", 1),
    ("C  최종 크기 + 명암 3단계 (hero_toon_pixel)", "sword_combo_hard", 1),
    ("D  C + 반투명 제거 · 팔레트 고정 · 1px 외곽선", "sword_combo_pixel", 1),
]
FRAMES = [5, 20, 33, 38]
CAPTIONS = ["1타 타격", "2타 타격", "3타 준비", "3타 타격"]


def frame(d, i, ds):
    im = Image.open(f"capture_raw/{d}/f_{i:04d}.png").convert("RGBA")
    if ds > 1:
        im = im.resize((im.width // ds, im.height // ds), Image.BOX)
    return im


def sheet():
    font = ImageFont.truetype(FONT, 30)
    small = ImageFont.truetype(FONT, 22)
    x0, y0, x1, y1 = 30, 22, 191, 163
    s, lab, pad = 3, 56, 12
    cw, ch = (x1 - x0) * s, (y1 - y0) * s
    img = Image.new("RGBA", (pad + len(FRAMES) * (cw + pad), lab + len(ROWS) * (ch + lab + pad)), (78, 84, 98, 255))
    d = ImageDraw.Draw(img)
    for j, c in enumerate(CAPTIONS):
        d.text((pad + j * (cw + pad) + 8, 10), f"{c} (프레임 {FRAMES[j]})", font=small, fill=(230, 230, 230))
    for r, (title, folder, ds) in enumerate(ROWS):
        yb = lab + r * (ch + lab + pad)
        d.text((pad, yb + 6), title, font=font, fill=(255, 236, 170))
        for j, i in enumerate(FRAMES):
            im = frame(folder, i, ds).crop((x0, y0, x1, y1)).resize((cw, ch), Image.NEAREST)
            img.alpha_composite(im, (pad + j * (cw + pad), yb + lab))
    img.convert("RGB").save(f"{OUT}/compare_sword_combo.png")

    zs, box = 10, (95, 40, 150, 95)
    bw, bh = (box[2] - box[0]) * zs, (box[3] - box[1]) * zs
    z = Image.new("RGBA", (pad + len(ROWS) * (bw + pad), bh + lab + pad), (78, 84, 98, 255))
    dz = ImageDraw.Draw(z)
    for r, (title, folder, ds) in enumerate(ROWS):
        xo = pad + r * (bw + pad)
        z.alpha_composite(frame(folder, 20, ds).crop(box).resize((bw, bh), Image.NEAREST), (xo, lab))
        dz.text((xo, 10), title[:1], font=font, fill=(255, 236, 170))
    z.convert("RGB").save(f"{OUT}/zoom_frame20.png")


def metrics():
    res = {}
    for title, folder, ds in ROWS:
        cols, semi, vis = set(), 0, 0
        for f in sorted(glob.glob(f"capture_raw/{folder}/f_*.png")):
            im = Image.open(f).convert("RGBA")
            if ds > 1:
                im = im.resize((im.width // ds, im.height // ds), Image.BOX)
            a = np.array(im)
            al = a[:, :, 3]
            vis += int((al > 0).sum())
            semi += int(((al > 0) & (al < 255)).sum())
            cols.update(map(tuple, a[:, :, :3][al == 255].tolist()))
        res[title] = {"distinct_opaque_colours": len(cols), "semi_transparent_pct": round(100 * semi / vis, 2)}
        print(title, res[title])
    with open(f"{OUT}/metrics.json", "w") as fp:
        json.dump(res, fp, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sheet()
    metrics()
