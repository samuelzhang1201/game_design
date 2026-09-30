"""Rescale the BUILT house meshes to the table's footprint_m.

  python3 tools/map3d/scale_houses.py [--dry-run]

Why this exists rather than "just re-run retopo_houses.py": house size on the
3D map is a LOOK value, not a fact about the source mesh (owner 2026-09-21:
"忽略房屋和地图的真实比例的大小，尽量贴近AI原图模型的生成游戏模型" — the map is
built at 50 m per pack px, so a true-to-life cottage is 7-12 px at the closest
zoom and reads as gravel). Changing footprint_m and re-running the retopo
bake would re-voxelise the 500k-tri Hunyuan3D sources, re-bake 14 texture
pairs and — because tri_budget() scales with the footprint SQUARED — double
every mesh's triangle count for a change that is a pure uniform scale. This
walks the built .glb instead and multiplies its POSITION data, so the
silhouette, the UVs, the baked albedo/normal and the triangle count are
bit-for-bit what the retopo produced, only bigger.

It reads data/map3d_houses.csv (footprint_m, the authored input) against
assets/3D/buildings/houses.json (the built mesh's measured size), scales any
type whose two disagree, and writes the new measured height_m back into both
— the same writeback contract retopo_houses.py has, which
tests/map3d/test_map3d_houses_meshes.gd pins.

A uniform scale needs no change to NORMAL (unit vectors), TEXCOORD or the
indices; only POSITION and its accessor min/max move.
"""
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "data", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "3D", "buildings")
MANIFEST = os.path.join(OUT, "houses.json")


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _total = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2, "%s is not a glTF 2.0 binary" % path
    chunks, off = [], 12
    while off < len(data):
        length, kind = struct.unpack("<II", data[off:off + 8])
        chunks.append((kind, data[off + 8:off + 8 + length]))
        off += 8 + length
    assert chunks[0][0] == 0x4E4F534A, "%s does not open with a JSON chunk" % path
    assert chunks[1][0] == 0x004E4942, "%s has no BIN chunk" % path
    return json.loads(chunks[0][1]), bytearray(chunks[1][1])


def write_glb(path, doc, blob):
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    blob = bytes(blob) + b"\0" * (-len(blob) % 4)
    body = (struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def scale_positions(doc, blob, k):
    """Multiply every POSITION accessor by k, in place (k = 1 measures
    without touching a byte). Returns the bounding box (min, max) over all
    of them."""
    done, lo, hi = set(), [1e30] * 3, [-1e30] * 3
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            idx = prim["attributes"].get("POSITION")
            if idx is None or idx in done:
                continue
            done.add(idx)
            acc = doc["accessors"][idx]
            assert acc["type"] == "VEC3" and acc["componentType"] == 5126, \
                "POSITION %d is not float32 VEC3" % idx
            if k != 1.0:
                view = doc["bufferViews"][acc["bufferView"]]
                stride = view.get("byteStride") or 12
                base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
                for i in range(acc["count"]):
                    at = base + i * stride
                    v = struct.unpack_from("<3f", blob, at)
                    struct.pack_into("<3f", blob, at, v[0] * k, v[1] * k, v[2] * k)
                acc["min"] = [c * k for c in acc["min"]]
                acc["max"] = [c * k for c in acc["max"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    assert done, "no POSITION accessor found"
    return lo, hi


def main():
    dry = "--dry-run" in sys.argv
    with open(TABLE) as f:
        head = f.readline().rstrip("\n").split(",")
        lines = f.read().splitlines()
    fi, hi_col, ti = head.index("footprint_m"), head.index("height_m"), head.index("type")
    wi = head.index("width_m") if "width_m" in head else None
    di = head.index("depth_m") if "depth_m" in head else None
    with open(MANIFEST) as f:
        manifest = json.load(f)

    out, changed, measured = [], 0, 0
    for line in lines:
        # every field before `notes` is plain, so a plain split is enough for
        # the three columns this touches; the rest of the row is passed through
        cells = line.split(",")
        t, want = cells[ti], float(cells[fi])
        entry = manifest.get(t)
        path = os.path.join(OUT, t, t + ".glb")
        if entry is None or not os.path.exists(path):
            out.append(line)
            continue
        have = float(entry["footprint_m"])
        k = want / have
        doc, blob = read_glb(path)
        # the manifest's `tris` is retopo_houses.py's count BEFORE the glTF
        # export, and the exporter's own triangulation moves it by a few
        # (cottage_a 4000 -> 3990, palace 94384 -> 92640), which
        # tests/map3d/test_map3d_houses_meshes.gd reads as a lie about the
        # mesh. Count the exported INDICES instead: this tool has the file
        # open and the glTF's own numbers are the ones the game loads.
        tris = sum(doc["accessors"][prim["indices"]]["count"] // 3
                   for mesh in doc["meshes"] for prim in mesh["primitives"]
                   if "indices" in prim)
        scaling = abs(k - 1.0) >= 1e-6
        lo, hi = scale_positions(doc, blob, k if scaling else 1.0)
        span = [hi[i] - lo[i] for i in range(3)]
        height = round(span[1], 3)          # glTF is Y-up
        long_axis = max(span[0], span[2])
        assert abs(long_axis - want) < 1e-2, \
            "%s came out %.3f m across, not its declared %.2f" % (t, long_axis, want)
        if scaling:
            print("%-14s x%.4f  %.1f -> %.1f m across, %.2f -> %.2f m tall"
                  % (t, k, have, want, float(entry["height_m"]), height))
            changed += 1
        # the measured columns are refreshed whether or not anything was
        # scaled: retopo_houses.py can have rebuilt one type (--only) and it
        # writes back height_m alone, so width_m/depth_m — which the packer
        # reserves ground by — would otherwise still describe the mesh
        # BEFORE it, which is how the rebuilt palace kept the old one's
        # 38.87 m depth against its real 66.07.
        if not dry:
            if scaling:
                write_glb(path, doc, blob)
            if entry.get("tris") != tris or entry.get("height_m") != height \
                    or float(entry.get("footprint_m", 0)) != want:
                measured += 1
            entry["tris"] = tris
            entry["footprint_m"] = want
            entry["height_m"] = height
        cells[hi_col] = "%.2f" % height
        # width_m / depth_m are the mesh's own horizontal spans, which
        # bake_houses.half_extents() packs against: measured like height_m,
        # never authored
        if wi is not None:
            cells[wi] = "%.2f" % span[0]
        if di is not None:
            cells[di] = "%.2f" % span[2]
        out.append(",".join(cells))

    # idempotent: the table and the manifest are rewritten from what the
    # meshes measure, so running this twice changes nothing
    if not dry:
        with open(MANIFEST, "w") as f:
            json.dump(manifest, f, indent=1, sort_keys=True)
        with open(TABLE, "w") as f:
            f.write(",".join(head) + "\n" + "\n".join(out) + "\n")
    print("%d mesh(es) rescaled, %d manifest triangle count(s) corrected%s"
          % (changed, measured, " (dry run)" if dry else ""))


if __name__ == "__main__":
    main()
