# Infantry Duels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In a battle that has fought a round, opposing front-rank infantry figures pair off and duel (strike → block or impact → guard → reply), and each group the engine removes is shown as a duelling front figure falling while the removed figure steps up into its place.

**Architecture:** View-only, under `scripts/map3d/`. Two pure classes (`Map3DDuel`: pairing and the hashed turn schedule; `Map3DFall`: which figure falls and the slot swap) with GUT tests, driven by a thin node-level driver (`Map3DDuelDriver`) that `Map3DLayerUnits.step` calls once a frame for `physical_groups` pieces. New clips are retargeted in the owner's Blender and appended to the installed `infantry.glb`.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, Blender 4 + Auto-Rig Pro over MCP, Python glTF append tooling.

**Spec:** `docs/superpowers/specs/2026-11-16-infantry-duel-animation-design.md`

## Global Constraints

- View-only: no file under `scripts/engine/` changes; no new `GameState` field, no save change, no `GameState.rng` draw. Every choice is hashed with `Map3DMarchLag.unit(key)`.
- Nothing under `scripts/map3d/` reads the `Game` autoload; everything comes through `Map3DContext` (`ctx.state()`, `ctx.repo`, `ctx.clock_speed()`).
- Fog: only admitted (drawn) figures pair; no foe order or stance is read. "Who strikes first" is the battle record's `att` side.
- Tuning values are `data/screens/map3d/balance.csv` keys (`key,value,notes`, a note on each); per-clip data is `data/screens/map3d/army_art.csv` columns. No constants in code beyond structure.
- A pair forms only between two infantry figures with role `front`, both drawn, same battle, battle `rounds > 0`.
- One fall per removed group, at the moment `Map3DBattleGroups.sync` sees it removed; after the step-up walk every saved row has exactly one figure at its saved point. Saved rows/points are never written.
- Figures dropped with their whole piece (battle ended, unit destroyed/surrendered/left) vanish as today.
- Pause (`ctx.clock_speed() == 0`) freezes duels mid-motion; 2x/4x leave the duel tempo as at 1x.
- Clips are APPENDED to `assets/3D/units/infantry/infantry.glb`; existing clips, MARCH's certified stride/steps and the pivot bake stay byte-identical. No Hunyuan3D.
- Each step lands as its own PR against `main` (PR 1 = Tasks 1–2, PR 2 = Tasks 3–6, PR 3 = Tasks 7–9), body with `prd_step:`, `player_outcome:`, `wired:` lines; each visual result through the `visual-review` skill in a real window (never `--headless` for 3D).

## Review Focus

1. Uneven fronts (5 vs 2 front figures, or 0 on one side): pairs are centred, never cross, extras stay on today's behaviour; 0 → no pairs, no error. → Task 3 test `test_pairs_centre_the_shorter_side`, `test_no_front_no_pairs`.
2. A clip missing from a model (a model with no BLOCK or no DEATH): that arm never duels / the removed figure is freed as today, no crash. → Task 3 `test_an_arm_without_its_duel_clips_does_not_duel`, Task 7 `test_no_death_clip_frees_as_today`.
3. Two groups removed in one sync, more removals than paired front figures: one fall per removal, distinct fallers, the rest fall where they stand. → Task 7 `test_more_removals_than_pairs`.
4. Pause in the middle of a strike and resume: both figures of the pair resume in sync (no drift). → Task 5 `test_pause_freezes_and_resumes_in_step`.
5. A pair's opponent removed by a regroup/load (not a loss): the survivor drops back to guard and is re-paired, nothing falls. → Task 8 `test_a_regroup_removes_without_a_fall`.

---

## PR 1 — Clips

### Task 1: Retarget and append BLOCK, BLOCK_2, IMPACT, IMPACT_2, DEATH

**Files:**
- Create: `tools/units3d/soldier_arp/duel_clips.py` (Blender CLI: appends baked clips to a GLB, like the pivot bake: new animation buffers only, every existing JSON section and binary byte kept)
- Modify: `tools/units3d/soldier_arp/README.md` (a "Duel clips" section: sources, steps, the command)
- Modify: `assets/3D/units/infantry/infantry.glb`, `assets/3D/units/infantry/infantry.glb.import`

