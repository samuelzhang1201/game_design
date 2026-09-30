"""Structure views of the owner's picked courier and spy designs (spec
2026-09-28-courier-art §1): the rider alone front / side / back, the mount alone
side / front / above, and the mounted piece side, on BOTH Z-Image Turbo and
Qwen-Image-2512 fast (never klein, owner 2026-09-28). Text only: each view
repeats the picked design's own words. Modelling references for the Blender
build, not game art.

  python3 tools/units3d/gen_courier_sheet.py [--who courier|spy] [--tiers zimage] [--only R1,M1] [--force] [--dry-run]

Output: assets/3D/units/courier/model_wip/sheet/<tier>_<who>_<view>.png and contact_sheet.png.
"""
import csv, re, sys, urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as v2  # TIERS, graph, run, call

ROOT = Path(__file__).resolve().parents[2]
DESIGNS = ROOT / "assets" / "flux" / "courier_design_prompts.csv"
VIEWS = ROOT / "assets" / "flux" / "courier_sheet_prompts.csv"
OUT = ROOT / "assets" / "3D" / "units" / "courier" / "model_wip" / "sheet"
SEED = 20260928
TIERS = ["zimage", "qwenfast"]
MINUTES = {"zimage": 0.5, "qwenfast": 2.0}
QWEN_SCALE = 1.18  # Qwen-Image's native class is ~1584x1056 against Z-Image's 1344x896
TEXT = ("Photograph. {view}. {desc}. Technical reference for a 3D modeller, realistic "
        "replica medieval dress, realistic proportions, everything asked for fully inside "
        "the frame with a margin, plain pure white background, soft even studio light, no "
        "cast shadow, sharp focus, no text")
NEGATIVE = ("cartoon, anime, toy, miniature figurine, chibi, big head, stylised, fantasy "
            "costume, modern clothing, crowd, a second horse, a second rider, landscape, grass, "
            "sky, text, labels, watermark, signature, cropped, cut off hooves, cut off head, "
            "blurry, extra fingers, fused fingers, malformed hands, extra legs, five legs")


def arg(name, default):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a else default


def picked():
    """who -> the picked design row."""
    out = {}
    with open(DESIGNS, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["picked"].strip():
                out["courier" if r["id"].startswith("C") else "spy"] = r
    if set(out) != {"courier", "spy"}:
        sys.exit("pick one C* and one S* design first (courier_design_prompts.csv `picked`)")
    return out


def size_for(tier, w, h):
    if tier != "qwenfast":
        return w, h
    return int(round(w * QWEN_SCALE / 16)) * 16, int(round(h * QWEN_SCALE / 16)) * 16


def describe(row, parts):
    # the design's gait ("at a canter") would fight a view that stands the
    # horse square, so it is dropped; a part drawn alone is not told about the
    # other as a subject, or it draws it
    words = re.sub(r",? at an? (canter|trot|gallop|walk)\b", "", row["prompt"])
    if parts == "rider":
        return "The person only, dressed exactly as in: " + words
    if parts == "mount":
        return "The horse and its saddle and tack only, exactly as in: " + words
    return words


def main():
    only = set(filter(None, arg("--only", "").split(",")))
    whos = [arg("--who", "")] if "--who" in sys.argv else ["courier", "spy"]
    tiers = arg("--tiers", ",".join(TIERS)).split(",")
    with open(VIEWS, newline="", encoding="utf-8") as f:
        views = [v for v in csv.DictReader(f) if not only or v["view"] in only]
    picks = picked()
    todo = [(t, w, v) for t in tiers for w in whos for v in views]
    if "--dry-run" in sys.argv:
        for t, w, v in todo:
            print(f"{t}_{w}_{v['view']}  {'x'.join(map(str, size_for(t, int(v['width']), int(v['height']))))}")
        print(f"{len(todo)} image(s), about {int(sum(MINUTES[t] for t, _, _ in todo)) + 1} min")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (t, w, v) in enumerate(todo):
        dst = OUT / f"{t}_{w}_{v['view']}.png"
        if dst.exists() and "--force" not in sys.argv:
            print("keep", dst.name); continue
        tpl, vals = v2.TIERS[t]
        width, height = size_for(t, int(v["width"]), int(v["height"]))
        text = TEXT.format(view=v["prompt"][0].upper() + v["prompt"][1:], desc=describe(picks[w], v["parts"]))
        g = v2.graph(tpl, dict(vals, prompt=text, negative=NEGATIVE, seed=SEED + views.index(v),
                               width=width, height=height, prefix=f"courier_sheet/{t}_{w}_{v['view']}"))
        img, dt = v2.run(g, 4 * 3600)  # the wait includes other jobs queued ahead
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                    "type": img.get("type", "output")})
        dst.write_bytes(v2.call("/view?" + q))
        print(f"{dst.name}  {dt:.0f}s", flush=True)
    sheet()


def sheet():
    """Per design: a row per tier, a column per view."""
    from PIL import Image, ImageDraw
    views = ["R1", "R2", "R3", "M1", "M2", "M3", "A1"]
    cw, ch = 360, 360
    rows = [(t, w) for w in ("courier", "spy") for t in TIERS]
    im = Image.new("RGB", (cw * len(views), (ch + 24) * len(rows)), "white")
    d = ImageDraw.Draw(im)
    for r, (t, w) in enumerate(rows):
        for c, v in enumerate(views):
            x, y = c * cw, r * (ch + 24)
            f = OUT / f"{t}_{w}_{v}.png"
            if f.exists():
                p = Image.open(f).convert("RGB"); p.thumbnail((cw, ch))
                im.paste(p, (x + (cw - p.width) // 2, y + 24))
            d.text((x + 8, y + 6), f"{t} / {w} / {v}", fill="black")
    im.save(OUT / "contact_sheet.png"); print("->", OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
