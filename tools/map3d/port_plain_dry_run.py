"""Port plains DRY RUN (owner 2026-10-12, R18): what bake_houses.port_plain
would do to every port of a COMMITTED Terrain3D build, writing nothing.

    python3 tools/map3d/port_plain_dry_run.py [--map ID]

Reads the build's bake/height_war.r16 (the finished heights), houses.csv (each
port's landmark, rank 0, and its houses' median ground), rivers.json (the
river band, rebuilt as bake_world.carve draws `wet`: 1 in the water, fading to
0 over river_wet_m) and the pack's world_cell_index.png (open water: no cell
and at or under the sea). Runs port_plain on a COPY of the heights per port
and then the harbour bearing on the result, and prints one row per port the
pass catches or that stands lofty: its cut, blend, whether a low shore (so a
timber pier) results, and the river channel / band vertices inside its cut.
Approximate by construction (the real pass runs mid-bake, before the houses
and the river's carve are final), but on the same code.
"""
import argparse
import csv
import json
import math
import os
import statistics
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import bake_world as bw  # noqa: E402
import bake_houses  # noqa: E402
from packs import default_pack, map3d_dir  # noqa: E402


def river_wet(rivers, vw, vh, ox, oz, vm, wet_m):
    """`wet` as bake_world.carve stamps it, from rivers.json's water lines."""
    wet = np.zeros((vh, vw), dtype=np.float32)
    wet_v = wet_m / vm
    for r in rivers:
        for x, z, _y, width, _mouth in r["points"]:
            cx, cy = (x - ox) / vm, (z - oz) / vm
            half = 0.5 * width / vm
            rr = int(math.ceil(half + wet_v)) + 1
            x0, x1 = max(int(cx) - rr, 0), min(int(cx) + rr + 2, vw)
            y0, y1 = max(int(cy) - rr, 0), min(int(cy) + rr + 2, vh)
            if x0 >= x1 or y0 >= y1:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1]
            s = np.maximum(np.hypot(xx - cx, yy - cy) - half, 0.0)
            np.maximum(wet[y0:y1, x0:x1], np.clip(1.0 - s / wet_v, 0.0, 1.0), out=wet[y0:y1, x0:x1])
    return wet


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default=None)
    args = ap.parse_args(argv)
    pack = args.map or default_pack()
    bake = os.path.join(map3d_dir(pack), "bake")
    world = json.load(open(os.path.join(bake, "world.json")))
    vw, vh = world["vertices"]
    vm = float(world["vertex_m"])
    ox, oz = world["pack_origin"]
    sea_y = float(world["sea_y"])
    k = float(world["m_per_px"]) / vm
    height0 = np.fromfile(os.path.join(bake, "height_war.r16"), dtype=np.float16).astype(np.float32).reshape(vh, vw)
    idx = np.asarray(Image.open(os.path.join(bw.ROOT, "assets", "maps", pack, "world_cell_index.png"))
                     .convert("RGB")).astype(np.int64)
    has_cell = ~((idx[..., 0] == 255) & (idx[..., 1] == 255) & (idx[..., 2] == 255))
    ph, pw = has_cell.shape
    pxi = np.clip((np.arange(vw) / k).astype(np.int64), 0, pw - 1)
    pyi = np.clip((np.arange(vh) / k).astype(np.int64), 0, ph - 1)
    open_water = ~has_cell[pyi][:, pxi] & (height0 <= sea_y)
    land = (~open_water).astype(np.float32)
    rules = bw.load_rules()
    types = bw.house_types()
    wet = river_wet(json.load(open(os.path.join(bake, "rivers.json")))["rivers"], vw, vh, ox, oz, vm,
                    float(rules["river_wet_m"]))
    homes, centre, town_rows = {}, {}, {}
    with open(os.path.join(bake, "houses.csv")) as f:
        for r in csv.DictReader(f):
            if types.get(r["type"], {}).get("role") in ("pier", "ship", "wall", "tower", "gate"):
                continue
            x, z = (float(r["x_m"]) - ox) / vm, (float(r["z_m"]) - oz) / vm
            if int(r["rank"]) == 0:
                centre[r["burg_code"]] = (x, z)
            ix, iy = min(max(int(round(x)), 0), vw - 1), min(max(int(round(z)), 0), vh - 1)
            homes.setdefault(r["burg_code"], []).append(float(height0[iy, ix]))
            town_rows.setdefault(r["burg_code"], []).append(
                dict(r, rank=int(r["rank"]), x_m=float(r["x_m"]) - ox, z_m=float(r["z_m"]) - oz))
    rise_town = float(rules["pier_stair_town_rise_m"])
    max_shore = float(rules["pier_max_shore_m"])
    rows = []
    piers_all = []
    with open(os.path.join(bw.ROOT, "data", "maps", pack, "political", "burgs.csv")) as f:
        for b in csv.DictReader(f):
            if not int(b["is_port"] or 0) or b["burg_code"] not in centre:
                continue
            b = dict(b)
            b["population"] = float(b["population"] or 0)
            vx, vy = centre[b["burg_code"]]
            med = statistics.median(homes[b["burg_code"]]) - sea_y
            before = bake_houses._port_bearing(vx, vy, rules, height0, sea_y, open_water)
            cliff = before is not None and (before[0] > 0.0 or med >= rise_town)
            h = height0.copy()
            res = bake_houses.port_plain(b, h, vx, vy, rules, types, sea_y, open_water, land=land, wet=wet)
            # the harbour on the (possibly cut) heights: the pier each port ends with
            lm = town_rows[b["burg_code"]][0]
            rel = [dict(r, x_m=(r["x_m"] - lm["x_m"]), z_m=(r["z_m"] - lm["z_m"])) for r in town_rows[b["burg_code"]]]
            bb = dict(b, x=vx / k, y=vy / k)
            laid = bake_houses.harbour(bb, rel, rules, land, h, k, vw, vh, sea_y, water=open_water, types=types)
            piers = [r for r in laid if types.get(r["type"], {}).get("role") == "pier"]
            piers_all.append((b["burg_code"], res["cut"],
                              [(r["type"], math.hypot(r["x_m"], r["z_m"])) for r in piers]))
            if not cliff and not res["cut"]:
                continue
            after = bake_houses._port_bearing(vx, vy, rules, h, sea_y, open_water)
            chan = band = 0
            if res["window"] is not None:
                y0, y1, x0, x1 = res["window"]
                cut = (height0[y0:y1, x0:x1] - h[y0:y1, x0:x1]) > 0.01
                ww = wet[y0:y1, x0:x1]
                chan = int((cut & (ww >= 0.999)).sum())
                band = int((cut & (ww > 0.0) & (ww < 0.999)).sum())
                near = int(((ww > 0.0) & (np.hypot(*np.mgrid[y0:y1, x0:x1] - np.array([vy, vx])[:, None, None])
                                          * vm <= res["blend"] + 600)).sum())
            else:
                near = 0
            rows.append((b["burg_code"], b["group"], med, None if before is None else before[0],
                         "GIVEUP(%.0f)" % res["need"] if res["cut"] is None else res["cut"], res["blend"], after is not None and after[0] <= 0.0 and after[0] <= max_shore,
                         chan, band, near))
    print("%-14s %-8s %6s %6s %7s %7s %5s %5s %5s %6s" % ("port", "group", "town_m", "shore", "cut_m", "blend",
                                                          "pier", "chan", "band", "wetnr"))
    for code, grp, med, shore, cut, blend, pier, chan, band, near in sorted(rows, key=lambda r: -r[2]):
        print("%-14s %-8s %6.0f %6s %7s %7.0f %5s %5d %5d %6d" % (
            code, grp, med, "-" if shore is None else "%.0f" % shore,
            cut if isinstance(cut, str) else "%.0f" % cut, blend, "yes" if pier else "no", chan, band, near))
    print("%d ports caught" % len(rows))
    print("\nEVERY PORT'S PIER (type, metres from the centre to the pier's middle)")
    cut_n = 0
    for code, cut, ps in sorted(piers_all, key=lambda r: -max([d for _t, d in r[2]] or [-1])):
        cut_n += 1 if cut else 0
        print("%-14s cut=%-6s %s" % (code, "GIVEUP" if cut is None else "%.0f" % cut,
                                     ", ".join("%s %.0f m" % p for p in ps) or "NO PIER"))
    print("%d ports, %d cut, %d with a pier, %d without" % (
        len(piers_all), cut_n, sum(1 for r in piers_all if r[2]), sum(1 for r in piers_all if not r[2])))


if __name__ == "__main__":
    main()
