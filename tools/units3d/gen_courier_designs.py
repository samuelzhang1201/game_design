"""Courier and spy design sheets (owner 2026-09-28, spec
2026-09-28-courier-art §1): every row of assets/imagegen/courier_design_prompts.csv
on BOTH Z-Image Turbo and Qwen-Image-2512 fast (never klein, owner
2026-09-28), 2 seeds each, for the owner to compare and pick one courier (C*)
and one spy (S*). The pick goes in the CSV's `picked` column as <tier>_s<n>.

  python3 tools/units3d/gen_courier_designs.py            # the desktop tiers, all rows, 2 seeds
  python3 tools/units3d/gen_courier_designs.py --tiers zimage --only C1,S2 --seeds 1
  python3 tools/units3d/gen_courier_designs.py --dry-run  # list the jobs, queue nothing

Output: assets/3D/units/courier/model_wip/designs/<tier>_<id>_s<n>.png and contact_sheet.png.
Existing files are kept unless --force. Each tier runs on its machine (gen_cavalry_v2.host_of).
"""
import csv, sys, urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as v2  # the Z-Image graph, call / run

ROOT = Path(__file__).resolve().parents[2]
ROWS = ROOT / "assets" / "imagegen" / "courier_design_prompts.csv"
OUT = ROOT / "assets" / "3D" / "units" / "courier" / "model_wip" / "designs"
SEED = 20260928
TIERS = ["zimage", "qwendesk", "qwenfast"]  # Z-Image Turbo first: its row is done in minutes
MINUTES = {"zimage": 0.2, "qwendesk": 0.3, "qwenfast": 2.0}
WRAP = ("Photograph of {p}. Three-quarter side view from eye level, the entire horse and "
        "rider fully inside the frame with a generous margin, all four hooves visible. "
        "Museum-quality historical reenactment with accurate replica medieval dress, "
        "realistic adult proportions and realistic horse anatomy, plain pure white seamless "
        "studio background, soft even studio light, sharp detail over the whole figure, clear "
        "readable silhouette, character concept reference for a 3D game model, no text")
NEGATIVE = ("cartoon, anime, toy, miniature, figurine, chibi, big head, stylised, fantasy "
            "costume, plate armour, great helm, lance, shield, spikes, horns, modern clothing, "
            "crowd, a second horse, a second rider, landscape, grass, sky, text, watermark, "
            "signature, cropped, cut off hooves, cut off head, blurry, extra fingers, fused "
            "fingers, malformed hands, extra legs, five legs")
NEGATIVE_ARMOURED = NEGATIVE.replace("plate armour, great helm, ", "")  # C3 wears mail and a kettle hat


def arg(name, default):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a else default


def jobs():
    only = set(filter(None, arg("--only", "").split(",")))
    seeds = int(arg("--seeds", "2"))
    tiers = arg("--tiers", ",".join(v2.DEFAULT_TIERS)).split(",")
    with open(ROWS, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["id"] in only]
    return [(t, r, s) for t in tiers for r in rows for s in range(1, seeds + 1)]


def sheet(files):
    """One row per tier, the same design and seed in the same column."""
    from PIL import Image, ImageDraw
    cw, ch = 528, 352
    tiers = [t for t in TIERS if any(f.name.startswith(t + "_") for f in files)]
    cells = sorted({f.stem.split("_", 1)[1] for f in files})
    im = Image.new("RGB", (cw * len(cells), (ch + 28) * len(tiers)), "white")
    d = ImageDraw.Draw(im)
    for r, t in enumerate(tiers):
        for c, cell in enumerate(cells):
            f = OUT / f"{t}_{cell}.png"
            x, y = c * cw, r * (ch + 28)
            if f.exists():
                im.paste(Image.open(f).convert("RGB").resize((cw, ch)), (x, y + 28))
            d.text((x + 8, y + 6), f"{t} / {cell}", fill="black")
    im.save(OUT / "contact_sheet.png")
    print("->", OUT / "contact_sheet.png")


def main():
    todo = jobs()
    if "--dry-run" in sys.argv:
        for t, r, s in todo:
            print(f"{t}_{r['id']}_s{s}: {WRAP.format(p=r['prompt'])[:100]}...")
        mins = sum(MINUTES[t] for t, _, _ in todo)
        print(f"{len(todo)} image(s), about {int(mins) + 1} min on {', '.join(sorted({t for t, _, _ in todo}))}")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for t, r, s in todo:
        tpl, vals = v2.TIERS[t]
        dst = OUT / f"{t}_{r['id']}_s{s}.png"
        if dst.exists() and "--force" not in sys.argv:
            print("keep", dst.name); done.append(dst); continue
        v = dict(vals, prompt=WRAP.format(p=r["prompt"]),
                 negative=NEGATIVE_ARMOURED if r["id"] == "C3" else NEGATIVE,
                 seed=SEED + s - 1, prefix=f"courier_designs/{t}_{r['id']}_s{s}")
        img, dt = v2.run(v2.graph(tpl, v), 3600, v2.host_of(t))
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                    "type": img.get("type", "output")})
        dst.write_bytes(v2.call("/view?" + q, host=v2.host_of(t)))
        print(f"{dst.name}  {dt:.0f}s", flush=True); done.append(dst)
    sheet(sorted(done))


if __name__ == "__main__":
    main()
