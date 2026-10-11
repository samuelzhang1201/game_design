# Owner batch 2026-10-12 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the owner's 16-item debug batch of 2026-10-12 on `main` through one PR, with every item either done and reviewed or explicitly waiting on a named editor step / owner ruling.

**Architecture:** A first pass (2026-10-12 night) wrote code for all 16 items in one worktree with ten parallel implementers; four Opus acceptance reviews then judged each item (verdicts below). This plan keeps what was accepted, fixes or redoes the rest along the reviewers' architectures, and splits the work into three code lanes in separate worktrees (UI/engine, 3D map, war room) plus one bake lane, an editor phase that needs the Godot editor on the integration worktree, a visual-review phase and the PR.

**Tech Stack:** Godot 4.7 / GDScript (typed), GUT, Terrain3D, Python bake tools (`tools/map3d/`), gdai MCP for editor work.

**Spec:** the owner's list (verbatim in §Spec below) plus the four acceptance reviews summarised in §Review verdicts. No separate spec file: this batch is fixes inside existing features, each feature's spec is under `docs/superpowers/specs/`.

## Spec — the owner's words (2026-10-12)

1. 游戏名改为“Beyond the King's Words”, 请更改文件folder名以及游戏中UI的显示名称
2. 游戏一开始的背景介绍，需要有malvern的半身立绘显示在对话框左上方，玩家立绘在对话框右上方，对话内容要分段，玩家hit continue 按钮继续看对话，每一段topic的对话呈现在一个对话框里，尽量不要出现下拉scroll的情况。
3. 玩家选中单位后，在地图显示的光圈太大了，请改的小一点，但是更亮一点，光圈要有发光的感觉
4. 当大地图上军事单位为复数个model时，不需要完全同步，每个model行动的时候，可以有微小的时间差，不用完全100%整齐，有一点不一致感
5. war room中，如果是过高的坡度挡住军队移动，那么应该在地图上有明显合理的标记告诉玩家这段地方不通，需要绕行
6. war room上面的小地图太小了，那个丢出去的标记反而太大了，把小地图放大，每个字母都可以合理显示，标记缩小，要能放在小地图上的格子里
7. 小地图边上可以放4个那个丢出去的标记物件，玩家最多可以取出4个物件丢上去，同时下面的战略地图就可以覆盖最多4个格子的面积，相应也要有缩放。
8. war room战略地图的线条画的太浅了，除了省界边境线，其他的根本看不出来，请调整
9. war room桌子四角的蜡烛只要保留左上角那个即可
10. war room战略地图上的村庄，城市地点画的大一点，清楚些
11. 我想把所有在悬崖边的定居点的地图数据改为非悬崖，平原即可，不要使用带有悬崖高的码头，全部使用普通版码头。
12. 房屋模型现在硬生生放在地面上，我希望房屋脚下加上一点点小小的过渡，乡村可以是泥土，城市可以是砖头地面
13. 麦田/草地能否做出类似树木那种随风飘荡的感觉？尽量不要太牺牲fps和性能
14. 玩家自己控制的身份是不能send spy的
15. war room工具栏左边有条淡黄色的横过来的光斑，不知道是什么，请删除
16. 游戏初始的黑屏，请在右下角加上地图里那个转动的齿轮，告诉玩家正在读取游戏。

## Review verdicts (Opus acceptance, 2026-10-12)

| # | Verdict | What carries over / what changes |
|---|---|---|
| 1 | ACCEPT WITH FIXES | name strings kept; title labels in `main_menu.tscn` still read "Crown / and Council"; add a one-time user:// copy |
| 2 | ACCEPT WITH FIXES | pages + Continue kept; busts need editor nodes; frame toggle, zero guard, dim colour as export; both busts lit (text is a narrator, not a speaker) |
| 3 | ACCEPT WITH FIXES | premultiplied blend instead of additive; narrow the band (not the radius); elliptical from the formation extent; draw over roads |
| 4 | REDO | no timers: start each figure at a hashed clip phase; per-figure positional lag spring; clamp after jitter |
| 5 | ACCEPT WITH FIXES | bars from the router's real detours (`blocked_runs`), shared cell walk, entry edge, min px, pending march only |
| 6 | REDO (lever) | the flat chart is read at a 33° graze: letters 4–6 px; tilt the chart on a reading stand |
| 7 | REDO | one sheet laid over the held cells' bounding rect (union sheet), not a camera back-off; markers 2–4 authored |
| 8 | ACCEPT WITH FIXES | seams back to 3 px / alpha B0, border stays heaviest |
| 9 | ACCEPT WITH FIXES | re-bracket the key candle's energy/range; delete Candlestick2–4 in the editor |
| 10 | ACCEPT WITH FIXES | works/market glyphs clear the outer ring and halo; halo opacity key |
| 11 | REDO | explicit `pier_cliff_landings` key; a port-plain height pass so every port gets the normal pier; full rebake |
| 12 | REDO | own `Map3DLayerAprons`, draped meshes, authored `.tres` materials, priority under roads; houses layer back under 300 lines |
| 13 | ACCEPT AS STOPGAP | drop `crop_gain`; add a wind-slope normal tilt (real light motion, ALU only); crop cards = own spec later |
| 14 | ACCEPT WITH FIXES | 身份 read as 省份: refuse a spy into the crown's CONTROLLED provinces, not the whole realm; LEDGER drops the dead row |
| 15 | REDO | identified: the Hand slot's painted glyph (pale ink, 36×18 px smear); delete Hand + Sep0, clicking the lit crayon drops to the hand |
| 16 | REDO | `scenes/hud/load_wheel.tscn` (compass wheel) under the curtain; GameRoot instantiates its overlays one per frame so the wheel turns over the pre-menu black too |

