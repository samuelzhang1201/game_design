# Courier Art (sub-project D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every art stand-in the courier and missive sub-projects left.
- a 3D courier rider and a separate 3D spy (a merchant), built from scratch
  in Blender from owner-picked Z-Image designs;
- five courier card paintings;
- the Missive board's seven art pieces `U-20`..`U-26`.

**Architecture:** Three code tasks can land first, because each keeps
today's look while its art is missing:
- the riders' GALLOP / IDLE playback;
- the card and desk paintings;
- the board's art slots.

The art tasks then fill the data tables (`courier_art.csv`,
`courier_paintings.csv`, `missive_art.csv`). They are gated on the owner's
picks and reviews:
- Z-Image designs, then structure views;
- the two Blender models;
- the paintings and board pieces, on Z-Image and Qwen side by side.

**Tech Stack:**
- Godot 4.7 with typed GDScript, tested with GUT (`./run_tests.sh`).
- Python 3, stdlib only, talking to the local ComfyUI at
  `http://127.0.0.1:8188`.
- Blender, through the Blender MCP; headless `blender -b` for the build
  scripts.
- Z-Image Turbo and Qwen-Image-2512 (fast tier). Both are Apache-2.0.
  Every batch runs on BOTH for the owner to compare; klein 4B is retired
  (owner 2026-09-28).

**Spec:** `docs/superpowers/specs/2026-09-28-courier-art-design.md`

## Global Constraints

- **Work in a worktree.** Branch `courier-art`, worktree
  `.claude/worktrees/courier-art` off `main`. Give it an untracked
  `assets/map3d` symlink to the main checkout's `assets/map3d` so the 3D map
  can load for shots. Never commit that symlink.
- **Design values live in `data/*.csv`, never hardcoded.** New balance rows
  are appended at the END of `data/balance.csv`.
- **Nothing under `scripts/map3d/` may reach the `Game` autoload**
  (`map3d_view.gd` is the one exception); a test scans for it.
- **Tests never use a literal `user://` path.** Use `tests/run_dir.gd`'s
  helper.
- **No AI 3D.** Hunyuan and any image-to-3D are banned (owner 2026-09-24).
  ComfyUI work ends at the image.
- **Only these weights, and always both:** Z-Image Turbo
  `z_image_turbo_bf16.safetensors` (preset `zimage`) and Qwen-Image-2512
  `qwen-image-2512-Q6_K.gguf` with the Lightning LoRA (preset
  `qwen2512fast` in `generate.py`, tier `qwenfast` in `gen_cavalry_v2.py`).
  Never FLUX.2 klein 4B (owner 2026-09-28). Every batch runs on both
  models and its contact sheet shows them side by side.
- **Announce every batch.** Before queuing ANY ComfyUI batch, tell the owner
  the image count and time, and wait for a yes. The owner cancels
  unrequested batches.
- **Blender hygiene.** Never touch the owner's working scene. Each new model
  goes in its own scene (`courier`, `spy`) and its own place (`kit.py
  _free_slot`).
- **The 3D unit contract** (`tools/units3d/README.md`):
  - the model faces +Y, with +Z up, standing on z = 0;
  - no base;
  - one material over one 2048 atlas;
  - 15,000–20,000 triangles per `.glb`;
  - `<name>.glb.import` keeps `meshes/force_disable_compression=true`, like
    the houses.
- **Paintings keep their colour.** They use the characters' v2 style
  (`STYLE_CORE.txt` + `NEGATIVE.txt`).
- **Commits.** Every commit ends with a blank line and
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **The suite.** `./run_tests.sh` runs green in the foreground before every
  code commit. Errors 0 in a worktree without the gdai plugin binaries.
- **No 3D snapshot with `--headless`.** It hangs.
  `tools/snapshot_screen.tscn` runs through the real window.

## Review Focus

1. **A rider whose model lacks a clip.** A stand-in `.glb` with only
   MARCH / GARRISON, or a model with no AnimationPlayer at all, must still
   draw and animate. It falls back GALLOP→MARCH and IDLE→GARRISON, and never
   errors. (Task 3 tests it.)
2. **A paused clock with a courier mid-ride.** He must hold still in IDLE
   and not keep galloping in place, and pressing play must return him to
   GALLOP. (Task 3 tests the choice function.)
3. **Weather exactly at the foul threshold.** At `mud` (700) the card shows
   the foul painting; at `rain` (850) it does not. A weather kind missing
   from `weather.csv` falls back to the kind's own painting. (Task 4 tests
   it.)
4. **A missive_art key installed with no margin.** A texture with an empty
   or zero `margin` must still draw, stretched with no nine-slice, not
   crash. A texture path that does not load keeps the flat fallback.
   (Task 5 tests it.)
5. **Art named but missing on disk.** Every texture any of the three tables
   names must exist. A test holds this, so a half-installed batch fails the
   suite instead of drawing holes. (Tasks 4 and 5 test it.)

---

### Task 1: Z-Image and Qwen design sheets for the courier and the spy

**Files:**
- Create: `tools/units3d/gen_courier_designs.py`
- Create: `assets/imagegen/courier_design_prompts.csv`

**Interfaces:**
- Consumes: `tools/units3d/gen_cavalry_v2.py`:
  - `TIERS["zimage"]` and `TIERS["qwenfast"]`;
  - `graph(template_file, values)`;
  - `run(g, timeout)`;
  - `call(path)`.
- Produces:
  - `assets/imagegen/out/courier_designs/<tier>_<id>_s<n>.png`, where `tier`
    is `zimage` or `qwenfast`;
  - the contact sheet `contact_sheet.png`, one row per tier;
  - the CSV's `picked` column: exactly one `C*` row and one `S*` row get
    `picked=<tier>_s<n>`. Task 2 reads it.

- [ ] **Step 1: Write the prompts CSV**

`assets/imagegen/courier_design_prompts.csv` (header, then six rows, exact):

```csv
id,name_zh,prompt,picked
C1,王家快马信使,"a royal post rider on a light chestnut riding horse at a canter, no armour, a short sleeveless tabard in deep blue with a small gold crown badge on the chest over a cream linen shirt, a brown leather dispatch case on a strap across the body, a small brass post horn at his hip, a soft felt cap, riding boots, a light riding saddle and simple bridle",
C2,长途驿骑,"a long-distance relay rider on a dark bay horse at a canter, a hooded grey-brown wool travelling cloak thrown back over the shoulders, a padded brown doublet, wrapped wool leggings and dusty riding boots, full leather saddlebags and a rolled blanket behind the saddle, a leather satchel of letters at his side, the horse and rider dusty from the road",
C3,轻甲护送信使,"a mounted army dispatch rider on a grey horse at a canter, a mail shirt under a short red surcoat, an open-faced steel kettle hat, a sword at his hip, a leather message tube slung on his back, riding boots and leather gloves, a plain military saddle",
C4,传令旗手,"a herald messenger on a white horse at a canter, no armour, a bright blue and gold quartered tabard, a short pole fixed to his saddle carrying a small swallow-tailed blue pennon with a gold crown, a leather dispatch case at his side, a soft hat with a feather, riding boots",
S1,行商·骑马,"a travelling merchant on a sturdy brown horse at a trot, a wide-brimmed felt hat, a plain green-brown wool coat with a leather belt and a purse, a heavy canvas pack tied behind the saddle and two bulging leather bags hanging at the horse's flanks, a walking staff tied along the saddle, riding boots, an ordinary unremarkable face",
S2,行商·驮马,"a travelling merchant riding a small shaggy dun pack pony at a trot, a wide-brimmed felt hat, a plain grey-brown wool coat and hood, bundles of cloth and a small wooden chest lashed on both sides of the pony, a tin pot hanging from the load, worn boots, an ordinary unremarkable face",
```

- [ ] **Step 2: Write the generator**

`tools/units3d/gen_courier_designs.py`:

