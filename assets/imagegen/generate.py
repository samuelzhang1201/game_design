#!/usr/bin/env python3
"""Bulk image generation for the art prompt library, through a local ComfyUI.

    python3 assets/imagegen/generate.py --build-csv           # re-parse the library into prompts.csv
    python3 assets/imagegen/generate.py --ids C-01,T-01,I-04  # generate a few entries
    python3 assets/imagegen/generate.py --chapter T --variants 5   # every tile, 5 seeds each
    python3 assets/imagegen/generate.py --ids C-01 --dry-run  # print the assembled prompt only
    python3 assets/imagegen/generate.py --model qwenedit_fast --images out/cast/K-01_x.png \
        --instruction "the same man seen from behind, full body"   # edit a picture

Edit presets (qwenedit / qwenedit_fast, Qwen-Image-Edit-2511) take one to
three pictures with --images: the first is edited, the others are references.
The prompt is --instruction, followed by the assembled row prompt when --ids
are given too; without --ids the output goes to out/edits/. An edit's file
name carries --tag (or the instruction's first words) and a 6-character hash
of the instruction and the input pictures, so two edits never share a name.

Every prompt is assembled as  STYLE_CORE + subject + CANVAS  from the files
beside this script, never typed by hand (prompt library §0.1 / §10.8). The
ComfyUI graph is the chosen model's template (qwen2512_template.json or
zimage_turbo_template.json); this script only fills its slots and talks to
the server's HTTP API (queue, history, view). No Flux model is used (owner
2026-10-01: 我们不用flux模型). Outputs are copied to
assets/imagegen/out/<chapter dir>/<ID>_<slug>_<model>_s<seed>.png.

Stdlib only (json, csv, urllib); no ComfyUI SDK needed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LIBRARY = ROOT / "docs" / "references" / "art_prompt_library.md"
PROMPTS_CSV = HERE / "prompts.csv"
STYLE_CORE = HERE / "STYLE_CORE.txt"
NEGATIVE = HERE / "NEGATIVE.txt"
OUT_DIR = HERE / "out"
SERVER = "http://127.0.0.1:8188"

# Prompt library §0.3: where each ID prefix is filed.
CHAPTER_DIR = {
    "C": "characters", "K": "cast", "E": "expressions", "P": "expressions", "M": "map",
    "T": "terrain", "I": "icons", "D": "decor", "G": "goods", "B": "estates", "H": "buildings",
    "W": "tactical",
    "V": "events", "U": "ui",
    # A- (2026-09-15) are the houses' and kingdoms' arms. They are not library
    # entries: arms_prompts.py writes them from the map pack's coa into
    # arms_prompts.csv, read with --prompts-file.
    "A": "arms",
    # X- (2026-09-18) is the game's own application icon, read with
    # --prompts-file app_icon_prompts.csv; installed by install_map_art.py app_icon.
    "X": "app_icon",
    # L- (2026-10-10) are the LEDGER galaxy's materials: a star's sphere and a
    # link's strand, read with --prompts-file ledger_art_prompts.csv.
    "L": "ledger",
}
# Table-driven chapters carry their canvas per chapter (§5, §6, §7, §9);
# E/P rows are fragments layered onto a character, not assets on their own.
# B- (§6.11, 2026-09-14) is the manor card's painted estate: the v2 colour
# style of the characters, on its own 5:4 vignette canvas.
TABLE_CANVAS = {"T": "C-TILE", "I": "C-ICON", "D": "C-MAPMARK", "G": "C-MAPMARK",
                "B": "C-ESTATE", "H": "C-ICON", "W": "C-SYMBOL",
                "U": "C-UIPIECE", "E": "", "P": ""}
# Prompt library §10.7 target sizes per canvas, generated at the models' native
# 1024-class resolution (icons and tiles are downscaled afterwards).
CANVAS_SIZE = {
    "C-PORTRAIT": (1024, 1024), "C-BUST": (1024, 1024), "C-FULL": (1024, 1536),
    "C-ICON": (1024, 1024), "C-TILE": (1024, 1024), "C-MAP": (1536, 1024),
    "C-SCENE": (1536, 1024), "C-EVENT": (1536, 640), "C-SYMBOL": (1024, 1024), "C-MAPMARK": (1024, 1024),
    "C-UIPIECE": (1024, 1024), "C-UIWIDE": (1536, 512), "C-FRAME": (1792, 1008),
    "C-ESTATE": (1280, 1024), "C-ARMS": (1024, 1024),
    "C-COURIER": (1280, 1024),
    "C-TILEWIDE": (1024, 1024),
    "C-TOWNFLAT": (1024, 1024),
    "C-WARPIECE": (1024, 1024),
    "C-ORB": (1024, 1024), "C-STRAND": (1536, 512),
}
# One preset per model: which template graph to fill and its sampler values.
# Only two models make the game's 2D art (owner 2026-10-01: no Flux at all —
# klein and schnell, and their templates, are gone): zimage = Z-Image Turbo
# (Apache 2.0, 6B, 8 steps, CFG 1, no negative path); qwen2512 =
# Qwen-Image-2512 Q6_K GGUF (Apache 2.0, 20B; needs the ComfyUI-GGUF node) at
# full quality, qwen2512fast = the same with the Lightning 8-step LoRA
# (Apache 2.0), the owner's pick for the game's art since 2026-09-30.
# qwenedit / qwenedit_fast = Qwen-Image-Edit-2511 Q6_K GGUF (Apache 2.0, 20B,
# image editing with up to three input pictures; owner 2026-10-10) without and
# with its own Lightning 8-step LoRA (Apache 2.0); "edit" presets need --images.
# Models: assets/imagegen/download_models.sh.
# NOT listed on purpose: every Flux model, Ideogram 4 open weights
# (non-commercial), HunyuanImage (licence excludes EU/UK/KR), Qwen-Image-2.1
# (research licence), Krea 2 open / SD3.5 (revenue cap).
MODEL_PRESETS = {
    "zimage": {"template": "zimage_turbo_template.json", "unet": "z_image_turbo_bf16.safetensors",
               "steps": 8, "guidance": 0.0, "cfg": 1.0},
    "qwen2512": {"template": "qwen2512_template.json", "unet": "qwen-image-2512-Q6_K.gguf",
                 "steps": 50, "guidance": 0.0, "cfg": 4.0, "lora_strength": 0.0},
    "qwen2512fast": {"template": "qwen2512_template.json", "unet": "qwen-image-2512-Q6_K.gguf",
                     "steps": 8, "guidance": 0.0, "cfg": 1.0, "lora_strength": 1.0},
    "qwenedit": {"template": "qwen_edit2511_template.json", "unet": "qwen-image-edit-2511-Q6_K.gguf",
                 "steps": 40, "guidance": 0.0, "cfg": 4.0, "lora_strength": 0.0, "edit": True},
    "qwenedit_fast": {"template": "qwen_edit2511_template.json", "unet": "qwen-image-edit-2511-Q6_K.gguf",
                      "steps": 8, "guidance": 0.0, "cfg": 1.0, "lora_strength": 1.0, "edit": True},
}
EDIT_SLOTS = ("image1", "image2", "image3")
# The edit template's LoadImage node per input slot; an unused one is deleted.
EDIT_PIXELS = 1024 * 1024


# ---------------------------------------------------------------- parsing

def _canvas_fragments(text: str) -> dict[str, str]:
    """§1.3 table: [C-XXX] code -> its verbatim fragment."""
    out = {}
    for m in re.finditer(r"^\| `\[(C-[A-Z]+)\]` \| [^|]+ \| `([^`]+)` \|", text, re.M):
        out[m.group(1)] = m.group(2).strip()
    return out


def parse_library(text: str) -> list[dict]:
    rows = []
    # Headed entries (C-, V-, M-): a heading line, then a fenced block that
    # starts with [S] and ends with the canvas code.
    for m in re.finditer(r"^#{3,4} `([A-Z]-\d\d)` ([^\n]*)\n(?:[^\n]*\n)*?```\n(.*?)```",
                         text, re.M | re.S):
        entry_id, title, block = m.group(1), m.group(2).strip(), " ".join(m.group(3).split())
        canvas = re.search(r"\[(C-[A-Z]+)\]", block)
        subject = re.sub(r"\[S\]|\[C-[A-Z]+\]", "", block).strip(" ,")
        # Optional **外貌** line between the heading and the block: looks and
        # clothing only, for the full-body and bust tiers (library §2 note).
        look = re.search(r"\*\*外貌\*\*：`([^`]+)`", m.group(0))
        rows.append({"id": entry_id, "chapter": entry_id[0], "title": title,
                     "canvas": canvas.group(1) if canvas else "", "subject": subject,
                     "appearance": " ".join(look.group(1).split()) if look else ""})
    # Table entries (T-, I-, W-, U-, E-, P-): one row each, canvas by chapter.
    for m in re.finditer(r"^\| `([A-Z]-\d\d)` \| ([^|]+) \| `([^`]+)` \|", text, re.M):
        entry_id, title, subject = m.group(1), m.group(2).strip(), " ".join(m.group(3).split())
        rows.append({"id": entry_id, "chapter": entry_id[0], "title": title,
                     "canvas": TABLE_CANVAS.get(entry_id[0], ""), "subject": subject,
                     "appearance": ""})
    # Wide table entries (§9.1, the Missive board U-20..U-26, 2026-09-28):
    # ID | key | title | canvas | size | subject — each row names its own canvas.
    for m in re.finditer(r"^\| `([A-Z]-\d\d)` \| `[^`]+` \| ([^|]+) \| `\[(C-[A-Z]+)\]` \| [^|]+ \| `([^`]+)` \|",
                         text, re.M):
        rows.append({"id": m.group(1), "chapter": m.group(1)[0], "title": m.group(2).strip(),
                     "canvas": m.group(3), "subject": " ".join(m.group(4).split()), "appearance": ""})
    rows.sort(key=lambda r: (list(CHAPTER_DIR).index(r["chapter"]), r["id"]))
    for r in rows:
        w, h = CANVAS_SIZE.get(r["canvas"], (0, 0))
        r["width"], r["height"] = w, h
        r["dir"] = CHAPTER_DIR[r["chapter"]]
    return rows


def build_csv() -> None:
    text = LIBRARY.read_text(encoding="utf-8")
    rows = parse_library(text)
    with PROMPTS_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["id", "chapter", "dir", "title", "canvas", "width", "height", "subject", "appearance"])
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in w.fieldnames})
    frags = _canvas_fragments(text)
    (HERE / "canvas.json").write_text(json.dumps(frags, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    by = {}
    for r in rows:
        by[r["chapter"]] = by.get(r["chapter"], 0) + 1
    print(f"wrote {PROMPTS_CSV.name}: {len(rows)} entries {by}; canvas.json: {len(frags)} fragments")


# ---------------------------------------------------------------- prompts

def load_rows(prompts_file: str = "") -> list[dict]:
    """The library's prompts.csv, or another table of the same schema that a
    script wrote (arms_prompts.csv)."""
    path = (HERE / prompts_file) if prompts_file else PROMPTS_CSV
    if not prompts_file and not path.exists():
        build_csv()
    with path.open(encoding="utf-8") as f:
        return list(csv.DictReader(f))


def assemble(row: dict, canvas: dict[str, str], style: str, small: bool = False,
             fragments: list[str] | None = None) -> str:
    """STYLE_CORE + subject + canvas. For the full-body and bust tiers a row
    with an **外貌** line uses that (looks only) plus the pose/expression
    fragments (P-/E- rows) instead of the portrait prompt with its props."""
    if not row["canvas"]:
        raise ValueError(f"{row['id']} is a fragment (chapter {row['chapter']}), not a standalone asset")
    subject = row["subject"]
    if row["canvas"] in ("C-FULL", "C-BUST") and row.get("appearance"):
        subject = row["appearance"]
    for frag in fragments or []:
        subject += ", " + frag
    if small:  # §6: the 64 px icon tier gets a simplification suffix
        subject += ", extremely simplified, bold readable silhouette, minimal internal detail"
    return f"{style}, {subject}, {canvas[row['canvas']]}"


def negative_for(style_path: Path) -> Path:
    """The negative list that belongs to a style core. A non-default style may
    ship its own: STYLE_CORE_map_sepia.txt pairs with NEGATIVE_map_sepia.txt.
    It has to — the default list bans sepia and aged paper, which is exactly
    what the map-symbol style asks for (library appendix B)."""
    suffix = style_path.stem.replace("STYLE_CORE", "", 1).lstrip("_")
    paired = style_path.with_name(f"NEGATIVE_{suffix}.txt") if suffix else NEGATIVE
    return paired if paired.exists() else NEGATIVE


def slug(title: str, subject: str) -> str:
    """The English half of a headed title, else the subject's first words
    (table rows are titled in Chinese only)."""
    ascii_part = re.sub(r"[^A-Za-z0-9]+", "-", title.split("·")[-1]).strip("-").lower()
    if len(ascii_part) >= 3:
        return ascii_part
    words = [w for w in re.findall(r"[A-Za-z]+", subject) if w.lower() not in {"a", "an", "the", "of"}]
    return "-".join(words[:4]).lower() or "asset"


# ---------------------------------------------------------------- comfy api

def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(SERVER + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def _get(path: str) -> bytes:
    with urllib.request.urlopen(SERVER + path, timeout=60) as r:
        return r.read()


def upload(path: Path) -> str:
    """Send a local picture to ComfyUI's input folder; returns the name LoadImage takes."""
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: application/octet-stream\r\n\r\n").encode() + path.read_bytes() + \
        (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"subfolder\"\r\n\r\ncc_edit"
         f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
         f"\r\n--{boundary}--\r\n").encode()
    req = urllib.request.Request(SERVER + "/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        res = json.load(r)
    return f"{res['subfolder']}/{res['name']}" if res.get("subfolder") else res["name"]


def png_size(path: Path) -> tuple[int, int]:
    head = path.read_bytes()[:24]
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name}: an edit input must be a PNG")
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def edit_size(w: int, h: int) -> tuple[int, int]:
    """The input's aspect at about one megapixel, both sides multiples of 16."""
    k = (EDIT_PIXELS / float(w * h)) ** 0.5
    return max(256, int(round(w * k / 16.0)) * 16), max(256, int(round(h * k / 16.0)) * 16)


