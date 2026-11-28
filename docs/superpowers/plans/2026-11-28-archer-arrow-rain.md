# Archer arrow rain — step 1, the arrow layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** archer figures loose one drawn arrow each at their ATTACK release; it arcs to the nearest foe unit's figures, sticks in the ground and fades.

**Architecture:** `Map3DVolley` (pure static math: release crossing, landing, arc) and `Map3DVolleys` (live arrows → one authored MultiMesh), run from `Map3DDuelDriver.step` (the layer is at its shape cap). View-only.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-28-archer-arrow-rain-design.md`

## Global Constraints

- No engine state, save field or RNG draw; hashes via `Map3DMarchLag.unit(key)`; no `Game` read under `scripts/map3d/`.
- Look in `scenes/map3d/effects/arrow_volley.tscn` (+ `arrow_volley_mesh.tres`), authored through the editor (gdai MCP); reached via `GameArt.ARROW_VOLLEY`.
- Values `map3d_volley_*` in `data/screens/map3d/balance.csv`; the release share in `army_art.csv` archers `contact` as `ATTACK:<share>` (measured off the clip: the key where `cc_arrow`'s scale drops to 0.001, frame / last frame).
- Rebase on main after `archer-duel-hits` merges before editing `army_art.csv` or `map3d_duel_driver.gd`.

## Review Focus

- The clip wraps between frames (share 0.68, last pos 0.95, now 0.05) → still exactly one release. Test in Task 1.
- Paused clock (delta 0) → no release, arrows stand. Test in Task 2.
- No foe piece drawn (ghost/unseen) → no arrow, no error. Test in Task 2.
- At the cap `map3d_volley_max` → a new release is skipped, nothing grows. Test in Task 2.
- A figure freed mid-flight (fell, piece dropped) → its arrows fly on and expire. Test in Task 2.

---

### Task 1: `Map3DVolley` (pure)

**Files:** Create `scripts/map3d/map3d_volley.gd`; Test `tests/map3d/test_map3d_volley.gd`

**Interfaces — Produces:**
- `static func released(prev: float, now: float, share: float) -> bool` — shares 0..1 of the clip; true if `share` in (prev, now], or the clip wrapped (now < prev) and share in (prev, 1] ∪ [0, now].
- `static func landing(key: String, n: int, targets: Array, scatter_m: float) -> Vector2` — `targets` = Array of Vector2 stand points; picks `targets[floor(unit(key|n|t) * size)]`, adds an offset of radius `sqrt(unit(…|r)) * scatter_m` at angle `unit(…|a) * TAU`.
- `static func flight_s(dist: float, tune: Dictionary) -> float` — `clampf(dist / tune.speed_m, tune.min_s, tune.max_s)`.
- `static func at(from: Vector3, to: Vector3, s: float, apex: float) -> Vector3` — `from.lerp(to, s) + Vector3.UP * 4.0 * apex * s * (1.0 - s)`.
- `static func heading(from: Vector3, to: Vector3, s: float, apex: float) -> Vector3` — normalized derivative `(to - from) + UP * 4 * apex * (1 - 2s)`.

- [ ] Test: `released(0.6, 0.7, 0.68)` true; `released(0.69, 0.7, 0.68)` false; `released(0.95, 0.05, 0.68)` false; `released(0.95, 0.05, 0.02)` true; `released(0.5, 0.5, 0.5)` false. `flight_s(100, {speed_m=50,min_s=1,max_s=3})` = 2.0, `(10,…)` = 1.0, `(1000,…)` = 3.0. `at(A, B, 0.5, 10)` = midpoint + (0,10,0); `at(A,B,0,10)` = A; `at(A,B,1,10)` = B. `heading` at s = 0.5 is level (y = 0). `landing` same inputs → same point; within `scatter_m` of one of the targets; `n` changes it.
- [ ] Run `./run_tests.sh --test tests/map3d/test_map3d_volley.gd` → FAIL, implement, → PASS; commit.

### Task 2: `Map3DVolleys` (live arrows, MultiMesh)

**Files:** Create `scripts/map3d/map3d_volleys.gd`; Test `tests/map3d/test_map3d_volleys.gd`; Modify `data/screens/map3d/balance.csv` (keys below)

**Interfaces — Consumes:** Task 1. **Produces:**
- `func run(shots: Array, delta: float, running: bool, tune: Dictionary) -> void` — `shots`: `[{key, share_was, share, release, from: Vector3, h: float, targets: Array[Vector2], ground: Callable(Vector2)->float}]`; spawns, advances, sticks, fades, frees.
- `func live() -> Array` — `[{from, to, t, flight_s, apex, h, stuck_t}]` (tests).
- `func write(mm: MultiMesh) -> void` — one instance per live arrow: basis looking along `heading`, scaled by `h`; stuck arrows' alpha `1 - fade share` in the instance colour.
- `static func tune_of(repo) -> Dictionary` and `static func shots_of(ctx, battles) -> Array` (from `Map3DDuelDriver.gather`-like battles: shooters = group children playing ATTACK with a `contact` ATTACK share and no `duel` meta; targets = the other side's drawn pieces' stand points, nearest piece only).
- Keys: `map3d_volley_near_m` 300, `_from_h` 0.75, `_speed_m` 120, `_min_s` 1.2, `_max_s` 3, `_apex` 0.35, `_scatter_h` 1.5, `_sink_h` 0.15, `_stick_s` 4, `_fade_s` 1.5, `_max` 400 (first guesses; tuned in Task 4).

- [ ] Tests (bare RefCounted, no scene): one shot crossing → one arrow; same share again → none; `running` false → no spawn and `t` unchanged; empty `targets` → none; at `max` → skipped; after `flight_s` the arrow is stuck at `to` minus `sink_h·h` along heading; after `stick_s + fade_s` it is gone; `write` sets `instance_count` = live count.
- [ ] Run → FAIL, implement, → PASS; commit.

### Task 3: wire it (after rebase)

**Files:** Modify `scripts/map3d/map3d_duel_driver.gd` (a `volleys` member, made with the MultiMesh node instanced from `GameArt.ARROW_VOLLEY` under the pieces' parent, run in `step`), `data/screens/map3d/army_art.csv` (archers `contact` + `ATTACK:<measured>`), `scripts/engine/game_art.gd` (`ARROW_VOLLEY`), editor: `scenes/map3d/effects/arrow_volley.tscn`, `arrow_volley_mesh.tres`; guides `scripts/map3d/guide/battle_duels.md` (a Volleys bullet), `tools/units3d/archer_parts/README.md` (ATTACK played row).
- [ ] Test `tests/map3d/test_map3d_volley_wiring.gd`: archers' row parses an ATTACK contact in (0,1); the scene loads as a `MultiMeshInstance3D` with a mesh; `test_map3d_duel_data`, `test_editor_owned_look`, `test_map3d_editor_owned_look`, `test_map3d_shape` still pass.
- [ ] Commit.

### Task 4: visual review

- [ ] `visual-review` skill: `snapshot_screen --battle-case field --battle-arm archers --zoom3d 260` real-window shots, a `--write-movie --fixed-fps 30` clip; tune mesh thickness and the CSV first guesses; independent critic; bench `tools/map3d/bench.gd --battle-arm archers` vs main.
- [ ] PR with `prd_step:`, `player_outcome:`, `wired:`.
