# Open-field layout, meadow interiors, hedges with volume

**Status:** directions chosen by the owner (2026-10-13); phase 1 built on the owner's go-ahead (按默认做第 1 阶段). Stacked on PR #57 (`feat/rock-hedge`).

**Trigger.** PR #57's critic left three things open:
- the fields' outlines are still regular;
- the pale meadow and pasture fields are flat inside;
- the hedgerow line has no volume.

**The owner's choices** (2026-10-13, `/creative`, safe / balanced / bold each):

| Problem | Choice | In one line |
|---|---|---|
| Field outlines | **bold** | a real open-field generator: furlongs of long strips, laid by the land, with headlands |
| Meadow interior | **safe** | light and dark inside each field from the ground it lies on; bake only |
| Hedge volume | **balanced** | a continuous low hedge of the existing `hedge_bush` cards, with a ground shadow |
| Where hedges stand | **by history** | only round the crofts, the outside of the great fields, meadow and common edges, and the lanes. Inside a great field, furlongs are parted by grass balks and headlands, never hedges |

The last ruling changes PR #57: its hedgerow line runs round EVERY field. After this spec it runs only where a hedge stood. Inside the great fields the line is a pale grass balk again.

## Why it looks this way now

- **Outlines.** `bake_world.jitter_cells` makes the furlongs as a jittered-grid Voronoi of one size (`furlong_m` 320), warped by 12 m of noise. Every furlong is about the same size and has no long axis. From 1.5 km they read as a quilt of similar rounded blocks. The farmland's outline is a circle round the village, frayed by noise; it ignores the slope and the valleys.
- **Meadow interior.** A meadow, pasture or croft grass field takes one tint per field (`map3d_fields.csv`, pale `#E2E8BC` / `#F4F2DC`), plus `field_shade` and a 140 m grain. Nothing inside it answers the ground.
- **Hedges.** The hedge is a 9 m dark band on the ground (`Map3DGroundBalk`) plus clumps every 22 m at a 65% chance (`hedge_*`). The clumps read as scattered trees, not a line, and the band casts no shadow.

## 1. The open-field layout (bold)

What a medieval township's arable looks like from above:
- two or three **great fields**, each split into **furlongs**;
- a furlong is a block of parallel **strips** (selions), all running one way;
- neighbouring furlongs often run at right angles, which gives the patchwork;
- a furlong is about a furrow-long: 150–400 m along the strips and 80–300 m across;
- where the plough turned, a grass **headland** runs across the strips' ends;
- the strips follow the fall of the land, so the water drains down the furrows;
- the arable fills the good ground and stops at steep slopes, wet bottoms and the woods' edge; it is no circle.

The bake already draws the strips: `fields.png` A is each field's strip direction, and the shader draws strips and furrows. This section changes the furlongs' SHAPES and DIRECTIONS and adds headlands.

### 1a. The farmland follows the land

- A point's reach becomes an **effort**, not a distance. It is the walk from the village, with each metre of climb counted `reach_climb_k` times (`map3d_bake.csv`, about 8–15).
- Effort is a distance transform over a slope cost: `scipy.ndimage` on the 4-vertex grid the settlements' Voronoi already uses, or a cheap Dijkstra on that grid.
- The fields then run up the valleys and stop below the ridges, and the outline is shaped by the ground.
- The existing frays (`field_edge_noise`, `croft_edge_noise`) stay on top.

### 1b. Furlong regions turned by the land

- Each great field is cut into **furlong regions**: a Voronoi of seeds about `furlong_region_m` apart (about 500–700 m), warped like the great fields' edges.
- **Each region's strip direction:**
  - where the ground slopes more than `strip_fall_slope`, the fall line (the strips run downhill);
  - otherwise the current rule: towards the village or across that line, by hash.
  - Neighbours then disagree, which gives the patchwork, but each disagreement has a reason.
