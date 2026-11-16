"""Post-process captured frames into pixel-art-ready sprites.

Steps, in order, applied identically to every frame of a capture folder:
  1. Alpha to 0/255 (threshold). Partially transparent edge pixels are what
     make an outline look soft; a sprite pixel is either there or not.
  2. Snap every opaque colour to one shared palette built from the whole
     sequence (most frequent colours first). One palette for all frames means
     the same surface keeps the same colour from frame to frame, so hand
     clean-up does not fight per-frame colour drift.
  3. 1 px outer outline (4-neighbour), in a dark colour, so the silhouette
     reads against any background.

Usage:
  python tools/pixel_post.py <capture_dir> <out_dir> [--max-colors 48]
      [--outline 1a1420] [--alpha 128] [--downscale 1]
--downscale N first shrinks each frame by N with a box filter (only for the
"render big, then shrink" comparison; the recommended path renders at the
final size and uses N=1).
"""
import argparse
import collections
import glob
import json
import os
import shutil

import numpy as np
from PIL import Image


def load(path, downscale):
    im = Image.open(path).convert("RGBA")
    if downscale > 1:
        im = im.resize((im.width // downscale, im.height // downscale), Image.BOX)
    return np.array(im)


def build_palette(frames, alpha_cut, max_colors):
    counts = collections.Counter()
    for a in frames:
        mask = a[:, :, 3] >= alpha_cut
        rgb = a[:, :, :3][mask]
        counts.update(map(tuple, rgb))
    return np.array([c for c, _ in counts.most_common(max_colors)], dtype=np.int32)


def snap(a, palette, alpha_cut):
    out = np.zeros_like(a)
    mask = a[:, :, 3] >= alpha_cut
    rgb = a[:, :, :3][mask].astype(np.int32)
    d = ((rgb[:, None, :] - palette[None, :, :]) ** 2).sum(-1)
    out[:, :, :3][mask] = palette[d.argmin(1)].astype(np.uint8)
    out[:, :, 3][mask] = 255
    return out


def outline(a, color):
    solid = a[:, :, 3] == 255
    grow = np.zeros_like(solid)
    grow[1:, :] |= solid[:-1, :]
    grow[:-1, :] |= solid[1:, :]
    grow[:, 1:] |= solid[:, :-1]
    grow[:, :-1] |= solid[:, 1:]
    ring = grow & ~solid
    out = a.copy()
    out[ring, :3] = color
    out[ring, 3] = 255
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--max-colors", type=int, default=48)
    ap.add_argument("--outline", default="1a1420")
    ap.add_argument("--alpha", type=int, default=128)
    ap.add_argument("--downscale", type=int, default=1)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.src, "f_*.png")))
    frames = [load(f, args.downscale) for f in files]
    palette = build_palette(frames, args.alpha, args.max_colors)
    line = np.array([int(args.outline[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)
    os.makedirs(args.dst, exist_ok=True)
    for f, a in zip(files, frames):
        b = outline(snap(a, palette, args.alpha), line)
        Image.fromarray(b).save(os.path.join(args.dst, os.path.basename(f)))
    meta = os.path.join(args.src, "capture.json")
    if os.path.exists(meta):
        shutil.copy(meta, os.path.join(args.dst, "capture.json"))
    with open(os.path.join(args.dst, "palette.json"), "w") as fp:
        json.dump(["#%02x%02x%02x" % tuple(c) for c in palette.tolist()] + ["#" + args.outline], fp)
    print(f"{len(files)} frames -> {args.dst}, palette {len(palette)}+1 colours")


if __name__ == "__main__":
    main()
