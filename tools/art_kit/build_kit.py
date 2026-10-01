#!/usr/bin/env python3
"""Build the artist's kit into docs/art_team/kit/ (owner 2026-10-01: a
non-coding artist makes the game's art on her own machine; the style must be
LOCKED so it cannot drift).

    python3 tools/art_kit/build_kit.py

Writes:

* kit/comfyui/<名字>.json — one ComfyUI workflow per kind of asset, in API
  format (ComfyUI opens it when the file is dragged onto the canvas). The
  prompt is assembled INSIDE the graph from text boxes, exactly as
  assets/flux/generate.py assembles it: the style core and the canvas
  fragment are boxes titled 锁定, the subject is the one box she edits
  (② 主体（只改这里）), and two core StringConcatenate nodes join them; the
  model files, size, steps, CFG, sampler, LoRA and seed come from
  generate.py's own presets. Only Z-Image Turbo and Qwen-Image-2512 — no
  Flux (owner 2026-10-01).
* kit/comfyui_cloud/<名字>.json — the same workflows for Comfy Cloud, for
  when her own machine cannot run Qwen (owner 2026-10-01: 如果她的本地电脑
  无法跑的话，需要购买comfy cloud). Checked against the Cloud catalog that
  day: Z-Image Turbo, its text encoder and VAE are there under the same
  names, so those graphs are unchanged; Qwen-Image-2512 is there only as
  the full bf16 weights (the local Q6_K is quantized from them) and Cloud
  has no GGUF loader, so the Qwen graphs load qwen_image_2512_bf16 with the
  core UNETLoader. The 2512 Lightning 8-step LoRA is not in the public
  catalog: she imports it into her Cloud account once, under the same file
  name (Apache 2.0, huggingface.co/lightx2v/Qwen-Image-2512-Lightning).
* kit/blender/cc_art_check.zip — the Blender add-on (tools/art_kit/blender/),
  installed with Edit › Preferences › Add-ons › Install from Disk.

Rerun after changing a STYLE_CORE / NEGATIVE / canvas fragment, a template,
a preset, or specs.json (tools/art_kit/extract_specs.py). Stdlib only.
"""
from __future__ import annotations

import csv
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLUX = ROOT / "assets" / "flux"
OUT = ROOT / "docs" / "art_team" / "kit"
ADDON = ROOT / "tools" / "art_kit" / "blender" / "cc_art_check"
sys.path.insert(0, str(FLUX))
import generate as gen  # noqa: E402

LIBRARY_SEED = 954159497
HOUSE_SEED = 20260923      # tools/map3d/gen_house_refs.py SEED
UNIT_SEED = 20260928       # tools/units3d/gen_courier_designs.py SEED

# The house references, word for word around the subject
# (tools/map3d/gen_house_refs.py PROMPT / NEGATIVE, the owner's workflow).
HOUSE_PREFIX = "a single"
HOUSE_SUFFIX = ("isolated on a plain pure white background, centered, three-quarter front view, "
                "slightly elevated camera, game asset concept art, clean crisp silhouette, soft even "
                "studio lighting, no ground plane, no cast shadow, no people, no text")
HOUSE_NEGATIVE = ("landscape, terrain, grass, trees, sky, multiple buildings, village, map, top-down, "
                  "text, watermark, signature, cropped, out of frame, blurry, clutter, flags, banners, "
                  "cartoon, toy")
# The mounted references (tools/units3d/gen_courier_designs.py WRAP), and
# the same wording turned to a man on foot.
RIDER_SUFFIX = (". Three-quarter side view from eye level, the entire horse and rider fully inside the "
                "frame with a generous margin, all four hooves visible. Museum-quality historical "
                "reenactment with accurate replica medieval dress, realistic adult proportions and "
                "realistic horse anatomy, plain pure white seamless studio background, soft even studio "
                "light, sharp detail over the whole figure, clear readable silhouette, character concept "
                "reference for a 3D game model, no text")
FOOT_SUFFIX = (". Three-quarter front view from eye level, the whole figure fully inside the frame with a "
               "generous margin, both feet visible. Museum-quality historical reenactment with accurate "
               "replica medieval dress, realistic adult proportions, plain pure white seamless studio "
               "background, soft even studio light, sharp detail over the whole figure, clear readable "
               "silhouette, character concept reference for a 3D game model, no text")
