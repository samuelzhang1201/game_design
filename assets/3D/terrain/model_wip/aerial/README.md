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
| `aerial_meadow.png` | T-64 | 954159497 | GRASS | 120 m |
| `aerial_canopy.png` | T-52 | 954159498 | FOREST | 170 m |
| `aerial_upland.png` | T-74 | 954159499 | ROCKY | 350 m |
| `aerial_cliff.png` | T-73 | 954159499 | CLIFF | 200 m |
| `aerial_snow.png` | T-58 | 954159498 | SNOW | 180 m |
| `aerial_crop.png` | T-62 | 954159497 | CROP | 140 m |

Committed (~11 MB) because a seeded generation is only reproducible on the
same models and nodes; `assets/3D/terrain/` itself stays git-ignored. Pack each
into Terrain3D's two maps before `build_pack.sh`:

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_meadow.png aerial_meadow --match-mean '#666A35' --normal-strength 0.25 --rough 0.95 --fill-spots 0.2
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_canopy.png aerial_canopy --height-gain 1.3 --rough 0.95
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_upland.png aerial_upland --height-gain 1.2 --lift-patches 1.0 --patch-radius 220 --patch-inner 16 --fill-spots 0.1 --fill-dark-only --fill-inner 8 --fill-grow 10 --saturation 0.75 --contrast 0.9 --grey-tint '#BCA888' --grey-tint-amount 0.9 --grey-lift 0.2 --match-mean '#6D654B'

`--lift-patches` (visual review 2026-10-06) raises the upland's dark heather
blobs to their surroundings' light at low frequency, keeping the grain: tiled
every 200 m they read as black pits all over the hills.
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_cliff.png aerial_cliff --saturation 0.6 --contrast 0.9 --lift-darks 0.95 --lift-radius 24 --height-gain 1.3 --match-mean '#8A7A64'
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_snow.png aerial_snow --flatten-keep 0.0 --contrast 0.55 --saturation 0.3 --height-gain 0.8 --rough 0.75

The cliff (owner 2026-09-30, "先做悬崖纹理"): the escarpments wore ambientCG
rock023, which read as smeared pale plaster. A FRONTAL rock-wall picture (T-55)
drew its strata as bent tiger stripes down a slope (a top-down projection);
T-56's broken limestone read as crazy paving (taste: paving slabs). T-57, a
crag seen from above, won the critic's ranking with its black point lifted a
little, a touch warmer to sit with the golden grass (v4's cool grey read as a
second photograph), its dark shrub clumps lifted (they read as burn holes).
Known limits: the steepest faces still stretch (a top-down photo on a steep
face), and the scarps have no cliff silhouette — that is geometry.

The snow (owner 2026-09-30, "山顶雪帽"): Poly Haven snow_02 read as beige
plaster with brown worm marks and a ruled rim. T-58, sunlit snow from above,
with ALL of its own slow light flattened out (its cast shadows otherwise
repeat as blue blotches every tile), its contrast at 0.55 (more read as
crumpled paper) and nearly grey (cyan flecks in the dimples); the bake breaks
the line with noise, lowers it on north faces, and lays a band of scree under
it (data/map3d_bake.csv snow_*). An overcast snow prompt (T-59) came back
near-blank.

