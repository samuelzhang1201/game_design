"""Map-pack helpers for the Python tools, so none of them names a pack.

    from packs import default_pack      # with tools/ on sys.path
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
