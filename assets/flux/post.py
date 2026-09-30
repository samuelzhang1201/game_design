#!/usr/bin/env python3
"""Post-process generated portraits into game assets through ComfyUI.

    python3 assets/flux/post.py assets/flux/out/characters/C-01_*_c-full_*.png
    python3 assets/flux/post.py --tier chip assets/flux/out/characters/C-04_*_c-bust_*.png

Each file is uploaded to ComfyUI's input folder, run through
post_cutout_template.json (BiRefNet cutout -> alpha -> lanczos resize), and
the RGBA PNG is saved under assets/flux/out/game/<tier>/<ID>.png — never
into assets/2D/portraits/cast/, so nothing in the game changes until you copy it.

Tiers (sizes follow the game's existing art: scripts/ui/character_portrait.gd
draws 48x48 design px chips from 96x96 files, and full-body art is 660 px tall):
    full  -> height 660, width by aspect   (from a [C-FULL] render)
    chip  -> 96 x 96                        (from a [C-BUST] render)
    icon  -> 256 x 256                      (I-/U-/W- renders; the large tier of library §6)
    mark  -> height 256, width by aspect    (D-/[C-MAPMARK] renders, library §6.9)
The tier is read from the filename tag (_c-full_ / _c-bust_ / _c-mapmark_, or a
D- id) unless --tier is given. The mark tier runs a different graph:
sepia_alpha_template.json keys transparency off the render's own white paper,
because a sepia line drawing gives BiRefNet no silhouette to cut, and it is
trimmed to its own alpha bounding box first — a side-elevation symbol fills
anywhere from 47% to 77% of the square it was drawn in, so untrimmed the
margin would decide how big it lands on the map (a wide metropolis would draw
shorter than a market town).

--tone white-balances the finished asset onto the prompt library's one paper
colour (§1.4 Cream Laid #EDE3CE, "所有资源的统一底色"), which §10.5 has so far
asked you to eyeball: it measures the render's own paper, divides into the
target and applies that gain. Different style cores drift badly — the §9 UI
pieces measured #DEC5A3 against #FBF7E7 for the same chapter's objects, 48
levels of lightness and three times the warmth apart. Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import urllib.request
import uuid
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate as gen  # noqa: E402  (shared ComfyUI helpers)

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "post_cutout_template.json"
SEPIA_TEMPLATE = HERE / "sepia_alpha_template.json"
OUT_DIR = HERE / "out" / "game"
# (width, height); a 0 lets ImageScale take that side from the aspect ratio.
TIERS = {"full": (0, 660), "chip": (96, 96), "icon": (256, 256), "mark": (0, 256)}
# Prompt library §1.4: Cream Laid, the one paper colour every asset shares.
PAPER_TONE = "EDE3CE"
# The top slice of the luminance histogram that counts as "the paper", and the
# range a per-channel gain may move in. The clamp matters: a piece that is all
# wax or all ink has no paper to measure, and an unclamped gain would recolour
# the subject itself.
TONE_PERCENTILE = 0.90
TONE_GAIN_MIN = 0.75
TONE_GAIN_MAX = 1.35
# Below this luminance the brightest thing in the render is not paper, so
# there is nothing to balance against and the pass stands down.
TONE_MIN_PAPER_LUMA = 150.0
# How opaque a pixel must be to count as part of the drawing when trimming,
# and the blue-channel value that works out to, through the graph's
# alpha = clamp(2 x (1 - blue)): 24/255 of alpha is blue 243 of 255.
TRIM_ALPHA = 24
INK_BLUE_MAX = 243


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


def decode_png(path: Path) -> tuple[int, int, int, bytearray]:
    """Decode an 8-bit RGB or RGBA PNG to raw pixels, returning
    (width, height, channels, pixels). Stdlib only — this repo's toolchain has
    no Pillow. Enough for the ink scan below; not a general decoder."""
    d = path.read_bytes()
    width, height, depth, colour = struct.unpack(">IIBB", d[16:26])
    if depth != 8 or colour not in (2, 6):
        raise ValueError(f"{path.name}: expected 8-bit RGB or RGBA, got depth {depth} colour type {colour}")
    channels = 3 if colour == 2 else 4
    pos, idat = 8, b""
    while pos < len(d):
        length = struct.unpack(">I", d[pos:pos + 4])[0]
        if d[pos + 4:pos + 8] == b"IDAT":
            idat += d[pos + 8:pos + 8 + length]
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray()
    prev = bytearray(stride)
    i = 0
    for _ in range(height):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        for x in range(stride):  # undo the per-row PNG filter
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line
        prev = line
    return width, height, channels, out


def ink_bounds(path: Path) -> tuple[int, int, int, int]:
    """The drawing's own bounding box (x, y, w, h) in a [C-MAPMARK] render:
    the tightest rectangle holding every pixel the graph will make visible.
    The graph's alpha is clamp(2 x (1 - blue)), so a pixel clears TRIM_ALPHA
    exactly when its blue channel is at or below INK_BLUE_MAX — no need to
    render the cutout first to measure it. The whole frame when the render is
    blank, so a failed one still produces something to look at."""
    width, height, channels, px = decode_png(path)
    x0, y0, x1, y1 = width, height, -1, -1
    for y in range(height):
        row = px[y * width * channels:(y + 1) * width * channels]
        for x in range(width):
            if row[x * channels + 2] <= INK_BLUE_MAX:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    if x1 < 0:
        return 0, 0, width, height
    return x0, y0, x1 - x0 + 1, y1 - y0 + 1


def encode_png(path: Path, width: int, height: int, channels: int, px: bytes) -> None:
    """Write 8-bit RGB/RGBA with filter 0 on every row. The inverse of
    decode_png, and no more general than it needs to be."""
    stride = width * channels
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += px[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2 if channels == 3 else 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def paper_of(width: int, height: int, channels: int, px: bytes) -> tuple[int, int, int] | None:
    """The render's own paper colour: the mean of the brightest TONE_PERCENTILE
    of its visible pixels. The top slice, not the whole image, because a panel
    is mostly paper but a wax seal is mostly not — the brightest part of either
    is the sheet it was drawn on. None when nothing is visible."""
    lit = []
    for i in range(0, len(px), channels):
        if channels == 4 and px[i + 3] < 128:
            continue
        lit.append((0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2], i))
    if not lit:
        return None
    lit.sort()
    top = lit[int(len(lit) * TONE_PERCENTILE):] or lit[-1:]
    n = len(top)
    return (sum(px[i] for _, i in top) // n,
            sum(px[i + 1] for _, i in top) // n,
            sum(px[i + 2] for _, i in top) // n)


def tone_gain(source: Path, target_hex: str) -> tuple[list[float], str]:
    """The per-channel gain that puts `source`'s paper on `target_hex`.

    Measured on the SOURCE render, never on the finished asset: the cutout
    removes the paper, and what is left to measure is the subject — a wax
    seal came back claiming its paper was #775951 and the gain ran to the
    clamp trying to brighten the wax. The source always still has its sheet.
    Returns ([1,1,1], reason) when there is no paper worth balancing."""
    target = tuple(int(target_hex[i:i + 2], 16) for i in (0, 2, 4))
    width, height, channels, px = decode_png(source)
    paper = paper_of(width, height, channels, px)
    if paper is None:
        return [1.0, 1.0, 1.0], "nothing visible in the render"
    luma = 0.299 * paper[0] + 0.587 * paper[1] + 0.114 * paper[2]
    if luma < TONE_MIN_PAPER_LUMA:
        return [1.0, 1.0, 1.0], ("brightest tone #%02X%02X%02X is too dark to be paper"
                                 % paper)
    gain = [min(TONE_GAIN_MAX, max(TONE_GAIN_MIN, target[c] / max(paper[c], 1)))
            for c in range(3)]
    return gain, ("paper #%02X%02X%02X -> #%s  gain %.3f/%.3f/%.3f"
                  % (paper[0], paper[1], paper[2], target_hex, gain[0], gain[1], gain[2]))


def apply_gain(path: Path, gain: list[float]) -> None:
    """Multiply RGB in place, alpha untouched. A gain scales rather than
    shifts, so dark ink stays dark instead of being lifted toward grey."""
    if all(abs(g - 1.0) < 0.005 for g in gain):
        return
    width, height, channels, px = decode_png(path)
    out = bytearray(px)
    lut = [[min(255, int(v * gain[c] + 0.5)) for v in range(256)] for c in range(3)]
    for i in range(0, len(out), channels):
        out[i] = lut[0][out[i]]
        out[i + 1] = lut[1][out[i + 1]]
        out[i + 2] = lut[2][out[i + 2]]
    encode_png(path, width, height, channels, bytes(out))


def tier_of(path: Path, forced: str) -> str:
    if forced:
        return forced
    if "_c-full_" in path.name:
        return "full"
    if "_c-bust_" in path.name:
        return "chip"
    if "_c-mapmark_" in path.name or path.name.startswith("D-"):  # library §6.9 map symbols
        return "mark"
    if re.match(r"[IUW]-\d\d_", path.name):  # map icons, UI pieces, tactical symbols
        return "icon"
    raise ValueError(f"{path.name}: no _c-full_/_c-bust_/_c-mapmark_ tag in the name; pass --tier")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="generated PNGs")
    ap.add_argument("--tier", choices=TIERS, default="", help="force the output tier")
    ap.add_argument("--size", type=int, default=0,
                    help="override the tier's size (icons: the square; mark/full: the height, aspect kept)")
    ap.add_argument("--out-dir", default="", help="save here instead of out/game/<tier>/")
    ap.add_argument("--tone", nargs="?", const=PAPER_TONE, default="", metavar="RRGGBB",
                    help="white-balance the finished asset onto one paper colour "
                         "(default %s, the library's Cream Laid); off unless given" % PAPER_TONE)
    ap.add_argument("--no-trim", action="store_true",
                    help="mark tier: keep the render's empty margin instead of trimming to the drawing")
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--front", action="store_true",
                    help="queue the cut-outs at the FRONT of ComfyUI's queue, ahead of renders still waiting (2026-09-14)")
    args = ap.parse_args()
    tone = args.tone.lstrip("#").upper()
    if tone and len(tone) != 6:
        print(f"--tone wants six hex digits, got {args.tone!r}", file=sys.stderr)
        return 2
    templates = {name: json.loads(path.read_text(encoding="utf-8"))
                 for name, path in (("cutout", TEMPLATE), ("sepia", SEPIA_TEMPLATE))}
    jobs = []
    for f in args.files:
        path = Path(f)
        tier = tier_of(path, args.tier)
        entry_id = re.match(r"([A-Z]-\d\d)", path.name)
        stem = entry_id.group(1) if entry_id else path.stem
        # Keep A/B variants apart: model and style tags from the render's name.
        for tag in re.findall(r"_(klein|schnell|v1_antique|map_sepia|[a-z0-9]+_antique)_", path.name):
            stem += "_" + tag
        width, height = TIERS[tier]
        if args.size:
            # A tier with a 0 side sizes by the other one and keeps its aspect
            # (mark, full): --size must not square it off.
            width, height = (0, args.size) if width == 0 else (args.size, args.size)
        name = upload(path)
        values = {"image": name, "width": width, "height": height,
                  "prefix": f"flux/game/{tier}/{stem}"}
        if tier == "mark":
            if args.no_trim:
                w, h, _, _ = decode_png(path)
                box = (0, 0, w, h)
            else:
                box = ink_bounds(path)
            values.update({"crop_x": box[0], "crop_y": box[1],
                           "crop_w": box[2], "crop_h": box[3]})
            print(f"  trimmed to {box[2]}x{box[3]} at ({box[0]},{box[1]})")
        template = templates["sepia" if tier == "mark" else "cutout"]
        graph = gen.make_graph(template, values)
        payload = {"prompt": graph, "client_id": uuid.uuid4().hex}
        if args.front:
            payload["front"] = True
        res = gen._post("/prompt", payload)
        gain = [1.0, 1.0, 1.0]
        if tone:
            gain, why = tone_gain(path, tone)
            print(f"  {why}")
        jobs.append((res["prompt_id"], tier, stem, gain))
        print(f"queued {path.name} -> {tier} {res['prompt_id'][:8]}")
    failures = 0
    for prompt_id, tier, stem, gain in jobs:
        try:
            images = gen.wait_for(prompt_id, args.timeout)
        except (RuntimeError, TimeoutError) as e:
            print(f"FAILED {stem}: {e}", file=sys.stderr)
            failures += 1
            continue
        dest = (Path(args.out_dir) if args.out_dir else OUT_DIR / tier) / f"{stem}.png"
        gen.download(images[0], dest)
        apply_gain(dest, gain)
        shown = dest.relative_to(gen.ROOT) if dest.is_relative_to(gen.ROOT) else dest
        print(f"saved {shown}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