UNIT_NEGATIVE = ("cartoon, anime, toy, miniature, figurine, chibi, big head, stylised, fantasy armour, "
                 "spikes, horns, modern clothing, crowd, landscape, grass, sky, text, watermark, "
                 "signature, cropped, blurry, extra fingers, fused fingers, malformed hands, extra legs")


def _text(path: Path) -> str:
    return " ".join(path.read_text(encoding="utf-8").split())


def _rows(name: str = "") -> dict:
    return {r["id"]: r for r in gen.load_rows(name)}


def library(key, title, model, style_file, canvas, row, note, size=None):
    """A workflow assembled the generate.py way: STYLE_CORE, subject, canvas."""
    style_path = FLUX / style_file
    canvases = json.loads((FLUX / "canvas.json").read_text(encoding="utf-8"))
    subject = row["appearance"] if canvas in ("C-FULL", "C-BUST") and row.get("appearance") else row["subject"]
    w, h = size or gen.CANVAS_SIZE[canvas]
    return {"key": key, "title": title, "model": model, "note": note,
            "parts": [("① 风格（锁定，不要改）", _text(style_path)),
                      ("② 主体（只改这里）", subject),
                      ("③ 画幅（锁定，不要改）", canvases[canvas])],
            "joins": [", ", ", "], "negative": _text(gen.negative_for(style_path)),
            "width": w, "height": h, "seed": LIBRARY_SEED, "sample": row["id"]}


def wrapped(key, title, model, prefix, subject, suffix, joins, negative, size, seed, note, sample):
    return {"key": key, "title": title, "model": model, "note": note,
            "parts": [("① 前缀（锁定，不要改）", prefix), ("② 主体（只改这里）", subject),
                      ("③ 后缀（锁定，不要改）", suffix)],
            "joins": joins, "negative": negative, "width": size[0], "height": size[1],
            "seed": seed, "sample": sample}


