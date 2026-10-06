"""Phase 2c helper (plain Python + PIL, no bpy): a 10 cm grid with labelled axes drawn over a
common.grid_render image, and optionally the projected bones (Gate 3) from a JSON of
[[name, head, tail, deform], ...]."""
import json, sys
from PIL import Image, ImageDraw

R, S, C = 1400, 2.3, (0.0, 0.0, 1.0)
VIEWS = {"side": (1, 2), "front": (0, 2), "top": (0, 1)}


def px(p, view):
    h, v = VIEWS[view]
    return (R / 2 + (p[h] - C[h]) / S * R, R / 2 - (p[v] - C[v]) / S * R)


def overlay(src, out, view, bones=None, crop=None):
    im = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(im)
    h, v = VIEWS[view]
    for k in range(-12, 13):
        w = k / 10
        x = R / 2 + (w - C[h]) / S * R
        y = R / 2 - (w - C[v]) / S * R
        col = (90, 90, 90) if k % 5 else (160, 160, 60)
        d.line([(x, 0), (x, R)], fill=col, width=1)
        d.text((x + 2, 2), "%.1f" % w, fill=(220, 220, 120))
        if 0 <= y <= R:
            d.line([(0, y), (R, y)], fill=col, width=1)
            d.text((2, y + 1), "%.1f" % (w), fill=(220, 220, 120))
    for z in [x / 10 for x in range(0, 20)]:
        y = R / 2 - (z - C[v]) / S * R
        d.line([(0, y), (R, y)], fill=(60, 90, 60) if (z * 10) % 5 else (90, 160, 90), width=1)
        d.text((R - 40, y + 1), "%.1f" % z, fill=(150, 230, 150))
    for b in bones or []:
        name, hd, tl, deform = b
        a, c = px(hd, view), px(tl, view)
        col = (255, 60, 200) if not deform else ((60, 160, 255) if name.endswith(".R") else (255, 220, 40))
        d.line([a, c], fill=col, width=3)
        d.ellipse([a[0] - 4, a[1] - 4, a[0] + 4, a[1] + 4], outline=col, width=2)
    if crop:
        im = im.crop(crop)
    im.save(out)


if __name__ == "__main__":
    src, out, view = sys.argv[1:4]
    bones = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else None
    overlay(src, out, view, bones)