**Interfaces:**
- Produces: clips `BLOCK`, `BLOCK_2`, `IMPACT`, `IMPACT_2`, `DEATH` on the infantry's `AnimationPlayer`; all `loop_mode` 0 in the `.import`.

- [ ] **Step 1:** Unzip `~/Downloads/Sword and Shield Pack.zip` into a new empty folder under `assets/3D/units/soldier/model_wip/duel_sources/` (git-ignored). Sources: `sword and shield block.fbx` → BLOCK, `block (2)` → BLOCK_2, `impact.fbx` → IMPACT, `impact (2)` → IMPACT_2, `death.fbx` → DEATH.
- [ ] **Step 2:** In the owner's open Blender (MCP, `blender-natural-animation` skill), on `soldier_knight_arp.blend`'s rig, retarget each through `retarget.py`'s path, `fix_grip` the sword and shield as `rebuild.py` does for the attacks; root motion removed; DEATH keeps its fall to the ground. Save the actions; never touch another session's file.
- [ ] **Step 3:** Bake and append: `Blender --background --factory-startup --python tools/units3d/soldier_arp/duel_clips.py -- assets/3D/units/infantry/infantry.glb OUT.glb REVIEW_DIR`; the script asserts none of the five names exist yet, and that every pre-existing animation's accessors are unchanged byte for byte.
- [ ] **Step 4:** Install OUT.glb over `infantry.glb`; set the five clips `loop_mode` 0 in the `.import`; one import pass (`Godot --headless --path . --import`).
- [ ] **Step 5:** Run `./run_tests.sh --test tests/map3d/test_infantry_pivot.gd` and `python3 tools/units3d/soldier_arp/test_pivot_mapping.py`. Expected: PASS unchanged (pivot and MARCH untouched).
- [ ] **Step 6:** `visual-review`: shoot each new clip on the piece (`tools/units3d/shoot_glb.py` or a real-window snapshot) — sword in hand, shield on arm, feet on the ground, no hand flipped. Fix in Blender until the critic passes.
- [ ] **Step 7:** Commit `tools/units3d/soldier_arp/duel_clips.py`, README, the GLB and `.import`.

### Task 2: Duel data on the infantry row

**Files:**
- Modify: `data/screens/map3d/army_art.csv` (two new columns `duel`, `contact`; `infantry` row filled, other rows blank)
- Modify: `scripts/map3d/map3d_clip_chain.gd` (generalise the parser)
- Test: `tests/map3d/test_map3d_duel_data.gd`

**Interfaces:**
- Produces: `Map3DClipChain.of_column(art: Dictionary, column: String) -> Dictionary` (action → [clip]); `of_art(art)` becomes `of_column(art, "chains")`.
- Produces: `Map3DDuel.contact_of(art: Dictionary) -> Dictionary` (clip → share 0..1), parsed from `contact` = `"CLIP:share;CLIP:share"`.
- infantry `duel` = `STRIKE:ATTACK;SLASH;ATTACK_VAR1|BLOCK:BLOCK;BLOCK_2|IMPACT:IMPACT;IMPACT_2|DEATH:DEATH`.
- infantry `contact`: for each strike the share of its length where the blade meets; for BLOCK/BLOCK_2 the share where the shield is fully up; for IMPACT/IMPACT_2 the share of the jolt. Measured from the clips (frame of max sword-tip forward reach; shield-bone peak; hips' peak backward velocity) by `duel_clips.py`'s review output.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_duel_columns_parse() -> void:
	var art := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|IMPACT:IMPACT|DEATH:DEATH",
		"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.3;IMPACT:0.1"}
	assert_eq(Map3DClipChain.of_column(art, "duel")["STRIKE"], ["ATTACK", "SLASH"])
	assert_eq(Map3DDuel.contact_of(art), {"ATTACK": 0.4, "SLASH": 0.35, "BLOCK": 0.3, "IMPACT": 0.1})
	assert_eq(Map3DDuel.contact_of({}), {})

