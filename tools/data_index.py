"""The data folders for the Python tools (spec 2026-10-11-data-folders-by-scene):
data/tables.csv names each table's folder, and every indexed folder's
balance.csv merges into one dict — DataRepository.table_path / load_balance's
twins, so a bake reads the numbers the game does.

    from data_index import table_path, balance   # with tools/ on sys.path
"""
import csv
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA = os.path.join(ROOT, "data")


def _index() -> dict:
    with open(os.path.join(DATA, "tables.csv"), encoding="utf-8", newline="") as f:
        return {r["table"]: r["folder"] for r in csv.DictReader(f)}


def table_path(table: str) -> str:
    """The absolute path of data/<folder>/<table>.csv."""
    return os.path.join(DATA, _index()[table], table + ".csv")


def balance() -> dict:
    """Every folder's balance.csv as key -> float; a key in two files raises."""
    out, where = {}, {}
    for folder in sorted(set(_index().values())):
        path = os.path.join(DATA, folder, "balance.csv")
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                key = r["key"]
                if key in where:
                    raise ValueError("balance key %s is in both %s/balance.csv and %s/balance.csv"
                                     % (key, where[key], folder))
                where[key] = folder
                out[key] = float(r["value"])
    return out