```python
"""Courier and spy design sheets (owner 2026-09-28, spec
2026-09-28-courier-art §1): every row of assets/imagegen/courier_design_prompts.csv
on BOTH Z-Image Turbo and Qwen-Image-2512 fast (never klein, owner
2026-09-28), 2 seeds each, for the owner to compare and pick one courier (C*)
and one spy (S*). The pick goes in the CSV's `picked` column as <tier>_s<n>.

  python3 tools/units3d/gen_courier_designs.py            # both tiers, all rows, 2 seeds
  python3 tools/units3d/gen_courier_designs.py --tiers zimage --only C1,S2 --seeds 1
  python3 tools/units3d/gen_courier_designs.py --dry-run  # list the jobs, queue nothing

Output: assets/imagegen/out/courier_designs/<tier>_<id>_s<n>.png and contact_sheet.png.
Existing files are kept unless --force. Needs ComfyUI at COMFY_HOST.
"""
import csv, sys, urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as v2  # the Z-Image graph, call / run

ROOT = Path(__file__).resolve().parents[2]
ROWS = ROOT / "assets" / "imagegen" / "courier_design_prompts.csv"
OUT = ROOT / "assets" / "imagegen" / "out" / "courier_designs"
SEED = 20260928
TIERS = ["zimage", "qwenfast"]  # Z-Image Turbo first: its row is done in minutes
MINUTES = {"zimage": 0.5, "qwenfast": 2.0}
WRAP = ("Photograph of {p}. Three-quarter side view from eye level, the entire horse and "
        "rider fully inside the frame with a generous margin, all four hooves visible. "
        "Museum-quality historical reenactment with accurate replica medieval dress, "
        "realistic adult proportions and realistic horse anatomy, plain pure white seamless "
        "studio background, soft even studio light, sharp detail over the whole figure, clear "
        "readable silhouette, character concept reference for a 3D game model, no text")
NEGATIVE = ("cartoon, anime, toy, miniature, figurine, chibi, big head, stylised, fantasy "
            "costume, plate armour, great helm, lance, shield, spikes, horns, modern clothing, "
            "crowd, a second horse, a second rider, landscape, grass, sky, text, watermark, "
            "signature, cropped, cut off hooves, cut off head, blurry, extra fingers, fused "
            "fingers, malformed hands, extra legs, five legs")
NEGATIVE_ARMOURED = NEGATIVE.replace("plate armour, great helm, ", "")  # C3 wears mail and a kettle hat


def arg(name, default):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a else default


def jobs():
    only = set(filter(None, arg("--only", "").split(",")))
    seeds = int(arg("--seeds", "2"))
    tiers = arg("--tiers", ",".join(TIERS)).split(",")
    with open(ROWS, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if not only or r["id"] in only]
    return [(t, r, s) for t in tiers for r in rows for s in range(1, seeds + 1)]


def sheet(files):
    """One row per tier, the same design and seed in the same column."""
    from PIL import Image, ImageDraw
    cw, ch = 528, 352
    tiers = [t for t in TIERS if any(f.name.startswith(t + "_") for f in files)]
    cells = sorted({f.stem.split("_", 1)[1] for f in files})
    im = Image.new("RGB", (cw * len(cells), (ch + 28) * len(tiers)), "white")
    d = ImageDraw.Draw(im)
    for r, t in enumerate(tiers):
        for c, cell in enumerate(cells):
            f = OUT / f"{t}_{cell}.png"
            x, y = c * cw, r * (ch + 28)
            if f.exists():
                im.paste(Image.open(f).convert("RGB").resize((cw, ch)), (x, y + 28))
            d.text((x + 8, y + 6), f"{t} / {cell}", fill="black")
    im.save(OUT / "contact_sheet.png")
    print("->", OUT / "contact_sheet.png")


def main():
    todo = jobs()
    if "--dry-run" in sys.argv:
        for t, r, s in todo:
            print(f"{t}_{r['id']}_s{s}: {WRAP.format(p=r['prompt'])[:100]}...")
        mins = sum(MINUTES[t] for t, _, _ in todo)
        print(f"{len(todo)} image(s), about {int(mins) + 1} min on {', '.join(sorted({t for t, _, _ in todo}))}")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for t, r, s in todo:
        tpl, vals = v2.TIERS[t]
        dst = OUT / f"{t}_{r['id']}_s{s}.png"
        if dst.exists() and "--force" not in sys.argv:
            print("keep", dst.name); done.append(dst); continue
        v = dict(vals, prompt=WRAP.format(p=r["prompt"]),
                 negative=NEGATIVE_ARMOURED if r["id"] == "C3" else NEGATIVE,
                 seed=SEED + s - 1, prefix=f"courier_designs/{t}_{r['id']}_s{s}")
        img, dt = v2.run(v2.graph(tpl, v), 3600)
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                    "type": img.get("type", "output")})
        dst.write_bytes(v2.call("/view?" + q))
        print(f"{dst.name}  {dt:.0f}s", flush=True); done.append(dst)
    sheet(sorted(done))


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Dry-run it**

Run: `python3 tools/units3d/gen_courier_designs.py --dry-run`

Expected: 24 lines, `zimage_C1_s1` … `qwenfast_S2_s2`, then `24 image(s),
about 31 min on qwenfast, zimage`.

- [ ] **Step 4: Commit**

```bash
git add tools/units3d/gen_courier_designs.py assets/imagegen/courier_design_prompts.csv
git commit -m "tools(units3d): Z-Image design sheets for the courier and the spy"
```

- [ ] **Step 5: OWNER GATE — announce and run the batch**

1. Tell the owner: "24 images, 12 on Z-Image Turbo and 12 on Qwen fast,
   about 30 minutes. Start?"
2. On a yes, check ComfyUI is up (`curl -s http://127.0.0.1:8188/system_stats`).
3. Run `python3 tools/units3d/gen_courier_designs.py`.
4. Send the owner `assets/imagegen/out/courier_designs/contact_sheet.png`.

- [ ] **Step 6: OWNER GATE — record the picks**

The owner names one C image and one S image, from either model. Write
`<tier>_s<n>` into that row's `picked` cell (e.g. `C2,...,qwenfast_s1`), and
leave every other `picked` empty.

```bash
git add assets/imagegen/courier_design_prompts.csv
git commit -m "data(flux): the owner's courier and spy design picks"
```

---

### Task 2: Structure views of the two picked designs

**Files:**
- Create: `tools/units3d/gen_courier_sheet.py`
- Create: `assets/imagegen/courier_sheet_prompts.csv`

**Interfaces:**
- Consumes:
  - Task 1's picked rows (`picked` = `<tier>_s<n>`);
  - `tools/units3d/gen_cavalry_v2.py`: `TIERS["zimage"]`,
    `TIERS["qwenfast"]`, `graph`, `run`, `call`.
- Produces: `assets/imagegen/out/courier_sheet/<tier>_<who>_<view>.png`,
  where:
  - `tier` is `zimage` or `qwenfast`;
  - `who` is `courier` or `spy`;
  - `view` is one of `R1 R2 R3 M1 M2 M3 A1`.

  Tasks 6 and 8 model against them.

Both models are text-only here: no reference picture goes in (no
Qwen-Image-Edit is installed, and klein is retired). So each view repeats
the picked design's own words, and the contact sheet sets the two models
side by side per view.

- [ ] **Step 1: Write the views CSV** (`assets/imagegen/courier_sheet_prompts.csv`, exact)

```csv
view,parts,width,height,prompt
R1,rider,896,1344,"the rider alone standing on the ground with no horse, seen straight from the front, arms held a little out from the body, feet apart, the whole figure from hat to boots in frame"
R2,rider,896,1344,"the rider alone standing on the ground with no horse, seen exactly from the side, arms relaxed, the whole figure from hat to boots in frame"
R3,rider,896,1344,"the rider alone standing on the ground with no horse, seen straight from behind, arms held a little out from the body, the whole figure from hat to boots in frame"
M1,mount,1344,896,"the saddled horse alone with no rider, standing square, seen exactly from the side, the whole animal from ears to hooves and nose to tail in frame"
M2,mount,896,1344,"the saddled horse alone with no rider, standing square, seen straight from the front, the whole animal in frame"
M3,mount,1344,896,"the saddled horse alone with no rider, standing square, seen from directly above, the whole animal in frame"
A1,rider|mount,1344,896,"the rider seated on the horse, the horse standing square, seen exactly from the side, the whole piece in frame"
```

(The widths and heights are Z-Image's. The script scales them to Qwen's
own resolution class, ×1.18 rounded to a multiple of 16.)

- [ ] **Step 2: Write the generator**

`tools/units3d/gen_courier_sheet.py`:

