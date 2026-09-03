#!/usr/bin/env python3
"""Import an Azgaar Fantasy Map Generator full export into game data.

Reads the newest "*Full*.json" and newest map render PNG in assets/maps/
and writes (all committed to git; re-run after every re-export):

  data/kingdoms.csv    one row per state (state 0 "Neutrals" excluded)
  data/provinces.csv   one row per province
  data/burgs.csv       one row per burg
  assets/maps/world_map.png          byte copy under a stable name
  assets/maps/world_state_index.png  hit-test bitmap: each land cell's
      polygon filled with R = state_id & 0xFF, G = state_id >> 8, B = 0;
      untouched pixels stay white (255,255,255) = water / no state

Stdlib only (no Pillow): the PNG is written with zlib + struct, polygons
are filled with an even-odd scanline rasterizer. Deterministic: same
inputs => byte-identical outputs. Hand-edits to the generated CSVs are
overwritten; lasting changes belong in Azgaar.

Usage:  python3 tools/import_azgaar.py [--json PATH] [--png PATH]
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS = ROOT / "assets" / "maps"
DATA = ROOT / "data"
FICTION_KINGDOMS = {"averlain", "bentleigh", "doncaster", "empire"}
GENERATED_PNGS = {"world_map.png", "world_state_index.png"}


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return slug or "unnamed"


class SlugTable:
    """Hands out collision-free slugs (foo, foo_2, foo_3, ...)."""

    def __init__(self) -> None:
        self._used: dict[str, int] = {}

    def take(self, name: str) -> str:
        base = slugify(name)
        n = self._used.get(base, 0) + 1
        self._used[base] = n
        return base if n == 1 else f"{base}_{n}"


def newest(pattern_hits: list[Path], what: str) -> Path:
    if not pattern_hits:
        sys.exit(f"error: no {what} found in {MAPS}")
    return max(pattern_hits, key=lambda p: p.stat().st_mtime)


def active(entries: list) -> list[dict]:
    """Azgaar lists start with a literal 0 and may flag removed rows."""
    return [e for e in entries if isinstance(e, dict) and not e.get("removed")]


def png_dimensions(path: Path) -> tuple[int, int]:
    head = path.read_bytes()[:33]
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        sys.exit(f"error: {path} is not a PNG")
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def write_png_rgb(path: Path, width: int, height: int, buf: bytearray) -> None:
    """Minimal RGB8 PNG writer: buf is width*height*3 bytes, row-major."""

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    stride = width * 3
    raw = b"".join(
        b"\x00" + bytes(buf[y * stride:(y + 1) * stride]) for y in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def fill_polygon(buf: bytearray, width: int, height: int,
                 pts: list[tuple[float, float]], state_id: int) -> None:
    """Even-odd scanline fill sampling pixel centers (x+0.5, y+0.5)."""
    r, g = state_id & 0xFF, (state_id >> 8) & 0xFF
    ys = [p[1] for p in pts]
    y_lo = max(0, int(min(ys)))
    y_hi = min(height - 1, int(max(ys)) + 1)
    n = len(pts)
    for y in range(y_lo, y_hi + 1):
        yc = y + 0.5
        xs: list[float] = []
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if (y1 <= yc < y2) or (y2 <= yc < y1):
                xs.append(x1 + (yc - y1) / (y2 - y1) * (x2 - x1))
        xs.sort()
        for j in range(0, len(xs) - 1, 2):
            x_lo = max(0, int(xs[j] + 0.5))
            x_hi = min(width - 1, int(xs[j + 1] - 0.5))
            for x in range(x_lo, x_hi + 1):
                o = (y * width + x) * 3
                buf[o] = r
                buf[o + 1] = g
                buf[o + 2] = 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--png", type=Path, default=None)
    args = ap.parse_args()

    json_path = args.json or newest(
        sorted(MAPS.glob("*Full*.json")), "Azgaar full export (*Full*.json)")
    png_path = args.png or newest(
        [p for p in MAPS.glob("*.png") if p.name not in GENERATED_PNGS],
        "map render PNG")
    print(f"json: {json_path.name}\npng:  {png_path.name}")

    world = json.loads(json_path.read_text())
    width, height = world["info"]["width"], world["info"]["height"]
    png_w, png_h = png_dimensions(png_path)
    if (png_w, png_h) != (width, height):
        sys.exit(f"error: JSON says {width}x{height} but PNG is {png_w}x{png_h}")

    pack = world["pack"]
    rate = float(world["settings"].get("populationRate", 1000))
    cells: list[dict] = pack["cells"]
    vertices: list[dict] = pack["vertices"]
    states = [s for s in active(pack["states"]) if s["i"] != 0]
    provinces = active(pack["provinces"])
    burgs = active(pack["burgs"])

    # --- codes ------------------------------------------------------------
    state_code = {s["i"]: slugify(s["name"]) for s in states}
    if len(set(state_code.values())) != len(state_code):
        sys.exit("error: two states slugify to the same kingdom_code")
    prov_slugs, burg_slugs = SlugTable(), SlugTable()
    prov_code = {p["i"]: prov_slugs.take(p["name"]) for p in provinces}
    burg_code = {b["i"]: burg_slugs.take(b["name"]) for b in burgs}

    # --- referential checks ----------------------------------------------
    for p in provinces:
        if p["state"] not in state_code:
            sys.exit(f"error: province {p['i']} references missing state {p['state']}")
    burg_province: dict[int, int] = {}
    for b in burgs:
        if b["state"] not in state_code:
            sys.exit(f"error: burg {b['i']} references missing state {b['state']}")
        prov_id = cells[b["cell"]].get("province", 0)
        if prov_id not in prov_code:
            sys.exit(f"error: burg {b['i']} cell {b['cell']} has no province")
        burg_province[b["i"]] = prov_id

    # --- aggregate cells per province ------------------------------------
    prov_area: dict[int, float] = {i: 0.0 for i in prov_code}
    prov_pop: dict[int, float] = {i: 0.0 for i in prov_code}
    for c in cells:
        pid = c.get("province", 0)
        if pid in prov_area:
            prov_area[pid] += c.get("area", 0)
            prov_pop[pid] += c.get("pop", 0)
    for b in burgs:  # urban population on top of the cells' rural points
        prov_pop[burg_province[b["i"]]] += b.get("population", 0)

    # --- kingdoms.csv -----------------------------------------------------
    DATA.mkdir(exist_ok=True)
    with (DATA / "kingdoms.csv").open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["kingdom_code", "state_id", "label", "capital_burg",
                    "neighbor_codes", "color", "area", "population",
                    "center_x", "center_y"])
        for s in sorted(states, key=lambda s: s["i"]):
            center = cells[s["center"]]["p"]
            neighbors = "|".join(state_code[n] for n in s.get("neighbors", [])
                                 if n in state_code)
            w.writerow([state_code[s["i"]], s["i"], s["name"],
                        burg_code.get(s.get("capital", 0), ""),
                        neighbors, s.get("color", ""), int(s.get("area", 0)),
                        int(round((s.get("rural", 0) + s.get("urban", 0)) * rate)),
                        round(center[0], 2), round(center[1], 2)])

    # --- provinces.csv ----------------------------------------------------
    with (DATA / "provinces.csv").open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["province_code", "label", "kingdom_code", "capital_burg",
                    "area", "population"])
        for p in sorted(provinces, key=lambda p: p["i"]):
            w.writerow([prov_code[p["i"]], p["name"], state_code[p["state"]],
                        burg_code.get(p.get("burg", 0), ""),
                        int(prov_area[p["i"]]),
                        int(round(prov_pop[p["i"]] * rate))])

    # --- burgs.csv --------------------------------------------------------
    with (DATA / "burgs.csv").open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["burg_code", "label", "province_code", "kingdom_code",
                    "population", "is_capital", "is_port", "x", "y"])
        for b in sorted(burgs, key=lambda b: b["i"]):
            w.writerow([burg_code[b["i"]], b["name"],
                        prov_code[burg_province[b["i"]]], state_code[b["state"]],
                        int(round(b.get("population", 0) * rate)),
                        1 if b.get("capital") else 0, 1 if b.get("port") else 0,
                        round(b["x"], 2), round(b["y"], 2)])

    # --- bitmaps ----------------------------------------------------------
    shutil.copyfile(png_path, MAPS / "world_map.png")
    buf = bytearray(b"\xff" * (width * height * 3))
    for c in cells:
        sid = c.get("state", 0)
        if sid in state_code:
            pts = [tuple(vertices[v]["p"]) for v in c["v"]]
            fill_polygon(buf, width, height, pts, sid)
    write_png_rgb(MAPS / "world_state_index.png", width, height, buf)

    # --- report -----------------------------------------------------------
    missing = sorted(FICTION_KINGDOMS - set(state_code.values()))
    if missing:
        print(f"WARNING: fiction kingdoms not on the map yet: {', '.join(missing)}"
              "\n         (expected until states are renamed in Azgaar and re-exported)")
    print(f"wrote {len(states)} kingdoms, {len(provinces)} provinces, "
          f"{len(burgs)} burgs, world_map.png, world_state_index.png")


if __name__ == "__main__":
    main()
