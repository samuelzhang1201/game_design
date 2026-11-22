# Infantry Melee: Impact and a Mixed Fight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Infantry fights on the 3D map read as two coloured sides that mix in one fighting area, where every blow lands with a felt and heard impact, at every tier's frame budget.

**Architecture:** View-only, on top of the landed duels (`Map3DDuel`, `Map3DDuelDriver`, `Map3DFall`): a realm tint overlay on the figures, an impact layer driven by the duel turn's contact instant (hit-stop, knock-back, a pooled particle burst, a one-shot sound), and a scrum mode that gives every fighting figure a view offset into one shared area per battle. The engine's rows never move; everything is offsets and clip timing.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, Blender headless export (Python) for the tunic mask, ffmpeg + `--write-movie` for motion review.

**Spec:** `docs/superpowers/specs/2026-11-21-infantry-melee-scrum-design.md`

## Global Constraints

- View-only: no engine state, save field or RNG draw; hash with `Map3DMarchLag.unit(key)`. `scripts/map3d/` never reads `Game`.
- Distances in FIGURE HEIGHTS (camera-scaled miniatures); every number a key in `data/screens/map3d/balance.csv` (with a description naming the spec) or a column in `army_art.csv`.
- The look is authored in the editor (`.tscn` / `.tres` through gdai MCP); code only sets parameters on it. Map figures only: the WAR ROOM's tin (`WarPieces`) and ink (`WarInkFigure`) stay as they are.
- `Map3DLayerUnits` stays ≤ 500 lines (`test_map3d_shape.gd`): new code in its own files, hooks replace lines.
- After editing any script listed in `Map3DRoyalCarrierSource._SOURCES` (`map3d_battle_groups.gd`, `map3d_layer_units.gd`, `map3d_unit_glow.gd`, `map3d_unit_rig.gd`, `map3d_clip_chain.gd`, …) repin its SHA-256 and run `test_royal_boundary_input.gd` + `test_royal_upright_carrier.gd`.
- Each PR: `prd_step: Step 8`, `player_outcome:`, `wired: true`; visual review in a real window (`tools/snapshot_screen.gd --resolution WxH`, never headless); motion judged from `--write-movie out.avi --fixed-fps 30` recordings of `--screen root --battle-case field --battle-arm foot --speed 1 --still`.
- The guide `scripts/map3d/guide/battle_duels.md` is updated in the PR that changes the behaviour it describes (nested CLAUDE.md caps: `test_claude_md_size.gd`).

## Review Focus

1. The battle ends (or a unit withdraws) during a hit-stop or knock-back: every figure's `speed_scale` returns to 1 and every offset is cleared; no figure stays frozen or displaced. → Task 5 `test_a_battle_ending_mid_impact_restores_the_figures`.
2. The clock is paused during a hit-stop: it stays paused, and on resume the hold finishes its remainder, not a fresh hold. → Task 5 `test_a_pause_inside_the_hitstop_keeps_its_remainder`.
3. A figure falls inside the scrum: the body lies where it fought, and the replacement walks in from its slot to the scrum. → Task 9 `test_a_fall_in_the_scrum_lies_where_it_fought`.
4. One side's figures are not drawn (a foe the crown does not see, a ghost): no scrum forms; the seen side stands in its block. → Task 9 `test_no_scrum_against_unseen_figures`.
5. A battle record of several units a side with archers among them: the archers never enter the area; all opposed infantry share one area. → Task 9 `test_one_area_per_battle_archers_stay_out`.

---

## PR 1 — Realm colours on the figures

### Task 1: Export the tunic mask

**Files:**
- Modify: `tools/units3d/infantry_arp/game_export.py` (beside `_class_mask`, ~line 222)
- Create: `assets/3D/units/infantry/infantry_tunic_mask.png` (+ its `.import`: lossless, never VRAM compressed, mipmaps as the atlases have them)
- Test: `tools/units3d/infantry_arp/test_tunic_mask.py`

**Interfaces:**
- Produces: `infantry_tunic_mask.png`, one channel, the SAME atlas layout and size as `infantry_infantry_atlas.jpg`: 1.0 where the body class is 1 (green leather), 0 elsewhere, edges softened as `_class_mask` does.

