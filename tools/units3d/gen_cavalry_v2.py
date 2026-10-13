"""Cavalry redesign v2 (owner 2026-09-25): armoured rider WITH lance and
shield, four designs (assets/imagegen/cavalry_v2_prompts.csv) rendered on three
local model tiers so the owner can compare and pick one (klein, a Flux
model, was dropped 2026-10-01: no Flux).

  python3 tools/units3d/gen_cavalry_v2.py                 # the desktop tiers, all designs
  python3 tools/units3d/gen_cavalry_v2.py --tiers zimage,qwenfast --only A,C
  python3 tools/units3d/gen_cavalry_v2.py --seeds 2       # 2 seeds per cell

Tiers (all Apache-2.0, see claude/t2i-model-evaluation-2026-09.md):
  zimage   Z-Image Turbo, 8 steps                          desktop, ~10 s / image
  qwendesk Qwen-Image-2512 fp8 + Lightning 4-step LoRA      desktop, ~15 s / image
  qwenfast Qwen-Image-2512 Q6_K + Lightning LoRA, 8 steps  Mac,    ~2 min / image
  qwen     Qwen-Image-2512 Q6_K full, 50 steps             Mac,    ~18 min / image (run overnight)
Each tier runs on its machine (owner 2026-10-12/13: Z-Image only on the Windows desktop,
Qwen there by default): the desktop at ZIMAGE_URL, the Mac at COMFY_HOST.
Output: assets/3D/units/cavalry/model_wip/cavalry_v2/<tier>_<id>_s<n>.png, then a contact sheet
contact_sheet.png if Pillow is importable. Existing files are kept unless --force.
Needs the desktop's ComfyUI at ZIMAGE_URL (default http://192.168.4.85:8188) for the desktop
tiers and the Mac's at COMFY_HOST (default http://127.0.0.1:8188) for the Mac tiers.
"""
import csv, json, os, sys, time, urllib.parse, urllib.request, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMAGEGEN = ROOT / "assets" / "imagegen"
OUT = IMAGEGEN.parent / "3D" / "units" / "cavalry" / "model_wip" / "cavalry_v2"
HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")  # the Mac
DESK_HOST = os.environ.get("ZIMAGE_URL", "http://192.168.4.85:8188").rstrip("/")  # the Windows desktop
SEED = 20260925

WRAP = ("Photograph of {p}. Three-quarter side view from eye level, the entire horse and "
        "rider and the whole lance from tip to butt fully inside the frame with a generous "
        "margin, all four hooves visible. Museum-quality historical reenactment with accurate "
        "replica medieval arms and armour, realistic adult proportions and realistic horse "
        "anatomy, gloved hands closed firmly around the lance and the reins, plain pure white "
        "seamless studio background, soft even studio light, sharp detail over the whole "
        "figure, clear readable silhouette, character concept reference for a 3D game model, no text")
NEGATIVE = ("cartoon, anime, toy, miniature, figurine, chibi, big head, stylised, fantasy armour, "
            "spikes, horns, fur trim, flags, banners, modern clothing, crowd, a second horse, "
            "landscape, grass, sky, text, watermark, signature, cropped, cut off hooves, cut off "
            "head, cut off lance, blurry, extra fingers, fused fingers, malformed hands, extra legs, "
            "five legs, broken lance, two lances")
TIERS = {  # name: (template, values)
    "zimage": ("zimage_turbo_template.json", dict(unet="z_image_turbo_bf16.safetensors", steps=8, cfg=1.0, width=1344, height=896)),
    "qwendesk": ("qwen2512_desktop_template.json", dict(unet="qwen_image_2512_fp8_e4m3fn.safetensors", lora="Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors", steps=4, cfg=1.0, lora_strength=1.0, width=1584, height=1056)),
    "qwenfast": ("qwen2512_template.json", dict(unet="qwen-image-2512-Q6_K.gguf", steps=8, cfg=1.0, lora_strength=1.0, width=1584, height=1056)),
    "qwen": ("qwen2512_template.json", dict(unet="qwen-image-2512-Q6_K.gguf", steps=50, cfg=4.0, lora_strength=0.0, width=1584, height=1056)),
}


DESK_TIERS = {"zimage", "qwendesk"}
DEFAULT_TIERS = ["zimage", "qwendesk"]  # the Mac tiers (qwenfast, qwen) only when asked for


def host_of(tier):
    return DESK_HOST if tier in DESK_TIERS else HOST


def call(path, data=None, host=HOST):
    req = urllib.request.Request(host + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def graph(template_file, values):
    t = json.loads((IMAGEGEN / template_file).read_text(encoding="utf-8"))
    g = json.loads(json.dumps({k: v for k, v in t.items() if not k.startswith("_")}))
    for slot, targets in t.get("_slots", {}).items():
        if slot in values:
            for nid, name in targets:
                g[nid]["inputs"][name] = values[slot]
    return g


def run(g, timeout, host=HOST):
    pid = json.loads(call("/prompt", {"prompt": g, "client_id": str(uuid.uuid4())}, host))["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        h = json.loads(call("/history/" + pid, host=host))
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st.get("messages"))[-1500:])
            imgs = [i for o in h[pid].get("outputs", {}).values() for i in o.get("images", [])]
            if imgs:
                return imgs[0], time.time() - t0
        time.sleep(3)
    raise TimeoutError(pid)


def arg(name, default):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a else default


def sheet(files):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow not installed: skip contact sheet"); return
    tiers = [t for t in TIERS if any(f.name.startswith(t + "_") for f in files)]
    ids = sorted({f.name.split("_")[1] for f in files})
    cw, ch = 672, 448
    im = Image.new("RGB", (cw * len(ids), (ch + 28) * len(tiers)), "white")
    d = ImageDraw.Draw(im)
    for r, t in enumerate(tiers):
        for c, i in enumerate(ids):
            f = OUT / f"{t}_{i}_s1.png"
            if f.exists():
                im.paste(Image.open(f).convert("RGB").resize((cw, ch)), (c * cw, r * (ch + 28) + 28))
            d.text((c * cw + 8, r * (ch + 28) + 6), f"{t} / {i}", fill="black")
    im.save(OUT / "contact_sheet.png"); print("->", OUT / "contact_sheet.png")


def main():
    tiers = arg("--tiers", ",".join(DEFAULT_TIERS)).split(",")
    only = set(filter(None, arg("--only", "").split(",")))
    seeds = int(arg("--seeds", "1"))
    with open(IMAGEGEN / "cavalry_v2_prompts.csv", newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["id"] in only]
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for t in tiers:  # tier-major, so the quick tiers finish before qwen starts
        tpl, vals = TIERS[t]
        for r in rows:
            for s in range(1, seeds + 1):
                dst = OUT / f"{t}_{r['id']}_s{s}.png"
                if dst.exists() and "--force" not in sys.argv:
                    print("keep", dst.name); done.append(dst); continue
                v = dict(vals, prompt=WRAP.format(p=r["prompt"]), negative=NEGATIVE,
                         seed=SEED + s - 1, prefix=f"cavalry_v2/{t}_{r['id']}_s{s}")
                img, dt = run(graph(tpl, v), 3600, host_of(t))
                q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
                dst.write_bytes(call("/view?" + q, host=host_of(t)))
                print(f"{dst.name}  {dt:.0f}s", flush=True); done.append(dst)
    sheet(done)


if __name__ == "__main__":
    main()
