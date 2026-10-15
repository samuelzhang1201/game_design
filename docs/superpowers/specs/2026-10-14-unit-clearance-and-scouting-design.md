# Unit clearance, halting before an occupied target, contact and scout letters, the scouting fan

Date: 2026-10-14. Owner's request (Chinese, translated):

1. Military units on the map may never overlap — neither enemy nor own.
2. If a unit's target town/place is already occupied by another unit, the marcher halts IN FRONT of the occupant, on the side toward its own start, FACING it. If the occupant is an enemy, the player gets a missive with the basic facts — ground truth (seen with own eyes, at very close range).
3. Our marching armies get a scouting range: a faint sector in front of the army sweeping back and forth. An enemy inside it but not in contact → a HIGH-credibility missive. Range differs by arm; cavalry farthest.

## Owner rulings (2026-10-14)

- **Blocked by a non-enemy unit** (own or neutral): go round it, or wait in place when it cannot be passed. **Blocked by an enemy unit**: halt in front of it (clearance), face it, and the two are in contact — the battle system's contact rule takes over (battle, or a standoff when no battle starts). A column never paths round an enemy.
- This REVERSES the 2026-10-07 army-split §4 ruling ("columns pass through each other").
- Contact letter: everything exact (unit, arm, place, doing what) except men, which stay the narrowest estimate (`Sighting.about`); filed in the `truth` column.
- Scouting: a 120° sector per marching crown land unit; what it finds is ALSO drawn on the map (sight = the 12 km circle plus the sector).
- Contact letter trigger: the first close contact (within `battle_contact_km`) of ANY crown land unit, marching or standing; one per foe per episode (`scout_report_gap_days`).
- Accepted: two columns both moving may briefly cross on screen mid-day; clearance holds at every day's end and always against standing units.

## Owner rulings, second round (2026-10-15) and the design changes they made

- **R-A. Clearance is per arm**, sized to the drawn pieces so they never overlap on screen: `data/army/army_clearance.csv` (infantry 1140, archers 1850, cavalry 2200, artillery 1140, a fleet 0; a royal unit reads its chief arm) against the measured full-strength half extents 1132.8 / 1845.6 / 2197.2 / 1132.8. Two units' centres stay >= D = r_a + r_b apart; octagons, hulls and halt points use the pair's D; a town is touched within the seat unit's radius + the foe's + `army_clearance_touch_m`. `army_slot_spacing_m` is 4400 (>= 2 x the largest radius). `army_clearance_m` is gone: `army_clearance_on` 1/0 switches the rule. Two cavalry halted face to face (4401) still stand inside `battle_contact_km`. `tests/map3d/test_map3d_unit_clearance.gd` asserts radius >= half extent per arm and pitch >= 2 x the largest radius.
- **R-B. A host spreads round its target.** A foe column halted by a friendly within `army_spread_reach_m` (17600, four pitches: past the crown's outer camp ring, where a column facing an enemy camp halts) takes the nearest free camp-lattice slot round the target from ring 1 (`free_slot` with `near_m`, `held_taken`, as the spawn does); `SiegeSystem.at_town` counts that reach as at the town; a standoff is not re-aimed away by the host's daily `aim_entry` (`EnemyAi._stands_halted`: same aim, blocker in front and an enemy, or at a slot). An assault flag up makes any besieger at hand of the garrison storm the town, never open a field battle with the seat holder first.
- **R-C. Deadlock.** A column that has waited two days running (a closed way round, or the fourth pass of a detour) stops where it stands (order garrison, `road_blocked_by`); of two waiting on each other the LATER code stops. A crown unit's stop is the news line `army_road_blocked`; the AI re-plans.
- **R-D. Standing raider units are the crown's enemies** for clearance and contact: `_enemies` is kingdom hostility (the player's realm against the raider realm, or a diplomacy `Enemy` row), not crown-against-foes. They are halted in front of and faced, never gone round, and named in contact and scout letters (`Sighting.hostile_units`); the letter's realm word is the unit's own kingdom label (`{realm}`).

Design changes from the engine review: the geometry works on the disc of D + 1 with `r8` = ceil(D / cos 22.5) + 1 and ceil'd diagonals, so no whole-metre stop falls inside D; a unit already inside a disc is let go only while its next leg does not close on it (an enemy it closes on stops it on the spot); clumps join where octagons overlap (r8 + r8), hold only STANDING units (a column on the march is its own obstacle) within three pair radii of the first, and later passes keep the units earlier passes went round; the previews share one clearance record per state, day and set of places and read only the units near the walk; `CourierSystem.day_path_of` takes the points passed from `_march_one` (a detour's corners included); a seat is taken only while no unit stands within clearance of the town's point; a vacated seat stays empty until `reconcile` refills it (`ArmyGround.seat_of` readers handle the empty window).

## Design (architect plan, adopted)