Test state at the plan's writing: `./run_tests.sh --fast` on the first-pass tree = 2004 tests, 2002 passing, 2 pending (pre-existing LEDGER owner rulings), 0 failing. Three new test files never ran: they lack `const SuiteData := preload("res://tests/suite_data.gd")`.

## Implementer's rulings (defaults taken, pending the owner)

| Id | Item | Default | Alternative for the owner |
|---|---|---|---|
| R1 | 14 | 身份 = 省份: controlled provinces refuse; greyed button with the reason | whole realm; or no button |
| R2 | 2 | both busts lit equally, inside the box's top corners; text stays the narrator's | Malvern briefs the king (rewrite); busts above the box |
| R3 | 16 | wheel also covers the pre-menu black (overlay deferral) | curtain only |
| R4 | 15 | delete the Hand slot as asked; re-click the lit crayon = hand | keep a legible hand (light_keep 0) |
| R5 | 4 | both gait phase and positional lag desync | gait only |
| R6 | 3 | no scene bloom; premultiplied glow | turn on WorldEnvironment glow (whole-map look) |
| R7 | 12 | draped per-house aprons in their own layer | terrain-shader paving from a baked mask (continuous town paving) |
| R8 | 13 | normal tilt + existing amplitudes; no geometry tonight | crop card layer (own spec, perf bench) |
| R9 | 11 | every port incl. the capital gets a plain landing; cut ≤ `port_plain_max_cut_m` 45 m; cliff models stay in the repo unused | keep the capital's cliff |
| R10 | 6 | chart tilted 35° on a stand (overrides the flat-chart Ruling 24, which can no longer meet "every letter readable") | flat + hover readout |
| R11 | 7 | any held set whose bounding box is ≤ 4 cells (2×2, 1×3, 1×4); edge arrow shifts every marker one cell | 2×2 only; arrow resets to one |
| R12 | 5 | slope bars only while a march is drawn/pending and on drafts | also on sealed marches |
| R13 | 1 | repo root and `cc_art_check` module not renamed; Chinese 王冠与议会 left; app icon unchanged | new Chinese title; icon |
| R18 | 11 | (dry run on the real pack: cutting the 24 cliff ports to a plain needs 92–449 m cuts with ~1 km blends, 4 exceed 350 m, 3 low ports with hills in town get 94–148 m, and sparing rivers' wet bands leaves 43–163 m steps — new cliffs) R9's 45 m cap is kept, so nothing is carved on this pack; no cliff landing anywhere; every port gets the normal timber pier, a far landing (`pier_search_fallback_m` 2000) rather than none; the carve is built and tested but off (`port_plain_lofty` 0) | switch the carve on (`port_plain_lofty` 1, `port_plain_max_cut_m` 450, `port_plain_keep_river_band` 0) — towns on coastal plains, km-wide coves |
| R17 | 6 | no table placement gives a bigger chart AND ≥ 9 px letters with the room's camera as it was; chosen: war room opening pitch 52° → 45°, chart at 20° tilt, letters on the near margin, every 3rd cell lettered; landed at w 0.86 m (0.915 broke the 5 cm table-edge and 6 px view-top guards) → ~424 px wide at the near edge, caps ~9 px (were ~4.3), the marker fits a cell; a visibly wider chart needs a bigger table or smaller letters | camera unchanged: tilt 20°, w 0.64 → 341 px, caps 9.5 px; every cell named only via a hover readout |
| R16 | 16 | the title preview's campaign (~266 ms) stays on the main thread: the wheel stalls once for ~0.27 s at launch; threading it risks races on the engine's static caches | build the preview on a worker thread behind a completion guard |
| R15 | 7 | a toss refused past four cells gives no feedback beyond the marker staying in the tray; a margin-row lay that cannot fit sends every marker but the newest back | a refusal slip / sound |
| R14 | 2 | (found in review, not in this batch) Space during the opening narration still starts the clock behind the pages — left as is | hold the clock / ignore Space while the narration is up |

## Global Constraints

- Root `CLAUDE.md` and every nested `CLAUDE.md` of a touched folder are read first; their rules bind every task.
- The static LOOK lives in `.tscn`/`.tres` authored in the editor via gdai MCP: never text-edit a look resource, never build a look in `_ready()`, never a style/material assembled in code. Every such change is listed under Phase E, and code takes it through `@export`s.
- `scripts/map3d/` and `scripts/war_room/` never name `Game`; nothing in `scripts/engine/` names `scripts/ui`/`scripts/llm` or touches `Game`.
- `scripts/map3d/*.gd` ≤ 300 lines (`test_map3d_shape.gd`); nested `CLAUDE.md` ≤ 30 000 chars.
- Design values go in the folder `balance.csv` / tables of PR #39's layout (`data/<folder>/…`, indexed by `data/tables.csv`); code reads tables through `table_path()`, never a literal `res://data/…` path (`test_data_layout.gd`).
- Every test file that uses SuiteData starts with `const SuiteData := preload("res://tests/suite_data.gd")`.
- Presentation randomness is hashed from stable ids with `String.hash()`; no `randi()`, no `Time.*` below `Game`.
- **One Godot test process at a time on this machine.** Every Godot test run goes through `$LOCK <command>` (the lock script below). No agent leaves a background test or a polling loop running when it reports.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; implementer's rulings are named in the commit body.

## Review Focus

1. A save made before this batch (first-pass keys, an old `spy_refuse_own_realm`, a spy in flight) loads and plays — T2, T1 tests.
2. The narration at the minimum window (1280×720) with the busts authored shows no scrollbar on any page — T3 test, re-run after Phase E.
3. A march whose straight line grazes a closed cell's corner shows a bar exactly where the router detours, and none where the router walks straight because it is walled in — T10 tests.
4. Walking the war-room edge arrows with 1–4 markers out never multiplies markers — T11 test.
5. A port whose only shore is a cliff still gets exactly one normal pier after the rebake — T14 tests.

---

## Execution protocol

- **Worktrees.** Integration branch `feat/owner-batch-oct12` at `/Users/samuelzhang/game_design-oct12`. After T0, lanes branch from it: lane A `feat/oct12-ui` at `/Users/samuelzhang/game_design-oct12-ui`, lane B `feat/oct12-map3d` at `…-map3d`, lane C `feat/oct12-war` at `…-war`; each gets `cp -Rc <integration>/.godot <lane>/.godot`. Lane D (T14) runs in the integration worktree after lanes B and C merge. The lead merges each lane back (`git merge --no-ff`) after its Opus review.
- **Test lock.** `LOCK=/private/tmp/claude-501/-Users-samuelzhang-game-design/1a5a70d7-9a91-4294-8a8f-67e1e2bc89dd/scratchpad/godot_lock.sh` serialises Godot processes across lanes (mkdir lock, waits, removes on exit). Single files: `$LOCK ./gut_one.sh res://tests/<dir>/<file>.gd` (`gut_one.sh` in the same scratchpad: the GUT command line of `run_tests.sh` with `-gtest=`).
- **Agents.** One fresh `implementer` per task (Opus model for T8, T11, T14; Sonnet otherwise), tasks of a lane in order. After each task an Opus reviewer (read-only, no Godot) checks the diff against this plan; the implementer fixes its findings before the next task.
- **Per task:** failing test → code → `$LOCK` the task's test files → commit (stage only the task's files). Per lane end: `$LOCK ./run_tests.sh --fast` plus the lane's slow directory files.