```python
"""Structure views of the owner's picked courier and spy designs (spec
2026-09-28-courier-art §1): the rider alone front / side / back, the mount alone
side / front / above, and the mounted piece side, on BOTH Z-Image Turbo and
Qwen-Image-2512 fast (never klein, owner 2026-09-28). Text only: each view
repeats the picked design's own words. Modelling references for the Blender
build, not game art.

  python3 tools/units3d/gen_courier_sheet.py [--who courier|spy] [--tiers zimage] [--only R1,M1] [--force] [--dry-run]

Output: assets/imagegen/out/courier_sheet/<tier>_<who>_<view>.png and contact_sheet.png.
"""
import csv, sys, urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as v2  # TIERS, graph, run, call

ROOT = Path(__file__).resolve().parents[2]
DESIGNS = ROOT / "assets" / "imagegen" / "courier_design_prompts.csv"
VIEWS = ROOT / "assets" / "imagegen" / "courier_sheet_prompts.csv"
OUT = ROOT / "assets" / "imagegen" / "out" / "courier_sheet"
SEED = 20260928
TIERS = ["zimage", "qwenfast"]
MINUTES = {"zimage": 0.5, "qwenfast": 2.0}
QWEN_SCALE = 1.18  # Qwen-Image's native class is ~1584x1056 against Z-Image's 1344x896
TEXT = ("Photograph. {view}. {desc}. Technical reference for a 3D modeller, realistic "
        "replica medieval dress, realistic proportions, everything asked for fully inside "
        "the frame with a margin, plain pure white background, soft even studio light, no "
        "cast shadow, sharp focus, no text")
NEGATIVE = ("cartoon, anime, toy, miniature figurine, chibi, big head, stylised, fantasy "
            "costume, modern clothing, crowd, a second horse, a second rider, landscape, grass, "
            "sky, text, labels, watermark, signature, cropped, cut off hooves, cut off head, "
            "blurry, extra fingers, fused fingers, malformed hands, extra legs, five legs")


def arg(name, default):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a else default


def picked():
    """who -> the picked design row."""
    out = {}
    with open(DESIGNS, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["picked"].strip():
                out["courier" if r["id"].startswith("C") else "spy"] = r
    if set(out) != {"courier", "spy"}:
        sys.exit("pick one C* and one S* design first (courier_design_prompts.csv `picked`)")
    return out


def size_for(tier, w, h):
    if tier != "qwenfast":
        return w, h
    return int(round(w * QWEN_SCALE / 16)) * 16, int(round(h * QWEN_SCALE / 16)) * 16


def describe(row, parts):
    # a part drawn alone is not told about the other as a subject, or it draws it
    if parts == "rider":
        return "The person only, dressed exactly as in: " + row["prompt"]
    if parts == "mount":
        return "The horse and its saddle and tack only, exactly as in: " + row["prompt"]
    return row["prompt"]


def main():
    only = set(filter(None, arg("--only", "").split(",")))
    whos = [arg("--who", "")] if "--who" in sys.argv else ["courier", "spy"]
    tiers = arg("--tiers", ",".join(TIERS)).split(",")
    with open(VIEWS, newline="", encoding="utf-8") as f:
        views = [v for v in csv.DictReader(f) if not only or v["view"] in only]
    picks = picked()
    todo = [(t, w, v) for t in tiers for w in whos for v in views]
    if "--dry-run" in sys.argv:
        for t, w, v in todo:
            print(f"{t}_{w}_{v['view']}  {'x'.join(map(str, size_for(t, int(v['width']), int(v['height']))))}")
        print(f"{len(todo)} image(s), about {int(sum(MINUTES[t] for t, _, _ in todo)) + 1} min")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (t, w, v) in enumerate(todo):
        dst = OUT / f"{t}_{w}_{v['view']}.png"
        if dst.exists() and "--force" not in sys.argv:
            print("keep", dst.name); continue
        tpl, vals = v2.TIERS[t]
        width, height = size_for(t, int(v["width"]), int(v["height"]))
        text = TEXT.format(view=v["prompt"][0].upper() + v["prompt"][1:], desc=describe(picks[w], v["parts"]))
        g = v2.graph(tpl, dict(vals, prompt=text, negative=NEGATIVE, seed=SEED + views.index(v),
                               width=width, height=height, prefix=f"courier_sheet/{t}_{w}_{v['view']}"))
        img, dt = v2.run(g, 3600)
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                    "type": img.get("type", "output")})
        dst.write_bytes(v2.call("/view?" + q))
        print(f"{dst.name}  {dt:.0f}s", flush=True)
    sheet()


def sheet():
    """Per design: a row per tier, a column per view."""
    from PIL import Image, ImageDraw
    views = ["R1", "R2", "R3", "M1", "M2", "M3", "A1"]
    cw, ch = 360, 360
    rows = [(t, w) for w in ("courier", "spy") for t in TIERS]
    im = Image.new("RGB", (cw * len(views), (ch + 24) * len(rows)), "white")
    d = ImageDraw.Draw(im)
    for r, (t, w) in enumerate(rows):
        for c, v in enumerate(views):
            x, y = c * cw, r * (ch + 24)
            f = OUT / f"{t}_{w}_{v}.png"
            if f.exists():
                p = Image.open(f).convert("RGB"); p.thumbnail((cw, ch))
                im.paste(p, (x + (cw - p.width) // 2, y + 24))
            d.text((x + 8, y + 6), f"{t} / {w} / {v}", fill="black")
    im.save(OUT / "contact_sheet.png"); print("->", OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Dry-run it**

Run `python3 tools/units3d/gen_courier_sheet.py --dry-run` after Task 1's
picks are recorded.

Expected: 28 lines (2 tiers × 2 designs × 7 views), the qwenfast sizes at
~1.18×, and `28 image(s), about 36 min`.

- [ ] **Step 4: Commit**

```bash
git add tools/units3d/gen_courier_sheet.py assets/imagegen/courier_sheet_prompts.csv
git commit -m "tools(units3d): structure views of the picked courier and spy on Z-Image and Qwen"
```

- [ ] **Step 5: OWNER GATE — announce and run**

1. Tell the owner: "28 structure views, 14 on Z-Image and 14 on Qwen fast,
   about 35 minutes. Start?"
2. On a yes, run `python3 tools/units3d/gen_courier_sheet.py`.
3. Send the owner `contact_sheet.png`.
4. For each view, note which model held the design better. Tasks 6 and 8
   model from that one.
5. Re-roll a view that lost the design on BOTH models with `--only <view>
   --force` after changing `SEED` locally, and name the seed in Task 6's
   commit message.

---

### Task 3: The riders gallop and idle (code, works with today's stand-in)

**Files:**
- Modify: `scripts/map3d/map3d_units.gd`
- Modify: `scripts/map3d/map3d_layer_couriers.gd`
- Modify: `scripts/engine/data_repository.gd`: the `courier_art.csv` load
- Modify: `data/courier_art.csv`: add a `stride_m` column
- Modify: `data/balance.csv`
- Test: `tests/map3d/test_map3d_layer_couriers.gd`
- Test: `tests/map3d/test_map3d_units.gd`

**Interfaces:**
- Consumes:
  - `Map3DUnits.find_anim(node)`;
  - `Map3DUnits.clip_named(anim, action) -> String`;
  - `ctx.clock_speed() -> float`;
  - `repo.bal(key) -> float`.
- Produces:
  - `static func gait_rate(world_speed: float, k: float, clip_s: float, stride_m: float, lo: float, hi: float) -> float`
    on `Map3DUnits`. `march_rate` now calls it with the unit keys.
  - `static func clip_or_fallback(anim: AnimationPlayer, action: String) -> String`
    on `Map3DLayerCouriers`, with `const FALLBACK := {"GALLOP": "MARCH", "IDLE": "GARRISON"}`.
  - `static func action_for(moving: bool, clock_running: bool) -> String`
    on `Map3DLayerCouriers`: `"GALLOP"` or `"IDLE"`.
  - The `courier_art.csv` row gains `stride_m`: a float string, default
    `"0"`, meaning unknown.

- [ ] **Step 1: Write the failing tests**

Append to `tests/map3d/test_map3d_units.gd`:

```gdscript
func test_the_gait_rate_follows_the_ground_within_its_bounds() -> void:
	# 12 world m/s at scale 4 = 3 model m/s; a 1.2 s loop covering 2.4 model m wants 1.5x
	assert_almost_eq(Map3DUnits.gait_rate(12.0, 4.0, 1.2, 2.4, 0.5, 3.0), 1.5, 0.0001)
	assert_eq(Map3DUnits.gait_rate(120.0, 4.0, 1.2, 2.4, 0.5, 3.0), 3.0, "held at the top bound")
	assert_eq(Map3DUnits.gait_rate(0.1, 4.0, 1.2, 2.4, 0.5, 3.0), 0.5, "held at the bottom bound")
	assert_eq(Map3DUnits.gait_rate(12.0, 4.0, 1.2, 0.0, 0.5, 3.0), 1.0, "no stride known: normal speed")
```

Append to `tests/map3d/test_map3d_layer_couriers.gd`:

```gdscript
func _player(names: Array) -> AnimationPlayer:
	var p := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for n: String in names:
		var a := Animation.new()
		a.length = 1.0
		lib.add_animation(n, a)
	p.add_animation_library("", lib)
	autofree(p)
	return p


func test_a_moving_rider_gallops_and_a_paused_one_idles() -> void:
	assert_eq(Map3DLayerCouriers.action_for(true, true), "GALLOP")
	assert_eq(Map3DLayerCouriers.action_for(true, false), "IDLE", "a paused clock holds him still")
	assert_eq(Map3DLayerCouriers.action_for(false, true), "IDLE", "not yet set out")


func test_a_stand_in_without_the_couriers_clips_falls_back() -> void:
	var cav := _player(["cavalry|GARRISON", "cavalry|MARCH", "cavalry|ATTACK"])
	assert_eq(Map3DLayerCouriers.clip_or_fallback(cav, "GALLOP"), "cavalry|MARCH")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(cav, "IDLE"), "cavalry|GARRISON")
	var own := _player(["courier|GALLOP", "courier|IDLE"])
	assert_eq(Map3DLayerCouriers.clip_or_fallback(own, "GALLOP"), "courier|GALLOP")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(_player([]), "GALLOP"), "", "nothing to play: nothing played")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(null, "IDLE"), "", "no AnimationPlayer at all")


func test_the_courier_art_rows_carry_a_stride() -> void:
	var repo := DataRepository.load_all("res://data")
	for kind: String in repo.courier_art:
		assert_true((repo.courier_art[kind] as Dictionary).has("stride_m"), kind)
	assert_false(repo.balance.has("map3d_courier_anim_rate"), "the old fixed rate is gone")
	assert_gt(repo.bal("map3d_courier_anim_max"), repo.bal("map3d_courier_anim_min"))
```

(`repo.bal` asserts on a missing key, so absence is checked on
`repo.balance` itself.)

- [ ] **Step 2: Run them to see them fail**

Run:
```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_layer_couriers.gd -gpre_run_script=res://tests/pre_run.gd -gexit
```
Run the same command with `-gtest=res://tests/map3d/test_map3d_units.gd`.

Expected: FAIL (`gait_rate`, `action_for`, `clip_or_fallback` not found).

- [ ] **Step 3: Implement `gait_rate`**

In `scripts/map3d/map3d_units.gd`, replace `march_rate`'s body and add
`gait_rate` above it:

```gdscript
## A looped gait's playback rate so its feet keep pace with the ground: world
## speed over the piece's scale is the model's speed; a loop of `clip_s`
## seconds covers `stride_m` model metres. Held within [lo, hi] — a miniature
## crossing kilometres a day outruns any leg. 1.0 when the stride is unknown.
static func gait_rate(world_speed: float, k: float, clip_s: float, stride_m: float,
		lo: float, hi: float) -> float:
	if world_speed <= 0.0 or k <= 0.0 or stride_m <= 0.0:
		return 1.0
	return clampf(world_speed / k * clip_s / stride_m, lo, hi)


static func march_rate(repo: DataRepository, world_speed: float, k: float, clip_s: float,
		stride_m: float) -> float:
	return gait_rate(world_speed, k, clip_s, stride_m,
		repo.bal("map3d_unit_anim_min"), repo.bal("map3d_unit_anim_max"))
```

