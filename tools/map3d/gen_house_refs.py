"""Render the settlement buildings' photoreal REFERENCE images on the LOCAL
ComfyUI from assets/imagegen/house_ref_prompts.csv, one picture per type per
model, into assets/3D/buildings/<type>/model_wip/<type>_ref_<model>.png.

  python3 tools/map3d/gen_house_refs.py [--set houses|ships] [--model zimage,qwen2512fast] [--only a,b] [--seed N] [--variants N] [--tag T] [--force] [--front]

The models are Z-Image Turbo and Qwen-Image-2512 (owner 2026-09-30: no Flux
any more; both side by side for the owner to pick), filled from
assets/imagegen/generate.py's MODEL_PRESETS and templates with the SAME prompt
every model gets. Z-Image has no negative path, so NEGATIVE reaches Qwen
only (with a row's own `negative` column added). The old Flux.2 klein pictures stay as <type>_ref.png, the record the
shipped meshes were modelled against. Every job is queued first and
collected after; it waits its turn in ComfyUI's one shared queue unless
--front puts it ahead (the last model listed is queued first, so with
--front the first model listed runs first). --variants N renders N seeds
(seed, seed+1, ...) as <type>_ref_<model>_v1.png .. _vN.png beside the one
picture. --tag T names them <type>_ref_<model>_T[_vN].png, so a re-render
with a changed prompt keeps the pictures already picked from. --set ships
renders the harbours' SHIPS (owner 2026-10-02: 3-4 种中世纪的船) from
assets/imagegen/ship_ref_prompts.csv into assets/3D/ships/<type>/model_wip/,
worded as a ship, not a building.

A file already there is kept unless --force. The pictures are what the
hand-modelled houses (tools/map3d/blender_houses/) are modelled against.
ComfyUI stops at the image (owner 2026-09-24): no 3D is generated here.
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

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROMPTS = os.path.join(ROOT, "assets", "imagegen", "house_ref_prompts.csv")
BUILDINGS = os.path.join(ROOT, "assets", "3D", "buildings")
HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
COMFY = os.path.expanduser(os.environ.get(
    "COMFY_ROOT", "~/ComfyUI-Installs/GameDev/ComfyUI"))

# The owner's workflow, word for word around the subject.
PROMPT = ("a single {subject}, one building only, {features}, isolated on a "
          "plain pure white background, centered, three-quarter front view, "
          "slightly elevated camera, game asset concept art, clean crisp "
          "silhouette, soft even studio lighting, no ground plane, no cast "
          "shadow, no people, no text")
NEGATIVE = ("landscape, terrain, grass, trees, sky, multiple buildings, "
            "village, map, top-down, text, watermark, signature, cropped, "
            "out of frame, blurry, clutter, flags, banners, cartoon, toy")
SHIP_PROMPTS = os.path.join(ROOT, "assets", "imagegen", "ship_ref_prompts.csv")
SHIP_PROMPT = ("a single {subject}, one ship only, {features}, the whole hull "
               "out of the water, isolated on a plain pure white background, "
               "centered, three-quarter side view, slightly elevated camera, "
               "game asset concept art, clean crisp silhouette, soft even "
               "studio lighting, no water, no sea, no ground plane, no cast "
               "shadow, no people, no text")
SETS = {"houses": (PROMPTS, BUILDINGS, PROMPT),
        "ships": (SHIP_PROMPTS, os.path.join(ROOT, "assets", "3D", "ships"), SHIP_PROMPT)}
SEED = 20260923
MODELS = ["zimage", "qwen2512fast"]
IMAGEGEN_DIR = os.path.join(ROOT, "assets", "imagegen")


def _generate_module():
    spec = importlib.util.spec_from_file_location("imagegen_generate", os.path.join(IMAGEGEN_DIR, "generate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rows(only, path=PROMPTS):
    with open(path, newline="") as f:
        out = [r for r in csv.DictReader(f)]
    return [r for r in out if not only or r["type"] in only]


def post(path, data):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json"})
    body = urllib.request.urlopen(req).read()
    return json.loads(body) if body.strip() else {}


def get(path):
    return json.loads(urllib.request.urlopen(HOST + path).read())


def wait(pid, timeout_s):
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        h = get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st.get("messages"))[-2000:])
            if st.get("completed"):
                return h[pid]
        time.sleep(3)
    raise TimeoutError(pid)


def image_graph(gen, model, row, seed, prompt=PROMPT):
    preset = gen.MODEL_PRESETS[model]
    with open(os.path.join(IMAGEGEN_DIR, preset["template"])) as f:
        template = json.load(f)
    values = {"unet": preset["unet"], "steps": preset["steps"], "cfg": preset["cfg"],
              "guidance": preset["guidance"], "width": 1024, "height": 1024, "seed": seed,
              "prompt": prompt.format(subject=row["subject"], features=row["features"]),
              "negative": ", ".join(x for x in (NEGATIVE, row.get("negative", "")) if x), "prefix": "house_ref/%s_%s" % (row["type"], model)}
    if "lora_strength" in preset:
        values["lora_strength"] = preset["lora_strength"]
    return gen.make_graph(template, values)


def fetch(img, dest):
    src = os.path.join(COMFY, "output", img["subfolder"], img["filename"])
    if not os.path.exists(src):
        src = os.path.join(os.path.expanduser("~/ComfyUI-Shared/output"), img["subfolder"], img["filename"])
    shutil.copyfile(src, dest)


def main():
    args = sys.argv[1:]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    models = args[args.index("--model") + 1].split(",") if "--model" in args else MODELS
    gen = _generate_module()
    for m in models:
        if m not in gen.MODEL_PRESETS:
            sys.exit("not a model for the house references: %s" % m)
    variants = int(args[args.index("--variants") + 1]) if "--variants" in args else 1
    front = "--front" in args
    tag = "_" + args[args.index("--tag") + 1] if "--tag" in args else ""
    prompts, out_root, prompt = SETS[args[args.index("--set") + 1] if "--set" in args else "houses"]
    jobs = []
    for model in (list(reversed(models)) if front else models):
        gen.switch_model(gen.MODEL_PRESETS[model]["unet"])  # one unload per model, never two models thrashing
        for row in rows(only, prompts):
            t = row["type"]
            wip = os.path.join(out_root, t, "model_wip")
            os.makedirs(wip, exist_ok=True)
            if not os.path.exists(os.path.join(wip, ".gdignore")):
                open(os.path.join(wip, ".gdignore"), "w").close()
            for v in range(variants):
                name = "%s_ref_%s%s%s.png" % (t, model, tag, "_v%d" % (v + 1) if variants > 1 else "")
                ref = os.path.join(wip, name)
                if os.path.exists(ref) and "--force" not in args:
                    print("keep", ref)
                    continue
                pid = post("/prompt", {"prompt": image_graph(gen, model, row, seed + v, prompt),
                                       "client_id": str(uuid.uuid4()), "front": front})["prompt_id"]
                jobs.append((pid, ref))
                print("queued", model, t, v + 1, pid, flush=True)
        gen.mark_loaded(gen.MODEL_PRESETS[model]["unet"])
    t0 = time.time()
    for pid, ref in jobs:
        hist = wait(pid, 4 * 3600)
        img = [i for out in hist["outputs"].values() for i in out.get("images", [])][0]
        fetch(img, ref)
        print("%.0fs -> %s" % (time.time() - t0, ref), flush=True)
    gen.free_models()


if __name__ == "__main__":
    main()