---

### Task 0: Integrate main (PR #39) into the first pass

**Files:** every first-pass data edit moves to PR #39's folder: `spy_*` → `data/intel/balance.csv`; `opening_segment_max_chars` → `data/screens/ui/balance.csv` (or the folder `data/CLAUDE.md` names for the conversation screen); `war_*` → `data/screens/war_room/balance.csv` and `war_palette.csv`'s new home; `map3d_*` → `data/screens/map3d/balance.csv`; `map3d_bake.csv`, `map3d_houses.csv`, `map3d_settlements.csv`, `map3d_aprons.csv` → their `data/screens/map3d/` homes with a `tables.csv` row for `map3d_aprons`; `scripts/engine/data_repository.gd` loads `map3d_aprons` via `table_path()`.

- [ ] Lead: commit the first pass as `wip: owner batch 2026-10-12 first pass (pre-review)` (all current changes, no untracked junk).
- [ ] `git merge origin/main`; resolve every conflict by re-applying the first pass's key changes in the new file locations (keep main's notes and order; append new keys with their notes).
- [ ] Add the missing SuiteData preload to `tests/ui/test_opening_narration.gd`, `tests/map3d/test_map3d_house_apron.gd`, `tests/map3d/test_map3d_march_desync.gd`.
- [ ] `$LOCK ./run_tests.sh --fast` → 0 failing; `$LOCK ./gut_one.sh res://tests/engine/test_data_layout.gd` passes.
- [ ] Commit `merge: origin/main (data folders by scene) into the owner batch`.

