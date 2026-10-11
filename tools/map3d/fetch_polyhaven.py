"""SPIKE: download Poly Haven models (glTF, 1k textures) into
assets/3D/terrain/model_wip/polyhaven/models/<id>/ — the same files the Blender MCP's Poly Haven
download fetches, through the public API (https://api.polyhaven.com, CC0).
  python3 tools/map3d/fetch_polyhaven.py fir_tree_01 tree_small_02 ...
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEST = os.path.join(ROOT, "assets", "3D", "terrain", "model_wip", "polyhaven", "models")


def get(url):
    # curl, not urllib: the python.org build here has no CA bundle.
    return subprocess.run(["curl", "-sfL", "-A", "beyond-the-kings-words-spike", url],
                          check=True, capture_output=True).stdout


def fetch(asset_id, res="1k"):
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset_id}"))
    gltf = files["gltf"][res]["gltf"]
    out = os.path.join(DEST, asset_id)
    items = [(os.path.basename(gltf["url"]), gltf)] + list(gltf.get("include", {}).items())
    for rel, meta in items:
        path = os.path.join(out, rel)
        if os.path.exists(path) and os.path.getsize(path) == meta.get("size", -1):
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(get(meta["url"]))
        print(asset_id, rel, meta.get("size"))
    print("done", asset_id)


for a in sys.argv[1:]:
    fetch(a)
