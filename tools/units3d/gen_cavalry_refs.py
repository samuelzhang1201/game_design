"""Render the cavalry piece's REFERENCE images on the LOCAL ComfyUI (Flux.2
klein 4B base, Apache-2.0), the pictures the hand-modelled cavalry is
modelled against in Blender. Owner 2026-09-24: the Hunyuan3D wargame pieces
are to be remade by hand; ComfyUI stops at the image.

  python3 tools/units3d/gen_cavalry_refs.py concept [--only A,B] [--seed N] [--force]
  python3 tools/units3d/gen_cavalry_refs.py sheet --ref <picked.png> [--only ...] [--seed N] [--force]

`concept` renders every stage=concept row of assets/flux/cavalry_ref_prompts.csv
(one design each) into assets/flux/out/cavalry_ref/<id>.png. `sheet` renders
the stage=sheet rows — turnarounds and part breakdowns of ONE picked design —
with the picked picture fed in as a Flux.2 reference latent, so every sheet
draws that same horse, rider and kit. A file already there is kept unless
--force.
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
PROMPTS = os.path.join(ROOT, "assets", "flux", "cavalry_ref_prompts.csv")
OUT_DIR = os.path.join(ROOT, "assets", "flux", "out", "cavalry_ref")
HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
COMFY = os.path.expanduser(os.environ.get("COMFY_ROOT", "~/ComfyUI-Installs/GameDev/ComfyUI"))
SHARED_OUT = os.path.expanduser("~/ComfyUI-Shared/output")
SEED = 20260924

# Hands (owner 2026-09-24: "所有人的手都画错了"): the 4B model draws a hand
# holding a lance or a shield as a knot of fingers, so a concept holds NO
# weapon — the weapons are separate rigid parts in Blender anyway, drawn on
# their own sheet — and the hands are gloved fists on the reins.
# A concept is a photograph of a real reenactor: the realism ruling for the
# buildings (taste.md, simple realism, never toy) holds for the pieces too,
# and a whole figure on white with even light is what a modeller can read.
CONCEPT = ("photograph of {subject}, {features}, {pose}, museum-quality historical "
           "reenactment with accurate replica arms and armour, realistic adult human "
           "proportions and realistic horse anatomy, the whole horse and rider fully "
           "inside the frame from the tips of the ears to all four hooves with a "
           "generous margin, the rider's hands in mail mittens or plain leather gloves "
           "closed as simple fists with no loose fingers, three-quarter front view from eye level, isolated on a "
           "plain pure white seamless studio background, soft even studio lighting, "
           "sharp focus over the whole figure, clear readable silhouette")
SHEET = ("{subject}, {features}, {pose}, exactly the same horse, rider, colours and "
         "equipment as the reference photograph, orthographic technical reference for "
         "a 3D modeller, realistic, plain pure white background, soft even lighting, "
         "no cast shadow, sharp focus")
NEGATIVE = ("cartoon, anime, toy, miniature, figurine, chibi, big head, stylised, "
            "fantasy armour, spikes, horns, fur trim, fringe, tassels, loose chains, "
            "flags, banners, pennants, fifteenth-century full plate armour, modern "
            "clothing, crowd, a second horse, landscape, grass, sky, ground plane, "
            "text, watermark, signature, cropped, cut off hooves, cut off head, blurry, "
            "bare hands, extra fingers, fused fingers, malformed hands, deformed hands, "
            "a weapon held in the hand")
SIZE = {"concept": (1344, 896), "sheet": (1344, 896)}


def rows(stage, only):
    with open(PROMPTS, newline="") as f:
        out = [r for r in csv.DictReader(f) if r["stage"] == stage]
    return [r for r in out if not only or r["id"] in only]


def post(path, data):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json"})
    body = urllib.request.urlopen(req).read()
    return json.loads(body) if body.strip() else {}


def get(path):
    return json.loads(urllib.request.urlopen(HOST + path).read())


def upload(path):
    """POST a local picture into ComfyUI's input folder; returns its name there."""
    boundary = uuid.uuid4().hex
    name = "cavalry_ref_" + os.path.basename(path)
    with open(path, "rb") as f:
        data = f.read()
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n"
             "Content-Type: image/png\r\n\r\n" % (boundary, name)).encode() + data
            + ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
               "\r\n--%s--\r\n" % (boundary, boundary)).encode())
    req = urllib.request.Request(HOST + "/upload/image", data=body,
                                 headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    return json.loads(urllib.request.urlopen(req).read())["name"]


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


def graph(row, stage, seed, ref_name=None):
    w, h = SIZE[stage]
    text = (CONCEPT if stage == "concept" else SHEET).format(**row)
    g = {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-base-4b.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": text, "clip": ["2", 0]}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": NEGATIVE, "clip": ["2", 0]}},
        "6": {"class_type": "CFGGuider", "inputs": {"cfg": 4.0, "model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0]}},
        "7": {"class_type": "Flux2Scheduler", "inputs": {"steps": 32, "width": w, "height": h}},
        "8": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "9": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "10": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["9", 0], "guider": ["6", 0], "sampler": ["10", 0], "sigmas": ["7", 0], "latent_image": ["8", 0]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "cavalry_ref/%s" % row["id"]}},
    }
    if ref_name:
        # the picked design as a Flux.2 reference latent on the positive side
        g["20"] = {"class_type": "LoadImage", "inputs": {"image": ref_name}}
        g["21"] = {"class_type": "ImageScaleToTotalPixels", "inputs": {"image": ["20", 0], "upscale_method": "lanczos", "megapixels": 1.0, "resolution_steps": 16}}
        g["22"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["21", 0], "vae": ["3", 0]}}
        g["23"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["4", 0], "latent": ["22", 0]}}
        g["6"]["inputs"]["positive"] = ["23", 0]
    return g


def main():
    args = sys.argv[1:]
    stage = args[0] if args and args[0] in ("concept", "sheet") else "concept"
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    ref_name = None
    if stage == "sheet":
        if "--ref" not in args:
            sys.exit("sheet needs --ref <picked concept png>")
        ref_name = upload(args[args.index("--ref") + 1])
    os.makedirs(OUT_DIR, exist_ok=True)
    for row in rows(stage, only):
        dst = os.path.join(OUT_DIR, row["id"] + ".png")
        if os.path.exists(dst) and "--force" not in args:
            print("keep", dst)
            continue
        hist, dt = run(graph(row, stage, seed, ref_name), 3600)
        img = hist["outputs"]["13"]["images"][0]
        src = os.path.join(COMFY, "output", img["subfolder"], img["filename"])
        if not os.path.exists(src):
            src = os.path.join(SHARED_OUT, img["subfolder"], img["filename"])
        shutil.copyfile(src, dst)
        print("%s %.0fs -> %s" % (row["id"], dt, dst), flush=True)


if __name__ == "__main__":
    main()
