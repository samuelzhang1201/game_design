"""Render the settlement buildings' photoreal REFERENCE images on the LOCAL
ComfyUI: one Flux.2 klein 4B picture per type from
assets/flux/house_ref_prompts.csv into assets/3D/buildings/<type>/model_wip/<type>_ref.png.

  python3 tools/map3d/gen_house_refs.py [--only a,b] [--seed N] [--force]

A file already there is kept unless --force, so a hand-picked reference
(cottage_a is the owner's own) is never overwritten. The pictures are what
the hand-modelled houses (tools/map3d/blender_houses/) are modelled against.
ComfyUI stops at the image (owner 2026-09-24): Hunyuan3D image-to-3D was
removed over its licence, and no 3D is generated here.
"""

import csv
import json
import os
import shutil
import sys
import time
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROMPTS = os.path.join(ROOT, "assets", "flux", "house_ref_prompts.csv")
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
SEED = 20260923


def rows(only):
    with open(PROMPTS, newline="") as f:
        out = [r for r in csv.DictReader(f)]
    return [r for r in out if not only or r["type"] in only]


def post(path, data):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json"})
    body = urllib.request.urlopen(req).read()
    return json.loads(body) if body.strip() else {}


def get(path):
    return json.loads(urllib.request.urlopen(HOST + path).read())


def run(graph, timeout_s):
    pid = post("/prompt", {"prompt": graph, "client_id": str(uuid.uuid4())})["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        h = get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st.get("messages"))[-2000:])
            if st.get("completed"):
                return h[pid], time.time() - t0
        time.sleep(3)
    raise TimeoutError(pid)


def image_graph(row, seed):
    text = PROMPT.format(subject=row["subject"], features=row["features"])
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-base-4b.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": text, "clip": ["2", 0]}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": NEGATIVE, "clip": ["2", 0]}},
        "6": {"class_type": "CFGGuider", "inputs": {"cfg": 4.0, "model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0]}},
        "7": {"class_type": "Flux2Scheduler", "inputs": {"steps": 20, "width": 1024, "height": 1024}},
        "8": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "9": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "10": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["9", 0], "guider": ["6", 0], "sampler": ["10", 0], "sigmas": ["7", 0], "latent_image": ["8", 0]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "house_ref/%s" % row["type"]}},
    }


def main():
    args = sys.argv[1:]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    for row in rows(only):
        t = row["type"]
        wip = os.path.join(BUILDINGS, t, "model_wip")
        os.makedirs(wip, exist_ok=True)
        ref = os.path.join(wip, t + "_ref.png")
        if os.path.exists(ref) and "--force" not in args:
            print("keep", ref)
            continue
        hist, dt = run(image_graph(row, seed), 3600)
        img = hist["outputs"]["13"]["images"][0]
        src = os.path.join(COMFY, "output", img["subfolder"], img["filename"])
        if not os.path.exists(src):
            src = os.path.join(os.path.expanduser("~/ComfyUI-Shared/output"), img["subfolder"], img["filename"])
        shutil.copyfile(src, ref)
        print("%s %.0fs -> %s" % (t, dt, ref), flush=True)


if __name__ == "__main__":
    main()