def kinds() -> list[dict]:
    lib = _rows()
    table = _rows("table_prop_prompts.csv")
    arms = _rows("arms_prompts.csv")
    terrain = _rows("terrain_aerial_prompts.csv")
    trees = _rows("tree_crown_prompts.csv")
    house = next(csv.DictReader((FLUX / "house_ref_prompts.csv").open(encoding="utf-8")))
    rider = next(csv.DictReader((FLUX / "cavalry_v2_prompts.csv").open(encoding="utf-8")))
    q, z = "qwen2512fast", "zimage"
    return [
        library("人物_半身", "人物 · 半身（K-）", q, "STYLE_CORE.txt", "C-BUST", lib["K-01"],
                "主体写外貌和衣着（需求卡的「外貌」行），不写道具。"),
        library("人物_全身", "人物 · 全身（K-）", q, "STYLE_CORE.txt", "C-FULL", lib["K-01"],
                "主体写外貌和衣着，可以加一个姿态片段（库里的 P-）。"),
        library("事件插图", "事件插图（V-）", q, "STYLE_CORE.txt", "C-EVENT", lib["V-35"],
                "最多三个清晰人物；每只手都要有交代；画里的纸要合上或背过去，写明看不见任何字。"),
        library("庄园与军队彩绘", "庄园与军队彩绘（B-01..B-42）", q, "STYLE_CORE.txt", "C-ESTATE", lib["B-01"],
                "一处庄园（或一支部队）的小景，四周淡入纸色。"),
        library("信使彩绘", "信使彩绘（B-43..B-47）", q, "STYLE_CORE.txt", "C-COURIER", lib["B-43"],
                "一个骑手在路上，四周淡入纸色。", size=(1280, 1024)),
        library("图标", "图标（I-、H-、G-）", q, "STYLE_CORE.txt", "C-ICON", lib["I-40"],
                "单个物件，没有背景。开发会抠图、缩到 64–128 px，所以剪影要一眼认得出。"),
        library("纹章", "纹章（A-）", q, "STYLE_CORE_arms_matte.txt", "C-ARMS", arms["A-001"],
                "主体按需求卡逐字填（颜色、盾形、分割、图案、数量、位置）。", size=(640, 640)),
        library("桌面道具", "桌面道具（U-）", q, "STYLE_CORE_table_prop.txt", "C-UIPIECE", table["U-60"],
                "放在战争桌上的实物，照片质感。"),
        library("航拍地面", "航拍地面（T-）", z, "STYLE_CORE_aerial_ground.txt", "C-TILE", terrain["T-51"],
                "从地图高度往下拍的地面；1–10 米的纹理要清晰。"),
        library("树冠", "树冠（TR-）", z, "STYLE_CORE_aerial_tree.txt", "C-ICON", trees["TR-01"],
                "白底上的一棵树，从正上方往下拍。"),
        wrapped("房屋参考图", "房屋参考图（Tripo 的输入）", q, HOUSE_PREFIX,
                "%s, one building only, %s" % (house["subject"], house["features"]), HOUSE_SUFFIX,
                [" ", ", "], HOUSE_NEGATIVE, (1024, 1024), HOUSE_SEED,
                "主体写：建筑名, one building only, 屋顶、墙、门窗等特征。屋顶写暖色陶瓦，不写茅草。",
                house["type"]),
        wrapped("兵种参考图_骑兵", "兵种参考图 · 骑兵（Tripo 的输入）", z, "Photograph of", rider["prompt"],
                RIDER_SUFFIX, [" ", ""], UNIT_NEGATIVE, (1344, 896), UNIT_SEED,
                "主体写骑手、马、甲、盾、武器。盾牌背在背上的图生成不出来：盾牌单独做。", "cavalry " + rider["id"]),
        wrapped("兵种参考图_步兵", "兵种参考图 · 步兵（Tripo 的输入）", z, "Photograph of",
                "a thirteenth-century man-at-arms on foot, a close steel helmet with a narrow eye slit, "
                "worn matte plate over mail, a knee-length green wool cloak, a green heater shield with a "
                "white pale on his left arm, a tall spear held upright in his right hand",
                FOOT_SUFFIX, [" ", ""], UNIT_NEGATIVE, (896, 1344), UNIT_SEED,
                "主体写人、甲、盾、武器。站姿，长矛竖直。", "infantry"),
    ]


def graph(k: dict) -> dict:
    """The model's template filled from generate.py's preset, its positive
    prompt re-wired to the locked text boxes."""
    preset = gen.MODEL_PRESETS[k["model"]]
    template = json.loads((FLUX / preset["template"]).read_text(encoding="utf-8"))
    g = gen.make_graph(template, {
        "unet": preset["unet"], "prompt": "", "negative": k["negative"], "cfg": preset["cfg"],
        "steps": preset["steps"], "lora_strength": preset.get("lora_strength", 0.0),
        "width": k["width"], "height": k["height"], "seed": k["seed"],
        "prefix": "CrownCouncil/编号_%s_s%%KSampler.seed%%" % k["model"]})
    (prompt_node, prompt_input), = template["_slots"]["prompt"]
    ids = [str(100 + i) for i in range(len(k["parts"]))]
    for nid, (title, text) in zip(ids, k["parts"]):
        g[nid] = {"class_type": "PrimitiveStringMultiline", "inputs": {"value": text},
                  "_meta": {"title": title}}
    joined = ids[0]
    for i, (nid, sep) in enumerate(zip(ids[1:], k["joins"])):
        cid = str(110 + i)
        g[cid] = {"class_type": "StringConcatenate",
                  "inputs": {"string_a": [joined, 0], "string_b": [nid, 0], "delimiter": sep},
                  "_meta": {"title": "拼接（不要动）"}}
        joined = cid
    g[prompt_node]["inputs"][prompt_input] = [joined, 0]
    g[prompt_node]["_meta"] = {"title": "正面提示词（由上面三格拼成）"}
    titles = {"KSampler": "采样（锁定；种子每次 +1）", "SaveImage": "④ 文件名（把「编号」改成需求卡编号）",
              "EmptySD3LatentImage": "尺寸（锁定）"}
    for node in g.values():
        if node["class_type"] in titles:
            node["_meta"] = {"title": titles[node["class_type"]]}
    if "negative" in template["_slots"]:
        (neg_node, _), = template["_slots"]["negative"]
        g[neg_node]["_meta"] = {"title": "负面词（锁定）"}
    return g


