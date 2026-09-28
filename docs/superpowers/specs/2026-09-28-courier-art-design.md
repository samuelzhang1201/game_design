# Courier art (sub-project D of the missive system)

Owner 2026-09-28. The missive system is four sub-projects (spec
`2026-09-27-courier-core-design.md`): A the courier core and B the missive
board and spies are merged; C interception waits for enemy AI; **D is this
spec**. D replaces every stand-in the first two left behind:

- **3D riders.** On the map a courier and a spy both ride the cavalry
  `.glb` today (`data/courier_art.csv`: INTERIM).
- **Card paintings.** `CourierCard` has a painting slot that is empty.
- **Board art.** The Missive board draws flat colours where library
  `U-20`..`U-26` should be (`data/missive_art.csv`: only `envelope` is read).

## Owner rulings (2026-09-28)

- **Scope.** D covers all four pieces:
  - the courier card's paintings;
  - a 3D courier rider;
  - a SEPARATE 3D spy;
  - the board art `U-20`..`U-26`.
- **Designs come first, as 2D.** The 3D models start from Z-Image designs
  rendered in several versions. The owner picks one before any modelling.
- **Courier design directions.** Four, each at 2 seeds:
  - a royal post rider;
  - a long-distance relay rider;
  - a lightly armoured escort courier;
  - a herald with a pennon.
- **The spy's disguise is a travelling MERCHANT.** A spy rides at 900‰ of a
  courier, about 144 km a day, so he is mounted: on a horse or a pack pony.
- **The 3D models are built FROM SCRATCH in Blender** (through the Blender
  MCP), rider and mount alike, guided by a structure view. No CC0 scan and no
  AI 3D (the Hunyuan ruling of 2026-09-24 stands).
- **Five card paintings, by kind and state.**
  - the ordinary courier at the gallop;
  - the secret courier;
  - the spy as merchant;
  - a courier held up by foul weather;
  - a courier delivering to a camp.

## 1. Designs (Z-Image Turbo)

**Tool.** `tools/units3d/gen_courier_designs.py`, modelled on
`gen_cavalry_v2.py` and reusing its Z-Image graph
(`zimage_turbo_template.json`, `z_image_turbo_bf16.safetensors`, 8 steps,
cfg 1.0, 1344×896).

**Prompts.** `assets/flux/courier_design_prompts.csv`: `id, subject, prompt`.

- **Courier ids** are `C1`..`C4`, one per courier direction.
- **Spy ids** are `S1` (horse) and `S2` (pack pony).
- **Wrapper.** Every prompt uses the same photographic wrapper as the
  cavalry's `WRAP`, re-worded for a rider:
  - three-quarter side view, the whole mount and rider in frame, all four
    hooves visible;
  - replica historical dress, realistic proportions;
  - plain white studio ground;
  - "character concept reference for a 3D game model".
- **Negative.** It is also the cavalry's, with armour words removed for
  every design but C3.

**Batch.**

| Who | Designs | Seeds | Images |
|---|---|---|---|
| Courier | 4 | 2 | 8 |
| Spy | 2 | 2 | 4 |
| **Total** | | | **12** |

- The batch takes about 6 minutes at ~30 s per image.
- It is written to `assets/flux/out/courier_designs/<id>_s<n>.png`, which
  is git-ignored.
- It ends in a contact sheet `contact_sheet.png` with each tile labelled.

**Pick.** The owner picks ONE courier image and ONE spy image. The picks are
recorded in the prompts CSV's `picked` column as `<id>_s<n>`.

**Structure views.** `tools/units3d/gen_courier_sheet.py`, modelled on
`gen_cavalry_sheet.py`, renders the picked designs from their own prompt
turned to fixed views.

- **Views per design:**
  - `R1` the rider alone, front, arms slightly out;
  - `R2` the rider alone, side;
  - `R3` the rider alone, back;
  - `M1` the mount alone, side;
  - `M2` the mount alone, front;
  - `M3` the mount alone, from above;
  - `A1` the mounted piece, side.
- **Count.** Seven views per design, two designs, **14 images** (~7 min).
- **Seeds.** Each view is seeded by `SEED + view index`, so a re-run is
  identical.

**What the views are for.** They are Claude's modelling references, not
game art. The owner may look at them, but no pick is needed.

**Before a batch runs.** Every batch in this spec is announced to the
owner with its count and time before it is queued (the standing rule).