Note: `gait_rate(0.1, …)` must return the lower bound 0.5, and the guard
returns 1.0 only for `world_speed <= 0`. This is exactly what the test
asserts.

- [ ] **Step 4: Implement the courier layer's actions**

In `scripts/map3d/map3d_layer_couriers.gd`:
- replace `const MARCH := "MARCH"` with the constants and statics below;
- in `_piece_of`, keep the AnimationPlayer, its clip length and the stride
  in the piece dict instead of playing MARCH at a fixed rate;
- in `step`, set the pace and sync the action each frame.

```gdscript
const GALLOP := "GALLOP"
const IDLE := "IDLE"
## A stand-in model (the cavalry) has no courier clips: it rides its march and
## stands its garrison.
const FALLBACK := {"GALLOP": "MARCH", "IDLE": "GARRISON"}


## GALLOP while he rides and the clock runs; IDLE when paused or not yet set out.
static func action_for(moving: bool, clock_running: bool) -> String:
	return GALLOP if moving and clock_running else IDLE


## The clip for `action`, else its FALLBACK's, else "".
static func clip_or_fallback(anim: AnimationPlayer, action: String) -> String:
	if anim == null:
		return ""
	var name := Map3DUnits.clip_named(anim, action)
	if name == "" and FALLBACK.has(action):
		name = Map3DUnits.clip_named(anim, String(FALLBACK[action]))
	return name
```

In `_piece_of`, replace the block that plays MARCH with:

```gdscript
	var anims := Map3DUnits.find_anim(node)
	var gallop := clip_or_fallback(anims, GALLOP)
	var clip_s := anims.get_animation(gallop).length if anims != null and gallop != "" else 1.0
```

Then add to the `piece` dictionary: `"anim": anims, "clip_s": clip_s,
"stride_m": float(art.get("stride_m", "0")), "action": ""`.

Add the sync helper:

```gdscript
## Put his AnimationPlayer into `action`, blended; a pace for the gallop.
func _sync(piece: Dictionary, action: String, pace: float) -> void:
	var anim: AnimationPlayer = piece.get("anim")
	if anim == null:
		return
	var clip := clip_or_fallback(anim, action)
	if clip == "":
		return
	if String(piece["action"]) != action:
		anim.play(clip, ctx.repo.bal("map3d_unit_blend_s"))
		piece["action"] = action
	anim.speed_scale = pace if action == GALLOP else 1.0
```

In `step`, give each courier whose piece exists a pace and an action. Put
this inside the loop, after `xz` is computed, where `delta` is `step`'s
argument (rename `_delta` to `delta`):

```gdscript
		var moving := _shown_xz.has(id) and _shown_xz[id] != xz
		var prev: Vector2 = _shown_xz.get(id, xz)
		if _pieces.has(id):
			var piece: Dictionary = _pieces[id]
			var k := (piece["node"] as Node3D).transform.basis.get_scale().x
			var pace := Map3DUnits.gait_rate(prev.distance_to(xz) / maxf(delta, 0.001), k,
				float(piece["clip_s"]), float(piece["stride_m"]),
				ctx.repo.bal("map3d_courier_anim_min"), ctx.repo.bal("map3d_courier_anim_max"))
			_sync(piece, action_for(moving or not _waiting(c, xz), ctx.clock_speed() > 0.0), pace)
```

Keep the existing `_shown_xz` update and `dirty` logic after this block.
A courier who has set out counts as moving for the action even on a frame
where the share did not advance, so his gallop does not flicker between
frames; paused, `clock_speed()` is 0 and he idles. Update the class
comment's "galloping always" sentence to say he gallops while the clock
runs and idles while it is paused.

- [ ] **Step 5: Data**

`data/courier_art.csv`: add the column `stride_m` after `size`. Each row
gets `0` (the stand-in's stride is unknown, so the rate stays 1.0 × speed),
and `notes` stays.

`data/balance.csv`: delete the `map3d_courier_anim_rate` row and append:

```csv
map3d_courier_anim_min,0.8,"a courier's GALLOP playback rate floor (Map3DUnits.gait_rate): a slow road still reads as a gallop"
map3d_courier_anim_max,3,"a courier's GALLOP playback rate ceiling — past it the rider slides, as the regiments do past map3d_unit_anim_max"
```

`scripts/engine/data_repository.gd`: the `courier_art.csv` load keeps its
required columns `["kind", "model", "painting", "size"]`. `stride_m` is
read with `.get("stride_m", "0")` where it is used, so an older table still
loads. Nothing to change there unless the loader rejects unknown columns;
check it, and adapt only if it does.

`grep -rn "map3d_courier_anim_rate" scripts tests tools` must print nothing.

- [ ] **Step 6: Run the tests to see them pass**

Run the two test files as in Step 2. Expected: PASS.

- [ ] **Step 7: Full suite, then commit**

1. Run `./run_tests.sh` in the foreground. Expected: exit 0, no Failing.
2. Commit:

```bash
git add scripts/map3d/map3d_units.gd scripts/map3d/map3d_layer_couriers.gd data/courier_art.csv data/balance.csv tests/map3d/test_map3d_units.gd tests/map3d/test_map3d_layer_couriers.gd
git commit -m "feat(couriers): riders gallop while the clock runs and idle when it stops"
```

---

### Task 4: Card and desk paintings (code, draws as today until art lands)

**Files:**
- Create: `data/courier_paintings.csv`
- Modify: `scripts/engine/data_repository.gd`: load it as `courier_paintings: Dictionary` (key → texture)
- Modify: `scripts/engine/courier_card.gd`
- Modify: `scripts/ui/missive_screen.gd` and `scenes/missive_screen.tscn`: a painting at the desk's top
- Modify: `data/balance.csv`
- Modify: `docs/references/art_prompt_library.md`: the `[C-COURIER]` canvas row in §1.3
- Modify: `assets/imagegen/generate.py`: `CANVAS_SIZE["C-COURIER"]`
- Modify: `assets/imagegen/install_map_art.py`: `courier_paintings` chapter
- Create: `assets/imagegen/courier_paint_art.csv`
- Test: `tests/engine/test_courier_card.gd`
- Test: `tests/ui/test_missive_screen.gd`

**Interfaces:**
- Consumes:
  - `Weather.at(repo, state, px, abs_day) -> String` (a `weather.csv` kind);
  - `repo.weather_kinds[kind]` rows with `speed_permille` (`data/weather.csv`).
- Produces:
  - `static func painting_for(repo: DataRepository, kind: String, weather: String) -> String`
    on `CourierCard`;
  - `repo.courier_paintings["foul" | "delivered"] -> String` (texture path, `""` until installed);
  - `func desk_painting() -> TextureRect` on `MissiveScreen` (tests read it).

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_courier_card.gd`:

```gdscript
func test_the_card_wears_its_kinds_painting_or_the_foul_weather_one() -> void:
	repo.courier_art["ordinary"]["painting"] = "res://ordinary.png"
	repo.courier_paintings["foul"] = "res://foul.png"
	assert_eq(CourierCard.painting_for(repo, "ordinary", "clear"), "res://ordinary.png")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "rain"), "res://ordinary.png", "850 is above the line")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "mud"), "res://foul.png", "700 is at the line")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "blizzard"), "res://foul.png")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "no_such_weather"), "res://ordinary.png")
	repo.courier_paintings["foul"] = ""
	assert_eq(CourierCard.painting_for(repo, "ordinary", "blizzard"), "res://ordinary.png",
		"no foul art installed: the kind's own")


func test_every_courier_painting_named_exists() -> void:
	for kind: String in repo.courier_art:
		var p := String((repo.courier_art[kind] as Dictionary).get("painting", ""))
		assert_true(p == "" or ResourceLoader.exists(p) or FileAccess.file_exists(p), "%s: %s" % [kind, p])
	for key: String in repo.courier_paintings:
		var p := String(repo.courier_paintings[key])
		assert_true(p == "" or ResourceLoader.exists(p) or FileAccess.file_exists(p), "%s: %s" % [key, p])
```

Append to `tests/ui/test_missive_screen.gd` (it uses that file's own
`_root()` and `_enter()` helpers and `MissiveLog.subject`):

```gdscript
func test_a_receipt_on_the_desk_wears_the_delivered_painting() -> void:
	Game.start_campaign(42)
	var saved := String(Game.data.courier_paintings.get("delivered", ""))
	Game.data.courier_paintings["delivered"] = "res://icon.png"
	var subj := MissiveLog.subject("point", "", -1, Vector2(500, 300))
	var receipt := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("receipt", "credible", 3, subj, "Receipt", []))
	var monthly := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("monthly", "truth", 3, subj, "Steward's report", []))
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_frames(1)
	var ms := r.missive_screen()
	ms.select(receipt)
	assert_true(ms.desk_painting().visible, "a receipt shows the rider at the camp")
	ms.select(monthly)
	assert_false(ms.desk_painting().visible, "other letters show none")
	Game.data.courier_paintings["delivered"] = saved
