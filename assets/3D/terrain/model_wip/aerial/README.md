# Aerial ground pictures (look route, 2026-09-30)

The sources of the 3D map's aerial terrain layers: pictures of the ground as
seen from ~200 m up, generated locally (ComfyUI, Z-Image Turbo) from
`assets/imagegen/terrain_aerial_prompts.csv` with `STYLE_CORE_aerial_ground.txt`
(`generate.py --prompts-file terrain_aerial_prompts.csv --model zimage
--style-file STYLE_CORE_aerial_ground.txt --res 1024`). The Poly Haven sets
they replace are ground-level photos of 1-2 m of ground, stretched to
160-320 m tiles, which average to grey noise at map height.

| file | prompt | seed | layer (bake_world.py) | tile |
|---|---|---|---|---|
| `aerial_canopy.png` | T-52 | 954159498 | FOREST | 170 m |
| `aerial_upland.png` | T-74 | 954159499 | ROCKY | 350 m |

The grass, crops, snow and cliff wear the later pictures below (variant sets,
high ground, frontal rock face). Committed (~28 MB) because a seeded generation
is only reproducible on the same models and nodes. Pack each into Terrain3D's
two maps before `build_pack.sh`:

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_canopy.png aerial_canopy --height-gain 1.3 --rough 0.95
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_upland.png aerial_upland --height-gain 1.2 --lift-patches 1.0 --patch-radius 220 --patch-inner 16 --fill-spots 0.1 --fill-dark-only --fill-inner 8 --fill-grow 10 --saturation 0.75 --contrast 0.9 --grey-tint '#BCA888' --grey-tint-amount 0.9 --grey-lift 0.2 --match-mean '#6D654B'

`--lift-patches` (visual review 2026-10-06) raises the upland's dark heather
blobs to their surroundings' light at low frequency, keeping the grain: tiled
every 200 m they read as black pits all over the hills.

The upland, regenerated (owner 2026-10-06: "ok" to new art for it): `aerial_upland.png`
is T-74 (seed 954159499, Z-Image, `STYLE_CORE_aerial_ground.txt`: a rough upland
from an aircraft at 600 m, dry golden grass with a few irregular scree patches tens
of metres across). T-54's white stones repeated every 200 m tile (critics: stamped
noise); T-71, with the stones painted out, was a flat brown blanket. Its scree was
blue-grey, so `--grey-tint` turns the GREY pixels toward a tan stone at their own
light and lifts them (a global `--warm` is undone by `--match-mean`), and
`--fill-spots --fill-dark-only` paints out the heather's dark oval hollows (they
read as ponds or burns). Tiled at 350 m (`build_terrain.gd`): at 200 m the patches
read as specks and repeated. Critic: 4 -> 5.5/10. Rejected: T-75 (a straight path
crosses every tile), T-76 (white boulders again), T-74's other seeds (patches
crowded in one corner), every Qwen-2512 tile. Known limits: at 6 km the patches
dissolve and the snow still meets brown ground with no scree band — that is the
bake's snow margin, not this picture.

## Variant sets (spec 2026-10-12-ground-detail-textures, Phase 1)

Seven low-feature pictures from `assets/imagegen/ground_v2_prompts.csv` with
`STYLE_CORE_aerial_ground_v2.txt` (Z-Image Turbo on the Windows desktop,
`COMFYUI_URL=http://192.168.4.85:8188 generate.py --prompts-file ground_v2_prompts.csv
--style-file STYLE_CORE_aerial_ground_v2.txt --model zimage`), the owner's picks:

| file | prompt | seed | layer |
|---|---|---|---|
| `g2_meadow_a.png` | T-77 | 954159497 | GRASS (id 1) |
| `g2_meadow_b.png` | T-79 | 954159500 | GRASS_B |
| `g2_meadow_c.png` | T-78 | 954160100 | GRASS_C |
| `g2_upturf_a.png` | T-82 | 954160102 | UPTURF_A |
| `g2_upturf_b.png` | T-83 | 954159498 | UPTURF_B |
| `g2_crop_a.png` | T-80 | 954159497 | CROP (id 9) |
| `g2_crop_b.png` | T-80 | 954159498 | CROP_B |

Packed with:

    for k in g2_meadow_b g2_meadow_c; do python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/$k.png $k --match-mean '#666A35' --normal-strength 0.25 --rough 0.95 --fill-spots 0.2; done
    for k in g2_meadow_a g2_upturf_a g2_upturf_b; do python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/$k.png $k --match-mean '#666A35' --normal-strength 0.8 --rough 0.95 --fill-spots 0.2 --contrast 2.2; done

(the flattest three at contrast 2.2: at 1.0 the hills read airbrushed at the opening zoom)
    for k in g2_crop_a g2_crop_b; do python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/$k.png $k --saturation 0.25 --contrast 1.8 --flatten-keep 0.0 --fill-spots 0.12 --fill-dark-only --match-mean '#D4C89C' --normal-strength 0.6 --rough 0.95; done


## The high ground (spec 2026-10-13-map-art-phase2, B)

Owner-approved 2026-10-13 ("同意 A/B/C"), Z-Image on the Windows desktop
(`map_art_phase2_prompts.csv`, `STYLE_CORE_aerial_ground.txt`):

| file | prompt | seed | layer |
|---|---|---|---|
| `p2_scree.png` | T-86 | 954159498 | SCREE (the band under the snow caps) |
| `p2_ridge.png` | T-87 | 954159500 | RIDGE (the high plateaus, ridge_lo..ridge_hi) |
| `p2_snow.png` | T-88 | 954159497 | SNOW |

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_scree.png p2_scree --height-gain 1.2 --saturation 0.35 --match-mean '#8E8B84'
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_ridge.png p2_ridge --height-gain 1.4 --saturation 0.7 --lift-darks 0.6 --match-mean '#7A7060'
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_snow.png p2_snow --flatten-keep 0.0 --contrast 0.7 --saturation 0.3 --height-gain 0.9 --rough 0.75

## The frontal rock face (owner-approved 2026-10-13, "批准")

`p3_rock_face.png` is R-01 (seed 954159498, Z-Image, `rock_face_prompts.csv` /
`STYLE_CORE_rock_face.txt`): a weathered sandstone face photographed straight on,
blocky and fractured with no strata. It is the CLIFF layer:
Terrain3D projects the steep faces vertically (projection_threshold 0.87), where the
top-down crag read as pale vertical streaks.

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p3_rock_face.png p3_rock_face --height-gain 1.3 --saturation 0.8 --match-mean '#8A7A64'
