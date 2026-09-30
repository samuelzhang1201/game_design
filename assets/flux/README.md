# assets/flux — the Flux art pipeline

Batch-renders the game's art on the local ComfyUI (`127.0.0.1:8188`) from the
prompt library `docs/references/art_prompt_library.md`. **No prompt is typed by
hand**: every one is `STYLE_CORE + subject + [C-…] canvas fragment`, assembled by
`generate.py` (library §0.1 / §10.8). Output goes to `out/`, which is
git-ignored; nothing reaches the game until an installer copies it into
`assets/`.

## Model

**Since 2026-09-30 the game's art is re-rendered on Qwen-Image-2512**
(`--model qwen2512fast`, owner: klein is retired, and after comparing it with
Z-Image on the 21 chapter events the owner picked Qwen, seed 954159497, and
Qwen alone for the rest). A table's `seed` cell names the pick as
`<model>_s<seed>` (`event_art.csv`: `qwen2512fast_s954159497`). The title
screen's frame is `title_frame_prompts.csv` (U-27, canvas `C-TITLE`). The
klein notes below are history.

Until then only **Flux.2 [klein] 4B base** (`--model klein`, the default) makes game
assets: Apache 2.0, commercial use allowed, undistilled, 20 steps, CFG 4.0
(`--cfg`, library suggests 3.5–4.5), negative prompt applied. Files:
`diffusion_models/flux-2-klein-base-4b.safetensors`,
`text_encoders/qwen_3_4b.safetensors`, `vae/flux2-vae.safetensors`.
`--model schnell` (Flux.1 schnell, no negative path) is kept for comparison only.
**Never Flux.1 dev, Flux.2 dev or klein 9B** — non-commercial licences.

**Under evaluation (2026-09-24), not yet approved for game assets** — both
Apache 2.0; the full comparison is `claude/t2i-model-evaluation-2026-09.md` in
the Claude project. Download with `bash assets/flux/download_models.sh` (on the
Mac, ~47 GB, resumable), then restart ComfyUI.