func test_the_infantry_row_names_installed_clips_with_contacts() -> void:
	var repo: DataRepository = SuiteData.repo()
	var art: Dictionary = repo.army_art["infantry"]
	var duel := Map3DClipChain.of_column(art, "duel")
	var contact := Map3DDuel.contact_of(art)
	var anim := Map3DUnits.find_anim(load("res://scenes/models/units/infantry.tscn").instantiate())
	for kind: String in ["STRIKE", "BLOCK", "IMPACT", "DEATH"]:
		assert_true(duel.has(kind), kind)
		for clip: String in duel[kind]:
			assert_ne(Map3DUnits.clip_named(anim, clip), "", clip + " is installed")
			assert_eq(anim.get_animation(Map3DUnits.clip_named(anim, clip)).loop_mode, Animation.LOOP_NONE, clip)
			if kind != "DEATH": assert_between(float(contact[clip]), 0.0, 1.0, clip)
```

- [ ] **Step 2:** Run `./run_tests.sh --test tests/map3d/test_map3d_duel_data.gd`. Expected: FAIL (`of_column` / `Map3DDuel` not defined).
- [ ] **Step 3:** Add `of_column`, a minimal `scripts/map3d/map3d_duel.gd` (`class_name Map3DDuel extends RefCounted`) with `contact_of`, and the two CSV columns (notes column: cite the spec).
- [ ] **Step 4:** Run the test, plus `--test tests/map3d/test_map3d_clip_chain.gd`. Expected: PASS.
- [ ] **Step 5:** Commit; open PR 1 (`prd_step:` the spec's step 1, `player_outcome:` none yet — clips only, `wired: no`).

---

## PR 2 — Duels

### Task 3: Pairing

**Files:**
- Modify: `scripts/map3d/map3d_duel.gd`
- Test: `tests/map3d/test_map3d_duel.gd`

**Interfaces:**
- Produces: `Map3DDuel.duels(art: Dictionary, anim: AnimationPlayer) -> bool` — the arm's `duel` names STRIKE, BLOCK and IMPACT and every named clip resolves on `anim`.
- Produces: `Map3DDuel.pairs(a: Array, b: Array, across: Vector2, reach_m: float) -> Array` — `a`, `b`: `[{key: String, xz: Vector2}]` (side att, side def); returns `[{a: String, b: String}]` ordered along `across`.

Algorithm (not determined by the test alone): sort each side by `xz.dot(across)`; let S be the shorter, L the longer; choose the offset o in `0..L.size()-S.size()` minimising Σ|S[i].dot − L[i+o].dot| (ties: smallest o); pair S[i] ↔ L[i+o]; drop a pair whose `xz` distance exceeds `reach_m`.

- [ ] **Step 1: Write the failing tests** — `test_pairs_in_order_along_the_front` (3 v 3 at across −10, 0, 10 → pairs a0-b0, a1-b1, a2-b2, keys preserved); `test_pairs_centre_the_shorter_side` (a at −20, −10, 0, 10, 20; b at −5, 5; Σ by offset 30, 10, 10, 30 → tie, smallest o = 1 → b(−5)↔a(−10), b(5)↔a(0)); `test_no_front_no_pairs` (empty side → `[]`); `test_beyond_reach_is_not_a_pair`; `test_an_arm_without_its_duel_clips_does_not_duel` (an `AnimationPlayer` with STRIKE clips but no BLOCK → false; full set → true).
- [ ] **Step 2:** Run `./run_tests.sh --test tests/map3d/test_map3d_duel.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement `duels` and `pairs`.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 4: The turn schedule

**Files:**
- Modify: `scripts/map3d/map3d_duel.gd`
- Modify: `data/screens/map3d/balance.csv` (keys below)
- Test: `tests/map3d/test_map3d_duel.gd`

