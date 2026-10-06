"""System Python: lay PNGs side by side with captions.  python3 sheet.py OUT.png A.png:cap B.png:cap ..."""
import sys
from PIL import Image, ImageDraw
out, items = sys.argv[1], [a.split(":", 1) for a in sys.argv[2:]]
ims = [(Image.open(p).convert("RGB"), c) for p, c in items]
W = sum(i.width for i, _ in ims); H = max(i.height for i, _ in ims) + 22
s = Image.new("RGB", (W, H), "white"); d = ImageDraw.Draw(s); x = 0
for im, c in ims:
    s.paste(im, (x, 22)); d.text((x + 6, 5), c, fill="black"); x += im.width
s.save(out); print(out)