- [ ] **Step 1: Write the failing test** — `test_tunic_mask_matches_the_atlas`: given a 4×4 fake `body_class` array `[[1,2],[3,1]]` upscaled into a 2-tile atlas layout, `tunic_mask_tiles(cls, layout)` returns an array of the atlas's shape whose class-1 cells are ≥ 0.99 and class-2/3 cells ≤ 0.01 away from the softened edges.
- [ ] **Step 2: Run** `python3 -m pytest tools/units3d/infantry_arp/test_tunic_mask.py -q` — Expected: FAIL (`tunic_mask_tiles` undefined).
- [ ] **Step 3: Implement** `tunic_mask_tiles(cls: np.ndarray, layout: list) -> np.ndarray` (pure, no `bpy`) and call it from the export after the atlas is packed, writing the PNG next to the atlas. Reuse the packing layout the atlas loop already computes.
- [ ] **Step 4: Run the test** — Expected: PASS. Then run the export headless on the owner's `.blend` (`tools/units3d/infantry_arp/README.md`) and confirm the GLB and atlases are byte-identical to main (`git status` shows only the new PNG); if the GLB changed, stop and rule.
- [ ] **Step 5: Commit** `tools/units3d/infantry_arp/game_export.py`, the test, the PNG and its `.import`.

### Task 2: The tint overlay and who wears which colour

