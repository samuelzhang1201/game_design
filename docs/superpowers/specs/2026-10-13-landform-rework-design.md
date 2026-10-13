# Landform rework: valleys, ridges and drainage the sun can model

**Status:** plan only, pending the owner's three rulings below. The owner approved the rework itself on 2026-10-13 ("同意重做高度图,先写方案"); nothing is baked until the rulings land.

**Trigger.** After phase 2 art, the critics scored the map 6 / 10 at the opening zoom and 5 / 10 for the mountains, against about 9 for Civ VII. Their remaining gap #1: "hills and ranges are colour on a near-flat surface". The critic and the earlier snow tests called the range tops plateaus.

## Diagnosis (measured on the committed beria bake, `height_war.r16`)

**The high ground is not flat.**

| Height band | Median slope |
|---|---|
| 1000–1500 m | 0.40 |
| 1500–2000 m | 0.53 |

Under 5% of it is below 0.1, and no terrace spikes appear.

**The river corridors make the land read flat.**
- **One slope dominates.** 33% of all land has a slope of exactly 0.33–0.37, a spike about 10× the rest of the histogram. That value is `river_bank_slope` 0.35.
- **Each river is a smooth, even trench** up to `river_bank_max_m` 1500 m wide, starting in a round bowl at its source.
- **Ridges and terraces are cleared around every river:** `river_fade` (`bake_world.py` ~560) removes the ridges within 1000 m of every course, and the terraces within 600 m.
- **What is left between the trenches** is blobs of ridged noise 380–750 m across, with no line and no drainage. That is the "colour on a smooth surface" the critics see.

The ridged-noise amplitude and octaves are hard-coded (`RIDGE_*`, `bake_world.py` 54–62), which breaks the rule that design values live in data.

## What changes downstream

| Reads the height | Effect |
|---|---|
| `bake_march_grid.py` → `data/maps/<id>/geography/march_grid.png` | **Gameplay.** Which cells a column, courier or wagon goes round: routes, march days and courier roads change. Today 3,821 of 45,791 land cells are closed (8.3%). |
| `rivers.json`, `houses.csv` (pads, ports, walls), trees, relief AO, baked roads, rivers and bridges, the war room's contours | Look only. Re-baked and committed. |
| Engine height: `Elevation.metres_of_cell` (battle `height_factor`, supply tiers, landmarks) | **Unchanged.** It reads `cells.csv`, not the 3D bake. |
| Save / `GameState` | Only `route_m` of marches already under way. Those stay valid; new routes change. Determinism holds, since the grid is committed pack data. |

## The plan

**Phase 0 (needed for every option): fix the river corridor in `bake_world.py`.**
- **`river_fade`:** reaches full width only `river_head_m` downstream of the source, so a valley starts in a V-notch, not a bowl.
- **`carve`:**
  - A concave bank profile (`river_bank_profile`).
  - A slope varied by slow noise (`river_bank_slope_jitter`).
  - `river_bank_max_m` 1500 → about 600.
- **Move `RIDGE_*` into `map3d_bake.csv`:** as `relief_ridge_waves_m`, `relief_ridge_gain`, `relief_ridge_m`, `relief_ridge_from_m`, `relief_ridge_full_m`, `relief_ridge_coast_m`. `ridge_lo` / `ridge_hi` / `ridge_weight` already name the rock texture, hence the `relief_` prefix.

**Option C: Phase 0 alone, with `terrace_strength` lowered.** The smallest change; a cheap A/B first.

**Option B: oriented, domain-warped ridges on the high ground.**
- The ridge noise is stretched along the base gradient (`relief_ridge_warp_m`, `relief_ridge_aniso`) and sharpened (`relief_ridge_sharp`), so spurs run downslope.
- Cheaper, with lower risk to houses and rivers. It makes no real drainage.