---

## Lane A — UI and engine (worktree `…-ui`)

### Task 1: Name: finish the rename and copy the old user data

**Files:**
- Create: `scripts/ui/user_dir_migration.gd` (class `UserDirMigration`), `tests/ui/test_user_dir_migration.gd`
- Modify: the `Game` autoload script (`_ready`, before any config/save read), `docs/art_team/README.md`, `docs/design/DATA_ARCHITECTURE.md`, `tools/map3d/fetch_polyhaven.py` (user-agent), `assets/imagegen/app_icon_prompts.csv` (name column only)

**Interfaces:** Produces `UserDirMigration.copy_missing(from_dir: String, to_dir: String, files: PackedStringArray) -> PackedStringArray` (names copied) and `UserDirMigration.legacy_dir() -> String` = `OS.get_user_data_dir().get_base_dir().path_join("Crown and Council")`.

- [ ] Test `test_copies_a_missing_file`, `test_leaves_an_existing_file_untouched` (content unchanged), `test_no_old_dir_is_a_no_op` (returns empty) — dirs under `RunDir.dir("migration")`.
- [ ] Implement; `Game._ready` calls it for `["save.json", "config.json", "settings.cfg"]` unless `CC_FORCE_OFFLINE=1`. Copy only, never move or overwrite.
- [ ] Replace the remaining English old-name strings listed above. Leave 王冠与议会, the `cc_art_check` module name and the repo root (R13). If `tools/CLAUDE.md` names a rebuild command for `docs/art_team/kit/blender/cc_art_check.zip`, run it.
- [ ] Title labels, node renames, `title_entrance.csv` rows 8–9 and `tests/ui/test_title_living.gd` → Phase E1 (they change together with the scene).
- [ ] Run the test file; commit.

### Task 2: Spy: the crown's controlled provinces need no spy

**Files:** `scripts/engine/spy_system.gd`, `scripts/engine/action_system.gd`, `scripts/ui/spy_order_menu.gd`, the LEDGER action filter (`Ledger.actions_for`), `data/intel/balance.csv`, `tests/engine/test_spy_system.gd`, `tests/engine/test_map_objects.gd`, `tests/ui/test_map_detail_panel.gd`, `tests/ui/test_spy_orders.gd`, the intel section of `scripts/engine/CLAUDE.md`.

**Interfaces:** Produces `SpySystem.is_controlled(repo: DataRepository, state: GameState, cell: Vector2i) -> bool` — true iff the cell's province ∈ `MapManors.controlled_provinces(repo, state)`; used by both `validate` and `quality()`. Key `spy_refuse_controlled` (1/0) replaces `spy_refuse_own_realm`. Reason string: `"The crown's own lands need no spy"`.

- [ ] Tests: `test_a_controlled_province_is_refused_with_the_reason`; `test_an_uncontrolled_province_of_the_realm_is_allowed`; `test_a_foreign_province_is_allowed`; `test_wildlands_are_allowed`; `test_off_the_map_says_off_the_map_first`; `test_the_key_at_zero_lifts_the_refusal`; LEDGER: `test_no_spy_row_for_a_controlled_node`.
- [ ] Re-aim the three UI/engine tests the reviewer named at a foreign point on purpose (detail panel "afford" test, `test_map_objects.gd:388`, `test_spy_orders._land()`).
- [ ] `spy_order_menu.gd` takes the refusal from one `validate` call (no second route search).
- [ ] Run the touched files; commit (body: R1).

### Task 3: Opening narration: frames, guards, both busts lit

**Files:** `scripts/ui/conversation_scene.gd`, `tests/ui/test_opening_narration.gd`, `scripts/ui/CLAUDE.md`.

**Interfaces:** Adds `@export var narration_left_frame: Control`, `@export var narration_right_frame: Control`, `@export var narration_dim: Color = Color(1, 1, 1)` (both lit by default, R2). Visibility is toggled on the frames; `_fill_portrait` skips a box whose height is 0 and falls back to `box.size`.

- [ ] Tests (run now with nulls tolerated): page count = 11, no page empty, every page ≤ `opening_segment_max_chars`, Continue walks every page, the last page's button reads "I am ready. Let the reign begin."; with frames present: both visible on every page, both hidden on the first minister beat, neither dimmed; no scrollbar at 1280×720 (re-run after Phase E2).
- [ ] Implement; remove `NARRATION_DIM`. Commit.

