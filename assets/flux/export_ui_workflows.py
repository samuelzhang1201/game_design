#!/usr/bin/env python3
"""Export the API-format templates as ComfyUI *UI* workflows (the sidebar's
Workflows panel), filled with the current STYLE_CORE / NEGATIVE and a sample
prompt, so what you open in ComfyUI matches what generate.py runs.

    python3 assets/flux/export_ui_workflows.py            # writes both copies
    python3 assets/flux/export_ui_workflows.py --no-install   # repo copy only

Writes assets/flux/<name>.workflow.json and, unless --no-install,
<ComfyUI>/user/default/workflows/<name>.json. Widget order per node class is
read from the running ComfyUI's /object_info, so the export follows whatever
node schema the install has. Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate as gen  # noqa: E402

HERE = Path(__file__).resolve().parent
COMFY_WORKFLOWS = Path.home() / "ComfyUI-Installs/GameDev/ComfyUI/user/default/workflows"
SAMPLE_ID = "I-04"

# name, template, preset / slot overrides, note
EXPORTS = [
    ("CC Flux Bulk T2I", "flux_template.json", {"model": "schnell"},
     "Flux.1 schnell (Apache 2.0). No negative-prompt path: node 6 zeroes the conditioning.\n"
     "schnell: 4 steps, guidance ignored. Bulk: python3 assets/flux/generate.py --model schnell ..."),
    ("CC Flux2 Klein Bulk T2I", "flux2_klein_template.json", {"model": "klein"},
     "Flux.2 [klein] 4B base (Apache 2.0, commercial OK). Undistilled: CFG works and the\n"
     "negative box carries NEGATIVE.txt. 20 steps, cfg 4.0. Never klein 9B (non-commercial).\n"
     "Bulk: python3 assets/flux/generate.py --model klein --ids C-01 --canvas C-FULL --pose P-05"),
    ("CC Post Cutout", "post_cutout_template.json", {"width": 0, "height": 660},
     "A generated portrait becomes a game asset: BiRefNet mask -> InvertMask -> RGBA ->\n"
     "lanczos resize (full: height 660; chip: 96x96). Driven by assets/flux/post.py."),
]


def object_info(class_type: str) -> dict:
    with urllib.request.urlopen(f"{gen.SERVER}/object_info/{class_type}", timeout=30) as r:
        return json.load(r)[class_type]


def sample_values(overrides: dict) -> dict:
    rows = {r["id"]: r for r in gen.load_rows()}
    canvas = json.loads((HERE / "canvas.json").read_text(encoding="utf-8"))
    style = " ".join(gen.STYLE_CORE.read_text(encoding="utf-8").split())
    negative = " ".join(gen.NEGATIVE.read_text(encoding="utf-8").split())
    preset = gen.MODEL_PRESETS[overrides.get("model", "klein")]
    values = {"unet": preset["unet"], "prompt": gen.assemble(rows[SAMPLE_ID], canvas, style),
              "negative": negative, "guidance": preset["guidance"], "cfg": preset["cfg"],
              "steps": preset["steps"], "width": 1024, "height": 1024, "seed": 954159497,
              "prefix": "flux/manual/test", "image": "example.png"}
    values.update({k: v for k, v in overrides.items() if k != "model"})
    return values


def to_ui(api: dict, note: str, title: str) -> dict:
    nodes_api = {k: v for k, v in api.items() if not k.startswith("_")}
    schemas = {v["class_type"]: object_info(v["class_type"]) for v in nodes_api.values()}
    # depth = longest chain of links feeding a node -> column
    depth: dict[str, int] = {}

    def depth_of(nid: str) -> int:
        if nid in depth:
            return depth[nid]
        d = 0
        for val in nodes_api[nid]["inputs"].values():
            if isinstance(val, list) and len(val) == 2 and str(val[0]) in nodes_api:
                d = max(d, depth_of(str(val[0])) + 1)
        depth[nid] = d
        return d

    for nid in nodes_api:
        depth_of(nid)
    columns: dict[int, list[str]] = {}
    for nid in sorted(nodes_api, key=int):
        columns.setdefault(depth[nid], []).append(nid)
    ui_nodes = []
    links = []
    link_ids: dict[tuple[str, int], list[int]] = {}
    pending_inputs: dict[str, list[dict]] = {}
    for nid, node in nodes_api.items():
        schema = schemas[node["class_type"]]
        spec = list(schema["input"].get("required", {}).items()) + list(schema["input"].get("optional", {}).items())
        widgets = []
        inputs = []
        for name, meta in spec:
            val = node["inputs"].get(name)
            kind = meta[0] if isinstance(meta, list) else meta
            if isinstance(val, list) and len(val) == 2 and str(val[0]) in nodes_api:
                inputs.append({"name": name, "type": kind if isinstance(kind, str) else "*", "link": None, "_from": (str(val[0]), int(val[1]))})
            elif isinstance(kind, str) and kind in ("MODEL", "CLIP", "VAE", "CONDITIONING", "LATENT", "IMAGE", "MASK",
                                                     "GUIDER", "SIGMAS", "SAMPLER", "NOISE", "BACKGROUND_REMOVAL"):
                continue  # a socket the template leaves unwired
            else:
                if val is None:  # optional input the template leaves out: the schema default
                    opts = meta[1] if isinstance(meta, list) and len(meta) > 1 and isinstance(meta[1], dict) else {}
                    if "default" in opts:
                        val = opts["default"]
                    elif isinstance(kind, list) and kind:  # a combo: its first option
                        val = kind[0]
                    else:
                        continue
                widgets.append(val)
                if name in ("seed", "noise_seed"):
                    widgets.append("fixed")
        if node["class_type"] == "LoadImage":
            widgets.append("image")  # the upload button's widget
        out_types = schema.get("output", [])
        out_names = schema.get("output_name", out_types)
        outputs = [{"name": out_names[i], "type": out_types[i], "links": []} for i in range(len(out_types))]
        col = depth[nid]
        row = columns[col].index(nid)
        ui_nodes.append({"id": int(nid), "type": node["class_type"],
                         "pos": [col * 420 - 260, row * 230 + 80], "size": [380, 120 + 40 * len(widgets)],
                         "flags": {}, "order": 0, "mode": 0, "inputs": inputs, "outputs": outputs,
                         "properties": {"Node name for S&R": node["class_type"]}, "widgets_values": widgets,
                         "title": node.get("_meta", {}).get("title", node["class_type"])})
        pending_inputs[nid] = inputs
    by_id = {n["id"]: n for n in ui_nodes}
    for nid, inputs in pending_inputs.items():
        for slot_index, inp in enumerate(inputs):
            src, src_slot = inp.pop("_from")
            lid = len(links) + 1
            links.append([lid, int(src), src_slot, int(nid), slot_index, inp["type"]])
            inp["link"] = lid
            by_id[int(src)]["outputs"][src_slot]["links"].append(lid)
    for i, n in enumerate(sorted(ui_nodes, key=lambda n: (depth[str(n["id"])], n["id"]))):
        n["order"] = i
    ui_nodes.append({"id": len(nodes_api) + 1, "type": "Note", "pos": [-260, 80 + 230 * len(columns.get(0, []))],
                     "size": [380, 200], "flags": {}, "order": len(ui_nodes), "mode": 0, "inputs": [], "outputs": [],
                     "properties": {"Node name for S&R": "Note"},
                     "widgets_values": [f"{title}\n{note}\nPrompt = STYLE_CORE.txt + subject + [C-...] canvas, never typed by hand."]})
    width = 420 * (max(depth.values()) + 1) + 60
    return {"id": str(uuid.uuid4()), "revision": 0, "last_node_id": len(ui_nodes), "last_link_id": len(links),
            "nodes": ui_nodes, "links": links,
            "groups": [{"title": f"{title} — filled by assets/flux/generate.py / post.py",
                        "bounding": [-280, 0, width, 230 * max(len(c) for c in columns.values()) + 320],
                        "color": "#3f789e", "font_size": 20}],
            "config": {}, "extra": {"ds": {"scale": 0.6, "offset": [300, 80]}}, "version": 0.4}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-install", action="store_true", help="do not copy into the ComfyUI workflows folder")
    args = ap.parse_args()
    for name, template_name, overrides, note in EXPORTS:
        template = json.loads((HERE / template_name).read_text(encoding="utf-8"))
        api = gen.make_graph(template, sample_values(overrides))
        api["_slots"] = template.get("_slots", {})
        ui = to_ui(api, note, name)
        text = json.dumps(ui, indent=1, ensure_ascii=False)
        (HERE / f"{name}.workflow.json").write_text(text, encoding="utf-8")
        print(f"wrote assets/flux/{name}.workflow.json ({len(ui['nodes'])} nodes)")
        if not args.no_install:
            COMFY_WORKFLOWS.mkdir(parents=True, exist_ok=True)
            (COMFY_WORKFLOWS / f"{name}.json").write_text(text, encoding="utf-8")
            print(f"installed {COMFY_WORKFLOWS / (name + '.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