**Option A (recommended second): stream-power erosion on a coarse grid.**
- **Method**, after the terraces and before the carve, on an `erosion_cell_m` (about 100 m) grid:
  1. priority-flood pit fill;
  2. D8 flow routing, sorted by a stable argsort;
  3. `erosion_iters` of implicit Braun–Willett erosion (`erosion_k`, `erosion_m_exp`, `erosion_n_exp`);
  4. a thermal pass (`erosion_talus`).
- **Applying it:** only the change in height is upsampled and added. It fades in from `erosion_from_m`, is held off the coast and towns, and is capped by `erosion_max_cut_m`.
- **Deterministic:** no RNG and no wall-clock.
- **Effect:** branching gullies and continuous crests, the Civ VII read.
- **Risk:** highest. More march cells close, port slopes steepen, and `port_plain` may log more cuts over 45 m.

**Suggested order:** Phase 0 + C as one A/B round; then A if C is not enough.

Each round re-bakes and commits the whole pack: `height_war.r16`, `march_grid.png`, `rivers.json`, `houses.csv`, trees, relief AO, layers and the world scene.

## Tests (Python, `tools/map3d/test_bake_world.py`; no engine formula changes)

- **Implicit stream-power, one step:**
  - A chain of 4 cells, dx = 100, k = 10, m = 0.5, n = 1; heights [300, 200, 100, 0] with the outlet held; drained area A = [1, 2, 3, 4].
  - Each cell becomes h = (h + F·h_rcv)/(1 + F), with F = k·√A/dx, worked from the outlet upstream.
  - Expected **[289.616, 185.781, 85.237, 0]**.
- **Thermal pass:** two cells 100 m apart, heights [100, 0], talus 0.5. The transfer is (100 − 50)/2 = 25, giving **[75, 25]**.
- **Flow accumulation:** a 3×3 plane tilted east gives [1, 2, 3] along each row.
- **`river_fade` at a source:** at least 0.5 of full at 0.5 × reach, and 0 at `river_head_m` downstream.
- **Existing tests:** `test_terrace_*` and `test_carve_*` are kept, or updated with the new profile's hand values.

## Verification

- **Visual review:**
  - Real-window shots at 2560×1440: 600 m, 5 km, and 15 km over the central range and a river valley.
  - War-room sheet shots, since its contours change.
  - An independent critic against `taste.md` and the Civ VII frame.
- **Metrics, before and after:**

  | Metric | Now | Target |
  |---|---|---|
  | Land at slope 0.33–0.37 | 33% | < 8% |
  | Relief within 1 km of a river | 340 m | — |

  Also record slope p50 / p90 per height band.
- **March-grid diff:** cells opened and closed (now 3,821 closed). **Gate:** if more than 4,600 close, retune `army_max_slope`, or stop for the owner.
- **Houses:**
  - The per-burg count diff.
  - Every port keeps its timber pier (`test_map3d_houses_bake`).
  - Count the `port_plain` log lines.
- **Rivers:** every water line still falls, no river is lost, and joins stay within `river_join_m`.
- **Performance:** `tools/map3d/bench.gd` on an idle GPU.
- **Tests:** `./run_tests.sh --fast`, plus `tests/map3d` and `tests/war_room`. Tests that use the pack grid will need updated values, among them `test_courier_dispatch`, `test_road_graph` and `test_march_route_orders`. `sim_invasion`'s state hash will change.

## Rulings needed from the owner

1. **May routes change?**
   - (a) The march grid follows the new relief. This is the 2026-10-10 rule: the slope a column is refused is the slope the map *draws*.
   - (b) The same, plus a retune of `army_max_slope` so about the same share of land stays closed.
   - (c) Keep the old grid. This breaks the rule.

   Recommended: (b).
2. **First round:** Phase 0 + C, then A. Recommended.
3. **May the landmark "N m" labels drift?** They show engine cell metres, which are unchanged, so they may differ from a redrawn peak by up to `erosion_max_cut_m`. Recommended: yes, capped at 100 m.
