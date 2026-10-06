"""System Python: draw the 10 cm grid (labelled every 20 cm) and, optionally, bones on a
grid_render PNG. Bones: a JSON list of [name, head_xyz, tail_xyz, colour]."""
import json, sys
from PIL import Image, ImageDraw

R, S, C = 1400, 2.7, (0.0, 0.0, 1.25)
VIEWS = {"side": (1, 2), "front": (0, 2)}


def px(p, view):
    h, v = VIEWS[view]
    return (R / 2 + (p[h] - C[h]) / S * R, R / 2 - (p[v] - C[v]) / S * R)


def overlay(src, out, view, bones=None, points=None):
    im = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(im)
    h, v = VIEWS[view]
    lo_h, hi_h = C[h] - S / 2, C[h] + S / 2
    lo_v, hi_v = C[v] - S / 2, C[v] + S / 2
    k = round(lo_h, 1)
    while k <= hi_h:
        x = px([k if i == h else 0 for i in range(3)], view)[0]
        major = abs(round(k * 10) % 2) == 0
        d.line((x, 0, x, R), fill=(90, 90, 90) if major else (60, 60, 60), width=1)
        if major:
            d.text((x + 2, 2), "%.1f" % k, fill=(255, 255, 0))
        k = round(k + 0.1, 2)
    k = round(lo_v, 1)
    while k <= hi_v:
        y = px([k if i == v else 0 for i in range(3)], view)[1]
        major = abs(round(k * 10) % 2) == 0
        d.line((0, y, R, y), fill=(90, 90, 90) if major else (60, 60, 60), width=1)
        if major:
            d.text((2, y + 2), "%.1f" % k, fill=(255, 255, 0))
        k = round(k + 0.1, 2)
    for name, hd, tl, col in bones or []:
        a, b = px(hd, view), px(tl, view)
        d.line((a, b), fill=tuple(col), width=4)
        d.ellipse((a[0] - 5, a[1] - 5, a[0] + 5, a[1] + 5), outline=tuple(col), width=2)
    for name, p, col in points or []:
        a = px(p, view)
        d.ellipse((a[0] - 6, a[1] - 6, a[0] + 6, a[1] + 6), fill=tuple(col))
        d.text((a[0] + 8, a[1] - 6), name, fill=tuple(col))
    im.save(out)
    return out


if __name__ == "__main__":
    src, out, view = sys.argv[1:4]
    extra = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
    print(overlay(src, out, view, extra.get("bones"), extra.get("points")))
