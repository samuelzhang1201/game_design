# assets/imagegen — the 2D art pipeline (Z-Image and Qwen; no Flux)

Batch-renders the game's art on the local ComfyUI (`127.0.0.1:8188`) from the
prompt library `docs/references/art_prompt_library.md`. **No prompt is typed by
hand**: every one is `STYLE_CORE + subject + [C-…] canvas fragment`, assembled by
`generate.py` (library §0.1 / §10.8). Output goes to `out/`, which is
git-ignored; nothing reaches the game until an installer copies it into
`assets/`.

## Model

**Two local models make the game's 2D art, and no Flux model at all** (owner
2026-10-01: 我们不用flux模型 … 2D模型用Z_image 和Qwen跑本地模型); the klein /
schnell templates and presets were deleted that day, and the folder, once
`assets/flux/`, was renamed `assets/imagegen/` on 2026-10-11 (owner: 不要再有flux元素).

| `--model` | Model | Steps / CFG | Negative | Memory on MPS | For |
|---|---|---|---|---|---|
| `qwen2512desk4` (**default**) | Qwen-Image-2512 20B **on the Windows desktop**: `diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors` + `qwen_2.5_vl_7b_fp8_scaled.safetensors` + `qwen_image_vae.safetensors` + `loras/Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors` at strength 1 (`qwen2512_desktop_template.json`) | 4 / 1 | no effect at CFG 1 | not on the Mac | every Qwen job by default |
| `qwenedit_desk` (**default with `--images`**) | Qwen-Image-Edit-2511 20B on the desktop: `qwen_image_edit_2511_int8_convrot.safetensors` + the fp8 encoder above + `loras/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors` (`qwen_edit2511_desktop_template.json`) | 4 / 1 | no effect at CFG 1 | not on the Mac | every edit by default |
| `qwen2512desk` | the desktop graph with `loras/Wuli-Qwen-Image-2512-Turbo-LoRA-2steps-V1.0-bf16.safetensors` (Wuli-art, Apache 2.0) | 2 / 1 | no effect | not on the Mac | fastest; pulls towards photoreal and ignores "no …" more often |
| `qwen2512fast` (Mac fallback) | Qwen-Image-2512 20B, `qwen-image-2512-Q6_K.gguf` + `qwen_2.5_vl_7b.safetensors` + `qwen_image_vae.safetensors` + `loras/Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors` at strength 1 | 8 / 1 | no effect at CFG 1 | ~34 GB | characters, events, estate / army / courier paintings, icons, arms, table props, house references |
| `qwen2512` | the same without the LoRA | 50 / 4 | applied | ~33 GB | a full-quality re-render of a pick |
| `zimage` | Z-Image Turbo 6B, `z_image_turbo_bf16.safetensors` + `qwen_3_4b.safetensors` (type `lumina2`) + `vae/ae.safetensors` — **on the Windows desktop only** (below) | 8 / 1 | none (distilled) | not on the Mac | aerial ground (T-), tree crowns (TR-), unit references |
| `qwenedit_fast` (Mac fallback) | Qwen-Image-Edit-2511 20B, `qwen-image-edit-2511-Q6_K.gguf` + the Qwen encoder and VAE above + `loras/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors` at strength 1 | 8 / 1 | no effect at CFG 1 | ~34 GB | EDITING a picture (`--images`, below) |
| `qwenedit` | the same without the LoRA | 40 / 4 | applied | ~33 GB | a full-quality edit of a pick |

**Z-Image runs on the Windows desktop, never on the Mac** (owner 2026-10-12: 以后不要用这台mac使用Z_image模型，全部z_image模型处理请远程丢给windows的desktop). Its weights were removed from the Mac that day and `download_models.sh` no longer fetches them; `generate.py` sends every `--model zimage` run (and `--free --model zimage`) to the desktop's Comfy Desktop at `ZIMAGE_URL` (default `http://192.168.4.85:8188`), with no fallback to the Mac. **Qwen runs on the desktop by default too** (owner 2026-10-13, after a same-prompt same-seed bench: the desktop presets took 126 s for six pictures and an edit against the Mac's 991 s, at matching quality): `qwen2512desk4` / `qwen2512desk` / `qwenedit_desk` go to the same `ZIMAGE_URL`, and the Mac's GGUF presets (`qwen2512fast`, `qwen2512`, `qwenedit_fast`, `qwenedit`) are the fallback when the desktop is off. The desktop's CC Qwen UI workflows are their own fp8 / Lightning 4-step copies (never re-copy the Mac's GGUF ones over them). The tools that post their own graphs pick the machine per model the same way: `tools/map3d/gen_house_refs.py` and `tools/war_room/gen_room_refs.py` through `generate.use_model_server(model)` (default models `zimage` + `qwen2512desk4`, and `qwen2512desk4`), `tools/units3d/gen_*.py` through `gen_cavalry_v2.host_of(tier)` (tiers `zimage` and `qwendesk` on the desktop by default, `qwenfast` / `qwen` on the Mac at `COMFY_HOST` when asked for). Results come back over HTTP (`/view`), never from the Mac's output folder.

Since 2026-09-30 the game's art is re-rendered on Qwen-Image-2512 (after
comparing it with Z-Image on the 21 chapter events the owner picked Qwen, seed
954159497). A table's `seed` cell names the pick as `<model>_s<seed>`
(`event_art.csv`, `cast_art.csv`, `estate_paint_art.csv`,
`army_paint_art.csv`: `qwen2512fast_s954159497`, B-22 `_s954159498`). Art
rendered earlier on Flux.2 klein stays installed until it is re-rendered; the
icons are not re-rendered yet.

