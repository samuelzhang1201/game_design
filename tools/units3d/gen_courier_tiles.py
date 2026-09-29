"""Seamless material tiles for the courier and spy models' texture bake (owner
2026-09-29: the models' hand-painted look comes from painted material tiles laid
on each region, then baked into one atlas). Every row of
assets/flux/courier_material_prompts.csv on BOTH Z-Image Turbo and Qwen-Image-2512
fast (never klein, owner 2026-09-28), 2 seeds each, 1024x1024.

  python3 tools/units3d/gen_courier_tiles.py [--tiers zimage] [--only T1,T3] [--seeds 1] [--dry-run] [--force]

Output: assets/flux/out/courier_tiles/<tier>_<id>_s<n>.png and contact_sheet.png.
"""
import csv, sys, urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as v2  # TIERS, graph, run, call
import gen_courier_designs as designs  # arg, the per-tier minutes

ROOT = Path(__file__).resolve().parents[2]
ROWS = ROOT / "assets" / "flux" / "courier_material_prompts.csv"
OUT = ROOT / "assets" / "flux" / "out" / "courier_tiles"
SEED = 20260929
WRAP = ("Seamless tileable texture of {p}, seen flat and straight on, filling the whole square "
        "edge to edge, even soft diffuse light with no shadows, no perspective and no vignette, "
        "uniform detail across the whole square, a hand-painted game texture with subtle painterly "
        "brushwork, rich but natural colour, no objects, no text")
NEGATIVE = ("perspective, horizon, object, border, frame, vignette, shadow, gradient, seam, text, "
            "letters, watermark, logo, person, animal, face, cartoon, blurry")


def main():
    only = set(filter(None, designs.arg("--only", "").split(",")))
    seeds = int(designs.arg("--seeds", "2"))
    tiers = designs.arg("--tiers", "zimage,qwenfast").split(",")
    with open(ROWS, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["id"] in only]
    todo = [(t, r, s) for t in tiers for r in rows for s in range(1, seeds + 1)]
    if "--dry-run" in sys.argv:
        for t, r, s in todo:
            print(f"{t}_{r['id']}_s{s}  {r['key']}")
        print(f"{len(todo)} image(s), about {int(sum(designs.MINUTES[t] for t, _, _ in todo)) + 1} min")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for t, r, s in todo:
        dst = OUT / f"{t}_{r['id']}_s{s}.png"
        if dst.exists() and "--force" not in sys.argv:
            print("keep", dst.name); continue
        tpl, vals = v2.TIERS[t]
        g = v2.graph(tpl, dict(vals, prompt=WRAP.format(p=r["prompt"]), negative=NEGATIVE,
                               seed=SEED + s - 1, width=1024, height=1024,
                               prefix=f"courier_tiles/{t}_{r['id']}_s{s}"))
        img, dt = v2.run(g, 4 * 3600)  # the wait includes other jobs queued ahead
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                    "type": img.get("type", "output")})
        dst.write_bytes(v2.call("/view?" + q))
        print(f"{dst.name}  {dt:.0f}s", flush=True)
    sheet(rows, tiers, seeds)


def sheet(rows, tiers, seeds):
    from PIL import Image, ImageDraw
    cw = 256
    cols = [(r, s) for r in rows for s in range(1, seeds + 1)]
    im = Image.new("RGB", (cw * len(cols), (cw + 24) * len(tiers)), "white")
    d = ImageDraw.Draw(im)
    for y, t in enumerate(tiers):
        for x, (r, s) in enumerate(cols):
            f = OUT / f"{t}_{r['id']}_s{s}.png"
            if f.exists():
                im.paste(Image.open(f).convert("RGB").resize((cw, cw)), (x * cw, y * (cw + 24) + 24))
            d.text((x * cw + 6, y * (cw + 24) + 6), f"{t} {r['key']} s{s}", fill="black")
    im.save(OUT / "contact_sheet.png"); print("->", OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