### Task 4: Loading wheel over the black

**Files:** Create `scripts/ui/load_wheel.gd` (`@tool`, class `LoadWheel`, extends `TextureRect`), `tests/ui/test_load_wheel.gd`. Modify `scripts/ui/game_root.gd` (overlay deferral), `scripts/ui/main_menu.gd` (delete `_set_up_load_gear`), `scripts/ui/compass_layer.gd` (delete `always_turn`), the screens' `balance.csv` (delete `ui_load_gear_*`).

**Interfaces:** `LoadWheel` turns `rotation` by `map_compass_turn_deg_per_s` (read through `UiPalette.data()`) each `_process`, `pivot_offset` = size/2 on resize. `GameRoot` switches to MENU first, then instantiates its seven overlays one per process frame (`_build_overlays_stepwise()`), keeping their order and signal hookups.

- [ ] Tests: `test_wheel_turns_over_frames` (rotation grows over 5 process frames); `test_overlays_exist_after_the_menu_shows` (menu visible before the overlays; all seven present within 10 frames); after Phase E3: `test_title_curtain_holds_the_wheel_bottom_right` and `test_wheel_hides_with_the_curtain`.
- [ ] Measure the longest frame while the curtain is up (print in a debug run); split any step > 100 ms and note it in the commit.
- [ ] Commit (body: R3). The scene `scenes/hud/load_wheel.tscn` and its instances → Phase E3.

### Task 5: War-room roll without the hand

**Files:** `scripts/war_room/war_plan_tool.gd` (`pick_stick`), `scripts/war_room/war_tool_roll.gd` (comments, null-safe `slot("hand")`), `scripts/war_room/guide/plans.md:11`, `tests/ui/test_war_tool_art.gd`, a `tests/ui/test_war_room_tools.gd` case.

- [ ] Test `test_clicking_the_lit_crayon_again_drops_to_the_hand` (side == "" after the second pick); `test_war_tool_art` no longer requires a hand slot.
- [ ] Implement; the roll works with or without `Row/Hand`. Commit (body: R4). Deleting `Row/Hand` + `Row/Sep0` → Phase E4.

---

## Lane B — 3D map (worktree `…-map3d`)

### Task 6: Selection glow: smaller band, brighter crest, over roads

**Files:** `scripts/map3d/unit_select_glow.gdshader`, `scripts/map3d/map3d_priority.gd` (`UNIT_GLOW` between ROADS and SELECTION), the glow sizing in the units layer, `data/screens/map3d/balance.csv` (`map3d_unit_glow_ratio` back to 1.0; new `map3d_unit_glow_peak` 0.9, `map3d_unit_glow_inner` 0.75), `tests/map3d/test_map3d_military.gd`, `scripts/map3d/CLAUDE.md:39`.

