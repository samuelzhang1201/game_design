# Aerial ground pictures (look route, 2026-09-30)

The sources of the 3D map's aerial terrain layers: pictures of the ground as
seen from ~200 m up, generated locally (ComfyUI, Z-Image Turbo) from
`assets/flux/terrain_aerial_prompts.csv` with `STYLE_CORE_aerial_ground.txt`
(`generate.py --prompts-file terrain_aerial_prompts.csv --model zimage
--style-file STYLE_CORE_aerial_ground.txt --res 1024`). The Poly Haven sets
they replace are ground-level photos of 1-2 m of ground, stretched to
160-320 m tiles, which average to grey noise at map height.

| file | prompt | seed | layer (bake_world.py) | tile |
|---|---|---|---|---|
| `aerial_meadow.png` | T-64 | 954159497 | GRASS | 120 m |
| `aerial_canopy.png` | T-52 | 954159498 | FOREST | 170 m |
| `aerial_upland.png` | T-54 | 954159497 | ROCKY | 200 m |
| `aerial_cliff.png` | T-57 | 954159499 | CLIFF | 160 m |
| `aerial_snow.png` | T-58 | 954159498 | SNOW | 180 m |

Committed (~11 MB) because a seeded generation is only reproducible on the
same models and nodes; `assets/3D/terrain/` itself stays git-ignored. Pack each
into Terrain3D's two maps before `build_pack.sh`:

    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_meadow.png aerial_meadow --match-mean '#666A35' --normal-strength 0.25 --rough 0.95
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_canopy.png aerial_canopy --height-gain 1.3 --rough 0.95
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_upland.png aerial_upland --height-gain 1.2
    python3 tools/map3d/pack_aerial.py assets/3D/terrain/model_wip/aerial/aerial_cliff.png aerial_cliff --saturation 0.85 --lift-darks 0.6 --black 0.05 --warm 0.03 --height-gain 1.3
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
