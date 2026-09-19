"""Map-pack helpers for the Python tools, so none of them names a pack.

    from packs import default_pack, map3d_dir   # with tools/ on sys.path
"""
import csv
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def default_pack(maps_csv: str = os.path.join(ROOT, "data", "maps.csv")) -> str:
    """data/maps.csv's is_default pack, else its first row, else ""."""
    first = ""
    with open(maps_csv, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            first = first or row["map_id"]
            if row.get("is_default", "") == "1":
                return row["map_id"]
    return first


def map3d_dir(map_id: str, maps_csv: str = os.path.join(ROOT, "data", "maps.csv")) -> str:
    """Where map_id's 3D build lives, as a filesystem path: its maps.csv
    map3d_dir (res:// mapped to the repo root), else ROOT/assets/map3d/<id>."""
    with open(maps_csv, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            d = (row.get("map3d_dir") or "").strip()
            if row["map_id"] == map_id and d:
                if d.startswith("res://"):
                    return os.path.join(ROOT, d[len("res://"):])
                return d
    return os.path.join(ROOT, "assets", "map3d", map_id)
