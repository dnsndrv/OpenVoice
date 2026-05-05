#!/usr/bin/env python3
"""Generate macOS-compliant rounded AppIcon variants from a single 1024×1024 PNG.

Apple's icon template (Big Sur+) places the visible icon body inside an
824×824 rounded square centered in a 1024×1024 transparent canvas. The
corner radius matches the system squircle. We approximate it with a
superellipse (|x/a|^n + |y/b|^n = 1, n≈5) which is what Apple uses; a plain
rounded-rectangle is visually close at small sizes but the squircle reads
better at 256+ and matches Dock siblings.
"""
import sys, os
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops

SRC = sys.argv[1]
DST_DIR = Path(sys.argv[2])
DST_DIR.mkdir(parents=True, exist_ok=True)

CANVAS = 1024
BODY = 824
INSET = (CANVAS - BODY) // 2  # 100
SUPER_N = 5.0  # squircle exponent — closer to Apple's template than 4.0

def squircle_mask(size: int) -> Image.Image:
    """Filled white squircle on transparent of `size`×`size`."""
    s = max(size, 1024)  # supersample for crispness
    img = Image.new("L", (s, s), 0)
    px = img.load()
    half = s / 2.0
    for y in range(s):
        ny = (y + 0.5 - half) / half
        for x in range(s):
            nx = (x + 0.5 - half) / half
            v = abs(nx) ** SUPER_N + abs(ny) ** SUPER_N
            px[x, y] = 255 if v <= 1.0 else 0
    return img.resize((size, size), Image.LANCZOS)

print(f"▶ Generating squircle mask {BODY}×{BODY} (this takes ~5s)...")
mask = squircle_mask(BODY)

src = Image.open(SRC).convert("RGBA")
if src.size != (CANVAS, CANVAS):
    src = src.resize((CANVAS, CANVAS), Image.LANCZOS)

# Crop body region directly from the gradient source so colors fill the
# entire visible icon — the squircle only clips edges.
body = src.crop((INSET, INSET, INSET + BODY, INSET + BODY))
body.putalpha(mask)

# Compose onto transparent 1024 canvas (the 100px margin is part of the
# template — Dock and Finder rely on it for shadows / hover effects).
master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
master.paste(body, (INSET, INSET), body)
master_path = DST_DIR / "_master_1024.png"
master.save(master_path)
print(f"✓ master written: {master_path}")

variants = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for name, size in variants:
    out = master.resize((size, size), Image.LANCZOS)
    out.save(DST_DIR / name, optimize=True)
    print(f"✓ {name}  {size}×{size}")

# master file is just a build artifact, don't ship it
master_path.unlink()
print("done.")
