"""System Python: tile frame PNGs into a contact sheet, or write them as a GIF.

    python3 tile.py OUT.png COLS A.png B.png ...      (each tile captioned with its file's stem)
    python3 tile.py OUT.gif FPS A.png B.png ...
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

out, n, files = sys.argv[1], sys.argv[2], sys.argv[3:]
ims = [Image.open(f).convert("RGB") for f in files]
if out.endswith(".gif"):
    ims[0].save(out, save_all=True, append_images=ims[1:], duration=int(1000 / float(n)), loop=0)
else:
    cols = int(n)
    w, h = ims[0].size
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * (h + 18)), "white")
    d = ImageDraw.Draw(sheet)
    for i, (im, f) in enumerate(zip(ims, files)):
        x, y = (i % cols) * w, (i // cols) * (h + 18)
        sheet.paste(im, (x, y + 18))
        d.text((x + 4, y + 3), Path(f).stem, fill="black")
    sheet.save(out)
print(out)