Qwen runs as **GGUF, never fp8**: on Apple MPS ComfyUI upcasts fp8 weights to
16-bit (`comfy/model_management.py` `supports_cast`), so the 20 GB fp8 file
would take ~41 GB. The GGUF loader is the ComfyUI-GGUF custom node
(`custom_nodes/ComfyUI-GGUF`; its Python deps `gguf` and `protobuf` are
installed by `download_models.sh`). Download with `bash
assets/imagegen/download_models.sh` (~47 GB, resumable), then restart ComfyUI.
**Editing** (owner 2026-10-10): the `qwenedit` presets change a picture
instead of drawing one from words. `--images a.png[,b.png[,c.png]]` (PNG; the
first is edited, the others are references, e.g. a costume or a material) and
`--instruction "…"` (what to change). With `--ids` the row's assembled prompt
follows the instruction and the row's canvas sets the size; without, the
output keeps the first picture's aspect at about one megapixel (or takes
`--canvas`) and lands in `out/edits/`. An edit's name is `<first picture>_<--tag or the instruction's first words>_<6-char hash of instruction + pictures>_<model>_s<seed>`, so edits never overwrite each other. Uses: a 3D structure view from the
picked design (a unit figure's front / side / back T-pose sheet and its separate gear: `tools/guide/unit_reference_sheets.md`) (instead of keeping the design by words), a character's bust
from its picked full figure, a local fix (a cloak's colour, a missing boot)
without losing the pick, and variants of one piece of art. Download with
`bash assets/imagegen/download_models.sh qwenedit` (~17 GB).

**Memory**: on the Mac's unified memory ComfyUI never unloads a model on its
own, and Z-Image (19 GB) plus Qwen-Image (31 GB) together exceed the 48 GB,
so a model switch costs one unload (`POST /free`): before queueing, a run
whose model differs from the jobs already in ComfyUI's queue waits for the
queue to drain, then unloads unless the last run left the same model loaded
(`out/.comfy_loaded`); each run also ends by unloading when the queue is
empty. Two runs on different models therefore follow each other instead of
swapping 50 GB every job. A script that calls `generate.py` many times on ONE
model passes `--keep-loaded` and ends with `generate.py --free`;
`gen_house_refs.py` and `gen_room_refs.py` do the same through
`switch_model` / `mark_loaded` / `free_models`.

**Not allowed:** every Flux model, Ideogram 4 open weights (non-commercial),
HunyuanImage (licence excludes EU/UK/KR), Qwen-Image-2.1 (research licence),
Krea 2 open weights and SD 3.5 (licences end at US$1M company revenue).

**The artist's kit** (owner 2026-10-01, the art collaboration): the locked
ComfyUI workflows she drags into her own ComfyUI are built from these same
files by `tools/art_kit/build_kit.py` into `docs/art_team/kit/comfyui/` —
see `docs/art_team/README.md`.

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
| `qwen_edit2511_template.json` | The edit graph (ComfyUI's `image_qwen_image_edit_2511` settings): up to three `LoadImage` slots, of which `generate.py` deletes the unused; an empty latent at the output size. |
| `zimage_turbo_template.json` / `qwen2512_template.json` | API-format graphs for the two models (above). Each declares the slots the script fills in `_slots`. Node settings follow ComfyUI's own `image_z_image_turbo` / `image_qwen_image_2512` templates; the Qwen graph adds a `lora_strength` slot. |
| `download_models.sh` | Fetches the two models into `~/ComfyUI-Shared/models` (resumable, size-checked) and installs the GGUF node's Python deps. Run on the Mac: the Hugging Face host is not reachable from the agent's sandbox. |
| `post.py` + `post_cutout_template.json` | Post-processing through ComfyUI: BiRefNet cut-out → alpha → lanczos resize. Tiers `full` (660 tall), `chip` (96²), `icon` (256²), `mark` (256 tall). Writes `out/game/<tier>/<ID>.png`. Needs `models/background_removal/birefnet.safetensors`. `--tone` white-balances to the paper colour `#EDE3CE` (measured on the source, applied to the result); `--no-trim` keeps empty margins. |
| `sepia_alpha_template.json` | The D- map-symbol cut-out as a ComfyUI graph (blue channel → ink coverage → alpha, cropped to the drawing). `install_map_art.py` does the same arithmetic locally. |
| `install_map_art.py` | Turns renders into game assets, one chapter per call (below). Mapping tables: `goods_art`, `decor_art`, `estate_art`, `estate_paint_art`, `army_paint_art`, `building_art`, `biome_art`, `ui_icon_art`, `cast_art`, `arms_art` `.csv` (pipeline tables, not runtime data). |
| `export_ui_workflows.py` + `CC *.workflow.json` | Export the API templates, filled with the current style text, as ComfyUI UI workflows into the local `user/default/workflows/` so they can be opened and tried by hand. |