The grass (owner 2026-09-30, "现在的草地拉近看太模糊了", chose option 3):
T-51 was grass shot from ~20 m up spread over a 120 m tile, and the model
draws a fine grain as swirling strokes, so close in the meadow read as
smeared brush strokes, with blue-grey flecks from its normal map catching the
sky. T-64 ("patchy meadow", `STYLE_CORE_aerial_grass.txt` /
`NEGATIVE_aerial_grass.txt`: ground about 100 m across from a light aircraft)
has crisp patches of longer and shorter grass and a few bushes; it is packed
with a weak normal (0.25) and kept at T-51's mean colour (`--match-mean
'#666A35'`, the packed T-51's mean in linear light) so the bake's colour map,
which divides by each layer's mean, needs no rebuild. A detail texture over
it was tried and dropped: at the closest zoom a screen pixel is ~0.5-1 m, so
a close-up grass grain is sub-pixel and only averages away. Compared and
rejected: T-60 pasture and T-62 downland (softer), T-61 hay meadow (both
models drew blade close-ups), T-63 tussocks (black polka dots), and every
Qwen-2512 tile but one (close-ups again).

The crops (owner 2026-10-01, open fields): `aerial_crop.png` is T-62 (the even
chalk downland, `STYLE_CORE_aerial_grass.txt`) packed into a PALE STRAW ground
that each field's tint darkens to its crop — the colour map can only darken, so
no crop drawn on the grass layer could be gold:

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_crop.png aerial_crop --saturation 0.25 --contrast 0.8 --lift-darks 0.9 --lift-radius 16 --match-mean '#D4C89C' --normal-strength 0.25 --rough 0.95 --fill-spots 0.2

`--fill-spots 0.2` (visual review 2026-10-05) paints out the downland's bushes and
white stones: tiled every 140 m they drew rows of dark ovals across every field.

The crops, regenerated (visual review 2026-10-06, the owner's go-ahead for lever 3's
field textures): `aerial_crop_field.png` is T-68 (seed 954159498, Z-Image,
`STYLE_CORE_aerial_crop.txt` / `NEGATIVE_aerial_crop.txt` — a cornfield from a light
aircraft, about 100 m across, no rows or tramlines). The downland it replaces carried
the pasture's own grain, so the crops read as recoloured meadow at the opening zoom.
Close-up prompts (T-65, T-66) drew single ears — sub-pixel on a 140 m tile; T-67 and
the other T-68 seeds carry tramlines that would repeat across every field.

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_crop_field.png aerial_crop --saturation 0.25 --contrast 1.8 --flatten-keep 0.0 --fill-spots 0.12 --fill-dark-only --match-mean '#D4C89C' --normal-strength 0.6 --rough 0.95


The cliff, regenerated (owner 2026-10-06, approving a new top-down warm rock):
`aerial_cliff.png` is T-73 (seed 954159499, Z-Image, `STYLE_CORE_aerial_ground.txt`:
an eroded sandstone hillside from an aircraft at 800 m — buff and honey outcrops,
talus fans, gravel and dry grass, no layers or stripes). T-57's crag, laid on the
escarpments, read as a grey, vertically striped photograph. It is packed to the
bake's own far colour (`far_color_cliff` #8A7A64), so the colour map's cliff
multiplier is 1 after a rebake, with its dark pockets lifted (`--lift-darks 0.95`:
at 0.6 they read as burns), and tiled at 200 m (`build_terrain.gd`): at 260 m its
blocks read 2-3x house size, at T-57's 533 m a rubble of giants. The critics
ranked it over T-70 (gritstone boulders: clear, but the blocks too big), T-72
(an aircraft view of a mountainside: cold blue rock with a diagonal grain that
streaked down the slopes) and T-69 (one boulder dome in the middle of the frame:
it cannot tile). Every Qwen-2512 tile of T-69..T-73 drew a fish-eye close-up of
tufts and stones, one of them a maze — Z-Image only, as for every aerial so far.
Known limits: the steepest faces still smear (Terrain3D projects a side view from
`projection_threshold` 0.87, the 45-degree snap of a top-down picture), and the
rock's edge against the grass is the bake's blend.

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

Packed with the meadow's and the crop's settings above:

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
| `p2_snow.png` | T-88 | 954159497 | SNOW (replaces aerial_snow) |

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_scree.png p2_scree --height-gain 1.2 --saturation 0.35 --match-mean '#8E8B84'
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_ridge.png p2_ridge --height-gain 1.4 --saturation 0.7 --lift-darks 0.6 --match-mean '#7A7060'
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p2_snow.png p2_snow --flatten-keep 0.0 --contrast 0.7 --saturation 0.3 --height-gain 0.9 --rough 0.75

## The frontal rock face (owner-approved 2026-10-13, "批准")

`p3_rock_face.png` is R-01 (seed 954159498, Z-Image, `rock_face_prompts.csv` /
`STYLE_CORE_rock_face.txt`): a weathered sandstone face photographed straight on,
blocky and fractured with no strata. It replaces `aerial_cliff` as the CLIFF layer:
Terrain3D projects the steep faces vertically (projection_threshold 0.87), where the
top-down crag read as pale vertical streaks.

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/p3_rock_face.png p3_rock_face --height-gain 1.3 --saturation 0.8 --match-mean '#8A7A64'