def prune_images(graph: dict, template: dict, used: int) -> dict:
    """Delete the LoadImage nodes of the edit slots past `used`, and every
    input that points at them (TextEncodeQwenImageEditPlus takes them optionally)."""
    dead = {template["_slots"][s][0][0] for s in EDIT_SLOTS[used:] if s in template.get("_slots", {})}
    for node_id in dead:
        graph.pop(node_id, None)
    for node in graph.values():
        for name, value in list(node["inputs"].items()):
            if isinstance(value, list) and value and value[0] in dead:
                del node["inputs"][name]
    return graph


def free_models() -> bool:
    """Unload ComfyUI's models when its queue is empty. On Apple unified memory
    ComfyUI otherwise keeps the last models (~44 GB after a Qwen-Image-Edit
    batch, 2026-10-11) until the Mac runs out of swap. The queue is shared by
    every session, so a model another job still needs is never pulled away."""
    try:
        q = json.loads(_get("/queue"))
        if q.get("queue_running") or q.get("queue_pending"):
            print("models kept: other jobs are still in ComfyUI's queue")
            return False
        req = urllib.request.Request(SERVER + "/free", data=json.dumps({"unload_models": True, "free_memory": True}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=60).read()  # answers 200 with an empty body
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"could not unload ComfyUI's models: {e}", file=sys.stderr)
        return False
    print("models unloaded from ComfyUI (pass --keep-loaded between the runs of a batch)")
    return True


