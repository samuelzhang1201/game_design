#!/usr/bin/env python3
"""Install the PAINTED settlement illustrations as the map's settlement art
(owner 2026-09-16: the Blender models were rejected as too crude, and the
reference — docs/references/ChatGPT Image Sep 16, 2026, 05_58_06 PM.png —
is a painted aerial view, so the tiers are Flux illustrations now).

VARIANTS (owner 2026-09-16): each tier has several drawings and a settlement
wears one of them, so two towns of the same size do not look like twins. The
cut-outs live one directory per variant — `post.py` names its output after the
library id alone, so ten variants of S-01 would otherwise overwrite each other:

    out/game/settlements/v01/S-01_klein.png   -> painted/capital_01.png
    out/game/settlements/v02/S-01_klein.png   -> painted/capital_02.png

A tier's file is sized by how large it is ever DRAWN (settlement_art.csv's
`size` share of map_sprite_max_px 190 design px, times the ~3x window scale),
not one size for all — sixty 768 px sheets would bloat the repo for nothing.
The paintings carry their own light and contact shading, so no ground shadow
is composited under them.

    python3 assets/flux/install_settlement_art.py            # every variant
    python3 assets/flux/install_settlement_art.py --single   # v01 only, as <tier>.png
    python3 assets/flux/install_settlement_art.py --preview  # from the local
        # flood-fill cut-outs (preview_cutout.py) instead of the BiRefNet ones,
        # for a look at the map while ComfyUI is still busy
"""
import sys
from pathlib import Path

HERE = Path("/Users/samuelzhang/game_design/assets/flux")
sys.path.insert(0, str(HERE))
from post import decode_png, encode_png  # noqa: E402
from install_map_art import resize_rgba, trim_alpha  # noqa: E402

SRC = HERE / "out" / "game" / "settlements"
# The local flood-fill cut-outs, for a look at the map while ComfyUI is busy.
PREVIEW_SRC = HERE / "out" / "game" / "settlements_preview"
DEST = Path("/Users/samuelzhang/game_design/assets/settlements/painted")
# library id -> (tier data/settlement_art.csv names, installed height in px)
TIERS = {
    "S-01": ("capital", 768),
    "S-02": ("city", 640),
    "S-03": ("walled_town", 512),
    "S-04": ("town", 448),
    "S-05": ("village", 384),
    "S-06": ("hamlet", 320),
}
VARIANTS = 10


def fit(src: Path, dest: Path, px: int) -> str:
    w, h, ch, raw = decode_png(src)
    if ch != 4:
        return "%s is not RGBA" % src.name
    cw, chh, rgba = trim_alpha(w, h, bytearray(raw))
    tw = max(1, round(cw * px / chh))
    encode_png(dest, tw, px, 4, bytes(resize_rgba(cw, chh, rgba, tw, px)))
    return "%dx%d" % (tw, px)


def variant_source(art_id: str, n: int, src: Path = SRC) -> Path | None:
    """The cut-out of variant n: <src>/vNN/<ID>*.png."""
    hits = sorted((src / ("v%02d" % n)).glob("%s*.png" % art_id))
    return hits[0] if hits else None


def main() -> int:
    single = "--single" in sys.argv
    src = PREVIEW_SRC if "--preview" in sys.argv else SRC
    print("source: %s" % src)
    DEST.mkdir(parents=True, exist_ok=True)
    made = 0
    for art_id, (tier, px) in TIERS.items():
        if single:
            one = variant_source(art_id, 1, src) or next(iter(sorted(src.glob("%s*.png" % art_id))), None)
            if one is None:
                print("  (%s: no cut-out)" % tier)
                continue
            print("  %-12s %s  <- %s" % (tier, fit(one, DEST / ("%s.png" % tier), px), one.name))
            made += 1
            continue
        found = 0
        for n in range(1, VARIANTS + 1):
            one = variant_source(art_id, n, src)
            if one is None:
                continue
            fit(one, DEST / ("%s_%02d.png" % (tier, n)), px)
            found += 1
        if found == 0:
            print("  (%s: no cut-outs under %s/vNN/)" % (tier, src.name))
            continue
        # The plain <tier>.png stays as the fallback the CSV names, so a pack
        # or a test that asks for the tier without a variant still finds art.
        first = variant_source(art_id, 1, src)
        if first is not None:
            fit(first, DEST / ("%s.png" % tier), px)
        print("  %-12s %d variant(s) at %d px" % (tier, found, px))
        made += found
    print("%d settlement drawing(s) installed" % made)
    return 0


if __name__ == "__main__":
    sys.exit(main())
