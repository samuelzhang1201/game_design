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
| `aerial_meadow.png` | T-51 | 954159498 | GRASS | 120 m |
| `aerial_canopy.png` | T-52 | 954159498 | FOREST | 170 m |
| `aerial_upland.png` | T-54 | 954159497 | ROCKY | 200 m |

Committed (6.5 MB) because a seeded generation is only reproducible on the
same models and nodes; `assets/map3d/` itself stays git-ignored. Pack each
into Terrain3D's two maps before `build_pack.sh`:

    python3 tools/map3d/pack_aerial.py assets/map3d_aerial/aerial_meadow.png aerial_meadow
    python3 tools/map3d/pack_aerial.py assets/map3d_aerial/aerial_canopy.png aerial_canopy --height-gain 1.3 --rough 0.95
    python3 tools/map3d/pack_aerial.py assets/map3d_aerial/aerial_upland.png aerial_upland --height-gain 1.2
