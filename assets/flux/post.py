#!/usr/bin/env python3
"""Post-process generated portraits into game assets through ComfyUI.

    python3 assets/flux/post.py assets/flux/out/characters/C-01_*_c-full_*.png
    python3 assets/flux/post.py --tier chip assets/flux/out/characters/C-04_*_c-bust_*.png

Each file is uploaded to ComfyUI's input folder, run through
post_cutout_template.json (BiRefNet cutout -> alpha -> lanczos resize), and
the RGBA PNG is saved under assets/flux/out/game/<tier>/<ID>.png — never
into assets/portraits/, so nothing in the game changes until you copy it.

Tiers (sizes follow the game's existing art: scripts/ui/character_portrait.gd
draws 48x48 design px chips from 96x96 files, and full-body art is 660 px tall):
    full  -> height 660, width by aspect   (from a [C-FULL] render)
    chip  -> 96 x 96                        (from a [C-BUST] render)
The tier is read from the filename tag (_c-full_ / _c-bust_) unless --tier
is given. Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate as gen  # noqa: E402  (shared ComfyUI helpers)

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "post_cutout_template.json"
OUT_DIR = HERE / "out" / "game"
TIERS = {"full": (0, 660), "chip": (96, 96)}


def upload(path: Path) -> str:
    """POST the file to /upload/image (multipart, overwrite) and return the
    name LoadImage should use."""
    boundary = "----cc" + uuid.uuid4().hex
    data = path.read_bytes()
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="image"; filename="{path.name}"\r\n'.encode(),
        b"Content-Type: image/png\r\n\r\n", data, b"\r\n",
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n',
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="subfolder"\r\n\r\ncc_post\r\n',
        f"--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(gen.SERVER + "/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        res = json.load(r)
    sub = res.get("subfolder", "")
    return f"{sub}/{res['name']}" if sub else res["name"]


def tier_of(path: Path, forced: str) -> str:
    if forced:
        return forced
    if "_c-full_" in path.name:
        return "full"
    if "_c-bust_" in path.name:
        return "chip"
    raise ValueError(f"{path.name}: no _c-full_/_c-bust_ tag in the name; pass --tier")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="generated PNGs")
    ap.add_argument("--tier", choices=TIERS, default="", help="force the output tier")
    ap.add_argument("--timeout", type=float, default=300.0)
    args = ap.parse_args()
    template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    jobs = []
    for f in args.files:
        path = Path(f)
        tier = tier_of(path, args.tier)
        entry_id = re.match(r"([A-Z]-\d\d)", path.name)
        stem = entry_id.group(1) if entry_id else path.stem
        # Keep A/B variants apart: model and style tags from the render's name.
        for tag in re.findall(r"_(klein|schnell|v1_antique|[a-z0-9]+_antique)_", path.name):
            stem += "_" + tag
        width, height = TIERS[tier]
        name = upload(path)
        graph = gen.make_graph(template, {"image": name, "width": width, "height": height,
                                          "prefix": f"flux/game/{tier}/{stem}"})
        res = gen._post("/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex})
        jobs.append((res["prompt_id"], tier, stem))
        print(f"queued {path.name} -> {tier} {res['prompt_id'][:8]}")
    failures = 0
    for prompt_id, tier, stem in jobs:
        try:
            images = gen.wait_for(prompt_id, args.timeout)
        except (RuntimeError, TimeoutError) as e:
            print(f"FAILED {stem}: {e}", file=sys.stderr)
            failures += 1
            continue
        dest = OUT_DIR / tier / f"{stem}.png"
        gen.download(images[0], dest)
        print(f"saved {dest.relative_to(gen.ROOT)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