```

- [ ] **Step 2: Run them to see them fail**

Run `test_courier_card.gd` and `test_missive_screen.gd` with the Task 3
Step 2 command. Expected: FAIL (`painting_for`, `courier_paintings`,
`desk_painting` missing).

- [ ] **Step 3: Data and loading**

`data/courier_paintings.csv`:

```csv
key,texture,notes
foul,,"spec 2026-09-28-courier-art §4: library B-46, a courier held up by foul weather — the card shows it when the weather where he is slows a rider to courier_paint_foul_permille or less"
delivered,,"library B-47, a courier delivering to a camp — heads a RECEIPT on the Missive board's reading desk (a courier vanishes on delivery, so his card never shows it)"
```

Append to `data/balance.csv`:

```csv
courier_paint_foul_permille,700,"the courier card shows the foul-weather painting when the weather where he is slows a rider to this share or less (weather.csv speed_permille: mud 700, snow 650, blizzard 400)"
```

`scripts/engine/data_repository.gd`, beside the `missive_art` load:

```gdscript
## data/courier_paintings.csv: a courier state's painting — foul, delivered ("" until installed).
var courier_paintings: Dictionary = {}
```

and in the loader, mirroring `missive_art`:

```gdscript
	if not _load_if_present(dir + "/courier_paintings.csv", ["key", "texture"],
			func(r): courier_paintings[String(r["key"])] = String(r["texture"])):
		return false
```

Copy the surrounding `missive_art` block's exact shape, including what it
returns on failure.

- [ ] **Step 4: `CourierCard.painting_for`**

In `scripts/engine/courier_card.gd`:

```gdscript
## The card's painting: the foul-weather one when the weather here slows a
## rider to courier_paint_foul_permille or less and that art is installed,
## else the kind's own (spec 2026-09-28-courier-art §4).
static func painting_for(repo: DataRepository, kind: String, weather: String) -> String:
	var own := String((repo.courier_art.get(kind, {}) as Dictionary).get("painting", ""))
	var foul := String(repo.courier_paintings.get("foul", ""))
	var row: Dictionary = repo.weather_kinds.get(weather, {})
	if foul != "" and not row.is_empty() \
			and int(row.get("speed_permille", 1000)) <= int(repo.bal("courier_paint_foul_permille")):
		return foul
	return own
```

In `card()`, replace the `"painting"` line with
`"painting": painting_for(repo, kind, wx),`.

- [ ] **Step 5: The desk painting**

In `scenes/missive_screen.tscn`, add a `TextureRect` named `DeskPainting`
as the FIRST child of `Frame/Col/Body/Desk/Letter`, with
`unique_name_in_owner = true`, `expand_mode = 1` (ignore size),
`stretch_mode = 6` (keep aspect covered), `custom_minimum_size =
Vector2(0, 150)` and `visible = false`. Prefer the gdai MCP tools to edit
the scene. If the editor is not running, edit the `.tscn` text and keep
its format.

In `scripts/ui/missive_screen.gd`'s `_fill_desk`, after the empty-letter
early return, set the painting:

```gdscript
	var art := String(Game.data.courier_paintings.get("delivered", "")) if String(m.get("kind", "")) == "receipt" else ""
	var tex: Texture2D = UiPalette.load_art(art) if art != "" else null
	%DeskPainting.texture = tex
	%DeskPainting.visible = tex != null
```

Hide it in the empty-letter branch as well (`%DeskPainting.visible =
false` before `return`), and add:

```gdscript
func desk_painting() -> TextureRect:
	return %DeskPainting
```

- [ ] **Step 6: The canvas, the table and the installer**

Library §1.3's canvas table: add the row below after `[C-ESTATE]`:

```markdown
| `[C-COURIER]` | 信使彩绘（`B-43`~`B-47`，2026-09-28） | `a painted vignette of one rider on the road seen from a gentle raised three-quarter view, the whole rider and mount inside the frame with a little road, ground and sky around them, the edges fading softly into plain cream paper, no text, no border, no frame, 5:4 horizontal` |
```

`assets/imagegen/generate.py`: add `"C-COURIER": (1280, 1024)` to
`CANVAS_SIZE`.

`assets/imagegen/courier_paint_art.csv`:

```csv
art_id,key,dest,seed,notes
B-43,ordinary,art,,the ordinary courier at the gallop (courier_art.csv painting)
B-44,secret,art,,the secret courier (courier_art.csv painting)
B-45,spy,art,,the spy as merchant (courier_art.csv painting)
B-46,foul,state,,a courier held up by foul weather (courier_paintings.csv)
B-47,delivered,state,,a courier delivering to a camp (courier_paintings.csv)
```

`assets/imagegen/install_map_art.py`: add to the docstring
`python3 assets/imagegen/install_map_art.py courier_paintings  # B-43..47 -> assets/couriers/paint/<key>.png (courier card, the desk's receipt)`
and:

```python
## The courier card's paintings and the desk's receipt painting (owner
## 2026-09-28, spec 2026-09-28-courier-art §4): library B-43..B-47 on the
## [C-COURIER] 5:4 vignette, drawn in the same 240-px column box as the manor
## and army paintings, so the same crop and size.
def install_courier_paintings(size: tuple = PAINT_SIZE) -> int:
    return install_paintings(size, "courier_paint_art.csv", ROOT / "assets" / "couriers" / "paint")
```

Picks now name a MODEL as well as a seed (owner 2026-09-28: every image on
Z-Image and Qwen), so add one helper above `install_paintings` and use it
there in place of its two-line seed filter:

```python
def _pick(hits: list, seed: str) -> list:
    """The renders a table's `seed` cell picks: `<model>_s<seed>` (the stem's
    own suffix) or a bare seed number as before; all of them when empty."""
    if not seed:
        return hits
    suffix = "_" + seed if "_" in seed else "_s" + seed
    return [h for h in hits if h.stem.endswith(suffix)] or hits
```

In `install_paintings`, replace
`if seed:\n    hits = [h for h in hits if h.stem.endswith("_s" + seed)] or hits`
with `hits = _pick(hits, seed)`.