### What exists
Positions are whole pack metres (`x_m`/`y_m`/`dest_*`) in `GameState.regiments` and `GameState.foes`, read via `ArmySystem.position_of`. `march_day` walks crown codes sorted then foe codes sorted through `_march_one` (even pace; `days <= 1` jumps to dest, order → garrison, then `ArmyGround.settle`). `march_ahead` runs `_march_one` on a copy (the view's day walk). `MarchPath` A* is on a 4 km grid (too coarse for clearance). `EnemyAi._march_host` re-aims idle columns to `target_point_m` daily; `EnemyAi.spawn` stacks a host on one point. `ArmyGround.is_free` refuses within half the slot pitch (750 m); `standing_taken` ignores marchers; camp lattice pitch `army_slot_spacing_m` 1500 (rounded neighbours 1499.97 apart). Facing: `facing_deg` whole degrees (0 east, 90 south, y-down); `WarFront.facing_deg(vec)` / `facing_vector(deg)`. Contact: `battle_contact_km` 5; town contact inside `army_town_reach.csv`. Sight: `Sighting.seen_foes` within `player_sight_km` 12 of crown land units with men and held towns; `about()` gives estimates, never exact men. Missives: columns `truth`, `credible`, `consult`, `rumour`, filed immediately with `MissiveLog.add`; words from `data/council/templates.csv` via `MissiveWriter`.

### (a) Non-overlap
- R1. Every land unit with men (crown, foes, roster at pack positions; fleets exempt) is a disc; centres stay ≥ C = `army_clearance_m` apart. C = 0 disables the rule.
- R2. Each column's day walk is clipped at the first point it would come within C of another unit, in the fixed order (crown sorted, then foes sorted), against others' current positions (earlier movers already moved). Escape: a unit the column already stands within C of does not block it.
- R3. Occupied destination (the blocker stands within C of the column's destination) OR the blocker is an ENEMY of the column (anywhere on the path): the column halts where its path enters the blocker's disc. That is an arrival: order garrison, dest = here, `halted_by` = blocker code, `halt_day` = today's absolute day, front hold dropped (`drop_hold`), `ArmyGround.settle` preferring the camp slot nearest the halt point (only for a non-enemy occupant; facing an enemy it stands where it halted), then `facing_deg = WarFront.facing_deg(blocker − position)`.
- R4. A non-enemy blocker not at the destination: go round. Clump = first blocker entered plus every non-enemy blocker within 2C of a member, transitively. Octagon round each member, radius R8 = ceil(C / cos 22.5°); convex hull (monotone chain, integer points). E/X = first/last crossing of path and hull; walk the hull from E to X on the shorter side (sum of edge lengths each rounded to whole metres); tie → RIGHT (cross(X−E, v−E) > 0, i.e. +y heading east in y-down). Each detour leg checked with the march grid `clear`; that side blocked → try the other; both blocked → WAIT at E (step 0, order stays march, retry next day). Splice the detour into `route_m`. Destination inside a clump hull → R3 instead.
- The clip lives in `_march_one(…, blockers := null)`; `march_day` builds blockers once and moves each unit inside them; `march_ahead` builds them from current state; forecasts (`march_days_between`, `_days_walking`) pass none ("if the road is clear").
- Also: `ArmyGround.is_free` refuses within C (half pitch when C = 0); `standing_taken` → `held_taken` includes marchers; `free_slot`/`settle` take optional `near_m` (nearest free slot within the first ring with free slots); `EnemyAi.spawn` spreads units with `free_slot` in code order (first on the assembly point); `ArmyGround.leave` no longer refills at once — `reconcile` refills an empty seat once no unit is within C of the town point; `BattleSystem._town_contact` contacts at ≤ max(reach, C + `army_clearance_touch_m`); `BattleSystem._start` makes the player the attacker also when its column's `halt_day` is today; `set_march_m`/`aim_entry` clear `halted_by`, `halt_day` (and `facing_deg` on a new destination); `facing_of` reads foes too.

### (b) Halt geometry
Segment a→b, occupant q: halt at the smaller root of |a + t(b−a) − q| = C in [0,1], rounded to whole metres; if rounding left it inside C, step back 1 m along the path until ≥ C. Straight last leg ⇒ q + C·unit(start − q). Facing = `WarFront.facing_deg(q − p)`.

### (c) Letters (no RNG draw)
- `data/army/army_scouting.csv` (arm, scout_km, arc_deg, notes): infantry 15/120, archers 18/120, cavalry 30/120, artillery 12/120, fleet 0/0. Royal unit reads its chief arm.
- Only crown land units with men and order MARCH scout: sector radius scout_km around `ArmySystem.heading_of`, inclusive, total arc arc_deg. Sight per viewer = `player_sight_km` circle + sector for marchers; `Sighting.seen_foes`/`update` include sector finds.
- Contact = a foe with men within `battle_contact_km` of any crown land unit with men.
- `GameState.scout_log`: foe code → {scout: last abs day, contact: last abs day}; old saves load {}.
- `Sighting.scout_day(repo, state)` daily, foe code order: in contact → contact letter if no entry or `today − contact > scout_report_gap_days`, then set contact and scout to today; else in a sector → scout letter if `today − scout > gap`, set scout; foe gone/no men → drop entry. At most one letter of each kind a day, one fact per newly reported foe.
- `MissiveWriter.contact_report` (kind `contact`, column `truth`), `MissiveWriter.scout_report` (kind `scout`, column `credible`), subject `"point"` at the first foe. Facts: roster label, arm word (`army_split.csv` label_word), `{raider_realm}`, place (`Intel.place_label`), doing (marching toward `WarFront.compass_words` / standing), men = `Sighting.about(men, player_sight_estimate_quality, 0)`, which of our units saw it. Templates `scout_title`, `scout_line`, `contact_title`, `contact_line`. `MissiveLog.SCOUT_KINDS = ["scout","contact"]`, keep key `missive_keep_scout`.
- Hook in `TickEngine._end_day` after host news, before `BattleSystem.settle_day`.

### (d) The fan (view)
- Crown land units with a piece, men, order MARCH (paused clock included). Never foes, ghosts, fleets, the war room.
- `Sighting.scout_shape(repo, state, code)` → {r_m, arc_deg} or {}; the layer calls it through `ctx.repo`/`ctx.state()` (map3d never reads `Game`). World radius = r_m × `meta.m_per_px` / `ArmySystem.metres_per_pack_px`.
- `scripts/map3d/map3d_unit_scout.gd` (RefCounted helper like `Map3DUnitGlow`): polar grid `scout_rings` × `scout_spokes`, UV u = angle share −1..1, v = radius 0..1, draped on `ctx.height_at` + `scout_lift_m`; a world-space sibling under Units, at the piece's drawn xz and `_yaw`; re-draped past `scout_redrape_m` / `scout_redrape_deg`; no owner.
- `scripts/map3d/unit_scout_fan.gdshader`: unshaded, cull disabled, depth test on, depth_draw_never, shadows/fog disabled; faint fill feathered at apex/rim plus a brighter wedge θ(t) = half_arc · sin(2π(TIME/period + phase)). Instance uniforms `half_arc`, `phase` (hash of the code) — listed in `CODE_OWNED`. Look values in `scenes/map3d/materials/unit_scout_fan.tres`, made in the editor. `Map3DPriority.SCOUT_FAN`.
- `Map3DSight.places_key` also hashes `order`, `dest_x_m`, `dest_y_m`.

## Data
- `data/army/balance.csv`: `army_clearance_m` 1400 (< `army_slot_spacing_m` 1500), `army_clearance_touch_m` 10.
- `data/army/army_scouting.csv` + `data/tables.csv` row.
- `data/intel/balance.csv`: `scout_report_gap_days` 3, `missive_keep_scout` 12.

## Hand-computed tests (C 1400, R8 1516, 45° part 1072)
See the plan's numbered cases, reproduced in `tests/engine/test_march_clearance.gd`, `tests/engine/test_army_clearance.gd`, `tests/engine/test_scouting.gd`, `tests/map3d/test_map3d_unit_scout.gd`:
1. Octagon round (10000,0): (11516,0),(11072,1072),(10000,1516),(8928,1072),(8484,0),(8928,−1072),(10000,−1516),(11072,−1072); edge midpoints 1400.62 from q.
2. Path (0,0)→(20000,0), blocker (10000,0): right detour E(8484,0)→(8928,1072)→(10000,1516)→(11072,1072)→X(11516,0)→(20000,0); both sides 4640.
3. Clump (10000,0)+(12000,0): (8484,0)→(8928,1072)→(10000,1516)→(12000,1516)→(13072,1072)→(13516,0).
4. Blocker (10000,300): north side (8608,0)→(8928,−772)→(10000,−1216)→(11072,−772)→(11392,0); left 3992 vs right 5290.
5. Both sides closed → kind "wait".
6. Q (10000,0), R (0,0)→(10000,0): R halts (8600,0), garrison, facing 0, halted_by Q.
7. Q (3000,4000): R halts (2160,2880), facing 53.
8. A (0,0), B (10000,0) both → (5000,0): A at (5000,0); B at (6400,0) facing 180, halted_by A.
9. Passer-by: Q (10000,0), R (0,0)→(20000,0) arrives; ≥ 1400 every day; route contains (10000,1516).
10. Escape: Q 800 m from R, R leaves.
11. Opening campaign: all land units pairwise ≥ 1400.
12. Spawn: first unit on start, others ≥ 1400, infantry second at start + (1500,0).
13. Village town contact: 1405 m → contact, 1411 → none.
14. Crown column halting at a standing foe attacks.
15. Invasion end-to-end: pairs ≥ 1400 every day, across save/load.
16–21. Scouting: cavalry sector 30 km inclusive (30001 not), infantry 15, ±60°, garrison sees no sector; one letter then gap; contact in truth; rng untouched; scout_log saves; contact letter id before battle letter.
22–24. View: cavalry 1500 world m, infantry 750; mesh vertex count; only marching crown units get a fan.
Plus enemy-blocker cases: a crown column whose path meets a foe (not at the destination) halts in front of it facing it, no detour.