- [ ] Tests: `test_glow_draws_over_roads` (material `render_priority` > `Map3DPriority.ROADS`, after Phase E5); `test_glow_is_an_ellipse_from_the_extent` (a 4×1 line formation gets half-sizes in the extent's ratio); `test_glow_look_is_authored` (`gain`, `hot`, `haze` set in the `.tres`, after Phase E5).
- [ ] Shader: `blend_premul_alpha`; the crest adds light, ALPHA gives a faint darkening skirt; band from `peak`/`inner` uniforms. Commit (body: R6). `.tres` values and priority → Phase E5.

### Task 7: March desync without timers

**Files:** `scripts/map3d/map3d_unit_rig.gd`, create `scripts/map3d/map3d_march_lag.gd` (class `Map3DMarchLag`, pure), `tests/map3d/test_map3d_march_desync.gd`, `data/screens/map3d/balance.csv` (`map3d_march_lag_min_s` 0.25, `map3d_march_lag_max_s` 0.7, `map3d_march_lag_cap_share` 0.35; keep `map3d_march_desync_pace`; delete `map3d_march_desync_max_s`), `scripts/map3d/CLAUDE.md:41`.

**Interfaces:** `Map3DMarchLag.phase(code: String, index: int) -> float` in [0,1); `Map3DMarchLag.tau(code: String, index: int, min_s: float, max_s: float) -> float`; `Map3DMarchLag.step(o: Vector3, v: Vector3, tau: float, dt: float, cap: float) -> Vector3` = `o·e^(−dt/τ) − v·τ·(1−e^(−dt/τ))`, length clamped to `cap`.

- [ ] Tests: `test_phase_hashed_in_range_and_stable` (same value twice; ≥ 6 distinct of 9 figures); `test_play_march_starts_now_at_its_phase` (MARCH current at `phase × length` right after `play`); `test_jitter_never_exceeds_anim_max`; `test_lag_spring_by_hand` (τ 0.5, v (2,0,0), dt 0.5 from 0 → x −0.632121, then −0.864665, then → −1.0 with cap 1.0).
- [ ] Remove the scene-tree timers and the delay; standing figures keep pace 1.0 (jitter only while marching); clamp after jitter; each figure's local offset follows `step` in the piece's frame. Keep `map3d_layer_units.gd` ≤ 300 lines. Commit (body: R5).

### Task 8: Aprons as their own layer, draped, with authored materials

**Files:** Create `scripts/map3d/map3d_layer_aprons.gd` (class `Map3DLayerAprons`), `tests/map3d/test_map3d_layer_aprons.gd`. Modify `scripts/map3d/map3d_house_apron.gd` (geometry only: footprint → corners; no material), `scripts/map3d/house_apron.gdshader` (AA brick via `fwidth`; shares the houses' weather uniforms), `scripts/map3d/map3d_priority.gd` (`APRONS` below ROADS), `scripts/map3d/map3d_layer_houses.gd` (remove the apron code; back to ≤ 300 lines), `data/screens/map3d/map3d_aprons.csv` (geometry only: kind, `margin_m`, `lift_px`, `grid_n` 4), `scripts/map3d/guide/settlements_and_houses.md`, `tests/map3d/test_map3d_layer_houses.gd` (revert the apron allowance).

**Interfaces:** `Map3DLayerAprons` has `@export var dirt_material: Material`, `@export var brick_material: Material`; builds one `ArrayMesh` per settlement per kind from a `grid_n × grid_n` grid per apron, each vertex at `height_at(x, z) + lift`, cached like the roads' `_chunks`; hides with `map3d_lod_houses_m`.

- [ ] Tests: `test_drape_follows_ground` (plane y = 0.1x: corner at x = 20 → 2.0 + lift); `test_layer_fills_dirt_for_villages_brick_for_towns` (vertex counts = shown apron-wearing houses × grid); `test_aprons_hide_past_lod`; `test_aprons_under_roads` (priority); `test_apron_materials_are_the_tres` (after Phase E6).
- [ ] Implement; delete `material_of`. Commit (body: R7). The `.tres` materials and the `Aprons` node → Phase E6. Perf bench → Phase V.

### Task 9: Crop wind: light that moves with the wave

**Files:** `scripts/map3d/map3d_ground_wind.gd` (remove `wind_crop_gain`; add `wind_tilt`), `scripts/map3d/map3d_layer_wind.gd` (remove `crop_gain`; add `@export var tilt := 0.35` to `GROUND`), `tests/map3d/test_map3d_layer_wind.gd`.

- [ ] Test `test_tilt_reaches_the_ground_shader` (GROUND has "tilt"; `UNIFORMS` declares `wind_tilt`; `STAGE` bends `NORMAL`/the shading normal by `wind_tilt` × the wave's slope along `wind_dir`); delete the `crop_gain` test.
- [ ] In the stage, tilt the shading normal down-wind by the wave's derivative (ALU only, inside the existing `wind_on`/LOD gate). Commit (body: R8; crop cards need their own spec).

---

## Lane C — War room (worktree `…-war`)

### Task 10: Slope bars where the router really detours

**Files:** `scripts/engine/march_path.gd`, `scripts/war_room/war_slope_bars.gd`, `scripts/war_room/war_plan_hud.gd`, `scripts/war_room/war_room_pointer.gd:255-259`, `data/screens/war_room/balance.csv` (`war_slope_bar_min_px` 40), create `tests/engine/test_march_blocked_runs.gd`.

**Interfaces:** `MarchPath.cells_on(a: Vector2, b: Vector2) -> Array[Vector2i]` (the Amanatides–Woo walk `clear()` uses, now shared); `MarchPath.blocked_runs(repo: DataRepository, from: Vector2, wps: Array, to: Vector2) -> Array` of `[Vector2i, Vector2i]` (entry cell, exit cell) only for legs `route_m_of` replaced by a detour, empty on the walled-in fallback.

- [ ] Tests: corner graze — closed (4,2), line (2500,3500)→(5500,500) → `[[(4,2),(4,2)]]`; east–west through (4,2) → `[[(4,2),(4,2)]]`; no run when the march ends on the wall; none over water; empty on the walled-in fallback.
- [ ] Bars at each run's entry edge, at least `war_slope_bar_min_px` long on screen; drawn for the pending march and drafts only (R12). Rename `var len`. Commit.

### Task 11: Up to four markers lay one sheet over their cells

**Files:** `scripts/engine/war_sheets.gd` (`union`), `scripts/war_room/war_tray.gd`, create `scripts/war_room/war_tray_nodes.gd`, `scripts/war_room/war_room_view.gd` (shrinks: tray logic out), `scripts/war_room/war_room_pointer.gd`, `scripts/war_room/war_room_wall.gd`, the ink caches (`WarSheetInk.cache_key`, `WarPlanInk.cache_key`, `_inks.*_for`, `WarRoom.partition`), `data/screens/war_room/balance.csv` (`war_table_max_depth_m`; delete `war_tray_zoom_gain`), `scripts/war_room/CLAUDE.md:69`, `tests/war_room/test_war_tray.gd`, `tests/engine/test_war_sheets_union.gd`.

**Interfaces:** `WarSheets.union(repo: DataRepository, indices: Array[int]) -> Dictionary` = `{cell: Rect2i (merged cells), rect: Rect2 (cell grown by the collar), col, row, cols, rows, key: String}`; a one-index union equals today's sheet. Ink texture stays `war_sheet_texture_px` across the union (scale follows the zoom); above one cell the lower town-name tiers drop. Table width = min(`war_table_w_m`, `war_table_max_depth_m` × rect ratio); camera stays at `war_cam_distance_m`. `WarTray` refuses a toss whose bounding box would exceed `war_tray_max` cells (R11). An edge arrow shifts every held marker one cell. A toss starts from the marker's tray slot. Markers come from `@export var tray_markers: Array[Node3D]` (Marker2–4 authored, Phase E7); `duplicate()` and `tray_distance` are deleted.

- [ ] Tests: `test_union_rect` (cells (3,4)+(4,4) → merged, grown by the collar × `px_per_unit`); `test_toss_refused_past_four_cells` ((4,4)+(5,5) ok; + (6,4) refused, 3×2 = 6); `test_edge_arrow_moves_the_markers` (marker count unchanged); `test_union_table_fits_the_oak` (1×4 fits `war_table_max_depth_m`); `test_one_cell_union_is_todays_sheet`.
- [ ] Implement; fix the misplaced comment (old line 527) and `CLAUDE.md:69`. Commit (body: R11).

### Task 12: The index chart leans on a stand

**Files:** `scripts/war_room/war_index_chart.gd` / `war_room_wall.gd` (placement), `data/screens/war_room/balance.csv` (`war_chart_tilt_deg` 35, `war_chart_margin_m` 0.03; re-check `war_chart_w_m`/`_z_m` so the far edge stays on the oak), `tests/war_room/test_war_room_view.gd`.

- [ ] Tests: `test_chart_leans_by_the_key` (chart basis pitch = `war_chart_tilt_deg`); `test_chart_stays_on_the_table` (far edge z ≥ −table depth/2); `test_marker_fits_one_cell` (kept).
- [ ] Implement the lean as placement from data. Commit (body: R10). The stand mesh → Phase E8.

### Task 13: Ink and light tuning

**Files:** `data/screens/war_room/balance.csv` (`war_ink_seam_px` 3, `war_ink_town_halo_alpha` 0.85, candle `war_candle_key_energy` 1.8, `war_candle_key_range_m` 3.5), `war_palette.csv` (`seam_ink` alpha B0), `scripts/war_room/war_sheet_ink.gd:128-129` (works/market glyphs clear the outer ring and the halo), `scripts/war_room/war_ink_painter.gd` (halo alpha), the `war_ink_manor_px` note, `tests/war_room/test_war_sheet_ink.gd`, `tests/war_room/test_war_room_view.gd:826`.

- [ ] Tests: `test_border_is_heavier_than_seam` (`border_px > seam_px`); `test_glyphs_clear_the_capital_ring`; after Phase E9: `assert_eq(lights.size(), 1)`.
- [ ] Implement. Commit.

---

## Lane D — Bake (integration worktree, after lanes B and C merge)

### Task 14: Every port gets the normal pier on a plain landing

**Files:** `tools/map3d/bake_houses.py` (read `pier_cliff_landings`), `tools/map3d/bake_world.py` (port-plain pass beside `level_pad`), `data/screens/map3d/map3d_bake.csv` (restore `pier_cliff_min_shore_m` 20 and `pier_stair_town_rise_m` 30; add `pier_cliff_landings` 0, `port_plain_rise_m` 3, `port_plain_blend_m` 120, `port_plain_max_cut_m` 45), `tools/map3d/test_bake_houses.py`, `tests/map3d/test_map3d_houses_bake.gd`, `scripts/map3d/guide/settlements_and_houses.md`.

- [ ] Python test: a synthetic port whose only shore is a cliff gets a lowered landing and one `pier`, no `pier_cliff`/`pier_stair`. GUT: `test_every_port_has_one_normal_pier` replaces `test_a_cliff_harbour_runs_its_quay_out_over_the_water`.
- [ ] Port-plain pass: for each port whose harbour bearing rises above `pier_max_shore_m`, cut the built ground and a corridor to that shore down to `sea_y + port_plain_rise_m`, eased over `port_plain_blend_m`; cut only, never rivers; give up past `port_plain_max_cut_m` (log the port).
- [ ] Rebake with `build_pack.sh` (heights, regions, textures, AO, houses, trees, march grid, war-room relief) in the integration worktree; `$LOCK` the map3d and war_room bake tests; confirm `houses.csv` has 0 `pier_cliff`/`pier_stair` rows and ≥ 1 `pier` per port. Commit the rebuilt pack (body: R9).

---

## Phase E — Editor steps (Godot editor opened on the integration worktree, gdai MCP)

Precondition: the owner's editor is on `/Users/samuelzhang/game_design` (main); gdai speaks to one editor on port 3571. The lead asks the owner to open the integration worktree in the editor (or to do these steps). Before every editor save: compare open script buffers with disk; after: `git status`.

- E1 `main_menu.tscn`: `Title_Crown` → `Title_Line1` "Beyond the", `Title_andCouncil` → `Title_Line2` "King's Words"; `title_entrance.csv` rows 8–9 and `tests/ui/test_title_living.gd:18,71,74` follow. Visual check of the 816 px hero box.
- E2 `conversation.tscn`: under `…/AudienceCol/AudienceBody`, first child `NarrationLeftFrame` (PanelContainer, `PortraitFrame` stylebox, shrink-begin, hidden) with child `NarrationLeft` (Control, min 150×200, clip, mouse ignore); same as last child `NarrationRightFrame/NarrationRight`; assign the four exports.
- E3 Create `scenes/hud/load_wheel.tscn` (root `LoadWheel` TextureRect, `compass.png`, min 96, keep-aspect-centred, mouse ignore, script `load_wheel.gd`); instance as `Curtain/LoadWheel` in `main_menu.tscn`, anchored bottom-right, offsets (−124, −124, −28, −28); instance on GameRoot's pre-menu black.
- E4 `war_tool_roll.tscn`: delete `Row/Hand` and `Row/Sep0`.
- E5 `unit_select_glow.tres`: set `gain` 3.2, `hot` 0.55, `haze` 0.25, `skirt` 0.25, `render_priority` = `Map3DPriority.UNIT_GLOW` (2); the stale `inner`/`peak` lines drop on save (they are instance uniforms from data now); raise `strength` toward 0.5 only if Phase V finds the crest faint.
- E6 Author `scenes/map3d/materials/apron_dirt.tres` (color_a #7A6446, color_b #5E4C34, style 0, unit_m 1.0, fade_m 1.6) and `apron_brick.tres` (color_a #9A6B55, color_b #6F6560, style 1, unit_m 1.1, fade_m 1.2), both ShaderMaterial on `house_apron.gdshader`, `render_priority` = `Map3DPriority.APRONS` (−2, below the sea), `mortar` left default; add node `Aprons` (Node3D, `map3d_layer_aprons.gd`) as a direct child of the `World` root of `map3d_world.tscn`, a sibling of `Houses`, assign `dirt_material` / `brick_material`, and set `Houses.aprons` to it. Then add both to `CODE_OWNED` in `test_map3d_editor_owned_look.gd` with `["lift_px", "px_per_dist"]` if that test checks them.
- E7 `war_room.tscn`: `Marker2`–`Marker4` as siblings of `%Marker`; assign `tray_markers`.
- E8 `war_room.tscn`: a simple oak reading stand under the index chart.
- E9 `war_room.tscn`: delete `Candlestick2`, `Candlestick3`, `Candlestick4`.
- After E: `$LOCK` the "after Phase E" tests of T1, T3, T4, T5, T6, T8, T11, T13.

## Phase V — Visual review

One agent at a time (`$LOCK` around each `tools/snapshot_screen.gd --resolution 1280x720` and `1920x1080` shot, real window, never headless), following `.claude/skills/visual-review/SKILL.md` with an independent critic: items 1 (title), 2 (narration pages), 3 (glow on wheat, snow, road), 4 (a 3×3 block marching and stopping), 6/7 (chart letters, 1–4 marker sheets), 8/10 (ink at the opening view), 9 (one-candle light), 11 (a former cliff port), 12 (aprons village/town/slope/snow), 13 (wind in motion at play zoom), 15 (roll without the hand), 16 (wheel on both blacks). Plus the perf bench (`--pan`, three zooms) for items 12 and 13 against `bench_budget_ms`. Findings go back to the owning task.

## Phase R — Land

- [ ] `$LOCK` run `tests/ui`, `tests/map3d`, `tests/war_room` (the touched files and their folders) and `./run_tests.sh --fast`.
- [ ] Opus whole-branch review; fix findings.
- [ ] Push `feat/owner-batch-oct12`, `gh pr create` against `main` listing items, rulings R1–R13 and any editor step still open; ccd_pr `get_status`/`bind_pr`; merge only after `gut-tests` is green and the owner says so.
