#!/usr/bin/env python3
"""
comfy_batch.py — queue every row of illustrations_manifest.csv on a LOCAL ComfyUI instance.

Stdlib only. Works with any Flux (or other) workflow you already have:
  1. In ComfyUI, enable "Dev mode", then "Save (API Format)" your workflow -> my_flux_api.json
  2. Copy comfy_nodes.example.json -> comfy_nodes.json and fill in the node ids
     (the numeric keys in the API json) for prompt, seed, size and save nodes.
  3. Run:
       python comfy_batch.py --workflow my_flux_api.json --nodes comfy_nodes.json            # everything
       python comfy_batch.py ... --kind character_ref --variants 4                            # refs first, 4 seeds each
       python comfy_batch.py ... --only C1_IL07 C1_IL13 --variants 3                          # re-roll specific shots
       python comfy_batch.py ... --dry-run                                                    # print what would run

Output: <out>/<illus_id>_v<n>.png plus <out>/run_log.jsonl (seed, prompt, workflow hash)
so every accepted image can be regenerated exactly.
"""
import argparse
import csv
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid


def http_json(url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def set_field(wf, node_id, field, value):
    if node_id not in wf:
        sys.exit(f"node id '{node_id}' not found in workflow (check comfy_nodes.json)")
    wf[node_id]["inputs"][field] = value


def build(wf_template, nodes, row, seed, prefix):
    wf = json.loads(json.dumps(wf_template))
    set_field(wf, nodes["prompt"]["node"], nodes["prompt"]["field"], row["prompt"])
    set_field(wf, nodes["seed"]["node"], nodes["seed"]["field"], seed)
    set_field(wf, nodes["size"]["node"], nodes["size"]["width_field"], int(row["width"]))
    set_field(wf, nodes["size"]["node"], nodes["size"]["height_field"], int(row["height"]))
    set_field(wf, nodes["save"]["node"], nodes["save"]["field"], prefix)
    return wf


def wait_and_fetch(server, prompt_id, out_path, poll=2.0, timeout=1800):
    t0 = time.time()
    while time.time() - t0 < timeout:
        hist = http_json(f"{server}/history/{prompt_id}")
        if prompt_id in hist:
            entry = hist[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI error: {status.get('messages')}")
            for node_out in entry.get("outputs", {}).values():
                for img in node_out.get("images", []):
                    q = urllib.parse.urlencode({"filename": img["filename"],
                                                "subfolder": img.get("subfolder", ""),
                                                "type": img.get("type", "output")})
                    with urllib.request.urlopen(f"{server}/view?{q}", timeout=60) as r, open(out_path, "wb") as f:
                        f.write(r.read())
                    return
            raise RuntimeError("finished but no image output (is the save node an image saver?)")
        time.sleep(poll)
    raise TimeoutError(prompt_id)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="illustrations_manifest.csv")
    ap.add_argument("--workflow", required=True, help="API-format workflow JSON exported from ComfyUI")
    ap.add_argument("--nodes", required=True, help="node mapping JSON (see comfy_nodes.example.json)")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--out", default="illustrations_out")
    ap.add_argument("--only", nargs="*", help="illus_ids to run")
    ap.add_argument("--kind", choices=["scene", "character_ref"])
    ap.add_argument("--variants", type=int, default=1, help="seeds per shot (seed, seed+1, ...)")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    wf_raw = open(a.workflow, "rb").read()
    wf_template = json.loads(wf_raw)
    wf_hash = hashlib.sha256(wf_raw).hexdigest()[:12]
    nodes = json.load(open(a.nodes, encoding="utf-8"))
    rows = list(csv.DictReader(open(a.manifest, encoding="utf-8", newline="")))
    if a.only:
        rows = [r for r in rows if r["illus_id"] in set(a.only)]
    if a.kind:
        rows = [r for r in rows if r["kind"] == a.kind]
    os.makedirs(a.out, exist_ok=True)
    client_id = str(uuid.uuid4())
    log = open(os.path.join(a.out, "run_log.jsonl"), "a", encoding="utf-8")

    jobs = [(r, int(r["seed"]) + v, v) for r in rows for v in range(a.variants)]
    print(f"{len(jobs)} jobs ({len(rows)} shots x {a.variants} variants), workflow {wf_hash}")
    for i, (row, seed, v) in enumerate(jobs, 1):
        name = f"{row['illus_id']}_v{v}"
        out_path = os.path.join(a.out, name + ".png")
        if os.path.exists(out_path) and not a.overwrite:
            print(f"[{i}/{len(jobs)}] skip {name} (exists)")
            continue
        print(f"[{i}/{len(jobs)}] {name}  seed={seed}  {row['width']}x{row['height']}  {row['title_zh']}")
        if a.dry_run:
            continue
        wf = build(wf_template, nodes, row, seed, f"ourgrandages/{name}")
        resp = http_json(f"{a.server}/prompt", {"prompt": wf, "client_id": client_id})
        if resp.get("node_errors"):
            sys.exit(f"node errors: {resp['node_errors']}")
        wait_and_fetch(a.server, resp["prompt_id"], out_path)
        log.write(json.dumps({"illus_id": row["illus_id"], "variant": v, "seed": seed,
                              "width": int(row["width"]), "height": int(row["height"]),
                              "prompt": row["prompt"], "workflow_sha": wf_hash,
                              "file": os.path.basename(out_path), "ts": time.time()},
                             ensure_ascii=False) + "\n")
        log.flush()
    print("done")


if __name__ == "__main__":
    main()