## Usage

```bash
python3 assets/imagegen/generate.py --ids K-01,T-01 --dry-run        # print the assembled prompts
python3 assets/imagegen/generate.py --chapter C --limit 5            # the first five of a chapter
python3 assets/imagegen/generate.py --ids K-03 --canvas C-FULL --pose P-05        # full figure
python3 assets/imagegen/generate.py --ids K-03 --canvas C-BUST --expression E-08  # bust
python3 assets/imagegen/generate.py --prompts-file terrain_prompts_v2.csv --style-file STYLE_CORE_satellite_flat.txt
python3 assets/imagegen/generate.py --prompts-file arms_prompts.csv --style-file STYLE_CORE_arms_matte.txt --res 640
python3 assets/imagegen/post.py assets/imagegen/out/characters/K-03_*_c-full_*.png
python3 assets/imagegen/install_map_art.py cast
python3 assets/imagegen/generate.py --build-csv                      # after editing the library
```

- Seeds are `--seed` (default 954159497, the map's own) + the variant index, so a rerun reproduces; lock the seed when making expression variants.
- **Never pipe `generate.py`'s output** (`| head`, `| tail`): SIGPIPE kills it before it downloads, and `tail` also swallows the `FAILED` lines and the exit code. Redirect to a file and count: `python3 generate.py ... > run.log 2>&1; grep -c saved run.log`.
- After replacing a PNG under `assets/`, run `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --import`, or Godot keeps drawing the old `.ctex`.
- `E-` / `P-` rows are fragments (expression / pose), not assets; the script skips them.
- Characters use the library's `K-` entries (one per cast member, with a `**外貌**` looks line); `C-` entries are generic archetypes.

## Two machines (`split_batch.py`)

**Every batch runs on the Windows desktop; the Mac is the backup** (owner
2026-10-13: 默认全部用desktop跑，mac只做为backup生图机器，或者我明确要求使用mac跑).
`split_batch.py` therefore defaults to `--mac-share 0`: every id x seed gets both
Z-Image and Qwen (`qwen2512desk4`) on the desktop. Only when the owner asks for
the Mac does a batch split (the 2026-10-12 split was 20:80, `--mac-share 0.2`):
the Mac's share are Qwen jobs (`qwen2512fast`, Q6_K + Lightning 8 steps) spread
over the ids, run at the same time as the desktop's. `--dry-run` prints the
plan; a run writes `out/split/<tag>/` with `plan.json`, a log per machine,
`summary.md` (images and s/image per machine and preset) and `sheet.png` (one
row per id, each picture labelled model · machine · seed). `ZIMAGE_URL` is the
desktop's address; other flags pass through to generate.py. Edits are not split:
`generate.py --images` runs them on the desktop (`qwenedit_desk`).

## Install chapters (`install_map_art.py <chapter>`)

| Chapter | From → to |
|---|---|
| `goods` | G- → `assets/2D/goods/marks/` (greyscale, tinted by category) |
| `goods_icons` | colour G- → `assets/2D/icons/goods/` (64 px) |
| `decor` | D- ships and whale → `assets/decor/` |
| `estates` | D-43..D-78 → `assets/manors/<focus>_<size>.png` (greyed, lightened) |
| `events` | V-35..V-56 (by `event_art.csv`; V-56 planned, not yet rendered) → `assets/2D/events/illustrations/<event_id>.png` (1280×533, colour; cut INTO the scene, so a paper margin round a full-bleed render is trimmed off) |
| `paintings` | B-01..B-36 → `assets/2D/paintings/estates/` (720×576, colour) |
| `army_paintings` | B-37..B-42 → `assets/2D/paintings/armies/` |
| `buildings` | H- → `assets/2D/icons/buildings/bld_<code>.png` (128 px) |
| `ui` | I- → `assets/2D/icons/resources/<key>.png` (64 px, colour) |
| `compass` | I-73 → `assets/2D/ui/compass/compass.png` (256 px) |
| `cast` | K- → `assets/2D/portraits/cast/` (96 px chip) and `assets/2D/portraits/cast/full/` (1024 px tall) |
| `biomes` | satellite T- tiles → `assets/biomes/<key>.png` (1024 px, seamless) |
| `arms` | A- → `assets/2D/arms/<pack>/<key>.png` (256 px; `ARMS_PACK=<id>`, default the `data/world/maps.csv` default pack via `tools/packs.py`) |
| `app_icon` | X-01 → `icon.png` (1024 px, full bleed) |
| `title` | U-27 → `assets/2D/ui/panels/frame.png` (1792×1008, the render as it is) |

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