## 2. The 3D models

**Two models:**
- `assets/units3d/courier.glb` is worn by the `ordinary` and `secret` rows
  of `courier_art.csv`. The secret courier is not offered until C, so it
  shares the courier's model.
- `assets/units3d/spy.glb` is worn by the `spy` row.

**Build from scratch in Blender, high to low.**

- **High model.** A detailed high model per design, rider and mount,
  modelled and sculpted in Blender through the MCP against the structure
  views. It carries:
  - folds in the cloth;
  - leather straps, buckles and stitching;
  - the mane and tail as sculpted locks;
  - the merchant's packs.
- **Low model.** A game model of **15,000–20,000 triangles** per `.glb`.
- **Maps.** The high model is baked onto the low one: normal, AO and base
  colour go into ONE 2048 atlas with one material.
- **Not tubes.** The owner rejected the loft-built cavalry of 2026-09-25 as
  crude. So a primitive or a loft may block a form out, but every surface
  that ships is modelled or sculpted to the design.
- **Reproducible.** The work is kept as a reproducible build:
  `tools/units3d/courier_build.py` reads a saved
  `assets/units3d/ai_src/courier/<code>.blend`, which is git-ignored like
  the scans. The script rigs, animates and exports it, and the export can be
  re-run headless.
- **Log.** Tris, bones and clip ranges are recorded in
  `assets/units3d/units3d.json` like the other units.

**The contract** is the one in `tools/units3d/README.md`:
- the figure faces **+Y**, with **+Z** up, standing on **z = 0**;
- no base (owner 2026-09-27);
- the export round-trips: `shoot_units.py` photographs the BUILT `.glb`,
  and a new GUT test loads each courier `.glb` and finds its clips (§3).

**Rig and actions.**

- **Skeleton.** Horse and rider share one skeleton, the cavalry's layout of
  make_units' humanoid rider on a quadruped mount. So `Map3DUnits`' helpers
  (`find_anim`, `clip_named`, `model_size`, `stand_extent`) work unchanged.
- **Actions:**
  - `GALLOP` is a four-beat gallop loop. The rider rises in the stirrups
    and sways with the horse. The merchant's packs bounce and the pony's
    gait is shorter.
  - `IDLE` is a standing loop: the mount shifts its weight and swishes its
    tail, and the rider looks about.
- **Stride.** Each model writes its `stride_m` (the model metres one
  `GALLOP` loop covers) into `courier_art.csv`.

**The owner's review, in two steps:**
1. The blocked-out and then the sculpted high model are shown in Blender,
   in their own scene (never the owner's working scene; each new model in
   its own place, `kit.py _free_slot`).
2. Once the owner is satisfied, the built `.glb` is shot in the game
   (real window) at three zooms: the opening view, near, and the closest.

## 3. The riders in the game

**`data/courier_art.csv`.**
- `model` now names the two new models.
- A new column `stride_m`.
- `size` is kept and re-tuned only if the owner asks.
- The `INTERIM` notes go.

**`Map3DLayerCouriers`.**

- **Clips.** It plays `GALLOP` while the courier moves and `IDLE` while the
  clock is paused. A model without `GALLOP` falls back to `MARCH`, so a stand-in
  still works.
- **Playback rate.** The rate follows the ground covered, like the
  regiments: world speed ÷ scale × clip length ÷ `stride_m`, held within
  `map3d_courier_anim_min` / `_max`. These new balance keys replace
  `map3d_courier_anim_rate`, which is deleted.
- **Blend.** GALLOP ↔ IDLE blend over `map3d_unit_blend_s`.
- **Rules unchanged.** The size rule, the counter past
  `map3d_unit_counter_scale` and the ride-ahead drawing do not change.

**Tests.** They hold that:
- every `courier_art.csv` model exists and has `GALLOP` and `IDLE`;
- the rate formula holds, against hand-computed values;
- a model with no `GALLOP` falls back to `MARCH`.

## 4. The card paintings

**Five library entries**, `B-43`..`B-47` (the next free after `B-42`), in
art_prompt_library.md §6.11 beside the estate and army paintings:

| Entry | Scene |
|---|---|
| `B-43` | the ordinary courier at the gallop |
| `B-44` | the secret courier |
| `B-45` | the spy as merchant |
| `B-46` | a courier held up by foul weather |
| `B-47` | a courier delivering to a camp |

