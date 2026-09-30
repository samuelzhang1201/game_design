"""The Tripo 3D input pictures for the cavalry (owner 2026-09-30: 骑兵改用 tripo 3d
建模，使用之前步兵同样的方法; keep the current design). The in-game knight, described
the way `cavalry_scan.py` dressed it (design "Z-Image C" as built: no barding), in
three views WITHOUT his shield, and the shield on its own (owner: 盾牌单独做，骑士不带盾
出图 -- a large green heater slung on his back, taken to his arm for GARRISON, so it is a
separate model on its own bone), on a plain grey ground, on Z-Image and Qwen-Image-2512 side by side
for the owner to pick the one to feed Tripo.

  python3 tools/units3d/cavalry_tripo/gen_refs.py               # every view, 2 seeds, both tiers
  python3 tools/units3d/cavalry_tripo/gen_refs.py --only side --tiers zimage

Output: assets/3D/units/cavalry/model_wip/tripo_kit/<tier>_<view>_s<n>.png and
contact_sheet.png (git-ignored, beside the other sources). Existing files are kept
unless --force. Needs ComfyUI at COMFY_HOST (default http://127.0.0.1:8188).
"""
import os
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gen_cavalry_v2 as G  # noqa: E402  (the ComfyUI calls and templates)

MAIN = Path("/Users/samuelzhang/game_design")  # the git-ignored sources live in the main checkout
OUT = MAIN / "assets" / "3D" / "units" / "cavalry" / "model_wip" / "tripo_kit"
SEED = 20260930

KNIGHT = (
    "a fifteenth-century knight in a complete harness of plain matte steel plate armour, no etching, "
    "no gilding: a close helmet with the visor down and a narrow eye slit, a rounded breastplate, "
    "a fauld and tassets, rounded pauldrons, couters, vambraces, gauntlets, cuisses, poleyns, greaves "
    "and pointed sabatons in the stirrups; he sits upright in the saddle, his right hand holding a "
    "long plain wooden war lance with a small steel point and a round steel vamplate straight upright, "
    "its butt resting on the outside of his right thigh, the shaft clear of his leg; his left hand "
    "holding the reins; he carries NO shield. "
    "He rides a heavy warhorse with a dark charcoal grey dappled coat, black mane, black tail and "
    "black lower legs, a small white star on the forehead, without any horse armour: a brown leather "
    "war saddle with a high cantle, a dark green cloth saddle cloth over the hindquarters edged with "
    "a thin brass border, a leather breast strap with one round brass boss on the chest, a leather "
    "bridle and reins. The horse stands still and square, all four hooves flat on the ground and "
    "clearly apart, head up, neck relaxed, tail hanging"
)
SHIELD = (
    "a single large medieval heater shield, about 90 cm tall, on its own with nobody holding it: "
    "gently curved wooden boards covered in painted leather, painted dark green with a single white "
    "vertical stripe down its middle, a thin steel rim round its edge, a small round steel boss, and a "
    "long leather carrying strap (a guige) looped from its top corners"
)
# id: (subject, the view's words, landscape?) -- the view comes FIRST in the prompt: behind the
# long design text Z-Image drew every view as the same side profile
VIEWS = {
    "side": (KNIGHT, "A strict side profile view at ninety degrees: the horse's LEFT side faces the camera, "
             "its head points to the left edge of the picture, all four legs visible and apart", True),
    "threequarter": (KNIGHT, "A three-quarter view from forty-five degrees to the horse's front left: we see "
                     "the horse's face and chest AND its left flank, the head toward the lower left of the "
                     "picture, the rump receding to the right, all four legs visible", True),
    "front": (KNIGHT, "A view exactly from the front: the horse's face, chest and both forelegs toward the "
              "camera, the knight's visor facing us, the lance upright beside him", False),
    "shield": (SHIELD, "Its painted face seen straight on from the front, standing upright, the strap "
               "hanging behind", False),
}
WRAP = ("{v}. Orthographic technical reference photograph for 3D modelling of {d}. The whole subject "
        "inside the frame and filling only its central two thirds, with a wide empty margin on every "
        "side, nothing cut off, no perspective distortion, museum-quality replica arms and armour, "
        "realistic proportions, plain flat neutral grey seamless background, soft even shadowless studio "
        "light so every plate edge and strap is readable, sharp focus over the whole subject, "
        "photorealistic real steel, wood, leather and cloth, no text, no labels, no watermark")
NEGATIVE = (G.NEGATIVE + ", shield carried by the knight, shield on the arm, shield on the back, buckler, "
            "horse armour, barding, chanfron, crinet, peytral, caparison covering the legs, pennon, "
            "gilding, engraving, ground, shadow on the floor, rearing horse, galloping, motion blur, "
            "close-up, cropped legs")
SHIELD_NEGATIVE = ("person, hand, arm, knight, horse, wall, table, stand, cartoon, toy, fantasy, emblem, "
                   "coat of arms, cross, lion, text, watermark, cropped, blurry")
TIERS = {"zimage": G.TIERS["zimage"], "qwenfast": G.TIERS["qwenfast"]}


def front_call(path, data=None):
    """G.call, but a new prompt goes to the FRONT of the queue (the queue is shared with
    other sessions' long batches; this reorders them, never cancels them)."""
    if path == "/prompt" and data is not None:
        data = dict(data, front=True)
    return _call(path, data)


_call = G.call


def main():
    G.OUT = OUT  # the sheet helper reads the module's OUT
    if "--front" in sys.argv:
        G.call = front_call
    tiers = G.arg("--tiers", ",".join(TIERS)).split(",")
    only = set(filter(None, G.arg("--only", "").split(",")))
    seeds = int(G.arg("--seeds", "2"))
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for t in tiers:  # tier-major: Z-Image's quick renders come back first
        tpl, vals = TIERS[t]
        for view, (subject, words, wide) in VIEWS.items():
            if only and view not in only:
                continue
            w, h = vals["width"], vals["height"]
            size = dict(width=w, height=h) if wide else dict(width=h, height=w)
            for s in range(1, seeds + 1):
                dst = OUT / f"{t}_{view}_s{s}.png"
                if dst.exists() and "--force" not in sys.argv:
                    print("keep", dst.name); done.append(dst); continue
                v = dict(vals, **size, prompt=WRAP.format(d=subject, v=words),
                         negative=SHIELD_NEGATIVE if subject is SHIELD else NEGATIVE,
                         seed=SEED + s - 1, prefix=f"cavalry_tripo/{t}_{view}_s{s}")
                img, dt = G.run(G.graph(tpl, v), 3600)
                q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                            "type": img.get("type", "output")})
                dst.write_bytes(G.call("/view?" + q))
                print(f"{dst.name}  {dt:.0f}s", flush=True); done.append(dst)
    sheet(done)


def sheet(files):
    from PIL import Image, ImageDraw
    cw, ch = 480, 360
    rows = [(t, s) for t in TIERS for s in (1, 2)]
    im = Image.new("RGB", (cw * len(VIEWS), (ch + 24) * len(rows)), "white")
    d = ImageDraw.Draw(im)
    for r, (t, s) in enumerate(rows):
        for c, view in enumerate(VIEWS):
            f = OUT / f"{t}_{view}_s{s}.png"
            if f in files and f.exists():
                p = Image.open(f).convert("RGB")
                p.thumbnail((cw, ch))
                im.paste(p, (c * cw + (cw - p.width) // 2, r * (ch + 24) + 24))
            d.text((c * cw + 8, r * (ch + 24) + 5), f"{t} / {view} / s{s}", fill="black")
    im.save(OUT / "contact_sheet.png"); print("->", OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