CLOUD_QWEN = "qwen_image_2512_bf16.safetensors"


def cloud(g: dict) -> dict:
    """The Comfy Cloud copy of a graph: the GGUF loader (not on Cloud)
    becomes the core UNETLoader on the bf16 weights; nothing else changes."""
    g = json.loads(json.dumps(g))
    for node in g.values():
        if node["class_type"] == "UnetLoaderGGUF":
            node["class_type"] = "UNETLoader"
            node["inputs"] = {"unet_name": CLOUD_QWEN, "weight_dtype": "default"}
            node["_meta"] = {"title": "Qwen-Image-2512 bf16（Comfy Cloud）"}
    return g


def main() -> int:
    comfy = OUT / "comfyui"
    clouds = OUT / "comfyui_cloud"
    for d in (comfy, clouds):
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.json"):
            old.unlink()
    index = []
    for k in kinds():
        g = graph(k)
        (comfy / (k["key"] + ".json")).write_text(json.dumps(g, ensure_ascii=False, indent=1) + "\n",
                                                  encoding="utf-8")
        (clouds / (k["key"] + ".json")).write_text(json.dumps(cloud(g), ensure_ascii=False, indent=1) + "\n",
                                                   encoding="utf-8")
        preset = gen.MODEL_PRESETS[k["model"]]
        index.append("| %s | %s | %d×%d | %d | %s | %s |" % (
            k["key"], "Qwen-Image-2512" if k["model"].startswith("qwen") else "Z-Image Turbo",
            k["width"], k["height"], k["seed"], k["sample"], k["note"]))
        print("wrote kit/comfyui/%s.json (%s, %d steps)" % (k["key"], k["model"], preset["steps"]))
    (comfy / "README.md").write_text(
        "# ComfyUI 锁定工作流\n\n由 `tools/art_kit/build_kit.py` 生成，不要手改：风格、画幅、负面词、"
        "模型、尺寸、步数、种子都来自 `assets/flux/` 的同一套文件。\n\n"
        "把 `.json` 拖进 ComfyUI 画布即可打开。只改「② 主体（只改这里）」和「④ 文件名」里的「编号」；"
        "第一次打开时把采样节点种子下面的 control after generate 设为 increment。\n\n"
        "| 工作流 | 模型 | 尺寸 | 起始种子 | 示例主体 | 说明 |\n| --- | --- | --- | --- | --- | --- |\n"
        + "\n".join(index) + "\n", encoding="utf-8")
    (clouds / "README.md").write_text(
        "# Comfy Cloud 版锁定工作流\n\n本地电脑跑不动 Qwen 时用这一套（owner 2026-10-01）。和 `../comfyui/` "
        "的同名工作流只差一处：Qwen 的模型换成 Comfy Cloud 上的原版全精度 `%s`（本地用的 Q6_K 就是从它量化来的；"
        "Cloud 没有 GGUF 加载器）。风格、画幅、负面词、尺寸、步数、种子都一样；Z-Image 的工作流完全相同。\n\n"
        "**第一次用之前**：Qwen 的 8 步加速 LoRA 不在 Comfy Cloud 的公共模型库里，要导入到自己的 Cloud 账户一次——"
        "从 Hugging Face 的 `lightx2v/Qwen-Image-2512-Lightning` 导入 `Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors`，"
        "文件名不要改（Apache 2.0，可商用）。导入不了就告诉开发。\n\n"
        "同一个种子在云端和本地出的图不会逐像素相同（量化不同），但风格一致；同一个资源的候选图请在同一边出完。\n"
        % CLOUD_QWEN, encoding="utf-8")
    blender = OUT / "blender"
    blender.mkdir(parents=True, exist_ok=True)
    zpath = blender / "cc_art_check.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(ADDON.iterdir()):
            if f.suffix in (".py", ".json", ".toml"):
                z.write(f, "cc_art_check/" + f.name)
    print("wrote", zpath.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