**Style and canvas.**
- They use the characters' v2 colour style (`STYLE_CORE.txt`), as the estate
  and army paintings do.
- Canvas: a 5:4 vignette with a new canvas row `[C-COURIER]`, worded like
  `[C-ESTATE]` for a rider and road scene.
- The rider's dress follows the owner's picked design, so card and map
  agree. The prompts are therefore written AFTER the design pick (§1).

**Table and batch.**
- `assets/flux/courier_paint_art.csv` maps art id → key: `ordinary`,
  `secret`, `spy`, `foul`, `delivered`.
- Two seeds each: **10 images** with klein 4B (~15 min), and the owner picks
  per key.

**Install.** `install_map_art.py courier_paintings` runs the same path as
`paintings`:
- crop to the scene;
- widen to 5:4;
- box it to 720×576;
- keep the colour;
- write `assets/couriers/paint/<key>.png`.

**Which painting is shown.**

- **Card by kind.** `courier_art.csv` gets its `painting` column filled per
  kind.
- **Foul weather.** A new balance key, `courier_paint_foul_permille` 700,
  switches the card to `foul`: when the weather where the courier is now
  slows a rider to that share or less (`weather.csv` `speed_permille`: mud,
  snow and blizzard), `CourierCard.card` returns the `foul` painting instead
  of the kind's. The foul painting is a new `data/courier_paintings.csv`
  (`key, texture`) with rows `foul` and `delivered`, so a state painting is
  data, not a code path.
- **Delivered.** A courier vanishes on delivery, so his card can never show
  it. The `delivered` painting heads a RECEIPT letter on the board's reading
  desk (`MissiveScreen._fill_desk`, a receipt only), cover-cropped at the
  desk's width like the manor card's painting box.
- **No art yet.** Wherever a painting is missing, the card and the desk
  draw as they do today.

**Tests.** They hold that:
- the kind picks the painting;
- weather at or below the key picks `foul`, one above it does not;
- a receipt's desk shows `delivered` and other letters show none;
- every texture a table names exists.

## 5. The board art (`U-20`..`U-26`)

**Prompts.** They are written already (library §9.1), and the canvases are
the library's.

**Batch.**
- klein 4B, 2 seeds each: **14 images** (~20 min).
- The pieces go through `post.py --tone` to the cream paper (the library
  §9 check).
- The owner picks per key.

**Install.** `install_map_art.py missive` does the following:
- sizes each piece by its USE, as the library's table says:

  | Piece | Size |
  |---|---|
  | frame | 512² |
  | board tile | 512² seamless |
  | note | 512×256 |
  | letter | 512×768 |
  | envelope | 384×288 |
  | pin | 48² |
  | plaque | 576×144 |

- cuts out the pieces standing on the grey ground (the envelope, the pin);
- writes `assets/missives/<key>.png`;
- fills `missive_art.csv`'s `texture`.

**Code.**
- **Missive board.** `MissiveScreen` reads every key, not only `envelope`:
  - the frame, note, letter and plaque as nine-slices, with margins from a
    new `missive_art.csv` `margin` column in texture px;
  - the board as a tile;
  - the pin as a sprite at each note's top.
- **Report dialog.** `MissiveReportPopup` wears the letter.
- **Fallback.** A key with no texture keeps today's `UiPalette` flat style,
  so an uninstalled piece is never a hole.
- **Check the look.** Each piece is checked in the real window against the
  dark theme's panels (the visual-review loop).

**Tests.** They hold that:
- each key with a texture is drawn from it;
- each key without one draws the fallback;
- every named texture exists.

## 6. Order

1. §1 designs: 12 images → the owner picks.
2. §1 structure views: 14 images.
3. §2 the courier model: block out → owner → sculpt → owner → low, bake,
   rig, GALLOP / IDLE, export → game shots → owner.
4. While the owner reviews step 3: §4's prompts (after the pick) and
   batch, and §5's batch → owner picks → install and wire §3–§5.
5. §2 the spy model, the same way.
6. `CLAUDE.md`'s Couriers and Missives paragraphs record what D shipped.
   The `INTERIM` wording goes.

## Out of scope

- Couriers of other realms and their looks (they arrive with C).
- A foot messenger, ships and fleet couriers. Fleets are exempt from
  couriers (A).
- Any change to courier speed, routes or weather.
- The missive board's layout. D changes its look, not its structure.
- The Seal / Show on map button styling (left with the owner by B).
