"""Generate the settlement buildings' AI sources on the LOCAL ComfyUI
(owner 2026-09-23): a photoreal Flux reference per type, then Hunyuan3D 2.1
image-to-3D with its own texture paint.

  python3 tools/map3d/gen_house_sources.py image [--only a,b] [--seed N]
  python3 tools/map3d/gen_house_sources.py shape|paint|mesh [--only a,b] [--restart CMD]

`image` renders assets/flux/house_ref_prompts.csv through Flux.2 klein 4B
(the prompt shape and settings of the owner's "Hunyuan3D 2.1 Building
Pipeline" workflow, whose cottage `Dev/examples/building_src_rgb_00001_.png`
is the reference every other type follows) into
assets/flux/out/house_ref/<type>.png. A file already there is kept, so a
hand-picked reference (cottage_a is the owner's own) is never overwritten.

`mesh` cuts each reference out (BiRefNet), runs the Hunyuan3D 2.1 shape and
paint stages and copies the textured glTF to assets/hunyuan_ref/houses/sources/
<type>.glb — the input of retopo_houses.py, which takes it from there to the
game (retopo -> dilate_house_atlas.py -> scale_houses.py; see README.md).

Text-to-3D is never used: asked in words Hunyuan returns a toy (2026-09-22).
"""

import csv
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROMPTS = os.path.join(ROOT, "assets", "flux", "house_ref_prompts.csv")
REF_DIR = os.path.join(ROOT, "assets", "flux", "out", "house_ref")
SRC_DIR = os.path.join(ROOT, "assets", "hunyuan_ref", "houses", "sources")
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
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")


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


def upload(path, name):
    boundary = uuid.uuid4().hex
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n"
             "Content-Type: image/png\r\n\r\n") % (boundary, name)).encode()
    body += open(path, "rb").read()
    body += ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
             "\r\n--%s--\r\n" % (boundary, boundary)).encode()
    req = urllib.request.Request(HOST + "/upload/image", data=body,
                                 headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    return json.loads(urllib.request.urlopen(req).read())["name"]


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
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "3D/houses/%s_rgb" % row["type"]}},
    }


def cutout(image_name, out_name):
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "14": {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}},
        "15": {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["14", 0], "image": ["1", 0]}},
        "16": {"class_type": "InvertMask", "inputs": {"mask": ["15", 0]}},
        "17": {"class_type": "JoinImageWithAlpha", "inputs": {"image": ["1", 0], "alpha": ["16", 0]}},
    }


# The shape and the paint run as SEPARATE prompts, each in a freshly started
# ComfyUI (--restart). On this Mac's MPS pool the two stages together never
# fit (2026-09-23): FlashVDM's decode at octree 384 ran dry, then the paint's
# multiview model did with the shape's leftovers still held, and a failed
# prompt keeps its allocations, poisoning every prompt after it. Octree 256
# with the plain decoder is ample for a building drawn at ~20 px.
def shape_graph(image_name, out_name):
    g = cutout(image_name, out_name)
    g.update({
        # The cut-out, kept: project_house_texture.py fits the camera to it.
        "18": {"class_type": "SaveImage", "inputs": {"images": ["17", 0], "filename_prefix": "3D/houses/%s_rgba" % out_name}},
        "19": {"class_type": "Hy3D21VAELoader", "inputs": {"model_name": "Hunyuan3D-vae-v2-1-fp16.ckpt"}},
        "20": {"class_type": "Hy3D21MeshGenerator", "inputs": {"model": "hunyuan3D-dit-v2-1-fp16.ckpt", "image": ["17", 0], "steps": 30, "guidance_scale": 5.0, "seed": SEED, "attention_mode": "sdpa"}},
        "21": {"class_type": "Hy3D21VAEDecode", "inputs": {"vae": ["19", 0], "latents": ["20", 0], "box_v": 1.01, "octree_resolution": 256, "num_chunks": 8000, "mc_level": 0.0, "mc_algo": "mc", "enable_flash_vdm": False, "force_offload": True}},
        "22": {"class_type": "Hy3D21PostprocessMesh", "inputs": {"trimesh": ["21", 0], "remove_floaters": True, "remove_degenerate_faces": True, "reduce_faces": True, "max_facenum": 40000, "smooth_normals": False}},
        "23": {"class_type": "Hy3D21ExportMesh", "inputs": {"trimesh": ["22", 0], "filename_prefix": "3D/houses/%s_white" % out_name, "file_format": "glb"}},
    })
    return g