| `--model` | Model | Steps / CFG | Negative | Memory on MPS | For |
|---|---|---|---|---|---|
| `zimage` | Z-Image Turbo 6B, `z_image_turbo_bf16.safetensors` (+ klein's `qwen_3_4b` as type `lumina2`, `vae/ae.safetensors`) | 8 / 1 | none (distilled) | ~20 GB | portraits |
| `qwen2512` | Qwen-Image-2512 20B, `qwen-image-2512-Q6_K.gguf` + `qwen_2.5_vl_7b.safetensors` + `qwen_image_vae.safetensors` | 50 / 4 | applied | ~33 GB | multi-figure event art |
| `qwen2512fast` | the same + `loras/Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors` at strength 1 | 8 / 1 | no effect | ~34 GB | drafts of the above |

Qwen runs as **GGUF, never fp8**: on Apple MPS ComfyUI upcasts fp8 weights to
16-bit (`comfy/model_management.py` `supports_cast`), so the 20 GB fp8 file
would take ~41 GB. The GGUF loader is the ComfyUI-GGUF custom node
(`custom_nodes/ComfyUI-GGUF`, installed 2026-09-24; its Python deps `gguf` and
`protobuf` are installed by `download_models.sh`). **Not listed on purpose:**
Ideogram 4 open weights (non-commercial), HunyuanImage (licence excludes
EU/UK/KR), Qwen-Image-2.1 (research licence), Krea 2 open weights and SD 3.5
(licences end at US$1M company revenue).

## Files

| File | Role |
|---|---|
| `generate.py` | The driver (stdlib only). Reads `prompts.csv` (or `--prompts-file`), fills a template, queues it, downloads the result. |
| `prompts.csv` | Parsed from the library (516 rows: `id, chapter, dir, title, canvas, width, height, subject, appearance`). Rebuild with `--build-csv` after editing the library; never edit by hand. |
| `canvas.json` | The `[C-…]` canvas fragments (library §1.3 plus later ones: `C-ESTATE`, `C-ARMS`, `C-TOWN`, `C-TOWNFLAT`, `C-TILEWIDE`, `C-APPICON`, …). |
| `STYLE_CORE.txt` / `NEGATIVE.txt` | Library appendix A / B: the v2 colour-pencil core for characters, event art, UI icons and the estate paintings. |
| `STYLE_CORE_<x>.txt` + `NEGATIVE_<x>.txt` | Other style cores; `--style-file` picks one and its negative pairs by name (`--negative-file` overrides). Present: `map_sepia` (greyscale D- map symbols; natural pieces — trees, hills, fields, marsh — need `--negative-file NEGATIVE_map_sepia_natural.txt` or churches creep in), `satellite_flat` (the biome ground tiles), `town_satblend` (the aerial settlements), `arms_matte` (house and kingdom arms, owner's pick 2026-09-15), `app_icon` (X-01), `ui_vellum` (the U- panel plate). The other experiments were deleted 2026-09-18. |
| `*_prompts.csv` | Entry sheets outside the library, used with `--prompts-file`: `arms_prompts.csv` (generated, below), `app_icon_prompts.csv`, `terrain_prompts_v2.csv` (satellite biome tiles), `town_prompts_sat.csv` (aerial S-02..S-06), `town_prompts_v3.csv` (S-07, the unwalled capital), `town_prompts.csv` (the earlier painted tiers). |
| `arms_prompts.py` | Writes `arms_prompts.csv` + `arms_art.csv` from the pack's Azgaar `coa` (see Arms). |
| `flux2_klein_template.json` / `flux_template.json` | API-format graphs for klein / schnell. Each declares the slots the script fills in `_slots`. |
| `zimage_turbo_template.json` / `qwen2512_template.json` | API-format graphs for the models under evaluation (above). Node settings follow ComfyUI's own `image_z_image_turbo` / `image_qwen_image_2512` templates; the Qwen graph adds a `lora_strength` slot. |
| `download_models.sh` | Fetches the evaluation models into `~/ComfyUI-Shared/models` (resumable, size-checked) and installs the GGUF node's Python deps. Run on the Mac: the Hugging Face host is not reachable from the agent's sandbox. |
| `post.py` + `post_cutout_template.json` | Post-processing through ComfyUI: BiRefNet cut-out → alpha → lanczos resize. Tiers `full` (660 tall), `chip` (96²), `icon` (256²), `mark` (256 tall). Writes `out/game/<tier>/<ID>.png`. Needs `models/background_removal/birefnet.safetensors`. `--tone` white-balances to the paper colour `#EDE3CE` (measured on the source, applied to the result); `--no-trim` keeps empty margins. |
| `sepia_alpha_template.json` | The D- map-symbol cut-out as a ComfyUI graph (blue channel → ink coverage → alpha, cropped to the drawing). `install_map_art.py` does the same arithmetic locally. |
| `install_map_art.py` | Turns renders into game assets, one chapter per call (below). Mapping tables: `goods_art`, `decor_art`, `estate_art`, `estate_paint_art`, `army_paint_art`, `building_art`, `biome_art`, `ui_icon_art`, `cast_art`, `arms_art` `.csv` (pipeline tables, not runtime data). |
| `export_ui_workflows.py` + `CC *.workflow.json` | Export the API templates, filled with the current style text, as ComfyUI UI workflows into the local `user/default/workflows/` so they can be opened and tried by hand. |

## Usage

```bash
python3 assets/flux/generate.py --ids K-01,T-01 --dry-run        # print the assembled prompts
python3 assets/flux/generate.py --chapter C --limit 5            # the first five of a chapter
python3 assets/flux/generate.py --ids K-03 --canvas C-FULL --pose P-05        # full figure
python3 assets/flux/generate.py --ids K-03 --canvas C-BUST --expression E-08  # bust
python3 assets/flux/generate.py --prompts-file terrain_prompts_v2.csv --style-file STYLE_CORE_satellite_flat.txt
python3 assets/flux/generate.py --prompts-file arms_prompts.csv --style-file STYLE_CORE_arms_matte.txt --res 640
python3 assets/flux/post.py assets/flux/out/characters/K-03_*_c-full_*.png
python3 assets/flux/install_map_art.py cast
python3 assets/flux/generate.py --build-csv                      # after editing the library
```

- Seeds are `--seed` (default 954159497, the map's own) + the variant index, so a rerun reproduces; lock the seed when making expression variants.
- **Never pipe `generate.py`'s output** (`| head`, `| tail`): SIGPIPE kills it before it downloads, and `tail` also swallows the `FAILED` lines and the exit code. Redirect to a file and count: `python3 generate.py ... > run.log 2>&1; grep -c saved run.log`.
- After replacing a PNG under `assets/`, run `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --import`, or Godot keeps drawing the old `.ctex`.
- `E-` / `P-` rows are fragments (expression / pose), not assets; the script skips them.
- Characters use the library's `K-` entries (one per cast member, with a `**外貌**` looks line); `C-` entries are generic archetypes.

## Install chapters (`install_map_art.py <chapter>`)

| Chapter | From → to |
|---|---|
| `goods` | G- → `assets/goods/` (greyscale, tinted by category) |
| `goods_icons` | colour G- → `assets/goods/colour/` (64 px) |
| `decor` | D- ships and whale → `assets/decor/` |
| `estates` | D-43..D-78 → `assets/manors/<focus>_<size>.png` (greyed, lightened) |
| `events` | V-35..V-55 → `assets/events/<event_id>.png` (1280×533, colour; cut INTO the scene, so a paper margin round a full-bleed render is trimmed off) |
| `paintings` | B-01..B-36 → `assets/manors/paint/` (720×576, colour) |
| `army_paintings` | B-37..B-42 → `assets/armies/paint/` |
| `buildings` | H- → `assets/icons/bld_<code>.png` (128 px) |
| `ui` | I- → `assets/icons/<key>.png` (64 px, colour) |
| `compass` | I-73 → `assets/ui/compass.png` (256 px) |
| `cast` | K- → `assets/portraits/` (96 px chip) and `assets/portraits/full/` (1024 px tall) |
| `biomes` | satellite T- tiles → `assets/biomes/<key>.png` (1024 px, seamless) |
| `arms` | A- → `assets/arms/<pack>/<key>.png` (256 px; `ARMS_PACK=<id>`, default the `data/maps.csv` default pack via `tools/packs.py`) |
| `app_icon` | X-01 → `icon.png` (1024 px, full bleed) |

Every file is sized by its USE (design px × the ~3x largest window scale), never one size for all.

## Arms

`arms_prompts.py [--pack ID]` (default: `tools/packs.py`'s default pack)
translates each kingdom's and each house seat's Azgaar `coa` into plain words —
tinctures, shield shape, division, ordinaries, charges with count and placement —
never Azgaar's charge SVGs (mostly WappenWiki, CC BY-NC-SA). A new map usually
needs no new arms: it borrows other packs' art (`tools/NEW_MAP.md`,
`tools/arms_report.gd`). `install_map_art.py arms` cuts each shield out locally
(flood from the edges, stopping at the rim); `ARMS_SEEDS` picks re-rolled seeds.

## Canvas sizes (library §10.7: generate at the 1024 class, scale down later)

| Canvas | Size |
|---|---|
| square canvases (C-PORTRAIT, C-BUST, C-ICON, C-TILE, C-MAPMARK, C-ARMS, C-TOWN, C-APPICON, …) | 1024×1024 |
| C-FULL | 1024×1536 |
| C-SCENE / C-MAP | 1536×1024 |
| C-ESTATE | 1280×1024 |

`--res N` samples at a smaller long side (the arms use 640).

## Checks

After a batch, go through library §10.5: one paper colour (`post.py --tone` can
do it), no hue outside the palette, pencil grain intact, no ink outlines, light
from the upper left. For D- marks: a pure white ground, one hue, no ground
plate or cast shadow, and readable at 32 px.
