# Data Folders by Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `data/`'s 106 flat tables into scene folders, split `balance.csv` into one `balance.csv` per folder, and delete the 14 dead keys — with no change to what the game computes.

**Architecture:** A committed index `data/tables.csv` (`folder,table`) names each table's folder; `DataRepository.table_path()` resolves through it and `DataRepository.load_balance()` merges every folder's `balance.csv` into the one `balance` dict, so `bal()` and its ~1100 callers stay as they are. Guards pin the index to the disk, forbid duplicate keys, keep the engine off `screens/` keys and forbid stale flat paths.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, Python 3 for the bake tools.

**Spec:** `docs/superpowers/specs/2026-10-11-data-folders-by-scene-design.md`, with `2026-10-11-data-folders-table-map.csv` (folder,table) and `2026-10-11-data-folders-key-map.csv` (folder,key,…) beside it.

## Global Constraints

- Work in `.claude/worktrees/balance-folder` (branch `worktree-balance-folder`); land through one PR against `main`.
- Folders: `realm ledger council economy army battle intel story world screens/ui screens/map3d screens/war_room screens/ledger`; `data/maps/<id>/` and `data/CLAUDE.md` stay where they are.
- Every folder's balance file is `<folder>/balance.csv` with header `key,value,notes`.
- No table or key is renamed; no value or note text changes (except the 14 deleted rows).
- New CSVs are written UTF-8, LF line endings, no BOM, quoting only where a field needs it (Python `csv.writer(f, lineterminator="\n")`).
- Determinism: balance files load in sorted folder order; the merged dict must equal today's minus the 14 keys.
- The 14 dead keys: `war_hud_head_px war_hud_head_half_px war_hud_reading_px war_hud_reading_outline_px war_hud_reading_gap_px war_hud_halo_alpha war_hud_chalk_px war_hud_min_len_px war_plan_ring_min_mm map_show_markers map_lod_marker_scale map_pick_radius_px map_line_pick_px raid_appear_day`. `war_hover_budget_ms` stays.
- Engine-reads-screens exemptions (exactly these 21): `map_altitude_gain map_light_x map_light_y map_lod_town_pop map_lod_town_scale map_lod_village_scale map_manor_alpha map_manor_crown_deep map_manor_foreign_pale map_manor_house_sat map_manor_house_val map_manor_saturation map_manor_shade_levels map_manor_shade_step map_manor_value map_relief_max map_relief_min map_relief_strength map_terrain_blend province_card_max_towns ui_war_table`.
- `tests/engine/test_claude_md_size.gd` caps: root 20000 chars, nested 30000.
- Dated files under `docs/superpowers/specs|plans` are never rewritten.

## Review Focus

1. The owner edits a `balance.csv` in Numbers/Excel and it comes back with CRLF or a BOM — the loader must still read the first key (Task 2 test `test_balance_reads_crlf_and_bom`).
2. A key pasted into a second folder's `balance.csv` — the load must fail naming both files, not let one silently win (Task 2 test `test_duplicate_key_fails_naming_both_files`).
3. A new CSV dropped into a folder but not listed in `tables.csv` — must fail a test, not be silently unread (Task 4 `test_every_csv_on_disk_is_indexed`).
4. The editor's `@tool` look path (`UiPalette.data()` → `DataRepository.load_look`) must still find the look tables and the screen keys after the move (Task 3 runs `tests/ui`, `tests/map3d`, `tests/war_room`; `test_editor_owned_look` covers it).
5. A bake run after the move reads the same numbers it did before (Task 3 step: compare the Python helper's balance dict to the GDScript one's key set and values).

---

### Task 1: Delete the 14 dead keys

**Files:**
- Modify: `data/balance.csv` (remove the 14 rows)
- Modify: `tests/engine/test_map_objects.gd:21-23` (drop `map_lod_marker_scale`, `map_pick_radius_px`, `map_line_pick_px`, `map_show_markers` from the stand-in dict)
- Modify: `tests/engine/test_battle_data.gd:56` (drop `"raid_appear_day"` from the expected-keys list)

- [ ] **Step 1:** Confirm each key is still unread: `grep -rn "<key>" scripts tools tests` returns only the two test lines above (and nothing for the other ten).
- [ ] **Step 2:** Remove the 14 rows from `data/balance.csv` and the test mentions.
- [ ] **Step 3:** Run `./run_tests.sh --fast`. Expected: passes with the usual error count (2 with the gdai binaries installed).
- [ ] **Step 4:** Commit `chore(data): drop 14 balance keys no code reads`.

### Task 2: `table_path` and `load_balance` in DataRepository

**Files:**
- Modify: `scripts/engine/data_repository.gd`
- Create: `tests/fixtures/data_layout/tables.csv`, `tests/fixtures/data_layout/alpha/balance.csv`, `tests/fixtures/data_layout/alpha/things.csv`, `tests/fixtures/data_layout/beta/balance.csv`, `tests/fixtures/data_layout/dup/…` (see tests)
- Test: `tests/engine/test_data_layout_loader.gd`