- Inside a region the furlongs are a **rotated brick layout** (the shape `field_cells` already builds for the crofts), in the region's frame:
  - rows of furlongs `furlong_len_m` along the strips, `furlong_w_m` across, each varied by hash;
  - rows staggered;
  - a short furlong merged with its neighbour.
- **Size grades with effort.** Near the village a furlong is smaller (`furlong_near_scale`, about 0.6). Out at the arable's edge it is larger.
- **The warp stays low-frequency** (`field_warp_m` about 25 over 600 m), so the edges wander without lobing. Critic 2026-09-19: 100 m drew amoeba shapes.

### 1c. Headlands and natural edges

- Every furlong's two **strip ends** get a grass headland, `headland_m` wide (about 10). It is drawn as a balk, but wider, and it sits ACROSS the strips.
- `field_edges.png` already holds the signed distance to the furlong's edge. The bake splits that distance into two parts:
  - the distance along the strips, which is the headland;
  - the distance across them, which is the balk.
- A **road** or **stream** crossing the arable becomes an edge. A furlong's edge distance is the smaller of its own and the distance to the drawn road or stream line, so a lane parts the furlongs instead of running across them.

### 1d. Assarts

- Where the arable's effort edge meets the woods, a few furlongs push into the wood: `assart_share` of the edge regions are allowed past the edge by one row.
- `settled.png` clears the woods there as it already does for the fields.
- The edge of the farmland then has bites and spurs, not a smooth frayed ring.

### 1e. Later, optional: the reverse-S

The strips of real open fields bend in a gentle reverse-S, the ox team's turn. In the shader this is a phase offset `strip_bend × sin(along / strip_bend_wave_m)` on the strip pattern. It reads only at the nearest zoom. It comes last, behind a look value (0 = off), and is judged before it is kept.

### What stays

- The great fields and the rotation (crop per great field, `bare_share`).
- The crofts, the meadow by the water and the common pasture past the arable.
- The colour map. The far view is a patchwork of the same crops.
- One seeded stream: `prng` / `hash01` exactly as today, so a rebuild is deterministic.

## 2. Meadow and pasture interiors (safe, bake only)

Inside every field that is NOT arable (croft grass, meadow, pasture), the tint answers the ground:
- **Wet hollows are richer.** The bake's `relief_ao` / low-ground measure and the river's wet band darken and green the tint by `grass_hollow_*` in the hollows. Rises and dry knolls are paler and warmer by `grass_knoll_*`.
- **Wear near the village.** Within a pasture the grass is paler and browner towards the village side (`grass_wear_*` over the first share of its reach), where the beasts gather, and lusher out at the far edge.
- **A field-scale cloud.** A slow noise at about 80–150 m (`grass_cloud_m`, `grass_cloud`), seeded per field so neighbours differ.

Limits:
- All three are at vertex scale (20 m). Narrow trodden tracks (4–6 m) are below what the bake can carry; they are left out of this option.
- The values are clamped so a field never goes lighter than its tint today. Taste: "Colour a little richer than true, never lighter".

## 3. Hedges where they stood, with volume (balanced, by history)

### 3a. Where