**Files:**
- Create (in the editor): `scenes/map3d/materials/unit_realm_tint.gdshader`, `scenes/map3d/materials/unit_realm_tint.tres` (ShaderMaterial, `render_mode blend_mul`; `uniform sampler2D tunic_mask` set to Task 1's PNG; `instance uniform vec4 realm_tint`; output `ALBEDO = mix(vec3(1.0), realm_tint.rgb, mask)`), `assets/3D/units/realm_tint.tres` (an `ArtTable`, model `infantry` → that material)
- Create: `scripts/map3d/map3d_unit_dress.gd` (`class_name Map3DUnitDress`)
- Modify: `scripts/map3d/map3d_layer_units.gd:173-174` (replace the `Map3DUnitStandard.sync(...)` call; no net lines), `scripts/ui/game_art.gd` (a `UNIT_REALM_TINT` path constant)
- Modify: `data/screens/map3d/balance.csv` (`map3d_unit_tint_sat`, `map3d_unit_tint_val`)
- Test: `tests/map3d/test_map3d_unit_dress.gd`

**Interfaces:**
- Produces: `static func tint_of(repo: DataRepository, kingdom_code: String) -> Color` — `MapPalette.color_of`'s hue, saturation clamped up to `map3d_unit_tint_sat`, value `map3d_unit_tint_val`; `static func sync(repo: DataRepository, piece: Dictionary, reg: Dictionary, realm_flags: ArtTable, national_standard: PackedScene) -> void` — calls `Map3DUnitStandard.sync` exactly as the layer did, then for every figure mesh of the piece (`Map3DUnits.meshes`) sets `material_overlay` to the arm's tint material (none in the table: leaves it null) and `set_instance_shader_parameter("realm_tint", tint_of(...))`, only when the colour changed (kept on the piece as `tint`).

- [ ] **Step 1: Write the failing tests** — `test_tint_takes_the_realm_hue` (a realm whose palette colour is `Color.from_hsv(0.6, 0.2, 0.9)` with sat 0.55 / val 0.45 gives `h ≈ 0.6, s = 0.55, v = 0.45`); `test_sync_dresses_every_figure` (a piece of 3 figure meshes gets the overlay and the instance parameter on all 3); `test_a_model_with_no_mask_is_left_bare` (model not in the table → `material_overlay == null`); `test_war_room_material_untouched` (the figure's `get_active_material(0)` is still the scene's `StandardMaterial3D` after `sync`).
- [ ] **Step 2: Run** `./run_tests.sh --test tests/map3d/test_map3d_unit_dress.gd` — Expected: FAIL (class missing).
- [ ] **Step 3: Implement** `Map3DUnitDress` and the layer hook; author the shader, material and table in the editor (gdai MCP), checking open script buffers against disk before saving.
- [ ] **Step 4: Run** the test, `test_map3d_shape.gd`, `test_map3d_unit_scenes.gd`, the war room piece tests, `tests/ui/test_editor_owned_look.gd`, `tests/map3d/test_map3d_editor_owned_look.gd`, and the royal pin tests after repinning `map3d_layer_units.gd` — Expected: all PASS.
- [ ] **Step 5: Visual review** (visual-review skill): a field battle between two realms at 60 m and 300 m, before/after; the owner rules the colours. Then commit, guide line in `scripts/map3d/CLAUDE.md` (the piece bullet: the tint overlay), open the PR.

---

## PR 2 — Every blow lands

### Task 3: The contact instant and a hit-first reply

**Files:**
- Modify: `scripts/map3d/map3d_duel.gd` (`timing`), `data/screens/map3d/balance.csv` (`map3d_duel_hit` 0.3 → 0.75, first guess)
- Test: `tests/map3d/test_map3d_duel.gd`

**Interfaces:**
- Produces: `Map3DDuel.timing(...)` returns also `"contact_at": float` — the turn time at which strike and reply meet (= `strike_at + strike_len × strike_share`).

- [ ] **Step 1: Failing test** `test_timing_names_the_contact`: `timing(1.2, 0.5, 0.8, 0.25)` → `strike_at 0.0, reply_at 0.4, contact_at 0.6, end 1.2`; `timing(0.6, 0.25, 1.0, 0.75)` → `strike_at 0.6, reply_at 0.0, contact_at 0.75, end 1.2`.
- [ ] **Step 2: Run** `./run_tests.sh --test tests/map3d/test_map3d_duel.gd` — Expected: FAIL (no `contact_at`).
- [ ] **Step 3: Implement**; change the balance key and its description (owner 2026-11-21: 当一方的兵人attack时，对方的动画应该是被hit的动画).
- [ ] **Step 4: Run** — Expected: PASS. **Step 5: Commit.**

### Task 4: `Map3DImpact`, the pure curves

**Files:**
- Create: `scripts/map3d/map3d_impact.gd` (`class_name Map3DImpact`, RefCounted, static only)
- Modify: `data/screens/map3d/balance.csv` (`map3d_melee_hitstop_s` 0.08, `map3d_melee_knock_h` 0.15, `map3d_melee_knock_out_s` 0.12, `map3d_melee_knock_back_s` 0.35, `map3d_melee_block_knock` 0.4)
- Test: `tests/map3d/test_map3d_impact.gd`

**Interfaces:**
- Produces: `static func held(since_contact: float, hold_s: float) -> bool` (true for `0 ≤ since < hold`); `static func knock(since_contact: float, out_s: float, back_s: float) -> float` (0 before contact, eases 0→1 over `out_s` (ease-out), 1→0 over `back_s` (ease-in-out), 0 after); `static func tune_of(repo: DataRepository) -> Dictionary` (`hitstop`, `knock_h`, `knock_out`, `knock_back`, `block_knock`).

- [ ] **Step 1: Failing tests** `test_held_is_the_hitstop_window` (`held(-0.01,0.08)` false, `held(0,0.08)` true, `held(0.079,0.08)` true, `held(0.08,0.08)` false); `test_knock_goes_out_and_back` (`knock(-0.1,..)=0`, `knock(0.12,0.12,0.35)=1`, `knock(0.06,0.12,0.35)` = ease-out(0.5) hand-computed, `knock(0.47,0.12,0.35)=0`, `knock(1,..)=0`).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS). **Step 5: Commit.**

### Task 5: Impact in the duel driver

**Files:**
- Create: `scripts/map3d/map3d_impact_bursts.gd` (`class_name Map3DImpactBursts`, a pool), in the editor: `scenes/map3d/effects/impact_spark.tscn`, `scenes/map3d/effects/impact_dust.tscn` (one-shot `GPUParticles3D`), `assets/3D/effects/impact_bursts.tres` (`ArtTable`: `BLOCK` → spark, `HIT` → dust)
- Modify: `scripts/map3d/map3d_duel_driver.gd` (`_begin`, `_advance`, `_release`, `run`), `scripts/map3d/map3d_battle_groups.gd` (`_target` adds `child.get("knock_offset", Vector2.ZERO)`), `data/screens/map3d/balance.csv` (`map3d_impact_burst_max` 12, `map3d_impact_near_m`)
- Test: `tests/map3d/test_map3d_impact_driver.gd`