**Interfaces:**
- Produces: `Map3DDuel.turn(pair_key: String, n: int, strikes: int, variants: int, steal: float, double: float, impact: float) -> Dictionary` → `{striker: "a"|"b", strike: int (0..strikes-1), reply: "BLOCK"|"IMPACT", reply_variant: int (0..variants-1), rest_u: float (0..1)}`, every value hashed with `Map3DMarchLag.unit("%s|duel|%d|<field>" % [pair_key, n])`. Turn 0's striker is `"a"` (the att side). Turn n>0: the other of turn n−1's striker, except the same again when `unit(…|who) < double`; then a `"b"` turn is taken by `"a"` when `unit(…|steal) < steal` (the attacker strikes a little more often). `reply` is IMPACT when `unit(…|reply) < impact`. The striker sequence depends on earlier turns, so `turn` walks turns 0..n (n is small: a few per minute).
- Produces: `Map3DDuel.timing(strike_len: float, strike_share: float, reply_len: float, reply_share: float) -> Dictionary` → `{strike_at: float, reply_at: float, end: float}`: seconds from the turn's start; the earlier of the two starts at 0, the contact moments coincide (`strike_at + strike_len*strike_share == reply_at + reply_len*reply_share`), `end` is the later clip end.
- Balance keys (value, note): `map3d_duel_steal` 0.15, `map3d_duel_double` 0.15, `map3d_duel_impact` 0.3, `map3d_duel_rest_min_s` 0.3, `map3d_duel_rest_max_s` 0.9, `map3d_duel_reach_m` and `map3d_duel_step_max_m` (values from Task 5 Step 1's measurement).

- [ ] **Step 1: Write the failing tests** — `test_turn_is_stable_and_in_range` (same inputs → same dict; over 40 turns with strikes 3, variants 2: `strike` in 0..2, `reply_variant` in 0..1, `rest_u` in 0..1); `test_turn_zero_is_the_attackers`; `test_turns_alternate_without_double_or_steal` (`steal` 0, `double` 0 → a, b, a, b…; `steal` 1 → always a); `test_impact_share` (impact 0 → never IMPACT over 50 turns; 1 → always); `test_timing_meets_at_contact` (strike 1.0 s at 0.4, reply 0.8 s at 0.25 → reply_at 0.2, strike_at 0.0, end 1.0; reversed when the reply's contact is later: strike 0.5 s at 0.2, reply 1.0 s at 0.5 → strike_at 0.4, reply_at 0.0, end 1.0).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `turn` and `timing`; add the balance keys with notes ("view-only, spec 2026-11-16 infantry duels").
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 5: The driver — pairs on the map, pause, facing

**Files:**
- Create: `scripts/map3d/map3d_duel_driver.gd` (`class_name Map3DDuelDriver extends RefCounted`)
- Modify: `scripts/map3d/map3d_layer_units.gd` (own one driver; call it from `step` after the physical-groups loop; `_sync_action` leaves a duelling figure alone)
- Modify: `scripts/map3d/map3d_battle_groups.gd` (`_target` adds `child.get("duel_offset", Vector2.ZERO)` to `xz` and uses `child["duel_yaw"]` when present, so the existing `_walk` eases into and out of the duel spot)
- Test: `tests/map3d/test_map3d_duel_driver.gd`

**Interfaces:**
- Consumes: `Map3DDuel.duels/pairs/turn/timing/contact_of`, `Map3DClipChain.of_column`, `BattleSystem.battle_of(state, code)` (its `att` list and `rounds`).
- Produces: `Map3DDuelDriver.step(ctx: Map3DContext, pieces: Dictionary, delta: float) -> bool` (true when a duel offset changed and the caller must `_place` that piece); `is_duelling(anim: AnimationPlayer) -> bool`; `paired_slots(code: String) -> Array[int]` (for Task 7).
- Per pair it keeps `{a_anim, b_anim, t: float, n: int, turn: Dictionary, timing: Dictionary, started: {a: bool, b: bool}}`; `t` advances by `delta` only while `ctx.clock_speed() > 0`; when paused every duelling `AnimationPlayer.speed_scale` is 0, restored to 1 on resume. A clip is started (`anim.play(clip, 0.15)`, `seek(0)`) when `t` crosses its `strike_at`/`reply_at`; between turns both stand in GARRISON for `rest_min + rest_u*(rest_max-rest_min)`.
- Pair key: `"%s:%d|%s:%d" % [code_a, slot_a, code_b, slot_b]`. Pairs are rebuilt only when the set of front keys of a battle changes; surviving pair keys keep their state.
- Duel offset: each figure of a pair moves toward the other by `min(map3d_duel_step_max_m, max(0, (gap − map3d_duel_reach_m)/2))` along the line between them; `duel_yaw` faces the other.

- [ ] **Step 1: Measure (no code).** In a real window, a battle of two infantry units after round 1 (DEV MODE), read `Map3DLayerUnits.group_geometry()` for both units' front figures: the drawn XZ gap between facing front figures and each figure's drawn height. Set `map3d_duel_reach_m` to the largest front-to-front gap seen ×1.25 and `map3d_duel_step_max_m` so the gap closes to roughly one figure height × 0.6 (sword's length at the miniature's scale). Record the numbers in the keys' notes.
- [ ] **Step 2: Write the failing tests** with a hand-built `Map3DContext` (`clock_fn`/`day_fn` callables) and two stub pieces of `AnimationPlayer`s carrying stub clips (lengths 1.0 s, contact shares as in Task 4's timing test): `test_two_fronts_pair_after_the_first_round` (rounds 0 → no pairs; 1 → pairs); `test_the_strike_and_reply_meet` (step through 1 s in 0.05 s frames: the reply clip starts at 0.2 s, the strike at 0.0); `test_pause_freezes_and_resumes_in_step` (pause at 0.1 s for 2 s of frames: `t` unchanged, `speed_scale` 0 on both; resume: both 1, the reply still starts 0.1 s later); `test_a_foe_without_rounds_is_left_alone`; `test_an_unpaired_front_keeps_its_chain` (`is_duelling` false for the extra figure); `test_fast_clock_keeps_tempo` (clock speed 4: `t` advances by `delta`, not 4×); `test_unpairing_returns_to_the_saved_spot` (opponent gone → `duel_offset` / `duel_yaw` erased from both children, the step reports the piece for `_place`).
- [ ] **Step 3:** Run `./run_tests.sh --test tests/map3d/test_map3d_duel_driver.gd`. Expected: FAIL.
- [ ] **Step 4:** Implement the driver and the two small hooks; the layer passes `ctx` and `_pieces` and `_place`s each code the driver reports.
- [ ] **Step 5:** Run the driver test plus `tests/map3d/test_map3d_battle_groups.gd`, `test_map3d_battle_walk.gd`, `test_map3d_battle_signals.gd`, `test_map3d_clip_chain.gd`. Expected: PASS.
- [ ] **Step 6:** Commit.

### Task 6: Visual review and the guide

**Files:**
- Create: `scripts/map3d/guide/battle_duels.md` (the rules as they stand: pairing, schedule, pause, data keys)
- Modify: `scripts/map3d/CLAUDE.md` (one Topic guides line naming `Map3DDuel`, `Map3DDuelDriver`, later `Map3DFall`)

- [ ] **Step 1:** `visual-review` in a real window (`tools/snapshot_screen.gd --resolution 1920x1080` and the near zoom), variants of `map3d_duel_rest_*` and `map3d_duel_step_max_m`; critic checks: no air swings by paired figures, no pair in step with its neighbour, shields meet blades, no overlap, paused frame frozen.
- [ ] **Step 2:** Write the guide and index line; run `./run_tests.sh --test tests/engine/test_claude_md_size.gd`. Expected: PASS.
- [ ] **Step 3:** Commit; open PR 2 (`player_outcome:` front-rank infantry duel in battle, `wired: yes`).

---

## PR 3 — Falls and step-up

### Task 7: Which figure falls, and the swap

**Files:**
- Create: `scripts/map3d/map3d_fall.gd` (`class_name Map3DFall extends RefCounted`)
- Test: `tests/map3d/test_map3d_fall.gd`
- Modify: `data/screens/map3d/balance.csv` (`map3d_fall_hold_s` 2.0, `map3d_fall_fade_s` 1.5)

**Interfaces:**
- Produces: `Map3DFall.plan(code: String, removed: Array[int], paired: Array[int], kept: Array[int], n: int) -> Array` → `[{removed: int, faller: int}]`, one entry per removed slot, in `removed` order. `faller` is a distinct slot drawn from `paired ∩ kept` by hash (`Map3DMarchLag.unit("%s|fall|%d|%d" % [code, removed_slot, n])` over the remaining candidates); when no candidate is left, `faller == removed` (it falls where it stands).
- Produces: `Map3DFall.alpha(elapsed: float, hold_s: float, fade_s: float) -> float` — 1 until `hold_s`, then linear to 0 over `fade_s`.

- [ ] **Step 1: Write the failing tests** — `test_one_fall_per_removal_from_the_duel` (removed [9], paired [1,2,3] → one entry, faller in [1,2,3], stable); `test_more_removals_than_pairs` (removed [8,9], paired [2] → fallers {2, 9 or 8 itself}: exactly one uses 2, the other falls as itself, fallers distinct); `test_no_pairs_falls_where_it_stands` (paired [] → faller == removed); `test_alpha_holds_then_fades` (hold 2, fade 1.5: 0→1, 2→1, 2.75→0.5, 3.5→0); `test_no_death_clip_frees_as_today` lives in Task 8.
- [ ] **Step 2:** Run `./run_tests.sh --test tests/map3d/test_map3d_fall.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 8: Falls on the map

**Files:**
- Modify: `scripts/map3d/map3d_battle_groups.gd` (`sync` takes an optional `falls: Callable`; when set and the unit's battle continues, removed children are handed to it instead of `queue_free`)
- Modify: `scripts/map3d/map3d_duel_driver.gd` (owns falling bodies: plays DEATH, fades with `Map3DFall.alpha` through `Map3DCourierRide.apply`, frees; ends the faller's pair, the opponent to GARRISON)
- Modify: `scripts/map3d/map3d_layer_units.gd` (passes the driver's `fall` callable into `BattleGroupsView.sync` only for a loss refresh: same battle id, same group size/version as the last sample, fit count lower)
- Test: `tests/map3d/test_map3d_fall_driver.gd`

**Interfaces:**
- Consumes: `Map3DFall.plan/alpha`, `Map3DDuelDriver.paired_slots(code)`.
- The swap inside `sync`: for each `{removed, faller}` with `faller != removed`, the removed slot's child becomes the faller slot's child (its `at` stays where it stood, so `_walk` walks it to the faller's saved point), and the faller's old child is handed to `falls` as the body. With `faller == removed` the removed child itself is the body.
- A body is reparented under the piece's node (top_level as now), so it is freed with the piece if the piece is dropped.

- [ ] **Step 1: Write the failing tests** with a stub piece of 6 groups (slots 0..5; 0..2 front, paired 1 and 2) and a stub driver: `test_a_loss_drops_a_duellist_and_the_tail_steps_up` (sample with slot 5 removed → one body, from slot 1 or 2; that slot's row now holds the old slot-5 node walking from slot 5's place; after `map3d_battle_walk_s` of `tick`, 5 drawn nodes at the 5 saved points); `test_the_body_falls_then_fades_and_is_freed` (DEATH playing; alpha 1 at hold, 0 after hold+fade; node freed); `test_a_regroup_removes_without_a_fall` (group size version changed → `queue_free` as today, no body); `test_no_death_clip_frees_as_today` (model without DEATH → no body).
- [ ] **Step 2:** Run `./run_tests.sh --test tests/map3d/test_map3d_fall_driver.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement the hook, the swap and the bodies.
- [ ] **Step 4:** Run it plus every test from Task 5 Step 5. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 9: Visual review, guide, PR

- [ ] **Step 1:** `visual-review` in a real window: a battle where a group is lost (DEV MODE, a heavy round): the duellist falls on its opponent's impact moment or close to it, holds, fades; the flank figure walks in without crossing others; final count matches. Variants of `map3d_fall_hold_s` / `_fade_s`.
- [ ] **Step 2:** Add the falls section to `scripts/map3d/guide/battle_duels.md`.
- [ ] **Step 3:** Commit; open PR 3 (`player_outcome:` lost groups fall in the duel and the line closes up, `wired: yes`).
