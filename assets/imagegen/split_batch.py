#!/usr/bin/env python3
"""Run one art batch on the Windows desktop — and, when asked, part of it on the Mac
at the same time — then lay every result on one comparison sheet.

Owner 2026-10-13 (默认全部用desktop跑，mac只做为backup生图机器，或者我明确要求使用mac跑):
the default --mac-share is 0, every image on the desktop. A split (the 2026-10-12 ruling,
macbook 和 desktop 出图比例 20:80, 最后在一起比较分析) runs only when the owner asks
for the Mac: --mac-share 0.2.

    python3 assets/imagegen/split_batch.py --ids K-01,V-35 --variants 3 --dry-run   # the plan only
    python3 assets/imagegen/split_batch.py --ids K-01,V-35 --variants 3 --tag knight
    python3 assets/imagegen/split_batch.py --ids K-01 --variants 5 --mac-share 0.2   # owner asked for the Mac
    python3 assets/imagegen/split_batch.py --ids R-01 --variants 4 \
        --prompts-file unit_ref_prompts.csv --style-file STYLE_CORE_unit_ref.txt   # passed through

The batch is every id x variant (seed + i) x model family (Z-Image, Qwen-Image-2512),
so both models still run on every entry ([[art-image-pipeline]]). Z-Image never runs on
the Mac, so a Mac share is taken from the Qwen jobs, spread evenly over the ids and
seeds; the desktop draws every Z-Image job and the rest of the Qwen ones. The desktop
draws Qwen with --desk-qwen (qwen2512desk4, fp8 + Lightning 4 steps; qwen2512desk, the
Wuli 2-step build, drifts photoreal), the Mac with --mac-qwen (qwen2512fast, Q6_K +
Lightning 8 steps), so a split sheet also shows the two Qwen builds side by side. Both
machines run at the same time, each through generate.py (COMFYUI_URL points each call
at its machine); any other argument is passed through.

Output: generate.py's usual files under out/<chapter dir>/, plus out/split/<tag>/ with
plan.json, one log per machine, summary.md (images and seconds per machine and preset)
and sheet.png (one row per id, every picture labelled model · machine · seed).
Edits are not split: run them through generate.py --images, which defaults to
qwenedit_desk on the desktop (qwenedit_fast on the Mac when asked for).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
GENERATE = HERE / "generate.py"
OUT_DIR = HERE / "out"
MAC_URL = os.environ.get("MAC_COMFY_URL", "").rstrip("/")  # empty: generate.py finds the Mac's port
DESK_URL = os.environ.get("ZIMAGE_URL", "http://192.168.4.85:8188").rstrip("/")
FAMILY_LABEL = {"zimage": "Z-Image", "qwen": "Qwen"}
OWN_ARGS = ("--ids", "--variants", "--seed", "--model", "--chapter", "--images", "--instruction")


def plan_jobs(ids: list[str], variants: int, seed: int, mac_share: float,
              mac_qwen: str, desk_qwen: str, desk_zimage: str) -> list[dict]:
    """Every (id, seed, family) job with its machine and preset. The Mac takes
    round(share x total) Qwen jobs (at most all of them): the k-th goes to id
    k mod n at a seed spread evenly over the variants, so the Mac's pictures
    cover every id before any id gets a second one."""
    qwen = [(i, seed + v) for v in range(variants) for i in ids]
    total = 2 * len(qwen)
    mac_n = min(len(qwen), round(mac_share * total))
    mac_pick: set[tuple[str, int]] = set()
    for k in range(mac_n):
        mac_pick.add((ids[k % len(ids)], seed + (k * variants) // mac_n))
    for job in qwen:  # a high share can land two picks on one job; top up in order
        if len(mac_pick) >= mac_n:
            break
        mac_pick.add(job)
    jobs = [{"id": i, "seed": s, "family": "zimage", "machine": "desktop", "preset": desk_zimage}
            for i, s in qwen]
    for i, s in qwen:
        on_mac = (i, s) in mac_pick
        jobs.append({"id": i, "seed": s, "family": "qwen", "machine": "mac" if on_mac else "desktop",
                     "preset": mac_qwen if on_mac else desk_qwen})
    return jobs


def calls_for(jobs: list[dict], machine: str) -> list[dict]:
    """One generate.py call per (preset, seed) on `machine`, all its ids together;
    Z-Image first on the desktop, so each machine switches model at most once."""
    calls: dict[tuple[str, int], list[str]] = {}
    for j in jobs:
        if j["machine"] == machine:
            calls.setdefault((j["preset"], j["seed"]), []).append(j["id"])
    order = sorted(calls, key=lambda k: (not k[0].startswith("zimage"), k[0], k[1]))
    return [{"preset": p, "seed": s, "ids": calls[(p, s)]} for p, s in order]


def server_up(url: str) -> bool:
    import urllib.request
    try:
        with urllib.request.urlopen(url + "/system_stats", timeout=4):
            return True
    except OSError:
        return False


def run_machine(machine: str, calls: list[dict], passthrough: list[str], url: str,
                log: Path, results: dict) -> None:
    env = dict(os.environ)
    if url:
        env["COMFYUI_URL"] = url
    if machine == "desktop":
        env["ZIMAGE_URL"] = url
    saved: list[dict] = []
    t_start = time.time()
    with log.open("w", encoding="utf-8") as fh:
        for n, c in enumerate(calls):
            cmd = [sys.executable, str(GENERATE), "--ids", ",".join(c["ids"]), "--model", c["preset"],
                   "--seed", str(c["seed"]), "--variants", "1", "--timeout", "3600", *passthrough]
            if n < len(calls) - 1:
                cmd.append("--keep-loaded")
            fh.write(f"=== {' '.join(cmd[1:])}\n")
            fh.flush()
            t0 = time.time()
            proc = subprocess.run(cmd, env=env, cwd=HERE, capture_output=True, text=True)
            dt = time.time() - t0
            fh.write(proc.stdout + proc.stderr + f"=== exit {proc.returncode} in {dt:.0f}s\n")
            fh.flush()
            paths = re.findall(r"^saved (\S+)$", proc.stdout, re.M)
            for p in paths:
                saved.append({"path": p, "preset": c["preset"], "seed": c["seed"],
                              "seconds": dt / max(1, len(paths))})
            print(f"[{machine}] {c['preset']} s{c['seed']} {len(paths)}/{len(c['ids'])} images "
                  f"in {dt:.0f}s (exit {proc.returncode})", flush=True)
    results[machine] = {"saved": saved, "seconds": time.time() - t_start}


def id_of(path: str) -> str:
    return Path(path).name.split("_", 1)[0]


def build_sheet(entries: list[dict], dest: Path, height: int = 384) -> None:
    from PIL import Image, ImageDraw, ImageFont
    rows: dict[str, list[dict]] = {}
    for e in sorted(entries, key=lambda e: (e["id"], e["family"], e["machine"], e["seed"])):
        rows.setdefault(e["id"], []).append(e)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    label_h, pad, head_w = 50, 8, 90
    tiles: dict[str, list[tuple[Image.Image, str]]] = {}
    for rid, items in rows.items():
        for e in items:
            im = Image.open(ROOT / e["path"]).convert("RGB")
            w = round(im.width * height / im.height)
            text = f"{FAMILY_LABEL[e['family']]} · {e['machine']}\ns{e['seed']}"
            tiles.setdefault(rid, []).append((im.resize((w, height)), text))
    width = head_w + max(sum(t.width + pad for t, _ in ts) for ts in tiles.values()) + pad
    sheet = Image.new("RGB", (width, len(tiles) * (height + label_h + pad) + pad), (238, 234, 226))
    draw = ImageDraw.Draw(sheet)
    y = pad
    for rid, ts in tiles.items():
        draw.text((pad, y + height // 2), rid, fill=(30, 30, 30), font=font)
        x = head_w
        for im, text in ts:
            sheet.paste(im, (x, y))
            draw.text((x + 4, y + height + 4), text, fill=(30, 30, 30), font=font)
            x += im.width + pad
        y += height + label_h + pad
    sheet.save(dest)


def summary(plan: list[dict], results: dict, entries: list[dict]) -> str:
    lines = ["| machine | preset | planned | saved | s / image |", "|---|---|---|---|---|"]
    for machine in ("mac", "desktop"):
        for preset in sorted({j["preset"] for j in plan if j["machine"] == machine}):
            planned = sum(1 for j in plan if j["machine"] == machine and j["preset"] == preset)
            got = [s for s in results.get(machine, {}).get("saved", []) if s["preset"] == preset]
            per = sum(s["seconds"] for s in got) / len(got) if got else 0.0
            lines.append(f"| {machine} | {preset} | {planned} | {len(got)} | {per:.0f} |")
    n_mac = sum(1 for e in entries if e["machine"] == "mac")
    total = len(entries) or 1
    wall = {m: f"{r['seconds']:.0f}s" for m, r in results.items()}
    lines += ["", f"Actual split mac:desktop = {n_mac}:{len(entries) - n_mac} "
                  f"({100 * n_mac / total:.0f}% : {100 * (len(entries) - n_mac) / total:.0f}%); wall time {wall}"]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ids", required=True, help="comma-separated library ids")
    ap.add_argument("--variants", type=int, default=1, help="seeds per entry; variant i uses seed + i")
    ap.add_argument("--seed", type=int, default=954159497)
    ap.add_argument("--mac-share", type=float, default=0.0,
                    help="the Mac's share of the batch's images: 0 = all on the desktop (default); 0.2 when the owner asks for the Mac")
    ap.add_argument("--mac-qwen", default="qwen2512fast", help="the Mac's Qwen preset")
    ap.add_argument("--desk-qwen", default="qwen2512desk4", help="the desktop's Qwen preset")
    ap.add_argument("--desk-zimage", default="zimage", help="the desktop's Z-Image preset")
    ap.add_argument("--tag", default="", help="names out/split/<tag>/ (default: date and time)")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, queue nothing")
    args, passthrough = ap.parse_known_args()
    clash = [a for a in passthrough if a.split("=")[0] in OWN_ARGS]
    if clash:
        print(f"split_batch.py sets these itself: {clash}", file=sys.stderr)
        return 2

    sys.path.insert(0, str(HERE))
    from generate import MODEL_PRESETS  # noqa: E402 (probes the Mac's port; harmless)
    missing = [p for p in (args.mac_qwen, args.desk_qwen, args.desk_zimage) if p not in MODEL_PRESETS]
    if missing:
        print(f"generate.py has no preset {missing}",
              file=sys.stderr)
        return 2
    ids = [i.strip() for i in args.ids.split(",") if i.strip()]
    plan = plan_jobs(ids, args.variants, args.seed, args.mac_share,
                     args.mac_qwen, args.desk_qwen, args.desk_zimage)
    calls = {m: calls_for(plan, m) for m in ("mac", "desktop")}
    n_mac = sum(1 for j in plan if j["machine"] == "mac")
    print(f"{len(plan)} images: mac {n_mac}, desktop {len(plan) - n_mac} "
          f"(asked {args.mac_share:.0%} mac); desktop at {DESK_URL}")
    for m, cs in calls.items():
        for c in cs:
            print(f"  {m:8} {c['preset']:14} s{c['seed']}  {','.join(c['ids'])}")
    if args.dry_run:
        return 0
    up = {"mac": server_up(MAC_URL or "http://127.0.0.1:8188") or server_up("http://127.0.0.1:8189"),
          "desktop": server_up(DESK_URL)}
    down = [m for m, ok in up.items() if not ok and calls[m]]
    if down:
        print(f"ComfyUI not answering on: {down} — start it (desktop IP moved? set ZIMAGE_URL)", file=sys.stderr)
        return 1

    tag = args.tag or time.strftime("%Y%m%d_%H%M")
    run_dir = OUT_DIR / "split" / tag
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "plan.json").write_text(json.dumps(
        {"ids": ids, "variants": args.variants, "seed": args.seed, "mac_share": args.mac_share,
         "passthrough": passthrough, "jobs": plan}, indent=2), encoding="utf-8")
    results: dict = {}
    threads = [threading.Thread(target=run_machine, args=(m, calls[m], passthrough,
                                                          MAC_URL if m == "mac" else DESK_URL,
                                                          run_dir / f"{m}.log", results))
               for m in ("mac", "desktop") if calls[m]]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    family = {j["preset"]: j["family"] for j in plan}
    entries = [{"id": id_of(s["path"]), "path": s["path"], "seed": s["seed"], "machine": m,
                "family": family[s["preset"]], "preset": s["preset"]}
               for m, r in results.items() for s in r["saved"]]
    (run_dir / "summary.md").write_text(summary(plan, results, entries), encoding="utf-8")
    if entries:
        build_sheet(entries, run_dir / "sheet.png")
    print(f"\n{len(entries)}/{len(plan)} images; sheet {run_dir.relative_to(ROOT)}/sheet.png")
    print((run_dir / "summary.md").read_text(encoding="utf-8"))
    return 0 if len(entries) == len(plan) else 1


if __name__ == "__main__":
    sys.exit(main())
