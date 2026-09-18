# Relief detail — the height field gets landforms of its own

## Decisions (owner, 2026-09-17)

- The dark tactical satellite look (reference: `docs/references/Screenshot
  2026-09-17 at 17.36.09.png`) is the goal that exposed this. The spike proved
  the COLOUR half is cheap and reversible; the blocker is the height field.
- **Approach A**: synthesized fractal detail over the whole land, weighted by
  height, not confined to high ground.
- The detail is SYNTHESIZED, not interpolated. `geography/vertices.csv` carries
  `vertex_id,x,y` and **no height**; the only real elevation is one integer per
  Voronoi cell in `cells.csv`. There is no finer truth to recover.
- Rivers and coasts are real pack data and must not be contradicted: an invented
  ridge may not cut across a river valley or ride over the shoreline.
- The detailed relief is wanted **whether or not the dark palette is adopted** —
  it improves the current bright map too. The two decisions are independent.

## The problem, measured

| | |
|---|---|
| canvas | 2560 x 929 native px |
| `world_relief.png` | **1280 x 465**, L8 (`map_relief_scale` 2) |
| cells | 4833 total, **3500 land** |
| real detail | one height per **~680 native px** of land — a cell is ~26 px across |
| at the z4 framing | zoom 5.87, so one cell spans **~150 screen px** |

The hillshade therefore reads as smeared thumbprints: those blobs *are* the
individual Voronoi cells, box-blurred together. Raising `map_relief_shade`
0.20 → 0.42 during the spike made it worse, not better — there is no
information in the field to reveal. Heights are ints 1..100 (land 20..100,
median 34, 90th percentile 61).

## Pipeline (`tools/bake_relief.gd`, `MapIndex`)

All of it stays an offline bake. Nothing here runs at runtime.

1. **Base field at 1:1.** `map_relief_scale` 2 → 1, so the field is baked at
   2560 x 929. Otherwise unchanged: each pixel its cell's height, two
   `box_sum` passes at `map_relief_blur_px`.

2. **Suppression masks**, both at 1:1, both reusing the existing distance
   transform:
   - **Rivers** — stamp each `rivers.csv` `points` polyline into a
     `PackedByteArray` with a new `MapIndex.stamp_polylines`, the stamp radius
     scaled by that river's `discharge`. Hand the mask to the EXISTING
     `MapIndex.distance_to_land(mask, w, h)`, which seeds distance 0 at every
     non-zero pixel — so it returns distance-to-river in px with no new
     algorithm.
   - **Coast** — the same, from `coasts.csv` rows with `kind == "land"`.
   - Amplitude multiplier per pixel:
     `smoothstep(0, map_relief_detail_river_px, d_river) *
      smoothstep(0, map_relief_detail_coast_px, d_coast)`

3. **Detail field.** `FastNoiseLite`, `TYPE_SIMPLEX` with `FRACTAL_RIDGED`,
   frequency `1 / map_relief_detail_freq_px`, `map_relief_detail_octaves`,
   seeded from `map_relief_detail_seed`. Ridged fractal because ridgelines are
   the feature the reference reads by; domain warp so ridges run in coherent
   directions rather than as isotropic blobs.

4. **Weight by height, then sum.** `h_norm = clamp((height -
   map_relief_detail_floor) / (100 - map_relief_detail_floor), 0, 1)`, and the
   detail is added as `map_relief_detail_gain * h_norm * suppression * noise`.
   Approach A applies everywhere, but lowland detail is *small*, not absent, so
   plains stay legible while mountains grow ridges. Clamp to 0..255, write L8.

5. **`raise_high_ground` re-bands from the DETAILED field** so rock and snow
   follow a synthesized ridge instead of the flat cell value. It currently
   takes `heights: PackedInt32Array` per cell; it gains an optional detailed
   field and prefers it when given, keeping the per-cell path for the tests.

## Runtime

Nothing changes. `BiomeLayer` still loads `maps.csv` `relief_texture` into the
shader's `relief` sampler; only the file's resolution and content differ. The
field is the single consumer — confirmed by grep, and no test asserts its size.

Two follow-ups, not new mechanism:

- `map_relief_shade_px` (8 native px between slope samples) was tuned against a
  blurred field. With real detail it should come down; retune after the first
  bake rather than guessing now.
- The `exposure` / `saturation` uniforms added to `biome_tiles.gdshader` during
  the spike stay. They default to 1.0 / 1.0 and a re-render proved the default
  output byte-identical, so they are inert until something sets them.

## Balance keys (new — design values are data, never constants)

| key | meaning |
|---|---|
| `map_relief_scale` | 2 → **1** (the field is baked at full canvas) |
| `map_relief_detail_seed` | the detail's fixed seed — a look, never simulation |
| `map_relief_detail_freq_px` | wavelength of the coarsest octave, native px |
| `map_relief_detail_octaves` | octaves of ridged fractal |
| `map_relief_detail_gain` | amplitude in height units (0 = off) |
| `map_relief_detail_floor` | height below which detail fades toward nothing |
| `map_relief_detail_river_px` | how far a river holds the detail down |
| `map_relief_detail_coast_px` | the same for the shoreline |

## Tests (GUT)

- `stamp_polylines` marks the pixels a segment crosses and nothing else, on a
  hand-computed small case.
- Distance mask: a pixel on a stamped river reads 0, one N px away reads ~N.
- **`map_relief_detail_gain` 0 reproduces today's field exactly** — this is the
  guard that keeps the two existing `bake_relief` tests
  (`test_bake_relief_writes_cell_height_as_grey`,
  `test_bake_relief_smooths_across_cells`) passing unchanged.
- Detail amplitude is 0 on a river pixel and full far from one.
- Determinism: two bakes with the same seed are byte-identical.

## Risks

- **Bake cost.** `bake_relief` is per-pixel GDScript and currently runs at 1/2
  scale; 1:1 is 4x the pixels plus noise and two distance transforms.
  **Measuring this is step one of implementation**, before any tuning. If it is
  too slow the fallback is 1:1 for the relief only, leaving
  `map_biome_weights_scale` at 2.
- **Invented terrain contradicting other pack data.** Rivers and the coast are
  suppressed explicitly. Roads and settlements also sit in valleys, but they are
  drawn over the ground rather than cut into it, and they are point/line
  features at a much smaller scale — accepted, and worth a look at the first
  bake.
- The reference's credibility comes from real per-pixel DEM. Synthesized ridges
  will read as *plausible* terrain, not as a real place; if that is not enough,
  the honest answer is that this map cannot become a satellite photograph.

## Out of scope

- The dark tactical palette itself. The spike lives behind
  `tools/snapshot_map.gd --dark 1` as runtime overrides; adopting it is a
  separate decision with its own furniture questions (blackletter labels,
  heraldic borders, the compass, ships and whales all conflict with it).
- Re-generating the biome tiles in darker colours.
- Settlement art. The four C-rounds are paused; whatever is chosen there will
  need re-judging against whichever ground wins.