**Interfaces:**
- Consumes: `Map3DDuel.timing(...)["contact_at"]`, `Map3DImpact.held/knock/tune_of`.
- Produces: the driver emits each contact as `{"kind": "HIT"|"BLOCK", "at": Vector3, "striker": Dictionary, "struck": Dictionary}` into `func take_impacts() -> Array` (drained each step; PR 4 plays sounds from it); `Map3DImpactBursts.new(parent: Node3D, table: ArtTable, max_live: int)` with `func burst(kind: String, at: Vector3) -> bool` (false when `max_live` are live) and `func live_count() -> int`.
- Rules: at `contact_at` both anims of the pair hold `speed_scale 0` for `hitstop` (the pair's turn clock stands too); the struck figure's child gets `knock_offset = away × knock_h × h × knock(...)` (×`block_knock` on BLOCK) and its piece is returned as placed while it is non-zero; a burst at the midpoint of the pair at half a figure height, only within `map3d_impact_near_m` of the camera (farther: no burst, no knock, hit-stop kept). Release clears `knock_offset` and any hold. The bursts' parent is the pieces' parent node (the layer's `Units`), created on first use.

- [ ] **Step 1: Failing tests** `test_contact_freezes_the_pair` (after the turn crosses `contact_at`, both `speed_scale == 0` until `hitstop` has passed, then 1); `test_the_struck_figure_is_knocked_back` (offset points from striker to struck, peak `knock_h × h` at `knock_out` after contact, 0 at `knock_out + knock_back`); `test_a_block_knocks_less` (peak × 0.4); `test_contact_emits_one_impact` (exactly one entry per turn, kind = the reply kind); `test_bursts_are_capped` (13 bursts with max 12 → the 13th returns false); `test_a_battle_ending_mid_impact_restores_the_figures` (release during hold and knock → `speed_scale 1`, no `knock_offset`); `test_a_pause_inside_the_hitstop_keeps_its_remainder` (pause at 0.03 s into a 0.08 s hold, resume: frozen for 0.05 s more, then 1).
- [ ] **Step 2: Run** `./run_tests.sh --test tests/map3d/test_map3d_impact_driver.gd` — Expected: FAIL.
- [ ] **Step 3: Implement**; author the two particle scenes and the table in the editor.
- [ ] **Step 4: Run** it plus `test_map3d_duel_driver.gd`, `test_map3d_fall_driver.gd`, `test_map3d_battle_groups.gd`, `test_map3d_battle_walk.gd`, the royal pin tests after repinning — Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 6: No one fights air

**Files:**
- Modify: `scripts/map3d/map3d_duel_driver.gd` (`run`: front figures left unpaired in a fought battle are claimed as `waiting`)
- Test: `tests/map3d/test_map3d_duel_driver.gd`

**Interfaces:**
- Rule: an unpaired front figure of a battle with `rounds > 0` is claimed (`duel` meta, chain stopped), plays GARRISON, and takes `duel_yaw` toward the nearest foe figure; when it becomes pairable it pairs; when the battle goes it is released like a duellist.

- [ ] **Step 1: Failing tests** `test_an_unpaired_front_figure_guards_facing_a_foe` (3 v 1: two figures GARRISON, `duel` meta set, yaw toward the foe ±1°); `test_a_waiting_figure_takes_a_fallen_partners_place` (the waiting figure pairs with the foe after its duellist falls).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS).
- [ ] **Step 5:** Record a field battle (60 m, 150 m), review contact, hit-stop and bursts frame by frame with an independent critic, retune the keys, update `battle_duels.md` (Impact section), commit, open the PR.

---

## PR 3 — The mixed fight

**Starts only after the step-in walk fix (`claude/duel-step-in-walk`) has merged.** Its paced walk carries every `duel_offset` change; Task 8 lifts the step limit for scrum figures and relies on it for the feet. Read that PR's guide changes first.

### Task 7: `Map3DScrum`, the pure geometry

**Files:**
- Create: `scripts/map3d/map3d_scrum.gd` (`class_name Map3DScrum`, static only)
- Modify: `data/screens/map3d/balance.csv` (`map3d_melee_depth_h` 4, `map3d_melee_space_h` 0.8, `map3d_melee_push_h` 0.2)
- Test: `tests/map3d/test_map3d_scrum.gd`

**Interfaces:**
- Produces: `static func area(a: Array[Vector2], b: Array[Vector2], across: Vector2, depth: float) -> Dictionary` → `{centre: Vector2, along: Vector2, across: Vector2, half_len: float, half_depth: float}` (along = across rotated 90°; length spans both sides' extent along the front; centre on the midpoint between the two sides' mean points; `half_depth = depth / 2`); `static func target(key: String, area: Dictionary) -> Vector2` (a point inside, from `Map3DMarchLag.unit(key + "|u")` and `"|v"`); `static func separate(points: Dictionary, space: float, push_max: float) -> Dictionary` (one pass: each pair closer than `space` pushed apart equally along their line, each move ≤ `push_max`, keys iterated sorted); `static func pairs_nearest(a: Array, b: Array, reach: float) -> Array` (`[{a, b}]` by ascending distance, ties by key, each figure once, none beyond reach).

- [ ] **Step 1: Failing tests** `test_area_spans_both_fronts` (two rows of 3 at y = ±2, x = 0..4, across (0,1), depth 4 → centre (2,0), half_len 2, half_depth 2); `test_targets_stay_inside` (100 keys, all within the rectangle); `test_targets_are_stable` (same key twice → same point); `test_separate_pushes_overlaps_apart` ((0,0),(0.5,0) with space 0.8, push 0.2 → (−0.15,0),(0.65,0)); `test_separate_moves_at_most_push` ; `test_pairs_nearest_is_greedy_and_stable` (hand-laid 3 v 2 → expected pairs, the third figure unpaired).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS). **Step 5: Commit.**