def paint_graph(image_name, white_glb, out_name):
    g = cutout(image_name, out_name)
    g.update({
        "22": {"class_type": "Hy3D21LoadMesh", "inputs": {"glb_path": white_glb}},
        "24": {"class_type": "Hy3D21MeshUVWrap", "inputs": {"trimesh": ["22", 0]}},
        "25": {"class_type": "Hy3D21CameraConfig", "inputs": {"camera_azimuths": PAINT_AZIMUTHS, "camera_elevations": PAINT_ELEVATIONS, "view_weights": PAINT_WEIGHTS, "ortho_scale": 1.1}},
        "26": {"class_type": "Hy3DMultiViewsGenerator", "inputs": {"trimesh": ["24", 0], "camera_config": ["25", 0], "view_size": PAINT_VIEW_PX, "image": ["17", 0], "steps": 10, "guidance_scale": 3.0, "texture_size": 1024, "unwrap_mesh": False, "seed": SEED}},
        "27": {"class_type": "Hy3DBakeMultiViews", "inputs": {"pipeline": ["26", 0], "camera_config": ["25", 0], "albedo": ["26", 1], "mr": ["26", 2]}},
        "28": {"class_type": "Hy3DInPaint", "inputs": {"pipeline": ["27", 0], "albedo": ["27", 1], "albedo_mask": ["27", 2], "mr": ["27", 3], "mr_mask": ["27", 4], "output_mesh_name": out_name}},
    })
    return g


# FOUR views, not the workflow's six: three round the sides 120 degrees apart
# (each sees two walls obliquely) and one from straight above, since the map
# looks DOWN on a building and its roof is most of what anyone sees. Six
# views (and five) only fit this Mac's MPS pool by swapping — 190 s a step,
# half an hour a house, 2026-09-23 — and the multiview model will not go
# below 512 px a view, so the view COUNT is the one lever.
PAINT_AZIMUTHS = "0, 120, 240, 0"
PAINT_ELEVATIONS = "0, 0, 0, 90"
PAINT_WEIGHTS = "1, 1, 1, 1"
PAINT_VIEW_PX = 512


def restart(cmd):
    if cmd:
        os.system(cmd)


def main():
    args = sys.argv[1:]
    stage = args[0]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else SEED
    os.makedirs(REF_DIR, exist_ok=True)
    for row in rows(only):
        t = row["type"]
        ref = os.path.join(REF_DIR, t + ".png")
        if stage == "image":
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
        elif stage in ("shape", "paint", "mesh"):
            rs = args[args.index("--restart") + 1] if "--restart" in args else ""
            out_name = "house_%s" % t
            white_dir = os.path.join(os.path.expanduser("~/ComfyUI-Shared/output"), "3D", "houses")
            if stage in ("shape", "mesh"):
                restart(rs)
                name = upload(ref, "house_ref_%s.png" % t)
                hist, dt = run(shape_graph(name, out_name), 7200)
                print("%s shape %.0fs" % (t, dt), flush=True)
            if stage in ("paint", "mesh"):
                whites = sorted(f for f in os.listdir(white_dir) if f.startswith(out_name + "_white_"))
                restart(rs)
                name = upload(ref, "house_ref_%s.png" % t)
                hist, dt = run(paint_graph(name, os.path.join(white_dir, whites[-1]), out_name), 7200)
                glb = os.path.join(COMFY, "output", out_name + ".glb")
                os.makedirs(SRC_DIR, exist_ok=True)
                # The paint comes back upside down; align it on its white model.
                code = subprocess.call([BLENDER, "-b", "--factory-startup", "--python",
                                        os.path.join(ROOT, "tools", "map3d", "align_house_source.py"),
                                        "--", glb, os.path.join(white_dir, whites[-1]),
                                        os.path.join(SRC_DIR, t + ".glb")],
                                       stdout=subprocess.DEVNULL)
                if code != 0:
                    raise RuntimeError("%s: align_house_source.py refused the paint" % t)
                print("%s paint %.0fs -> ai_src/%s.glb" % (t, dt, t), flush=True)


if __name__ == "__main__":
    main()