**Interfaces:**
- Produces:
  - `static func table_path(dir: String, table: String) -> String` — `dir + "/" + folder + "/" + table + ".csv"`, where folder comes from `<dir>/tables.csv` (columns `folder,table`; `table` without `.csv`). The index is parsed once per `dir` and cached in a `static var _index_cache: Dictionary`. An unknown table sets `last_error = "tables.csv has no row for <table>"` and returns `dir + "/" + table + ".csv"`.
  - `static func table_folders(dir: String) -> Array[String]` — the index's distinct folders, sorted.
  - `static func load_balance(dir: String) -> Dictionary` — for each of `table_folders(dir)`, reads `<dir>/<folder>/balance.csv` if it exists (`key,value` required) into `{key: float(value)}`; on a repeated key sets `last_error = "balance key <key> is in both <folder_a>/balance.csv and <folder_b>/balance.csv"` and returns `{}`; on a parse failure returns `{}` with `parse_csv`'s error.

- [ ] **Step 1: Write the failing tests** (fixture dir `res://tests/fixtures/data_layout`; `tables.csv` rows `alpha,things` and `beta,others`; `alpha/balance.csv` `k_one,1,a note, with comma` (quoted); `beta/balance.csv` `k_two,2.5,`):
  - `test_table_path_resolves_through_the_index`: `table_path(F, "things") == F + "/alpha/things.csv"`.
  - `test_unknown_table_sets_last_error`: `table_path(F, "nope")` → `last_error` contains `"nope"`.
  - `test_balance_merges_every_folder`: `load_balance(F) == {"k_one": 1.0, "k_two": 2.5}`.
  - `test_duplicate_key_fails_naming_both_files`: a second fixture dir `data_layout_dup` whose `alpha` and `beta` balance files both hold `k_one` → `{}` and `last_error` contains `"alpha/balance.csv"` and `"beta/balance.csv"`.
  - `test_balance_reads_crlf_and_bom`: fixture `data_layout_crlf/alpha/balance.csv` written with a UTF-8 BOM and CRLF endings → `load_balance` returns `{"k_one": 1.0}`. If `parse_csv` keeps the BOM in the first header cell, strip `"﻿"` from the first header cell inside `parse_csv`.
  - `test_folder_without_balance_is_skipped`: a folder in the index with no `balance.csv` is fine.
- [ ] **Step 2:** Run `GODOT -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_data_layout_loader.gd -gexit` (or `./run_tests.sh --fast`). Expected: FAIL, `table_path` not found.
- [ ] **Step 3:** Implement the three functions with the signatures above (and the BOM strip if Step 1 showed it was needed). Leave `_load` / `load_look` untouched in this task.
- [ ] **Step 4:** Run the test file. Expected: PASS. Run `./run_tests.sh --fast`. Expected: green.
- [ ] **Step 5:** Commit `feat(data): table index lookup and per-folder balance loading`.

### Task 3: Move the tables and split the balance