Register `"courier_paintings": install_courier_paintings` in `main()`'s
`chapters`. It reads renders from `out/estates` (the B- chapter's dir), as
the army paintings do.

- [ ] **Step 7: Run the tests, the suite, commit**

1. Run the two test files. Expected: PASS.
2. Run `./run_tests.sh`. Expected: exit 0.
3. Run `python3 assets/imagegen/install_map_art.py courier_paintings`.
   Expected: five `(no render for B-4x / …)` lines and `0 asset(s)
   installed`.
4. Commit:

```bash
git add data/courier_paintings.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/courier_card.gd scripts/ui/missive_screen.gd scenes/missive_screen.tscn docs/references/art_prompt_library.md assets/imagegen/generate.py assets/imagegen/install_map_art.py assets/imagegen/courier_paint_art.csv tests/engine/test_courier_card.gd tests/ui/test_missive_screen.gd
git commit -m "feat(couriers): the card's painting by kind and weather, the receipt's on the desk"
```

---

### Task 5: The board's art slots and installer (code, flat fallback until art lands)

**Files:**
- Modify: `data/missive_art.csv`: add a `margin` column
- Modify: `scripts/engine/data_repository.gd`: keep `missive_art` as key → texture and add `missive_margin: Dictionary` (key → int)
- Create: `scripts/ui/missive_art.gd`: `class_name MissiveArt`, pure helpers turning a key into a StyleBox or a texture
- Modify: `scripts/ui/missive_screen.gd`
- Modify: `scripts/ui/missive_report_popup.gd`
- Modify: `assets/imagegen/install_map_art.py`: `missive` chapter
- Create: `assets/imagegen/missive_art_install.csv`: art id → key, size, cut-out flag
- Test: `tests/ui/test_missive_art.gd`

**Interfaces:**
- Consumes:
  - `UiPalette.load_art(path) -> Texture2D`;
  - `UiPalette.panel_style(border, width, margin, kind) -> StyleBox`;
  - `UiPalette.chip_style(bg, edge) -> StyleBoxFlat`.
- Produces:
  - `static func style(repo: DataRepository, key: String, fallback: StyleBox) -> StyleBox` on `MissiveArt`:
    - a `StyleBoxTexture` nine-sliced by `missive_margin[key]` when the key's
      texture loads;
    - `fallback` otherwise.
  - `static func texture(repo: DataRepository, key: String) -> Texture2D` on `MissiveArt` (null when none).

- [ ] **Step 1: Write the failing tests**

`tests/ui/test_missive_art.gd`:

```gdscript
extends GutTest
## The board's art slots (spec 2026-09-28-courier-art §5): an installed piece
## is drawn from its texture, nine-sliced by its margin; an uninstalled or
## unloadable one keeps the flat fallback.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")


func test_an_installed_piece_is_nine_sliced_by_its_margin() -> void:
	repo.missive_art["note"] = "res://icon.png"
	repo.missive_margin["note"] = 40
	var s := MissiveArt.style(repo, "note", StyleBoxFlat.new())
	assert_true(s is StyleBoxTexture)
	assert_eq((s as StyleBoxTexture).texture_margin_left, 40.0)
	assert_eq((s as StyleBoxTexture).texture_margin_bottom, 40.0)


func test_a_piece_with_no_margin_still_draws_stretched() -> void:
	repo.missive_art["board"] = "res://icon.png"
	repo.missive_margin["board"] = 0
	var s := MissiveArt.style(repo, "board", StyleBoxFlat.new())
	assert_true(s is StyleBoxTexture)
	assert_eq((s as StyleBoxTexture).texture_margin_left, 0.0)


func test_an_uninstalled_or_broken_piece_keeps_the_fallback() -> void:
	var flat := StyleBoxFlat.new()
	repo.missive_art["frame"] = ""
	assert_same(MissiveArt.style(repo, "frame", flat), flat)
	repo.missive_art["frame"] = "res://no/such/art.png"
	assert_same(MissiveArt.style(repo, "frame", flat), flat)
	assert_null(MissiveArt.texture(repo, "frame"))


func test_every_board_piece_named_exists() -> void:
	for key: String in repo.missive_art:
		var p := String(repo.missive_art[key])
		assert_true(p == "" or ResourceLoader.exists(p) or FileAccess.file_exists(p), "%s: %s" % [key, p])
	for key in ["frame", "board", "note", "letter", "envelope", "pin", "plaque"]:
		assert_true(repo.missive_art.has(key), key)
		assert_true(repo.missive_margin.has(key), key)
```

- [ ] **Step 2: Run to see it fail**

Run `test_missive_art.gd` with the Task 3 Step 2 command. Expected: FAIL.

- [ ] **Step 3: Data**

`data/missive_art.csv` gains `margin` (texture px of the nine-slice's
edge, from library §9.1's table) after `texture`:

```csv
key,texture,margin,notes
frame,,72,"spec §3: the board's wooden frame (nine-sliced); empty until the Flux art is installed — UiPalette's flat style stands in"
board,,0,the cork ground behind the columns (tiled)
note,,40,a pinned parchment slip
letter,,64,the reading desk's parchment
envelope,,0,the wax-sealed envelope that flies to the tab
pin,,0,the pin on a note
plaque,,48,a column header plaque
```

`data_repository.gd`: the `missive_art` load reads
`missive_margin[String(r["key"])] = int(String(r.get("margin", "0")) if String(r.get("margin", "")) != "" else "0")`
beside the texture. Declare `var missive_margin: Dictionary = {}` next to
`missive_art`.

- [ ] **Step 4: `MissiveArt`**

`scripts/ui/missive_art.gd`:

```gdscript
class_name MissiveArt
extends RefCounted
## The Missive board's art pieces (library U-20..U-26, spec
## 2026-09-28-courier-art §5): missive_art.csv names a texture and its
## nine-slice margin in texture px; a piece with no texture, or one that does
## not load, keeps the caller's flat fallback — never a hole.


static func texture(repo: DataRepository, key: String) -> Texture2D:
	var path := String(repo.missive_art.get(key, ""))
	return UiPalette.load_art(path) if path != "" else null


static func style(repo: DataRepository, key: String, fallback: StyleBox) -> StyleBox:
	var tex := texture(repo, key)
	if tex == null:
		return fallback
	var s := StyleBoxTexture.new()
	s.texture = tex
	var m := float(int(repo.missive_margin.get(key, 0)))
	s.texture_margin_left = m
	s.texture_margin_top = m
	s.texture_margin_right = m
	s.texture_margin_bottom = m
	if fallback != null:  # keep the fallback's content margins so text sits where it did
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			s.set_content_margin(side, fallback.get_content_margin(side))
	return s
```

Then run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path .
--import` once. Exit 134 is normal. Commit the new `.gd.uid` with the file.

- [ ] **Step 5: Wear the art on the board and the popup**

`scripts/ui/missive_screen.gd`:
- `_ready`: `%Frame`'s panel becomes
  `MissiveArt.style(Game.data, "frame", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16, "window"))`.
- `%Frame/Col/Body/Board`: this is an `HBoxContainer`, which has no panel.
  Wrap the four columns' background as follows:
  - add a `Panel` named `BoardGround` as the first child of `Body`'s
    `Board`'s parent, positioned under `Board` by making `Board` a child of
    a new `PanelContainer` named `BoardPanel` in the `.tscn`;
  - give `BoardPanel` the style `MissiveArt.style(Game.data, "board",
    StyleBoxEmpty.new())`;
  - if a texture is installed, set that style's
    `axis_stretch_horizontal`/`_vertical` to
    `StyleBoxTexture.AXIS_STRETCH_MODE_TILE`.
- `_note`: the `normal` style becomes `MissiveArt.style(Game.data, "note",
  style)`, where `style` is the existing chip style. A selected note keeps
  the flat lit style, so the selection still shows over parchment. When
  `MissiveArt.texture(Game.data, "pin")` is not null, add a `TextureRect`
  child to the note button:
  - the pin texture;
  - `mouse_filter = IGNORE`;
  - 14×14 design px;
  - anchored top-centre.
- `_ready`: each plaque `Label` gets
  `add_theme_stylebox_override("normal", MissiveArt.style(Game.data, "plaque", StyleBoxEmpty.new()))`.
- `%Desk`'s panel becomes `MissiveArt.style(Game.data, "letter",
  <its current style>)`. Read the current style from the `.tscn`, or use
  `UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 12, "column")` if it has
  none.

`scripts/ui/missive_report_popup.gd` `_ready`: `%Window`'s panel becomes
`MissiveArt.style(Game.data, "letter", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20, "window"))`.

`EnvelopeFlight` already reads `envelope`. Leave it.

Add to `test_missive_art.gd`:

```gdscript
func test_the_board_wears_an_installed_frame() -> void:
	var saved := String(Game.data.missive_art.get("frame", ""))
	Game.data.missive_art["frame"] = "res://icon.png"
	Game.data.missive_margin["frame"] = 8
	var screen: MissiveScreen = (load("res://scenes/missive_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	assert_true(screen.get_node("%Frame").get_theme_stylebox("panel") is StyleBoxTexture)
	Game.data.missive_art["frame"] = saved
```

- [ ] **Step 6: The installer**

`assets/imagegen/missive_art_install.csv` (sizes from library §9.1's table; `cut` = the piece stands on grey ground and is cut out to alpha):

```csv
art_id,key,width,height,cut,seed,notes
U-20,frame,512,512,0,,nine-slice margin 72
U-21,board,512,512,0,,seamless tile
U-22,note,512,256,0,,nine-slice margin 40
U-23,letter,512,768,0,,nine-slice margin 64
U-24,envelope,384,288,1,,cut out
U-25,pin,48,48,1,,cut out
U-26,plaque,576,144,0,,nine-slice margin 48
```

`assets/imagegen/install_map_art.py`:

```python
## The Missive board's pieces (owner 2026-09-28, spec 2026-09-28-courier-art
## §5): library U-20..U-26, each sized by its USE (library §9.1). The nine-slice
## pieces are cropped to the piece off its grey ground and resized; the
## envelope and the pin are cut out to alpha (the ground flooded from the edges,
## as the arms are) and fitted. Writes assets/missives/<key>.png and fills
## data/missive_art.csv's texture column.
def install_missive() -> int:
    rows = list(csv.DictReader((HERE / "missive_art_install.csv").open(encoding="utf-8")))
    dest = ROOT / "assets" / "missives"
    dest.mkdir(parents=True, exist_ok=True)
    installed = {}
    for r in rows:
        art_id, key, seed = r["art_id"], r["key"], r.get("seed", "").strip()
        hits = _pick(sorted((HERE / "out" / "ui").glob("%s_*.png" % art_id)), seed)
        if not hits:
            print("  (no render for %s / %s)" % (art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        tw, th = int(r["width"]), int(r["height"])
        if r["cut"] == "1":
            rgba = flood_ground(w, h, ch, px)
            cw, chh, cut = trim_alpha(w, h, rgba)
            side = max(cw, chh)
            sq = pad_square(cw, chh, cut, side)
            small = resize_rgba(side, side, sq, tw, th)
        else:
            rgba = to_rgba(w, h, ch, bytearray(px))
            box = scene_box(w, h, rgba, tw / th)
            cw, chh, piece = crop_rgba(w, rgba, box)
            small = resize_rgba(cw, chh, piece, tw, th)
        encode_png(dest / ("%s.png" % key), tw, th, 4, bytes(small))
        installed[key] = "res://assets/missives/%s.png" % key
        print("  %-6s %-9s %dx%d" % (art_id, key, tw, th))
    table = ROOT / "data" / "missive_art.csv"
    lines = list(csv.DictReader(table.open(encoding="utf-8")))
    for line in lines:
        if line["key"] in installed:
            line["texture"] = installed[line["key"]]
    with table.open("w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=list(lines[0].keys()))
        wr.writeheader(); wr.writerows(lines)
    return len(installed)
```

Register `"missive": install_missive` in `main()`, and add the docstring
line
`python3 assets/imagegen/install_map_art.py missive  # U-20..26 -> assets/missives/<key>.png (the Missive board)`.

Two checks against the existing code:
1. **Helper signatures.** `flood_ground`, `trim_alpha`, `pad_square`,
   `scene_box`, `crop_rgba`, `to_rgba` and `resize_rgba` exist above in the
   file. Check each signature and adapt the calls if a return shape
   differs.
2. **Output directory.** `out/ui` is the U- chapter's dir
   (`generate.py CHAPTER_DIR["U"]`). The paper tone is applied at
   generation by `post.py --tone` (Task 7).

Run `python3 assets/imagegen/install_map_art.py missive`. Expected: seven `(no
render …)` lines, `0 asset(s) installed`, and `data/missive_art.csv`
unchanged (`git diff --stat data/missive_art.csv` shows only Step 3's
edit).

- [ ] **Step 7: Tests, suite, a look, commit**

1. Run `test_missive_art.gd` and `test_missive_screen.gd`. Expected: PASS.
2. Run `./run_tests.sh`. Expected: exit 0.
3. With no art installed the board must look exactly as before. Shoot it
   through the real window:
   `/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen root --quiet --play-days 40 --missives credible --resolution 2560x1600 --out /private/tmp/claude-501/courier-art/board_fallback.png`.
   Compare it against the integration shot of 2026-09-28 and confirm there
   is no visible change.
4. Commit:

```bash
git add data/missive_art.csv scripts/engine/data_repository.gd scripts/ui/missive_art.gd scripts/ui/missive_art.gd.uid scripts/ui/missive_screen.gd scenes/missive_screen.tscn scripts/ui/missive_report_popup.gd assets/imagegen/install_map_art.py assets/imagegen/missive_art_install.csv tests/ui/test_missive_art.gd tests/ui/test_missive_art.gd.uid
git commit -m "feat(missives): the board wears its art pieces when installed, flat until then"
```

---

### Task 6: The courier model (Blender, from scratch)

**Files:**
- Create: `tools/units3d/courier_build.py`: rig, actions, atlas and export from a saved high/low `.blend`
- Create: `assets/units3d/ai_src/courier/courier.blend`: git-ignored, the modelling source
- Create: `assets/units3d/courier.glb` and `assets/units3d/courier.glb.import`, plus its atlas textures `assets/units3d/courier_*.jpg(.import)`
- Modify: `assets/units3d/units3d.json`
- Modify: `data/courier_art.csv`: `ordinary` and `secret` rows
- Modify: `tools/units3d/README.md`: a "Courier and spy" section
- Test: `tests/map3d/test_courier_models.gd`

**Interfaces:**
- Consumes:
  - the structure views `assets/imagegen/out/courier_sheet/courier_*.png` and
    the picked design image (Task 2);
  - the cavalry build's rig and bake helpers in
    `tools/units3d/cavalry_scan.py`: `build_rig`, `bake_into`, `reduce`,
    `atlas_images`, `atlas_material`, `rider_weights`, `save_blend`;
  - `tools/units3d/make_units.py`: `mounted_spec`, `build_armature`,
    `make_action`, `stash`, `gait`, `export`.
- Produces: `res://assets/units3d/courier.glb`, with ONE AnimationPlayer
  whose clips end in `GALLOP` and `IDLE`, and a `stride_m` value written
  into `courier_art.csv`.

- [ ] **Step 1: Set up the Blender scene**

1. Through the Blender MCP, call `get_addon_status` and `get_scene_info`.
2. Create a new scene `courier`, and never use the owner's active working
   scene.
3. Put the structure views in as reference images: R1, R2 and R3 as
   front / side / back empties at the rider's slot, and M1, M2 and M3 at
   the mount's. Place them by `tools/map3d/blender_houses/kit.py`'s
   `_free_slot` so nothing stacks on an earlier model.
4. Scale: the horse is 2.45 m nose to tail (the cavalry's). Horse and rider
   stand on z = 0 and face +Y.

- [ ] **Step 2: Block out, then OWNER GATE**

1. Block out the horse and the rider in simple forms against the three
   views of each:
   - the horse's barrel, neck, head and legs with correct joint positions;
   - the rider's torso, limbs, head and hat;
   - the design's big props: dispatch case, saddle, saddlebags and
     whatever the pick carries.
2. Match the SILHOUETTE in all three views.
3. Take viewport shots front, side, back and three-quarter
   (`get_viewport_screenshot`) and send them to the owner:
   "Courier block-out. Proportions and silhouette OK before I sculpt?"
4. Revise until the owner says yes.

- [ ] **Step 3: The high model, then OWNER GATE**

Model and sculpt the high model:
- the horse's anatomy: muscles, hooves, mane and tail as sculpted locks;
- the cloth with real folds at the joints and the hem;
- leather straps with their thickness, buckles, stitching lines;
- the design's badge or pennon.

Use multires or dyntopo sculpting and modifiers as needed. No surface that
ships may be a plain tube or loft. Paint base colour by region (vertex
paint or a texture) to the picked design's colours. Send the owner four
shots in Material Preview and revise until yes.

- [ ] **Step 4: Low model, bake, rig, actions: write `courier_build.py`**

`tools/units3d/courier_build.py` does the following, headless from the
saved `.blend`. Run it as
`blender -b assets/units3d/ai_src/courier/courier.blend --python tools/units3d/courier_build.py -- courier`.

1. Takes the collections `<code>_high_mount`, `<code>_high_rider` and
   `<code>_high_props` from the file.
2. Makes the low meshes with `reduce(high, name, tris, part)`, the mount at
   `MOUNT_TRIS` 9,000 and the rider plus props at `RIDER_TRIS` 8,000
   (total ≤ 20,000).
3. Unwraps into ONE atlas.
4. Bakes normal, AO and base colour from high to low with `bake_into`,
   2048 px.
5. Builds the one material with `atlas_material`.
6. Builds the armature with `mounted_spec` / `build_armature` and skins it
   the cavalry way (`rider_weights` for the rider, bone heat for the mount,
   verified with `unweighted_share` < 1%).
7. Authors two actions with `make_action`:
   - `GALLOP`, a 24-frame loop at 24 fps:
     - a four-beat transverse gallop: near hind, far hind, near fore, far
       fore, then the suspension phase;
     - the neck swings with the stride;
     - the rider rises in the stirrups, his torso pitched forward 15° and
       rocking against the horse's back;
     - loose props bounce one frame behind the saddle.
   - `IDLE`, a 72-frame loop:
     - the horse shifts its weight between the hind legs, swishes its tail
       and nods its head once;
     - the rider turns his head left and back.
8. Measures `stride_m`: the ground distance one GALLOP loop covers, i.e. how
   far the hind hoof's contact point moves back through one stance phase,
   times the number of beats per loop, in model metres. Prints it.
9. Exports `assets/units3d/courier.glb` with `export(...)` and appends
   `{tris, bones, clips, stride_m}` under `"courier"` in
   `assets/units3d/units3d.json`.

The script's constants go at the top with a comment each:
`MOUNT_TRIS`, `RIDER_TRIS`, `ATLAS_PX = 2048`, `GALLOP_FRAMES = 24`,
`IDLE_FRAMES = 72`, `FPS = 24`. Its docstring follows `cavalry_scan.py`'s
shape: what it builds, from what, and how to run it.

- [ ] **Step 5: Import settings and the models test**

After the first export, run `/Applications/Godot.app/Contents/MacOS/Godot
--headless --path . --import`. Then edit `assets/units3d/courier.glb.import`
to set `meshes/force_disable_compression=true` and re-import.

`tests/map3d/test_courier_models.gd`:

```gdscript
extends GutTest
## Every rider courier_art.csv names is a real model that gallops and idles
## (spec 2026-09-28-courier-art §2–3), within the game budget.


func test_every_courier_model_gallops_and_idles() -> void:
	var repo := DataRepository.load_all("res://data")
	for kind: String in repo.courier_art:
		var path := String((repo.courier_art[kind] as Dictionary)["model"])
		if path.ends_with("cavalry.glb"):
			continue  # a row still on the stand-in (the spy until Task 8)
		assert_true(ResourceLoader.exists(path), path)
		var node := (load(path) as PackedScene).instantiate()
		autofree(node)
		var anim := Map3DUnits.find_anim(node)
		assert_not_null(anim, path)
		assert_ne(Map3DUnits.clip_named(anim, "GALLOP"), "", path)
		assert_ne(Map3DUnits.clip_named(anim, "IDLE"), "", path)
		assert_gt(float((repo.courier_art[kind] as Dictionary).get("stride_m", "0")), 0.0, kind)


func test_the_courier_models_are_within_budget() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units3d/units3d.json"))
	for code in ["courier", "spy"]:
		if info.has(code):
			assert_between(int(info[code]["tris"]), 15000, 20000, code)
```

(`units3d.json` keys units at the top level: `cavalry`, `infantry`; the
build adds `courier` and `spy` beside them with a `tris` field.)

- [ ] **Step 6: Wire it and shoot it in the game, then OWNER GATE**

1. `data/courier_art.csv`:
   - `ordinary` and `secret` get `model` =
     `res://assets/units3d/courier.glb` and `stride_m` = the printed value;
   - `size` stays 0.7;
   - their `notes` lose `INTERIM` and read "the courier (owner's design
     <id>_s<n>, spec 2026-09-28-courier-art §2)".
2. Run the models test and `test_map3d_layer_couriers.gd`, then
   `./run_tests.sh`.
3. Shoot in the real window with a courier on the road (never
   `--headless`):
   - march a regiment through `--march3d fx,fy --march-confirm
     --march-commit`;
   - `--play-days 1 --speed 1`;
   - at `--zoom3d` 8000, 3000 and the rig's closest;
   - plus one shot with the clock paused (IDLE).
4. Send the four shots and a Blender turnaround of the `.glb` to the owner.
5. Revise until yes.

- [ ] **Step 7: Commit**

```bash
git add tools/units3d/courier_build.py tools/units3d/README.md assets/units3d/courier.glb assets/units3d/courier.glb.import assets/units3d/courier_*.jpg assets/units3d/courier_*.jpg.import assets/units3d/units3d.json data/courier_art.csv tests/map3d/test_courier_models.gd tests/map3d/test_courier_models.gd.uid
git commit -m "art(couriers): the courier rider, modelled from scratch — gallop and idle"
```

---

### Task 7: The paintings and the board art (Z-Image and Qwen batches, picks, install)

**Files:**
- Modify: `docs/references/art_prompt_library.md`: §6.11 rows `B-43`..`B-47`
- Modify: `assets/imagegen/courier_paint_art.csv` and `assets/imagegen/missive_art_install.csv`: the `seed` column
- Create: `assets/couriers/paint/*.png(.import)` and `assets/missives/*.png(.import)`
- Modify: `data/courier_art.csv`: the `painting` column
- Modify: `data/courier_paintings.csv` and `data/missive_art.csv`: the `texture` columns

**Interfaces:**
- Consumes: Task 4's `install_map_art.py courier_paintings`, Task 5's
  `install_map_art.py missive`, and the owner's design picks (Task 1). The
  paintings' dress follows them.
- Produces: installed textures that Tasks 4 and 5's code draws.

- [ ] **Step 1: Write the five painting prompts**

Add after `B-42` in art_prompt_library.md §6.11 a short note, then the
table:
- the note: > **信使彩绘**（owner 2026-09-28）: 信使卡顶部与看板回执的彩绘，v2 彩铅核，`[C-COURIER]` 画幅，装进 `assets/couriers/paint/<key>.png`.
- the table: `| ID | 主题 | Prompt 主体 |`, five rows.

Each subject describes the rider in the owner's PICKED design's own words
(copy the picked row's clothing and horse from
`courier_design_prompts.csv`). For B-45 use the picked S row:
- `B-43`: the courier galloping along a dirt road between fields, the
  dispatch case at his side.
- `B-44`: the same courier's dress under a plain dark hooded cloak riding
  at dusk on a quiet track, a sealed letter tucked inside the cloak.
- `B-45`: the merchant (picked S design) riding his mount along a road
  toward a walled town.
- `B-46`: the courier leading his horse on foot through driving snow and
  deep mud on a hillside road.
- `B-47`: the courier reining in at an army camp of tents and banners,
  handing a sealed letter to a soldier.

Close every subject with "shown as one painted scene in its own
countryside" as the army rows do. Then run `python3
assets/imagegen/generate.py --build-csv` and check that `python3
assets/imagegen/generate.py --ids B-43 --canvas C-COURIER --dry-run` prints
STYLE_CORE + the subject + the `[C-COURIER]` fragment.

- [ ] **Step 2: Check the board pieces' prompts**

Run `python3 assets/imagegen/generate.py --ids U-20,U-21,U-22,U-23,U-24,U-25,U-26 --dry-run`.

Confirm each prints with its canvas from library §9.1:
- `C-UIPIECE`: U-20, U-22, U-23;
- `C-TILE`: U-21;
- `C-ICON`: U-24, U-25;
- `C-UIWIDE`: U-26.

If the parser gives every U- row `C-UIPIECE`, generate those four with an
explicit `--canvas` per group in Step 3.

- [ ] **Step 3: OWNER GATE — announce and run both batches**

1. Tell the owner: "Courier paintings 5 × 2 seeds and board pieces 7 × 2
   seeds, each on Z-Image and on Qwen fast: 48 images, about 60 minutes.
   Start?"
2. On a yes, run every line once per model, Z-Image first (never klein):

```bash
for M in zimage qwen2512fast; do
  python3 assets/imagegen/generate.py --model $M --ids B-43,B-44,B-45,B-46,B-47 --canvas C-COURIER --variants 2
  python3 assets/imagegen/generate.py --model $M --ids U-20,U-22,U-23 --canvas C-UIPIECE --variants 2
  python3 assets/imagegen/generate.py --model $M --ids U-21 --canvas C-TILE --variants 2
  python3 assets/imagegen/generate.py --model $M --ids U-24,U-25 --canvas C-ICON --variants 2
  python3 assets/imagegen/generate.py --model $M --ids U-26 --canvas C-UIWIDE --variants 2
done
python3 assets/imagegen/post.py --tone assets/imagegen/out/ui/U-2*.png --out-dir assets/imagegen/out/ui
```

   The `zimage` preset has no negative path, so `NEGATIVE.txt` only steers
   Qwen. That is expected; compare as rendered.
3. Make a contact sheet per group with Pillow, one row per model and each
   entry's seeds side by side. Label each tile with its file stem, which
   ends `<model>_s<seed>`. Send both sheets to the owner.

- [ ] **Step 4: OWNER GATE — the picks, then install**

1. Write each pick into the `seed` column of `courier_paint_art.csv` and
   `missive_art_install.csv` as the render's stem suffix `<model>_s<seed>`
   (e.g. `qwen2512fast_s954159498`). Task 4's `_pick` matches it.
2. Run:

```bash
python3 assets/imagegen/install_map_art.py courier_paintings
python3 assets/imagegen/install_map_art.py missive
```

3. Then fill the texture paths by hand:
   - `data/courier_art.csv` `painting`:
     `res://assets/couriers/paint/ordinary.png` / `secret.png` / `spy.png`;
   - `data/courier_paintings.csv` `texture`: `foul.png` and `delivered.png`
     under `res://assets/couriers/paint/`.
   - `install_map_art.py missive` has already filled `missive_art.csv`.
4. Run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path .
   --import`.

- [ ] **Step 5: Look in the real window, then OWNER GATE**

Shoot at 2560x1600 and 1512x982, never headless:
- the courier card (click a courier: `--click3d` on him after
  `--march3d … --march-commit --play-days 1`);
- the board with letters (`--quiet --play-days 40 --missives credible`);
- a receipt on the desk;
- the spy report dialog (`--spy3d … --play-days 8 --shot-on report`).

Run the visual-review loop (`.claude/skills/visual-review/`): crop and
compare against the dark theme's panels, and use an independent critic
subagent. Fix what reads wrong: margins in `missive_art.csv`, the pin's
size, the desk painting's height.

Send the owner the shots and revise until yes. Record any new ruling in
`.claude/skills/visual-review/taste.md`.

- [ ] **Step 6: Suite and commit**

1. Run `./run_tests.sh`. Expected: exit 0. The every-texture-exists tests
   now check real files.
2. Commit:

```bash
git add docs/references/art_prompt_library.md assets/imagegen/prompts.csv assets/imagegen/courier_paint_art.csv assets/imagegen/missive_art_install.csv assets/couriers assets/missives data/courier_art.csv data/courier_paintings.csv data/missive_art.csv .claude/skills/visual-review/taste.md
git commit -m "art(missives): the courier paintings and the board's pieces"
```

---

### Task 8: The spy model (Blender, from scratch)

**Files:**
- Modify: `tools/units3d/courier_build.py`: it already takes the code as its argument; add the spy's constants if they differ
- Create: `assets/units3d/ai_src/courier/spy.blend`: git-ignored
- Create: `assets/units3d/spy.glb`, `spy.glb.import` and `spy_*.jpg(.import)`
- Modify: `assets/units3d/units3d.json` and `data/courier_art.csv`: the `spy` row

**Interfaces:**
- Consumes: Task 6's `courier_build.py` and the spy structure views
  `assets/imagegen/out/courier_sheet/spy_*.png`.
- Produces: `res://assets/units3d/spy.glb` with `GALLOP` and `IDLE`.

- [ ] **Step 1: Scene**

Create a new Blender scene `spy` with the spy's R/M views as references,
in a free slot (Task 6 Step 1's rules).

- [ ] **Step 2: Block out, then OWNER GATE**

Block out as Task 6 Step 2, for the picked S design:
- the mount's proportions: a pony is shorter-legged and stockier than the
  courier's horse; take them from M1–M3;
- the rider's coat and hat;
- the packs and bundles as the big forms.

Send shots and revise until yes.

- [ ] **Step 3: The high model, then OWNER GATE**

Sculpt as Task 6 Step 3:
- the packs' canvas folds and ropes;
- the wool coat;
- the pony's shaggy coat as sculpted tufts, not a noise texture.

Send shots and revise until yes.

- [ ] **Step 4: Build**

Save `spy.blend` with collections `spy_high_mount`, `spy_high_rider` and
`spy_high_props`. Run
`blender -b assets/units3d/ai_src/courier/spy.blend --python tools/units3d/courier_build.py -- spy`.

GALLOP for a pony carrying packs has a shorter stride and quicker beat.
Put per-code overrides in the script as a dict at the top:
`GAIT = {"courier": {"frames": 24, ...}, "spy": {"frames": 20, ...}}`. The
packs bounce with a one-frame lag. The script prints `stride_m`. Then set
`meshes/force_disable_compression=true` in `spy.glb.import` and re-import.

- [ ] **Step 5: Wire, test, shoot, then OWNER GATE**

1. In `data/courier_art.csv`, the `spy` row gets `model` =
   `res://assets/units3d/spy.glb`, its `stride_m`, and notes naming the
   design.
2. Run `test_courier_models.gd` (it now checks the spy too) and
   `./run_tests.sh`.
3. Shoot a spy riding: `--spy3d x,y --play-days 1` at three zooms, plus
   paused. Send to the owner and revise until yes.

- [ ] **Step 6: Commit**

```bash
git add tools/units3d/courier_build.py assets/units3d/spy.glb assets/units3d/spy.glb.import assets/units3d/spy_*.jpg assets/units3d/spy_*.jpg.import assets/units3d/units3d.json data/courier_art.csv
git commit -m "art(spies): the merchant spy, modelled from scratch — gallop and idle"
```

---

### Task 9: Record what D shipped

**Files:**
- Modify: `CLAUDE.md`: the "Couriers" and "Missives and spies" paragraphs
- Modify: `docs/superpowers/specs/2026-09-27-courier-core-design.md`: the sub-project table's D row reads "done 2026-09-XX"

- [ ] **Step 1: CLAUDE.md**

In the Couriers paragraph:
- replace "(the cavalry .glb as an INTERIM stand-in until D)" with the
  courier's own model, and say how it was built: from scratch in Blender
  from the owner's Z-Image design, `courier_build.py`, GALLOP / IDLE at
  `gait_rate` within `map3d_courier_anim_min` / `_max`;
- add that the card's painting follows kind and weather
  (`courier_paint_foul_permille`, `courier_paintings.csv`).

In the Missives paragraph:
- replace "flat stand-ins until installed (`missive_art.csv`)" with the
  installed pieces;
- name `MissiveArt`, the `margin` column and `install_map_art.py missive`;
- add that the receipt on the desk wears the delivered painting.

Keep each addition to one or two sentences in the file's own style.

- [ ] **Step 2: Suite and commit**

1. Run `./run_tests.sh`. Expected: exit 0.
2. Commit:

```bash
git add CLAUDE.md docs/superpowers/specs/2026-09-27-courier-core-design.md
git commit -m "docs: sub-project D — the couriers' and the board's art"
```