- A new bake output, `bake/hedge_lines.png`: the signed metres to the nearest **hedge line**, encoded like `field_edges.png`. It is a separate file so `field_edges.png` stays what the balk and rim read.
- **Hedge lines:**
  - each croft close's edge;
  - the boundary between the arable and anything that is not arable (the great fields' ring fence);
  - meadow edges;
  - the pasture's edge against the woods;
  - both sides of every lane within a village's reach.
- **Not hedge lines:** the edges between furlongs, and the headlands. Those stay grass balks.

### 3b. On the ground: a balk and a hedge are drawn differently

`Map3DGroundBalk` draws two lines:
- the **balk** from `field_edges.png`: a pale grass line, narrow (`balk_*` returns to a grass colour);
- the **hedge** from `hedge_lines.png`: dark green (`hedge_*` in the ground look) and a **soft ground shadow** on the side away from the sun.

The shadow:
- `hedge_lines.png` is sampled again, offset toward the sun by `hedge_height_m / tan(elevation)`;
- it darkens where that offset point lies inside the hedge (`hedge_shadow`, `hedge_shadow_soft_m`);
- the sun's direction comes as a uniform from `Map3DSun` (one per frame, not per pixel);
- it is light and short: taste, "the sun models the land; it never hides it".

### 3c. In 3D: a continuous hedge of cards

- `bake_trees.py` plants `hedge_bush` (the SC-04 hawthorn cards, atlas cells 14–15, already approved in PR #57) along `hedge_lines.png`:
  - every `hedge_line_spacing_m` (about 8–12 m);
  - its crowns spread to overlap (`spread_m`), so the hedge reads as one line, not beads;
  - gaps come from the run noise (`hedge_run_m`) at a lower cut, a few gateways per field, not half the hedge.
- The hedge TREES (oak, hornbeam) stand out of the line every `hedge_tree_every_m` (about 40–90 m).
- The old per-field hedge candidates (`hedge_chance` on `field_edges.png`) are removed. Their job moves to the hedge line.

**Budget.**
- Today `trees.bin` holds about 297k clumps.
- PR #57's per-field edges total about 11,000 km. The historical hedge lines are a fraction of that, to be measured in the bake.
- At 10 m spacing every 1,000 km of hedge is 100k clumps. The bake prints the total hedge km and clump count.
- `bench.gd` must hold every tier's budget at all three zooms, `--pan` included.
- If it does not, in this order:
  1. widen the spacing (the crowns' spread closes the line);
  2. thin the hedge first under a lower `tree_density` (`Map3DGeometry.thin_rank` already thins evenly);
  3. end the hedge cards earlier than the woods by their own far distance.

### 3d. What "balanced" excludes

No new 3D model and no hedge mesh pipeline. If the cards cannot carry the volume at the opening zoom, the bold option (Blender / Tripo hedge modules) comes back to the owner as its own decision.

## Phases

Each phase is its own commit series and goes through `visual-review`: 600 m, 1.5 km, 5 km and 30 km, blind independent critic, the bench before any merge.

| Phase | Content | Depends on |
|---|---|---|
| 1 | `hedge_lines.png` + balk vs hedge drawing + ground shadow + continuous `hedge_bush` + budget | today's zones (the hedge lines are zone boundaries, so they survive phase 2) |
| 2 | the open-field layout: effort reach, furlong regions by the fall line, brick furlongs, headlands, road / stream edges, assarts | — |
| 3 | meadow and pasture interiors | phase 2's zones |
| 4 | reverse-S strips (optional, judged and kept only if it reads) | phase 2 |

## Phase 1 as built (2026-10-13)

What changed against §3, and why:

- **Where.** The hedge lines are two levels, not three:
  - R is the township's **in-field**: open field, meadows and crofts as one whole, closed over `hedge_infield_close_m`, holes filled, islands under `hedge_infield_min_km2` dropped.
  - G is the **crofts**.
  - The meadows are NOT hedged: they were shared and mown like the open field. Hedged as their own level, every wet blob drew a hedge snaking along the rivers.
- **No circles.** A croft is decided per close (at its middle), not by a radius. The croft cut at a radius drew its hedge as a ring round every village, and a second ring round the houses; the village's own ground now counts as croft.
- **The encoding.** One channel per level, and the reader takes the least |distance| after each channel's own sample. A single channel holding the nearest line's distance crossed zero midway between two lines and drew a false hedge there.
- **Lanes.** Lanes are hedged only outside the in-field: a lane through the open field ran unhedged, and its clumps read as scattered beads.
- **No ground band** (`hedge` 0 in the look, the stage kept). 20% of the line has no bushes on it (gateways, roads, houses), and there the dark band read as a painted path. The blind critic ranked "no band" first at 600 m and 1.5 km. While it is off, the map is never loaded.
- **No shadow stage.** The cards cast real shadows out to `map3d_tree_card_far_m`, so the shadow stage in §3b was not built.
- **The hedge's own "never".** The woods' ground mask cut 26% of the hedge points, mostly the 50 m house clearance (every croft hedge) and the woods' slope limit. A hedge clump is tested at its own spot instead: `hedge_max_slope`, `hedge_house_clear_m`, and `hedge_road_clear_*` from the road's middle.
- **The croft closes' own hedges are off** (`hedge_chance` 0). Scattered on a jittered grid, they read as beads over the croft plots. The closes keep their darker rims.
- **The row.** `hedge_bush` has 5 crowns over 7 m, laid in a row along the line (`row` 1); a clump stands every 10 m. With 3 crowns the line read as beads.

**Numbers.**
- About 2,160 km of hedge: 216k row clumps and 43k hedge trees.
- `trees.bin` holds 498k clumps; it held 297k before.

**Bench** (`--pan`, ComfyUI open on the Mac, so the GPU was not idle). Both sides were over budget before this change too.

| Tier, zoom | Before (ms) | After (ms) |
|---|---|---|
| high, near | 17.3 | 17.6 |
| high, mid | 14.8 | 14.9 |
| high, far | 21.4 | 20.3 |
| low, near | 8.4 | 8.4 |
| low, mid | 10.3 | 10.7 |
| low, far | 12.0 | 14.7 |

The `- Trees` rows of the same runs move by ±2 ms, so the far rows are within noise. Re-run on an idle GPU before merge.

**The critic's open points** (blind, after phase 1):
- At 5 km, the opening zoom, the hedges read as thin dark dotted lines. #57's dark balks made a clearer patchwork there, because the open field's inside is now one sheet. Phase 2's furlongs and headlands are the answer, not a darker balk.
- A long in-field ring winds round a hill and reads like a contour line.
- The field rim's pale balk band is a little strong at 600 m.

## Phase 2 trials (2026-10-14): not kept

The owner's ruling, after the trials: drop the layout and fix the near strips instead (放弃布局，改修近景垄条).

**What was tried.** §1 was built in full, on the branch `feat/open-field-phase2-trials` (local, not merged): the effort reach, furlong regions, brick furlongs, headlands, lanes parting the furlongs, and assarts. Variants:

| Variant | What a blind critic saw |
|---|---|
| 600 m regions, headlands 2× | big tan sheets: a region's furlongs share a crop and a grain and run together |
| 400 m regions | a crazy-paving net of headlands and lane balks at 5 km |
| 350 m regions, ±0.25 rad per furlong | still muddy sheets at 5 km |
| phase 1's Voronoi blocks, strips down the fall line | neighbours on one slope agree and merge again |

Two critics ranked phase 1's Voronoi furlongs first at every zoom.

**Why it failed.** The historical rules, one grain per furlong region and strips down the fall line, make neighbouring blocks agree. The patchwork the opening zoom reads by is a contrast between neighbours.

**Measured on the way.**
- The effort reach costs farmland: k = 10 halved it, k = 2 took a fifth.
- The climb pushed the capital's fields off its hill.

## Near strips (2026-10-14)

Every critic named the same defect: at 600 m the arable round the capital was a flat straw sheet.

- **The crofts' corn plots are sown.** Most of what the 600 m view shows by the capital is its crofts, not arable. Their "plot" closes were never sown, so no strips were drawn on them. They are now sown, with their strips along the close.
- **The strip direction is read per texel (`Map3DGroundStrips`).**
  - Blending the direction across a 40 m texel swung the strips into arcs.
  - The nearest texel's direction cut the strip ends in 40 m steps.
  - The pattern is now drawn for each of the four texels round a pixel and blended. Each texel's own sown share weighs its pattern.
- **`strip_m` is 15**, down from 22. The critic: the strips read as house-row-wide painted bands.
- **Critic.** Blind, the croft strips came first at 600 m and 1.5 km, and tied at 5 km.

## Phase 3 as built (2026-10-14)

`bake_world.grass_interior` is applied to every grass field: croft grass, meadow and pasture. Every term only darkens or turns a channel down:

| Term | Driven by | Effect |
|---|---|---|
| Hollow | the height against its mean over `grass_relief_m`, or the river's wet band | darker and greener |
| Knoll | a rise over the same mean | warmer |
| Wear | nearness to the village, pasture and crofts only | browner |
| Cloud | two field-scale noises mixed by the field's own hash | a soft dark veil |

All keys are `grass_*` in `map3d_bake.csv`.

**Blind critic.** Three variants were shot:
- **×1**, the values above;
- **×2.5 in patches** (`grass_cloud_cut` 0.45);
- **before**.

×1 came first at all three zooms.
- ×2.5 read as a dark veil laid over the land.
- "Before" read as a khaki grade, duller, and the pasture no longer parted from the stubble.

**Open:** at 5 km the grass fields' inner variety nearly vanishes. The critic asks for a larger, lower-frequency variation to survive the opening zoom.

## Far view (2026-10-14)

- **The hedges' dark ink line at 3–5 km was the woods' canopy map.** `bake/woods.png` carries the wood where no tree is drawn. Hedge rows and hedge trees, smeared over 40 m texels, drew a dark line round every field. Now they count `hedgerow_canopy` (0) of themselves; the bankside rows keep theirs.
- **The rows' cards end at their own distance.** `map3d_tree_species.csv` has a new `far_m` column: `hedge_bush` ends at 2,000 m and fades over half of that. Godot fades an object after its end distance and measures to the 2 km chunk's middle, so with the woods' 2 km margin the rows stayed solid past 3 km.
- **A broad grass variation that reads at 5 km.** `grass_broad` (0.25) at `grass_broad_m` (900) turns the grass lusher or drier across several fields.
- **Blind critic.** The hedges fade into a soft texture of trees at 3 km, with no seam. The broad grass variation came first at 5 km, ahead of 0.14 and of none.
- **Open:** where the pale-green fields meet the pasture, the edge steps in 20 m stairs (a hard cut). A dark smudged band lies below the central fields.

## Tests

- `tools/map3d/test_bake_world.py`:
  - **Effort reach:** a hill at the same distance as a valley floor is reached later.
  - **Strip direction:** a furlong region on a slope runs down the fall line, within a tolerance.
  - **Headlands:** a strip end is nearer its headland than a long side is to its balk.
  - **Hedge lines:** an edge between two arable furlongs is not a hedge line; an arable/pasture edge and a croft edge are.
  - **Interiors:** a meadow field's tint is never lighter than its row's tint.
  - **Determinism:** the same seed gives the same bytes.
- `tools/map3d/test_bake_trees.py`:
  - hedge clumps stand within `hedge_band_m` of a hedge line;
  - none stands on a furlong-to-furlong edge;
  - the spacing holds.
- `tests/map3d`: the balk and hedge uniforms exist and are set from the look (the editor-owned-look test); the sun uniform reaches the ground material.
- `./run_tests.sh --fast` per commit; `tests/map3d` locally for the shader pieces.

## Acceptance

- **1.5 km and 5 km:** a blind critic describes the arable as long strip blocks in a patchwork that follows the land, not as similar rounded blocks.
- **600 m:** the hedge reads as a raised line with a shadow, and the furlongs inside a great field have no hedge.
- **Meadows:** a blind critic no longer calls any field "flat colour". No field is lighter than today.
- **30 km:** the patchwork's colour and the far view match today's.
- **Bench:** every tier within its budget.

## Open for the owner (defaults used unless the owner says otherwise)

1. **Strip direction on a slope: down the fall line** (drainage, the common case on clay). The alternative is along the contour.
2. **Hedge gaps: a few gateways per field.** PR #57 had long bare stretches.
3. **The reverse-S is optional** and judged last.
