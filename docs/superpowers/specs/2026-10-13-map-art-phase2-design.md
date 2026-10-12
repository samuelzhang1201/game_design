# Map art, phase 2: field margins, rock and snow, ground life

**Status:** draft. Nothing is generated until the owner approves; this follows the owner's ruling to ask before queuing any batch.

**Trigger.** The overnight goal of 2026-10-13 was to make the 3D map look like Civilization VII. Two blind critic rounds scored the map at 5–5.5 / 10 at play zooms, against about 9 for the reference, after every code and value lever was tried (PRs #50 and #51). Both rounds named new art as the ceiling.

## The three gaps and what fixes them

| # | Gap (critic) | taste.md | Fix |
|---|---|---|---|
| 1 | Fields read as tinted decals; edges are noise, not hedges and balks | Nothing ends on a hard cut; places are systems | **A.** Margin textures, drawn by the bake along `field_edges.png` |
| 2 | Mountains read as frost on a lowland: no ridges, gullies or scree | The sun models the land; each material is seen from where the player looks | **B.** Rock, scree and snow-rib textures for the high ground |
| 3 | Open ground has no life between the trees | Nature clusters; material and life rescue a picture | **C.** Ground scatter: rock and shrub props, plus more varied tree silhouettes |

## A. Field margins (2 textures)

- **T-84 hedgerow margin.** A rough grass and bramble strip with a low hawthorn line.
- **T-85 grassy balk.** The strip between furlongs.
- **How they are drawn.** As a new layer the bake lays on the band `field_edges.png` already marks (`hedge_band_m`). That band is where `bake_trees` plants its hedge clumps today, so the hedges get a ground under them instead of sitting on crop.
- **Risk.** The band is under a vertex (20 m) in places. At 20 m vertex spacing a margin narrower than about 2 vertices can vanish, so the band is widened to 2 vertices for this layer only. Judge at 600 m and 1.5 km.

## B. High ground (3 textures)

- **T-86 grey scree.** Replaces nothing; it is the `snow_scree_band` layer, which today wears `aerial_upland`.
- **T-87 ridge and gully.** The plateau tops above the turf band and below the snow. The 2026-10-13 snow tests showed the ranges are plateaus, so slope rules alone cannot draw ridges. This texture carries them.
- **T-88 snowfield with rock ribs.** Replaces `aerial_snow`. A flat snow picture reads as a white sheet; ribs give the caps their form from above.

## C. Ground life (no images; 3D props and tree crowns)

- **Rock and shrub props.** 6–8 low-poly props (2 boulder clusters, 2 scree piles, 2 gorse or bramble clumps, 2 heather tufts) at the game budget (skill §7). They are placed with Terrain3D's instancer, as the trees are, by a new `bake_scatter.py` that clusters them on rough ground, the scree band and field margins. They are shown near only (≤ 2 km) and benched per tier.
  - Source: Poly Haven CC0 models first (no generation).
  - Tripo, the owner's paid plan, only for what is missing.
  - No Hunyuan.
- **Tree silhouettes.** 4 more crowns for the existing atlas (`tree_crown_prompts.csv`, TR-xx): a wind-bent pine, a tall poplar, an old pollarded willow, a spreading field maple. These break the "puffball" sameness the critic named.

## Generation (on the owner's yes)

- **Z-Image on the Windows desktop.** It draws aerials. Qwen drew close-ups again on 2026-10-12, so for aerial ground it is skipped unless the owner asks.

  ```
  COMFYUI_URL=http://192.168.4.85:8188 python3 assets/imagegen/generate.py --prompts-file map_art_phase2_prompts.csv --style-file STYLE_CORE_aerial_ground.txt --chapter T --model zimage --variants 4
  ```
- **Count.** 5 textures × 4 seeds = 20 images. The tree crowns are 4 × 4 = 16 more on both models, as tree crowns always are.
- **The owner picks** from one contact sheet per class.

## Acceptance

The same blind critic round as 2026-10-13, against the Civ VII frame:
- **Opening zoom:** from 5.5 to at least 6.5.
- **Mountains:** at least 6.
- **Bench:** each tier still holds 60 fps (props near only).

## Open for the owner

1. Approve A, B and C (or a subset).
2. Props: Poly Haven only, or Tripo allowed for the gaps?
