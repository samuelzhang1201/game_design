#!/usr/bin/env python3
"""The WAR ROOM's reference pictures (owner 2026-10-01: Qwen-Image-2512 only),
rendered on the local ComfyUI from assets/imagegen/war_room_ref_prompts.csv into
assets/3D/war_room/<type>/model_wip/<type>_ref_<model>.png — what the room,
table, candlestick, rake and pennant in tools/war_room/blender/ were modelled
against.

  python3 tools/war_room/gen_room_refs.py [--model qwen2512fast] [--only a,b] [--seed N] [--force]

Each CSV row gives its own prompt template ({subject}, {features}), negative
and canvas size. A file already there is kept unless --force. Ask the owner
before queuing any generation (house rule). The graph and the model presets
are assets/imagegen/generate.py's, as tools/map3d/gen_house_refs.py uses them.
"""
import csv
import importlib.util
import json
import os
import shutil
import sys
import time
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMAGEGEN = os.path.join(ROOT, "assets", "imagegen")
PROMPTS = os.path.join(IMAGEGEN, "war_room_ref_prompts.csv")
OUT = os.path.join(ROOT, "assets", "3D", "war_room")
HOST = "http://127.0.0.1:8188"
COMFY_OUTPUTS = [os.path.expanduser("~/ComfyUI-Installs/GameDev/ComfyUI/output"),
                 os.path.expanduser("~/ComfyUI-Shared/output")]
SEED = 20261001


def _generate_module():
    spec = importlib.util.spec_from_file_location("imagegen_generate", os.path.join(IMAGEGEN, "generate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _post(path, data):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json"})
    body = urllib.request.urlopen(req).read()
    return json.loads(body) if body.strip() else {}


def _fetch(img, dest):
    for base in COMFY_OUTPUTS:
        src = os.path.join(base, img["subfolder"], img["filename"])
        if os.path.exists(src):
            shutil.copyfile(src, dest)
            return
    url = HOST + "/view?filename=%s&subfolder=%s&type=output" % (img["filename"], img["subfolder"])
    with open(dest, "wb") as f:
        f.write(urllib.request.urlopen(url).read())


def main():
    args = sys.argv[1:]
    model = args[args.index("--model") + 1] if "--model" in args else "qwen2512fast"
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    gen = _generate_module()
    if model not in gen.MODEL_PRESETS or model in ("klein", "schnell"):
        sys.exit("not a model for the war room references: %s" % model)
    preset = gen.MODEL_PRESETS[model]
    with open(os.path.join(IMAGEGEN, preset["template"])) as f:
        template = json.load(f)
    with open(PROMPTS, newline="") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["type"] in only]
    jobs = []
    for row in rows:
        wip = os.path.join(OUT, row["type"], "model_wip")
        os.makedirs(wip, exist_ok=True)
        dest = os.path.join(wip, "%s_ref_%s.png" % (row["type"], model))
        if os.path.exists(dest) and "--force" not in args:
            print("keep", dest)
            continue
        values = {"unet": preset["unet"], "steps": preset["steps"], "cfg": preset["cfg"],
                  "guidance": preset["guidance"], "width": int(row["width"]), "height": int(row["height"]),
                  "seed": seed, "negative": row["negative"],
                  "prompt": row["prompt_template"].format(subject=row["subject"], features=row["features"]),
                  "prefix": "war_room_ref/%s_%s" % (row["type"], model)}
        if "lora_strength" in preset:
            values["lora_strength"] = preset["lora_strength"]
        pid = _post("/prompt", {"prompt": gen.make_graph(template, values),
                                "client_id": str(uuid.uuid4())})["prompt_id"]
        jobs.append((pid, dest))
        print("queued", row["type"], pid, flush=True)
    for pid, dest in jobs:
        _fetch(gen.wait_for(pid, 1800)[0], dest)
        print("got", dest, flush=True)


if __name__ == "__main__":
    t0 = time.time()
    main()
    print("done in %.0fs" % (time.time() - t0))
