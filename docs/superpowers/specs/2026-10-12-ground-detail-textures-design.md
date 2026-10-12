# Ground detail textures: no visible repeat

**Status:** draft for the owner's go-ahead (2026-10-12). Nothing is generated until the owner approves the texture list below.

**Trigger.** The owner is not satisfied with the ground (2026-10-12): close in, the meadow and the fields show the same picture again and again. The target is the ground in *Civilization VII* (reference video `youtube.com/watch?v=f7My1m__jno`, the 1.5.0 Earth-map trailer).

## What makes the reference work

*Civ VII*'s ground has four layers. This spec covers only the first.

| Layer | Civ VII | Ours now | In this spec |
|---|---|---|---|
| 1. Ground textures | small detail textures with nothing recognisable in them; every colour comes from a large colour map | aerial photographs, the meadow repeating every 120 m, with patches you can recognise | **yes** |
| 2. Ground scatter | dense small rocks, grass tufts and shrubs near the camera | trees only | no (next spec) |
| 3. Sculpted relief | crafted rock faces and strong normal detail | soft heightmap | no |
| 4. Light | low warm sun, soft long shadows, strong AO, haze, depth of field | SSAO, haze and sky, tuned conservatively | no |

## Why the obvious fixes fail

- **Tinting does not hide a repeat.** Measured 2026-10-12: stronger `macro_variation` colours, then finer macro noise. Both left the repeat visible, darkened the ground and blotched it, which breaks "Colour a little richer than true, never lighter".
- **Ground-level photos turn grey.** The 2026-09-30 move from Poly Haven to aerial pictures happened because 1–2 m of ground-level photo, stretched to a 160–320 m tile, averages to grey noise at map height. "Each material is seen from where the player looks" still holds, so the textures stay aerial.
- **The repeat comes from recognisable things in the picture**, not from the tile size: a bush, a trail, a light patch with a distinct shape. The eye finds the same shape at a fixed distance. Three things fix it:
  1. a picture with no shape worth recognising;
  2. per-tile jitter;
  3. more than one picture for the same ground.

## The plan

### Phase 0: code only, no new art (do first)

Terrain3D 1.0.2's texture asset has `detiling_shift` (a random per-cell offset) beside the `detiling_rotation` we already set (0.10–0.22 rad, `tools/map3d/build_terrain.gd` `TEXTURES`).

- Add a shift column to `TEXTURES`.
- Bracket rotation × shift at 600 m, 1500 m and 5000 m (`visual-review`).
- Rebuild the pack.

This may remove much of the repeat on its own. Whatever is still visible tells Phase 1 which ground classes need new pictures.

**Result (2026-10-12).** Bracketed at 600 m, 1500 m and 5000 m, three settings, judged by an independent critic shown blind labels:

| Setting | What the critic saw |
|---|---|
| A: today | no shift; low-contrast banding in the wheat, an even mottle in the meadow |
| B: shift 0.5, rotation unchanged | the wheat's banding broken, no seams, no new defect; at 1500 m barely different from A |
| C: rotation ×2, shift 1.0 | neighbouring cells' crop rows point different ways, a CG checker; breaks "Nothing ends on a hard cut" and "Hand-built, not machined" |

- **B is kept** (shift 0.5 on the ground layers, rotation as it was) as a free, harmless step.
- **No setting fixes the repeat.** What remains comes from each picture having one grain direction and one patch scale, so Phase 1 is needed for every class it lists.
- **Rotation stays small:** larger rotation makes the crops' rows disagree.

### Phase 1: variant sets (new art, needs the owner's go-ahead)

- **Variants per ground class.** Each repeated class gets 2–3 interchangeable pictures, all low-feature: nothing distinct larger than about 3 m.
- **The bake picks the variant.** `tools/map3d/bake_world.py` picks a cell's variant by a seeded low-frequency noise. The new `data/screens/map3d/map3d_bake.csv` keys are `variant_wave_m` (patch size, about 300–800 m) and `variant_blend`. The bake writes it as the base/overlay pair Terrain3D already blends, so two neighbouring tiles of meadow are rarely the same picture.
- **Colour stays the bake's colour map.** The far view does not change.

**Texture list.** Seven pictures, three ground classes:

| id | class | variant | subject direction |
|---|---|---|---|
| T-77 | meadow | A short turf | close-grazed turf, a fine even grain, soft mottling only, no clumps, no bushes |
| T-78 | meadow | B longer grass | longer grass in soft wind-laid swirls, low contrast, no flowers, no trails |
| T-79 | meadow | C mixed sward | a mixed sward: fine variation of sage, olive and yellow-green, isotropic, no shapes |
| T-80 | crop | A standing grain | the inside of a standing cereal crop, fine grain, faint lighter and darker clouds |
| T-81 | crop | B stubble / tilth | harvested stubble over pale soil, fine even grain, no rows, no tracks |
| T-82 | upland | A dry turf | dry golden-olive turf with grit showing through, low contrast, no rocks larger than a metre |
| T-83 | upland | B heathy turf | short heather and grass interleaved finely, no patches larger than a few metres |

- **Prompting.** A new `STYLE_CORE_aerial_ground_v2.txt`: taken straight down from about 300 m, a frame about 120 m across, isotropic, low contrast, "no single object you could recognise again".
- **Negative list.** `NEGATIVE_aerial_ground_v2.txt` adds to the current list: bushes, trails, paths, sheep, molehills, isolated clumps, boulders, any lone object, patches with a defined outline.

**Generation** (`assets/imagegen/terrain_aerial_prompts.csv`, `generate.py`):

| | |
|---|---|
| Models | both, as for every batch: Z-Image Turbo and Qwen-Image-2512 |
| Size | 1024 px |
| Seeds | 4 per model per picture |
| Candidates | 7 × 2 × 4 = **56** |
| Who picks | the owner, from a contact sheet per class |

**Install path.**

1. `pack_aerial.py` makes each picture seamless and packs it at 2048 px.
2. Add the rows to `build_terrain.gd` `TEXTURES`, each with its own tile size and detiling.
3. Run the bake's variant mix.
4. Rebuild the pack (`build_pack.sh`).

## Acceptance

- **At 600 m and 1500 m:** an independent critic, shown a shot with a 3×3-tile window marked, cannot point to the same patch twice.
- **At 5000 m and 30000 m:** the view matches today's within the critic's eye. Colour is the colour map's job.
- **Bench:** `bench.gd` holds every tier's budget. The texture array grows from 11 to 15 layers at 2048 px; check the low tier's VRAM.

## Open for the owner

1. Approve the seven pictures (or cut the list).
2. Two variants per class or three? Three hides the repeat better and costs a layer each.
3. Should Phase 0 run first and the list shrink to what still shows? Recommended.
