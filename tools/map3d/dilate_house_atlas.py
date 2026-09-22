"""Grow the baked house atlases out into the black between their UV islands.

  python3 tools/map3d/dilate_house_atlas.py [--px 24] [--dry-run]

`retopo_houses.py` unwraps a voxel remesh with `smart_project`, so each type's
2048 px atlas is some thousands of PER-TRIANGLE islands about a dozen pixels
across, with pure black between them and a bake margin that does not close the
gap. At the size a house is actually drawn (roughly 24-50 px for the whole
building, density v5) every sample comes from a low mip, and a low mip of that
atlas is the island averaged with the black around it: the houses render
darker than their own texture and the big landmarks — `church_tower` worst,
its atlas 79% black — render as a crust of white and black speckle.

This walks each built .glb and floods every island's own colour outward into
the background, so a mip averages roof with roof instead of roof with void.
It touches only pixels that are already black; nothing an island covers moves,
and the geometry, the UVs and the triangle count are untouched.

A future re-bake should not need it: `scene.render.bake.margin_type` and a
margin wide enough for these islands is the proper fix at the source, and
retopo_houses.py now sets both. This exists because the meshes it fixes were
already baked, and re-running the whole retopo (voxel remesh + 14 texture
pairs) for a post-process is not a trade worth making.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "map3d_houses")
BACKGROUND = 6          # a pixel this dark on every channel is unbaked atlas, not a surface
JPEG_QUALITY = 92       # as retopo_houses.py exports


def dilate(img, px):
    """Flood the non-background pixels outward by `px` rings, nearest first."""
    a = np.asarray(img.convert("RGB"), dtype=np.uint8).copy()
    filled = a.max(axis=2) > BACKGROUND
    if not filled.any():
        return img, 0
    grown = 0
    for _ in range(px):
        empty = ~filled
        if not empty.any():
            break
        src = np.zeros(a.shape, dtype=np.uint8)
        got = np.zeros(filled.shape, dtype=bool)
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nb = np.roll(filled, shift, axis=axis)
            nv = np.roll(a, shift, axis=axis)
            take = empty & nb & ~got
            src[take] = nv[take]
            got |= take
        a[got] = src[got]
        filled |= got
        grown += int(got.sum())
    return Image.fromarray(a), grown


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    chunks, off = [], 12
    while off < len(data):
        length, kind = struct.unpack("<II", data[off:off + 8])
        chunks.append((kind, data[off + 8:off + 8 + length]))
        off += 8 + length
    return json.loads(chunks[0][1]), chunks[1][1]


def write_glb(path, doc, views):
    """Rebuild the BIN chunk from `views` (one bytes per bufferView, in the
    document's own order) and re-offset every bufferView onto it."""
    blob = bytearray()
    for i, view in enumerate(doc["bufferViews"]):
        blob += b"\0" * (-len(blob) % 4)
        view["byteOffset"] = len(blob)
        view["byteLength"] = len(views[i])
        blob += views[i]
    doc["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = (struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def main():
    px = 24
    if "--px" in sys.argv:
        px = int(sys.argv[sys.argv.index("--px") + 1])
    dry = "--dry-run" in sys.argv

    for name in sorted(os.listdir(OUT)):
        if not name.endswith(".glb"):
            continue
        path = os.path.join(OUT, name)
        doc, bin_chunk = read_glb(path)
        views = []
        for view in doc["bufferViews"]:
            at = view.get("byteOffset", 0)
            views.append(bin_chunk[at:at + view["byteLength"]])
        touched = []
        for image in doc.get("images", []):
            idx = image["bufferView"]
            img = Image.open(io.BytesIO(views[idx]))
            before = (np.asarray(img.convert("L")) <= BACKGROUND).mean()
            grown_img, grown = dilate(img, px)
            after = (np.asarray(grown_img.convert("L")) <= BACKGROUND).mean()
            buf = io.BytesIO()
            grown_img.save(buf, format="JPEG", quality=JPEG_QUALITY)
            views[idx] = buf.getvalue()
            touched.append("%s %.0f%%->%.0f%% black" % (image["name"].split("_")[-1],
                                                        before * 100, after * 100))
        if touched:
            print("%-16s %s" % (name[:-4], ", ".join(touched)))
            if not dry:
                write_glb(path, doc, views)
    print("done%s" % (" (dry run)" if dry else ""))


if __name__ == "__main__":
    main()