### Task 8: The scrum in the driver

**Files:**
- Modify: `scripts/map3d/map3d_duel_driver.gd` (`gather`: both ranks of every infantry piece that duels, except the standard bearer; `run`: per battle, `Map3DScrum.area` → targets → `separate` → `pairs_nearest`; `_aim`: a scrum figure's `duel_offset` = its separated target pulled toward its partner to `close_h × h`, minus its stand point, no `step_max_h` clamp)
- Modify: `data/screens/map3d/balance.csv` descriptions of `map3d_duel_step_max_h` (front-line duels only)
- Test: `tests/map3d/test_map3d_scrum_driver.gd`

**Interfaces:**
- Consumes: Task 7's functions; Task 6's `waiting` claim for figures left unpaired.
- Produces: a figure dict's `"rank"` (`front`/`reserve`) and `"bearer": bool` from `gather`; `Map3DDuelDriver.scrum_targets(battle_id: int) -> Dictionary` (key → Vector2, for tests and the bench).
- Rules: one area per battle over all opposed infantry figures (`att` side vs `def` side); other arms are not gathered; a side with no drawn figures → no scrum; the bearer keeps its slot; leaving (battle over, unit gone) releases to the slot.

- [ ] **Step 1: Failing tests** `test_both_ranks_enter_the_area` (2 × 10 figures → 18 claimed (bearers out), every offset target inside the area); `test_the_bearer_keeps_its_slot`; `test_scrum_figures_keep_their_space` (after `run`, no two claimed figures' targets closer than `space − 1e-3` given room); `test_a_withdrawing_unit_walks_back` (drop one side → every figure released, offsets cleared, foes released or waiting).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS) with `test_map3d_duel_driver.gd`, `test_map3d_fall_driver.gd`, `test_map3d_battle_groups.gd`. **Step 5: Commit.**

### Task 9: Edges — falls, fog, mixed arms

**Files:**
- Test: `tests/map3d/test_map3d_scrum_driver.gd`; modify `map3d_duel_driver.gd` / `map3d_fall.gd` only where a test fails.

- [ ] **Step 1: Tests** `test_a_fall_in_the_scrum_lies_where_it_fought` (the body's `fallen` child keeps its scrum offset; the walker's child has `step_up` and a target in the area); `test_no_scrum_against_unseen_figures` (side b empty in `gather` → nobody claimed for the scrum); `test_one_area_per_battle_archers_stay_out` (3 infantry + 1 archer pieces v 2 infantry → one area, the archer piece's figures unclaimed).
- [ ] **Step 2: Run**; fix what fails, each fix RED→GREEN. **Step 3: Commit.**

### Task 10: Picks and the glow in the crowd

**Files:**
- Modify: `scripts/map3d/map3d_battle_groups.gd` (`place` records `piece["figure_rects"]: Array[Rect2]`, one per drawn figure), `scripts/map3d/map3d_picker.gd` (before `_nearest_piece`, a figure box holding the click wins; several → the one whose bottom edge is lowest on screen, i.e. nearest the camera), the accessor that hands `unit_rects()` to the picker (add figure rects without net growth of `map3d_layer_units.gd`)
- Test: `tests/map3d/test_map3d_picker.gd`

**Interfaces:**
- Produces: `static func figure_at(figure_rects: Dictionary, pos: Vector2) -> String` in `Map3DPicker` (code → Array[Rect2]).

- [ ] **Step 1: Failing tests** `test_a_click_on_a_scrum_figure_picks_its_unit` (two units' boxes overlap; the click is inside only B's figure box → B); `test_the_nearer_figure_wins` (inside both figures' boxes → the lower bottom edge); `test_glow_follows_each_figure` (a selected unit's glow children sit under each figure's drawn point).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS); repin and run the royal tests. **Step 5: Commit.**

### Task 11: The bench gate (and animation LOD only if it fails)

**Files:**
- Modify: `tools/map3d/bench.gd` (`--battle-arm ARM`: stage a field battle of that arm as `tools/snapshot_screen.gd` does — move its staging into a shared helper both call — and frame it at each zoom)
- Conditional create: `scripts/map3d/map3d_anim_lod.gd` (`static func every_n(dist_m: float, near_m: float, far_m: float, n_far: int) -> int`; figures beyond `near` switch their `AnimationPlayer` to manual process and `advance` every n frames)

- [ ] **Step 1:** Run the bench with `--battle-arm foot` at each tier's `bench_size` on an idle GPU (no ComfyUI job): record median/p95 against `bench_budget_ms` before (main) and after (this branch).
- [ ] **Step 2:** Within budget at every tier → ledger the numbers, skip LOD. Over budget → write `test_every_n_steps_with_distance` (near 1, far `n_far`, linear between), implement `Map3DAnimLod`, re-bench until within budget.
- [ ] **Step 3:** Record the scrum (60 m, 150 m, 300 m), independent critic on motion (feet, overlaps, unison), retune keys, update `battle_duels.md` (Scrum section) and the R-H note, commit, open the PR.

---

## PR 4 — Sound

### Task 12: Source and install the clips

**Files:**
- Create: `assets/audio/units/impact_clash_*.wav`, `assets/audio/units/impact_hit_*.wav` (+ `.import`), `assets/audio/units/impact_sounds.tres` (`ArtTable`: `BLOCK` → clash, `HIT` → hit; several variants per key as an `Array` if the table allows, else numbered keys `BLOCK_1..`), lines in `assets/audio/units/SOURCES.md`; `scripts/ui/game_art.gd` (`UNIT_IMPACT_SOUNDS`)

- [ ] **Step 1:** Find CC0 candidates; **ask the owner per file (name, source URL, size) before each download**; originals into the git-ignored `source/`, cut and normalised copies committed.
- [ ] **Step 2: Commit.**

### Task 13: Play them on contact

**Files:**
- Modify: `scripts/map3d/map3d_unit_sound.gd` (`static func impact(repo: DataRepository, camera: Camera3D, at_node: Node3D, stream: AudioStream, live: int) -> bool` on the pattern of `one_shot`, refusing past `map3d_impact_voices` live players), the layer/driver hook that drains `take_impacts()` (no net growth of the layer), `data/screens/map3d/balance.csv` (`map3d_impact_db`, `map3d_impact_voices` 6)
- Test: `tests/map3d/test_map3d_unit_sound.gd`

- [ ] **Step 1: Failing tests** `test_an_impact_plays_its_kind` (HIT → a player with the HIT stream on the struck figure's node); `test_impacts_are_capped` (7th live → refused); `test_far_impacts_are_silent` (past `map3d_unit_sound_far_m` → none).
- [ ] **Step 2–4:** run (FAIL), implement, run (PASS).
- [ ] **Step 5:** Record with sound (`--write-movie` keeps audio in the AVI), owner listens, retune `map3d_impact_db`, commit, open the PR.
