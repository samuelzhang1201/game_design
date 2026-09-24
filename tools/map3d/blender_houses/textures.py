"""Fetch and tint the Poly Haven (CC0) textures the hand-modelled houses wear.

  python3 tools/map3d/blender_houses/textures.py

Downloads each source's 1k diffuse and GL normal into
assets/map3d/sources/polyhaven/houses/ (git-ignored), then writes one tinted
diffuse per material KEY into its tinted/ folder: desaturated, contrast
softened and its mean shifted onto the key's target colour, so a roof or a
wall is the palette's colour and the texture only carries its courses. The
normals are used as downloaded. kit.py reads tinted/<key>.jpg and
<source>_nor_gl_1k.jpg; every .glb embeds what it uses, so nothing here is
committed.

The targets sit a little DARKER than data/terrain_palette.csv's house_*
values: the 3D map's sun and Filmic tonemap lift a sunlit wall toward white
(the first church read paper-white at the closest zoom, 2026-09-24; the
first full set read pink-roofed and blue-white-walled in game, and every
target moved darker and warmer; the roofs then went to the old Hunyuan
roofs' own measured albedo, ~(120,30,20) to (80,32,19) — anything lighter
reads pink under the map's light; a sunlit wall renders ~1.6x its
albedo and a little cold, so limewash and dressed stone sit warmer and
darker still).
"""
import json
import os
import subprocess

from PIL import Image, ImageEnhance, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, "assets", "map3d", "sources", "polyhaven", "houses")
OUT = os.path.join(SRC, "tinted")

SOURCES = ["clay_roof_tiles_03", "roof_slates_02", "rustic_stone_wall_02", "medieval_blocks_03",
           "painted_plaster_wall", "clay_plaster", "old_planks_02", "rough_wood"]

# key: (source, target hex, saturation, contrast). Roofs: tile or slate, never
# thatch and never a dark brown tile (taste.md 2026-09-24); the houses' tiles
# are all WARM, orange-red terracotta in five shades (owner 2026-09-24:
# "房顶颜色还是用那种带橘红色元素的暖色系比较好看"), slate is kept for the
# church landmarks only.
KEYS = {
    "roof_red":         ("clay_roof_tiles_03", "#84301A", 1.1, 0.95),
    "roof_rose":        ("clay_roof_tiles_03", "#7A2C1C", 1.1, 0.95),
    "roof_orange":      ("clay_roof_tiles_03", "#94441C", 1.1, 0.95),
    "roof_orange_brown": ("clay_roof_tiles_03", "#7C3E1E", 1.0, 0.95),
    "roof_brown_grey":  ("clay_roof_tiles_03", "#6E4630", 0.8, 0.95),
    "roof_slate":       ("roof_slates_02", "#585752", 0.4, 0.9),
    "wall_rubble":      ("rustic_stone_wall_02", "#7A7264", 0.5, 0.85),
    "wall_ashlar":      ("medieval_blocks_03", "#6C6456", 0.45, 0.85),
    "wall_plaster":     ("painted_plaster_wall", "#766A56", 0.9, 1.0),
    "wall_daub":        ("clay_plaster", "#7C6A50", 0.8, 1.0),
    "timber":           ("old_planks_02", "#3E2A1D", 0.8, 0.8),
    "planks":           ("old_planks_02", "#6A5845", 0.7, 0.9),
    # the church's great wooden cross (owner 2026-09-24): hewn, cracked oak
    # darkened so it stands as a dark silhouette on stone and slate
    "cross_wood":       ("rough_wood", "#4A3424", 0.8, 1.1),
}


def _get(url):
    # curl, like tools/map3d/fetch_polyhaven.py: python.org's Python ships no
    # root certificates on macOS, so urllib fails the TLS handshake
    return subprocess.run(["curl", "-sfL", url], check=True, capture_output=True).stdout


def fetch(asset):
    for kind in ("Diffuse", "nor_gl"):
        path = os.path.join(SRC, "%s_%s_1k.jpg" % (asset, kind))
        if os.path.exists(path):
            continue
        url = json.loads(_get("https://api.polyhaven.com/files/" + asset))[kind]["1k"]["jpg"]["url"]
        with open(path, "wb") as f:
            f.write(_get(url))
        print("fetched", os.path.basename(path))


def tint(src, hexcol, sat, con):
    im = Image.open(os.path.join(SRC, src + "_Diffuse_1k.jpg")).convert("RGB")
    im = ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(sat)).enhance(con)
    mean = ImageStat.Stat(im).mean
    target = [int(hexcol[i:i + 2], 16) for i in (1, 3, 5)]
    return Image.merge("RGB", [im.getchannel(i).point(lambda v, k=target[i] / max(mean[i], 1.0): min(255, int(v * k)))
                               for i in range(3)])


def main():
    os.makedirs(OUT, exist_ok=True)
    for asset in SOURCES:
        fetch(asset)
    for key, (src, hexcol, sat, con) in KEYS.items():
        tint(src, hexcol, sat, con).save(os.path.join(OUT, key + ".jpg"), quality=90)
    print("tinted", len(KEYS), "keys into", OUT)


if __name__ == "__main__":
    main()
