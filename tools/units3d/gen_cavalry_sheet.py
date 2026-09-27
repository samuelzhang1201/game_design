"""The modelling reference set of the PICKED cavalry design (owner 2026-09-25:
Z-Image's design C, assets/flux/out/cavalry_v2/zimage_C_s1.png): whole-piece
elevations and part breakdowns, every one drawn by FLUX.2 klein 4B with the
picked picture fed in as a reference latent, so each sheet shows that same
horse, rider and kit. Rows: assets/flux/cavalry_c_sheet_prompts.csv.

  python3 tools/units3d/gen_cavalry_sheet.py [--only S1,P3] [--seed N] [--model klein|zimage] [--force]

klein (default) holds the kit exactly but tends to keep the reference's pose;
zimage has no reference, so it turns the view as asked and keeps the kit only
as far as the words carry it (<id>_zimage.png).

Output: assets/flux/out/cavalry_c_sheet/<id>.png and contact_sheet.png.
Needs ComfyUI at COMFY_HOST (default http://127.0.0.1:8188).
"""
import csv, os, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_refs as refs  # post / get / upload / run, the klein graph
import gen_cavalry_v2 as v2  # the Z-Image graph

ROOT = Path(__file__).resolve().parents[2]
ROWS = ROOT / "assets" / "flux" / "cavalry_c_sheet_prompts.csv"
OUT = ROOT / "assets" / "flux" / "out" / "cavalry_c_sheet"
REF = ROOT / "assets" / "flux" / "out" / "cavalry_v2" / "zimage_C_s1.png"
SEED = 20260925

# Everything the picked picture shows, said in words and cut into the pieces
# a row names in its `parts` column: a part drawn alone (the helmet, the
# rider on foot) must not be told about the horse, or it draws the horse.
PARTS = {
    "rider": "a fifteenth-century knight in a complete polished steel gothic plate harness with fluted plates and mail at the joints",
    "helmet": "a close armet helmet of polished steel with its visor down, one narrow eye slit and small breathing holes",
    "horse": "a warhorse with a very dark charcoal-grey coat, almost black, with faint dapples, a small white star on the forehead, dark legs and a long black mane and tail",
    "tack": "a brown leather bridle and reins, a brown leather breast strap with a round brass boss, a brown leather high war saddle over a dark green wool saddle cloth covering the hindquarters with a brass-studded border",
    "shield": "a green heater shield with one vertical white stripe down the middle, a domed steel boss and a riveted steel rim",
    "lance": "a wooden lance with a steel leaf-shaped head and a brass collar",
}
TEXT = ("Photograph. {prompt}. {desc}. Technical reference for a 3D modeller, realistic "
        "museum-quality replica arms and armour, realistic proportions, everything asked "
        "for fully inside the frame with a margin, plain pure white background, soft even "
        "studio light, no cast shadow, sharp focus, no text")
NEGATIVE = ("cartoon, anime, toy, miniature figurine, chibi, big head, stylised, fantasy "
            "armour, spikes, horns, fur trim, flags, banners, pennants, modern clothing, "
            "crowd, a second horse, a second knight, landscape, grass, sky, text, labels, "
            "watermark, signature, cropped, cut off hooves, cut off head, blurry, extra "
            "fingers, fused fingers, malformed hands, extra legs, five legs, broken lance")


def main():
    args = sys.argv[1:]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    with open(ROWS, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["id"] in only]
    OUT.mkdir(parents=True, exist_ok=True)
    model = args[args.index("--model") + 1] if "--model" in args else "klein"
    ref_name = refs.upload(str(REF)) if model == "klein" else None
    refs.NEGATIVE = NEGATIVE
    for r in rows:
        dst = OUT / (r["id"] + ("" if model == "klein" else "_" + model) + ".png")
        if dst.exists() and "--force" not in args:
            print("keep", dst.name); continue
        refs.SIZE["sheet"] = (int(r["width"]), int(r["height"]))
        desc = ", ".join(PARTS[k] for k in r["parts"].split("|"))
        refs.SHEET = TEXT.format(prompt=r["prompt"], desc=desc[0].upper() + desc[1:]).replace("{", "{{").replace("}", "}}")
        if model == "klein":
            g, out_node = refs.graph({"id": "c_" + r["id"]}, "sheet", seed, ref_name), "13"
        else:  # Z-Image Turbo, text only: follows a turned view where the reference pins the pose
            g = v2.graph(*v2.TIERS["zimage"][:1], dict(v2.TIERS["zimage"][1], prompt=refs.SHEET, seed=seed,
                         width=int(r["width"]), height=int(r["height"]), prefix="cavalry_c_sheet/" + r["id"]))
            out_node = next(k for k, n in g.items() if n["class_type"] == "SaveImage")
        hist, dt = refs.run(g, 3600)
        img = hist["outputs"][out_node]["images"][0]
        q = "filename=%s&subfolder=%s&type=output" % (img["filename"], img["subfolder"])
        dst.write_bytes(refs.urllib.request.urlopen(refs.HOST + "/view?" + q).read())
        print("%s %.0fs" % (dst.name, dt), flush=True)
    sheet()


def sheet():
    from PIL import Image, ImageDraw
    files = sorted(OUT.glob("[SP]*.png"))
    cw, ch, cols = 560, 400, 4
    im = Image.new("RGB", (cw * cols, (ch + 24) * ((len(files) + cols - 1) // cols)), "white")
    d = ImageDraw.Draw(im)
    for i, f in enumerate(files):
        x, y = (i % cols) * cw, (i // cols) * (ch + 24)
        p = Image.open(f).convert("RGB")
        p.thumbnail((cw, ch))
        im.paste(p, (x + (cw - p.width) // 2, y + 24))
        d.text((x + 8, y + 6), f.stem, fill="black")
    im.save(OUT / "contact_sheet.png")
    print("->", OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