def make_graph(template: dict, values: dict) -> dict:
    """Fill the template's _slots (slot name -> [[node id, input name], ...])
    with `values`; slots the template does not declare are ignored, so one
    driver serves graphs with different node sets."""
    g = json.loads(json.dumps({k: v for k, v in template.items() if not k.startswith("_")}))
    for slot, targets in template.get("_slots", {}).items():
        if slot not in values:
            continue
        for node_id, input_name in targets:
            g[node_id]["inputs"][input_name] = values[slot]
    return g


def wait_for(prompt_id: str, timeout: float) -> list[dict]:
    t0 = time.time()
    while time.time() - t0 < timeout:
        hist = json.loads(_get(f"/history/{prompt_id}"))
        if prompt_id in hist:
            entry = hist[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                msgs = [m for m in status.get("messages", []) if m[0] == "execution_error"]
                raise RuntimeError(f"ComfyUI error: {msgs[-1][1].get('exception_message') if msgs else status}")
            images = []
            for node_out in entry.get("outputs", {}).values():
                images.extend(node_out.get("images", []))
            if images:
                return images
        time.sleep(2.0)
    raise TimeoutError(f"job {prompt_id} did not finish in {timeout:.0f}s")


def download(image: dict, dest: Path) -> None:
    q = urllib.parse.urlencode({"filename": image["filename"], "subfolder": image.get("subfolder", ""),
                                "type": image.get("type", "output")})
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(_get("/view?" + q))


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build-csv", action="store_true", help="re-parse the prompt library into prompts.csv")
    ap.add_argument("--ids", default="", help="comma-separated IDs, e.g. C-01,T-01")
    ap.add_argument("--chapter", default="", help="one chapter letter: C V M T I D W U")
    ap.add_argument("--limit", type=int, default=0, help="stop after N entries")
    ap.add_argument("--variants", type=int, default=1, help="seeds per entry (tiles want 4-6)")
    ap.add_argument("--seed", type=int, default=954159497, help="base seed; variant i uses seed + i")
    ap.add_argument("--model", choices=MODEL_PRESETS, default="qwen2512fast")
    ap.add_argument("--steps", type=int, default=0, help="override the preset's steps")
    ap.add_argument("--cfg", type=float, default=0.0, help="override the preset's CFG")
    ap.add_argument("--small", action="store_true", help="icons: add the §6 small-tier suffix")
    ap.add_argument("--canvas", default="", help="override the canvas fragment, e.g. C-FULL or C-BUST for characters")
    ap.add_argument("--pose", default="", help="P-xx pose fragment appended to the subject (full-body tier)")
    ap.add_argument("--expression", default="", help="E-xx expression fragment appended to the subject (bust tier)")
    ap.add_argument("--style-file", default="", help="use another STYLE_CORE file (A/B tests), e.g. STYLE_CORE_map_sepia.txt")
    ap.add_argument("--negative-file", default="", help="override the negative list; by default the one paired with --style-file")
    ap.add_argument("--res", type=int, default=0,
                    help="sample resolution: scale the canvas so its longer side is N px (e.g. 512), keeping the aspect")
    ap.add_argument("--prompts-file", default="",
                    help="read entries from this CSV beside the script instead of prompts.csv, e.g. arms_prompts.csv")
    ap.add_argument("--images", default="",
                    help="edit presets: 1-3 comma-separated PNGs; the first is edited, the others are references")
    ap.add_argument("--instruction", default="",
                    help="edit presets: what to change, put before the row prompt (or alone without --ids)")
    ap.add_argument("--tag", default="",
                    help="edits: a readable name part, e.g. infantry_body_front (default: the instruction's first words)")
    ap.add_argument("--keep-loaded", action="store_true",
                    help="leave the models loaded after this run (a script calling generate.py many times; end it with --free)")
    ap.add_argument("--free", action="store_true", help="only unload ComfyUI's models (when its queue is empty), then exit")
    ap.add_argument("--dry-run", action="store_true", help="print prompts, queue nothing")
    ap.add_argument("--front", action="store_true", help="queue ahead of jobs already waiting in ComfyUI")
    ap.add_argument("--timeout", type=float, default=900.0, help="seconds to wait per image")
    args = ap.parse_args()
    if args.free:
        free_models()
        return 0

    if args.build_csv:
        build_csv()
        if not (args.ids or args.chapter):
            return 0

    rows = load_rows(args.prompts_file)
    canvas = json.loads((HERE / "canvas.json").read_text(encoding="utf-8"))
    by_id = {r["id"]: r for r in rows}
    fragments: list[str] = []
    for code in (args.pose, args.expression):
        if code:
            frag = by_id.get(code.upper())
            if frag is None or frag["chapter"] not in ("P", "E"):
                print(f"{code} is not a P-/E- fragment row", file=sys.stderr)
                return 2
            fragments.append(frag["subject"])
    style_path = (HERE / args.style_file) if args.style_file else STYLE_CORE
    style = " ".join(style_path.read_text(encoding="utf-8").split())
    negative_path = (HERE / args.negative_file) if args.negative_file else negative_for(style_path)
    wanted = [s.strip().upper() for s in args.ids.split(",") if s.strip()]
    if wanted:
        rows = [r for r in rows if r["id"] in wanted]
        missing = set(wanted) - {r["id"] for r in rows}
        if missing:
            print(f"unknown ids: {sorted(missing)}", file=sys.stderr)
            return 2
    if args.chapter:
        rows = [r for r in rows if r["chapter"] == args.chapter.upper()]
    rows = [r for r in rows if r["canvas"]]
    preset = dict(MODEL_PRESETS[args.model])
    images = [Path(p.strip()).expanduser() for p in args.images.split(",") if p.strip()]
    images = [p if p.is_absolute() else (Path.cwd() / p) for p in images]
    if preset.get("edit"):
        if not 1 <= len(images) <= len(EDIT_SLOTS):
            print(f"{args.model} needs --images with 1-{len(EDIT_SLOTS)} pictures", file=sys.stderr)
            return 2
        for p in images:
            if not p.exists():
                print(f"no such picture: {p}", file=sys.stderr)
                return 2
        if not (wanted or args.chapter):
            if not args.instruction:
                print("an edit without --ids needs --instruction", file=sys.stderr)
                return 2
            w, h = CANVAS_SIZE[args.canvas.upper()] if args.canvas else edit_size(*png_size(images[0]))
            rows = [{"id": "EDIT", "chapter": "", "dir": "edits", "title": images[0].stem,
                     "canvas": "", "subject": "", "width": w, "height": h}]
    elif images or args.instruction:
        print(f"--images / --instruction need an edit preset (qwenedit, qwenedit_fast), not {args.model}",
              file=sys.stderr)
        return 2
    if args.canvas:
        code = args.canvas.upper()
        if code not in canvas or code not in CANVAS_SIZE:
            print(f"unknown canvas {code}; choose from {sorted(canvas)}", file=sys.stderr)
            return 2
        for r in rows:
            if r["id"] != "EDIT":
                r["canvas"] = code
            r["width"], r["height"] = CANVAS_SIZE[code]
    if args.res:
        # Sample passes run small and cheap. Both sides stay multiples of 16
        # so the VAE is happy, and the aspect the canvas asked for survives.
        for r in rows:
            w, h = int(r["width"]), int(r["height"])
            k = float(args.res) / float(max(w, h))
            r["width"] = max(128, int(round(w * k / 16.0)) * 16)
            r["height"] = max(128, int(round(h * k / 16.0)) * 16)
    if args.limit:
        rows = rows[: args.limit]
    if not rows:
        print("nothing selected (use --ids or --chapter; E/P rows are fragments)", file=sys.stderr)
        return 2

    if args.steps:
        preset["steps"] = args.steps
    if args.cfg:
        preset["cfg"] = args.cfg
    template = json.loads((HERE / preset["template"]).read_text(encoding="utf-8"))
    negative = " ".join(negative_path.read_text(encoding="utf-8").split())
    uses_negative = "negative" in template.get("_slots", {})
    print(f"style {style_path.name}  negative {negative_path.name}")
    print(f"model {preset['unet']}  template {preset['template']}  steps {preset['steps']}  "
          f"{'cfg ' + str(preset['cfg']) if 'cfg' in template.get('_slots', {}) else 'guidance ' + str(preset['guidance'])}  "
          f"{len(rows)} entries x {args.variants} variant(s)")
    if not uses_negative:
        print(f"note: {preset['template']} has no negative-prompt path (distilled / guidance model); "
              "NEGATIVE.txt is not applied")

    uploaded = [] if args.dry_run else [upload(p) for p in images]
    # Same seed + same first words used to overwrite an earlier edit (2026-10-10):
    # the hash keys the name to the whole instruction and the pictures.
    edit_key = hashlib.sha1("\n".join([args.instruction] + [p.name for p in images]).encode()).hexdigest()[:6]
    edit_label = re.sub(r"[^A-Za-z0-9_-]+", "-", args.tag).strip("-") if args.tag else slug("", args.instruction)
    jobs = []
    for r in rows:
        prompt = "" if r["id"] == "EDIT" else assemble(r, canvas, style, args.small, fragments)
        if args.instruction:
            prompt = f"{args.instruction}, {prompt}" if prompt else args.instruction
        for i in range(args.variants):
            seed = args.seed + i
            tag = f"_{args.canvas.lower()}" if args.canvas else ""
            for code in (args.pose, args.expression):
                if code:
                    tag += f"_{code.lower()}"
            if args.style_file:
                tag += "_" + Path(args.style_file).stem.replace("STYLE_CORE_", "").lower()
            if args.res:
                tag += "_r%d" % args.res
            if preset.get("edit"):
                tag += f"_{edit_label}_{edit_key}"
            if r["id"] == "EDIT":
                name = f"{r['title']}{tag}_{args.model}_s{seed}"
            else:
                name = f"{r['id']}_{slug(r['title'], r['subject'])}{tag}_{args.model}_s{seed}"
            prefix = f"imagegen/{r['dir']}/{name}"
            if args.dry_run:
                print(f"\n[{r['id']}] {r['dir']}/{name}.png  {r['width']}x{r['height']}\n{prompt}")
                continue
            values = {
                "unet": preset["unet"], "prompt": prompt, "negative": negative,
                "guidance": preset["guidance"], "cfg": preset["cfg"], "steps": preset["steps"],
                "lora_strength": preset.get("lora_strength", 0.0),
                "width": int(r["width"]), "height": int(r["height"]), "seed": seed, "prefix": prefix}
            values.update(zip(EDIT_SLOTS, uploaded))
            graph = make_graph(template, values)
            if preset.get("edit"):
                graph = prune_images(graph, template, len(uploaded))
            try:
                payload = {"prompt": graph, "client_id": uuid.uuid4().hex}
                if args.front:
                    payload["front"] = True
                res = _post("/prompt", payload)
            except urllib.error.HTTPError as e:
                print(f"queue failed for {r['id']}: {e.read().decode()[:500]}", file=sys.stderr)
                return 1
            jobs.append((res["prompt_id"], r, name))
            print(f"queued {r['id']} seed {seed} -> {res['prompt_id'][:8]}")
    if args.dry_run:
        return 0

    failures = 0
    for prompt_id, r, name in jobs:
        try:
            images = wait_for(prompt_id, args.timeout)
        except (RuntimeError, TimeoutError) as e:
            print(f"FAILED {r['id']}: {e}", file=sys.stderr)
            failures += 1
            continue
        for k, img in enumerate(images):
            dest = OUT_DIR / r["dir"] / (f"{name}.png" if k == 0 else f"{name}_{k}.png")
            download(img, dest)
            print(f"saved {dest.relative_to(ROOT)}")
    if not args.keep_loaded:
        free_models()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
