# P6.1a — task kinds and search coverage (pure)

Scope: the first slice of P6.1 (`docs/superpowers/plans/2026-10-16-battle-system/
06-area-tasks-and-sieges.md`, "P6.1 授权区域与四类自动任务"). It lands only the
data and the pure pieces later slices use: the four area-task kinds as a CSV
table, and `TaskCoverage` — the integer grid of searched cells with the day each
was last searched. No saved state, no action, no movement, no UI.

P6.1 split (each its own PR, after the preceding merge):
1. **a (this)** `data/army/task_kinds.csv` + `DataRepository.task_kinds`;
   `TaskCoverage` (cell size from CSV, mark / searched_cells / cells_in_circle).
2. **b** `ArmyTasks.preview` — legal kinds, concrete objects, estimated route and
   courier delay, cost, supply floor, return point; reads only what the realm
   knows (Review Focus 1: `test_task_preview_does_not_reveal_hidden_state`).
3. **c** `ArmyTasks.issue` / `receive` through `ActionSystem` (order cost,
   courier delivery per unit, pending → received, revision replaces on arrival
   only); saved `GameState.army_tasks`.
4. **d** `ArmyTasks.step_day` search execution: stable cell order, last-searched
   day and route, actual scouting footprint, unreachable cells stay unsearched
   (Review Focus 2), encounter policy keep-distance/report vs approach.
5. **e** raid and destroy: finite real stores, carry cap, effect ids never
   repeated (Review Focus 3), facility revision.
6. **f** supply floor incl. the return and one packing day, battle pause and
   resume/return/fail, completion → camp.
7. **g** WAR ROOM circle UI (editor-authored; visual-review).

Spec: `docs/superpowers/specs/2026-10-16-battle-system-design.md` §13–14, §16.

## Contract

- `data/army/task_kinds.csv` (`kind,label,needs_target,default_encounter,
  allowed_encounters,notes`): rows `search`, `raid`, `destroy`, `siege` (the four
  kinds; implementer: confirm the four against the spec §13–14 and the plan's
  wording and record the mapping); indexed in `data/tables.csv`; loaded as
  `repo.task_kinds` (by kind).
- `data/army/balance.csv`: `task_cell_m` (whole metres per coverage cell, first
  draft 2 000).
- `TaskCoverage` (new `scripts/engine/task_coverage.gd`, pure, RefCounted):
  - `cell_of(repo, at_m: Vector2i) -> Vector2i` (floor division by
    `task_cell_m`, negatives floored).
  - `cells_in_circle(repo, center_m: Vector2i, radius_m: int) -> Array[Vector2i]`
    — every cell whose CENTRE lies within the circle (squared whole metres,
    inclusive), sorted by (y, x).
  - `mark(coverage: Dictionary, cells: Array[Vector2i], day: int)` — key
    `"x:y"`, value the newest day (never lowered).
  - `searched_cells(coverage) -> int` — unique cells.
  - `last_searched(coverage, cell) -> int` (−1 when never).

## Hand checks (tests/engine/test_task_coverage.gd)

- The plan's test verbatim: mark [(1,2),(1,3)] day 10, then [(1,2)] day 11 →
  2 cells, `coverage["1:2"] == 11`; marking (1,2) on day 9 later keeps 11.
- `cell_of` with 2 000 m cells: (0,0)→(0,0); (1 999, 2 000)→(0,1);
  (−1, −2 000)→(−1,−1).
- `cells_in_circle((3 000, 3 000), 1 500)` with 2 000 m cells: centres
  (1 000,1 000)… only cell (1,1) (centre (3 000,3 000)) is within 1 500 → [(1,1)];
  radius 2 000 → (1,1),(0,1),(1,0),(2,1),(1,2) (centres 2 000 away exactly) —
  sorted by (y, x): [(1,0),(0,1),(1,1),(2,1),(1,2)].
- `repo.task_kinds` has the four kinds.

## Implementer rulings pending the owner

1. The four kinds' exact ids and their defaults.
2. Cell size 2 000 m first draft; a cell counts when its centre is inside.

## Steps

1. Tests red. 2. CSV, index, loader, `TaskCoverage` green. 3. A short "Area
tasks" paragraph in `scripts/engine/guide/regiments.md` (or a new topic guide if
that guide is near its size cap — then add it to the engine `CLAUDE.md` index).
4. `--fast` green; one PR.

## Implementer rulings (P6.1a, as built)

1. Kind ids `search`, `raid`, `destroy`, `siege` map to spec 13.2 to 13.5 one to one. `needs_target`: search 0, raid 0 (the target KIND is an optional filter, 13.3), destroy 1 (the player names the object kind, 13.4), siege 1 (one named town, 13.5).
2. Encounter defaults: search `keep_distance` (allowed `keep_distance|approach`, 13.2). The spec defines the choice only for search, so raid, destroy and siege are `approach` only (a defended target is scouted and engaged, 13.3).
3. Cell size 2 000 m; a cell counts when its centre (2000 c + 1000) is inside the circle, inclusive. The plan's hand checks held unchanged.
4. A negative radius yields no cells; `cell_of` uses integer floor division, no floats.
5. The guide paragraph went into `guide/regiments.md` (27.6k of the 30k cap), no new topic guide.