**Files:**
- Create: `data/tables.csv` (106 rows, from the spec's table map, in its order)
- Move (`git mv`, content untouched): all 106 `data/<table>.csv` → `data/<folder>/<table>.csv`
- Create: `data/<folder>/balance.csv` × 13; Delete: `data/balance.csv`
- Create: `tools/data_index.py`
- Modify: `scripts/engine/data_repository.gd`; every file under `scripts/`, `tools/`, `tests/` that names `data/<table>.csv` or `data/balance.csv`
- One-off migration script: kept in the session scratchpad, NOT committed

**Interfaces:**
- Consumes: Task 2's `table_path`, `table_folders`, `load_balance`.
- Produces:
  - `tools/data_index.py`: `table_path(name: str) -> str` (absolute path under the repo's `data/`) and `balance() -> dict[str, float]` (same merge and duplicate rule as `load_balance`), both reading `data/tables.csv`.

- [ ] **Step 1: Snapshot today's dict.** Before touching anything, dump `DataRepository.load_all("res://data").balance` (sorted `key=value` lines) to the scratchpad as `balance_before.txt` with a headless `-s` script.
- [ ] **Step 2: Write the migration script** (scratchpad) that: writes `data/tables.csv`; runs `git mv` per table; splits `data/balance.csv` rows by the key map's folder column, keeping each row's exact `value` and `notes` and the original row order within a file (a key in the key map but absent from `balance.csv` — the 14 deleted — is skipped; a key in `balance.csv` but absent from the key map aborts the run); `git rm data/balance.csv`; rewrites path strings:
  - in `scripts/engine/data_repository.gd`: `dir + "/<table>.csv"` → `table_path(dir, "<table>")` (111 sites) and the two `dir + "/balance.csv"` reads → `load_balance(dir)` (keep the existing `is_empty()` → fail behaviour);
  - in other `.gd` code: `"res://data/<table>.csv"` → `DataRepository.table_path("res://data", "<table>")`; the three `tools/bake_*.gd` `_balance()` helpers → `DataRepository.load_balance("res://data")`;
  - in `.py`: the two `balance()` readers (`tools/map3d/bake_march_grid.py`, `tools/map3d/bake_world.py`) → `data_index.balance()`; other `"data", "<table>.csv"` / `data/<table>.csv` → the folder path literally;
  - in comments and strings everywhere under `scripts/ tools/ tests/` (`.gd .gdshader .py .sh .tscn .tres`): `data/<table>.csv` → `data/<folder>/<table>.csv`, `balance.csv` next to a key → `<folder>/balance.csv` of that key.
- [ ] **Step 3:** Run the migration. `git status` shows 106 renames at 100% similarity (`git diff --cached -M --stat | grep -c "=>"` = 106).
- [ ] **Step 4:** Dump the dict again to `balance_after.txt`; `diff` against `balance_before.txt`. Expected: **no difference** (Task 1 already removed the 14 keys).
- [ ] **Step 5:** Check the Python side: `python3 -c "import sys; sys.path.insert(0,'tools'); import data_index; d=data_index.balance(); print(len(d))"` prints the same count as `balance_after.txt` lines, and the values match (compare in the same one-liner).
- [ ] **Step 6:** `./run_tests.sh --fast` → green; then GUT on `tests/ui`, `tests/map3d`, `tests/war_room` → green (the usual expected error count only).
- [ ] **Step 7:** Commit `refactor(data): tables into scene folders, balance split per folder`.

### Task 4: Layout guards

**Files:**
- Create: `tests/engine/test_data_layout.gd`
- Modify: `tests/engine/test_data_csv_shape.gd` (walk `res://data` recursively, skipping `maps/`)

- [ ] **Step 1: Write the tests:**
  - `test_every_csv_on_disk_is_indexed`: every `.csv` under `res://data` outside `maps/`, other than `tables.csv` and `*/balance.csv`, is a `tables.csv` row whose folder matches its directory; every row's file exists; no table appears twice.
  - `test_balance_files_sit_in_indexed_folders`: every `balance.csv` found lies in a folder of `table_folders("res://data")`.
  - `test_no_balance_key_repeats`: `load_balance("res://data")` is non-empty and `last_error == ""`.
  - `test_engine_reads_no_screen_key`: for each key in `screens/*/balance.csv`, no `scripts/engine/**/*.gd` contains `"<key>"`, nor `"<base>"` when the key is `<base>_table`, unless the key is in the exemption const (the 21 keys from Global Constraints, each commented with "an engine look helper reads it").
  - `test_no_flat_data_paths_remain`: no file under `scripts/ tools/ tests/` (`.gd .gdshader .py .sh`) nor any `scripts/**/CLAUDE.md`, `scripts/**/guide/*.md`, `tools/CLAUDE.md`, `data/CLAUDE.md` matches `data/<table>.csv` for an indexed table or `data/balance.csv`.
- [ ] **Step 2:** Run them. Expected: all pass except possibly `test_no_flat_data_paths_remain` on the `.md` guides (Task 5 fixes those); if so, mark only that test `pending("Task 5")` and remove the pending in Task 5.
- [ ] **Step 3:** Update `test_data_csv_shape.gd` to recurse; run it → PASS.
- [ ] **Step 4:** Commit `test(data): pin the folder layout, keys and paths`.

### Task 5: Guides

**Files:**
- Modify: `data/CLAUDE.md`, `CLAUDE.md`, every nested `scripts/**/CLAUDE.md`, `scripts/**/guide/*.md`, `tools/CLAUDE.md`, `.claude/skills/**` files that name `data/<table>.csv` or `balance.csv`

- [ ] **Step 1:** `data/CLAUDE.md`: replace the "`balance.csv` holds every tuning number" sentence with the folder table (one line per folder: what it holds) and the rules — a new table gets a `tables.csv` row in the folder of the scene it serves; a new number goes into that folder's `balance.csv`; a number only a screen reads goes under `screens/<screen>/`; a key lives in exactly one file.
- [ ] **Step 2:** Root `CLAUDE.md`: `data/*.csv` → `data/` (the "Design values live in" rule and the Layout block's `data/` line gains "by scene folder; `tables.csv` indexes them").
- [ ] **Step 3:** Rewrite `data/<table>.csv` → `data/<folder>/<table>.csv` and "`balance.csv` key(s) …" → "`<folder>/balance.csv` …" in the guides (reuse the Task 3 rewrite on `.md` files outside `docs/`).
- [ ] **Step 4:** Remove any `pending` from Task 4; run `./run_tests.sh --fast` (includes `test_claude_md_size` and `test_no_flat_data_paths_remain`) → green.
- [ ] **Step 5:** Commit `docs(data): guides name the scene folders`.

### Task 6: Land

- [ ] **Step 1:** `git fetch origin && git merge origin/main` (via the `sync_with_base_branch` tool); if a merged change added a `data/*.csv` or balance key, place it per the spec's rules and re-run Task 3 Steps 4–6.
- [ ] **Step 2:** Push and open the PR against `main` (title `refactor(data): tables and balance by scene folder`), body: the folder table, "no value changed", the 14 deleted keys, the 21 exemptions. Bind it with `ccd_pr` and read CI.
