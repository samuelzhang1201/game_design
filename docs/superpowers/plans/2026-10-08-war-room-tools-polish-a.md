# War Room Tools Polish — Batch A (interaction logic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the war room's selection, drawing tools and undo behave predictably (spec items A1–A15).

**Architecture:** Every change stays in the existing pieces: `WarPlanInput` (the left button for plans and selection), `WarPlanTool` (what is in hand, the undo stack), `WarRoomView` / `WarRoomPointer` (click routing), `WarPlanDesk` / `WarRoomScreen` / `WarFolioPanel` / `WarPlanName` (screen side, keys, writes), one new pure helper `WarDrafts.restore` with its `Game.restore_drafts` writer, and `WarRoom.intel_hints`' id.

**Tech Stack:** Godot 4.7, GDScript (typed), GUT.

**Spec:** `docs/superpowers/specs/2026-10-08-war-room-tools-polish-design.md` (Batch A).

## Global Constraints

- Typed GDScript everywhere; `scripts/war_room/` never reads the `Game` autoload; nothing under `scripts/engine/` names a `scripts/ui/` class.
- Every state write goes through `Game` (the plans: `Game.draw_plan` … `restore_plans`; drafts: `Game.plant_draft` / `strike_draft` / the new `restore_drafts`).
- Design numbers stay `balance.csv` keys (click slop is `war_rake_min_px`; pick radius `war_pick_px`).
- Tests drive the real input path: `view._gui_input(event)` for the pointer, `screen._unhandled_input(key)` for keys. Wait with `wait_process_frames`, never `wait_frames`.
- New UI tests go in a new file `tests/ui/test_war_room_tools.gd` (the two existing room test files are already long); copy the `_room`, `_button`, `_motion`, `_drag`, `_open_land` helpers from `tests/ui/test_war_room_plans.gd` and `_land_piece` / `_land_near` from `tests/ui/test_war_room_screen.gd` (they use `ClearPiece.find`).
- Run `./run_tests.sh --fast` between tasks; the whole `./run_tests.sh` before the last commit (expected error count 2 with the gdai binaries installed).
- Update `scripts/war_room/CLAUDE.md` (Selection, Plans → Input / Screen bullets) in the task that changes the rule it states; write the rule as it stands now.

## Review Focus

1. A stick in hand and a press that lands ON one of our pieces then moves: it must draw (the blue arrow's start is free), not pan or select — Task 4 test `test_a_drag_from_a_piece_with_the_blue_arrow_draws`.
2. Undo across a load: Cmd-Z right after `Game.load_campaign` must do nothing — Task 7 test `test_undo_after_a_new_campaign_does_nothing`.
3. A box drawn over nothing must leave the current selection untouched, not clear it — Task 2 test `test_an_empty_box_keeps_the_selection`.
4. The name box open and the player presses Tab / a digit after clicking the table: the key reaches the desk — Task 6 test `test_a_table_press_commits_the_name_and_keys_work_again`.
5. A sheet laid with the folio of a now-off-sheet unit open: the folio closes and the arrow greys — Task 3 test `test_a_new_sheet_drops_off_sheet_units_and_closes_their_book`.

---

### Task 1: A red selection holds; Esc in order (A1, A10)

**Files:**
- Modify: `scripts/ui/war_room_screen.gd` (`_ready`: the `_folio.closed` connection; `_unhandled_input`)
- Modify: `scripts/ui/war_folio_panel.gd:167-171` (`_unhandled_input`)
- Test: `tests/ui/test_war_room_tools.gd` (new)

**Interfaces:**
- Produces: `WarFolioPanel.escape_closes: bool` (default `true`; the room sets it `false` and closes the folio itself after the desk's Esc chain).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_supposed_piece_clicked_with_our_unit_chosen_stays_selected() -> void:
	# select one of ours by a real click (its folio docks), then click a supposed piece
	# assert: view.plan_input().sel_side == "red", sel == [pid], folio not visible,
	#         roll.slot("arrow", "red").why == ""
func test_escape_lays_the_stick_down_before_closing_the_book() -> void:
	# our unit clicked (folio visible), red front picked from the roll, Esc once:
	# assert tool not in hand, folio still visible, selection still ours
	# Esc again: selection empty and folio hidden
```

- [ ] **Step 2: Run** `./run_tests.sh --fast` is not enough (tests/ui): run `$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_war_room_tools.gd -gexit`. Expected: both FAIL (red selection emptied; Esc closes the book first).

- [ ] **Step 3: Implement**
  - In `WarRoomScreen._ready`, replace `_folio.closed.connect(_view.clear_selection)` with a lambda that clears only when a piece of ours is still the chosen one: `if _view.selected_army() != "": _view.clear_selection()` (`WarRoomView._on_plan_selection` already sets `_selected = ""` before emitting, so a side change no longer loops back).
  - Add `escape_closes` to `WarFolioPanel`; its `_unhandled_input` returns early when false. The room sets `_folio.escape_closes = false` in `_ready`.
  - In `WarRoomScreen._unhandled_input`, after `_plans.key(key)` declines an Escape in table mode and `_folio.visible`, close the folio and mark handled.

- [ ] **Step 4: Run the file again.** Expected: PASS. Then `./run_tests.sh --fast` and `tests/ui/test_war_folio_panel.gd`, `tests/ui/test_war_room_screen.gd` (they cover the folio's Esc).

- [ ] **Step 5: Commit** `fix(war room): a red selection holds over a docked book; Esc lays the stick down before the book`

---

### Task 2: The box selects exactly what lies in it (A2)

**Files:**
- Modify: `scripts/war_room/war_plan_input.gd:330-351` (`_box`)
- Test: `tests/ui/test_war_room_tools.gd`

**Interfaces:**
- Consumes: `WarRoomView.piece_pack_positions() -> Dictionary` (code → pack px of the drawn node), `WarRoomView.screen_pos_of_px`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_box_over_our_units_selects_them_after_red_work() -> void:
	# a supposed piece placed and clicked (red selected, red row lit), then a Shift-drag
	# box round one of our land pieces (its DRAWN screen spot)
	# assert sel_side == "blue" and sel == [that code]
func test_a_second_box_over_the_same_units_keeps_them() -> void:
	# box a unit, box it again: assert sel still == [code]
func test_an_empty_box_keeps_the_selection() -> void:
	# select a unit by click; Shift-drag a box over open table with no piece:
	# assert sel unchanged
```

- [ ] **Step 2: Run the file.** Expected: the first two FAIL (side last lit; toggle removes); the third passes already (keep it as a guard).

- [ ] **Step 3: Implement `_box(box: Rect2) -> void`**: collect OUR land pieces whose drawn spot (`piece_pack_positions()[code]`, else `q["at"]`) projects inside the box; if any, `select("blue", ids, false)`; else collect supposed pieces and hints as today and `select("red", ids, false)`; nothing in the box: no change. Update the CLAUDE.md Selection bullet ("a Shift-drag boxes what lies in it — ours first — replacing the selection").

- [ ] **Step 4: Run the file**, then `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `fix(war room): a box selects what lies in it, ours first, at the drawn spot`

---

### Task 3: A laid sheet trims the selection; fleets never march from the room (A3, A4)

**Files:**
- Modify: `scripts/war_room/war_plan_input.gd` (`why_of`, `_release`'s order branch, new `keep_on_sheet`)
- Modify: `scripts/war_room/war_room_view.gd:380` (`lay_sheet`, before `sheet_laid.emit`)
- Test: `tests/ui/test_war_room_tools.gd`

**Interfaces:**
- Produces: `WarPlanInput.keep_on_sheet() -> void` — drops from `sel` every blue code not in `WarRoom.on_sheet(...)` for the laid sheet and every red id not on it (`WarPlans.pieces_in`, `hints_on_sheet`); emits through `select` so rings, roll and `selection_changed` follow. `WarPlanInput.naval(code: String) -> bool` (`ArmySystem.regiment(repo, code, state).get("is_naval", "0") == "1"`).
- The view, after trimming, clears `_selected` and emits `selection_cleared` when the chosen piece is gone.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_new_sheet_drops_off_sheet_units_and_closes_their_book() -> void:
	# click a land piece (folio visible), view.lay_sheet(another index with no such unit)
	# assert sel.is_empty(), folio hidden, roll.slot("arrow","blue").why != ""
func test_a_fleet_alone_greys_the_blue_arrow() -> void:
	# view.plan_input().select("blue", [a fleet code on the sheet])
	# assert why_of("blue", "arrow") == "Fleets are ordered on the map"
```

- [ ] **Step 2: Run the file.** Expected: FAIL.

- [ ] **Step 3: Implement** `keep_on_sheet`, call it from `lay_sheet` just before `sheet_laid.emit(index)`, then reconcile `_selected`. In `why_of`, for a blue arrow with a selection whose every code is naval return exactly `"Fleets are ordered on the map"`. In `_release`'s order branch emit only the non-naval codes.

- [ ] **Step 4: Run the file**, then `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `fix(war room): a laid sheet trims the selection; fleets are ordered on the map`

---

### Task 4: A click still works with a stick in hand; the blue arrow is laid down after one march (A5, A6)

**Files:**
- Modify: `scripts/war_room/war_room_pointer.gd:44-93` (split the release branch of `on_left` into `click`)
- Modify: `scripts/war_room/war_room_view.gd` (new `click_through`)
- Modify: `scripts/war_room/war_plan_input.gd` (`_press`, `_release`)
- Modify: `scripts/war_room/war_plan_tool.gd` (new `cancel`)
- Test: `tests/ui/test_war_room_tools.gd`

**Interfaces:**
- Produces: `WarRoomPointer.click(at: Vector2, shift: bool) -> bool` — today's release-branch picking (pennant, our piece, edge arrow, chart, aimed ground, let the selection go), true when it took the click; `on_left` calls it. `WarRoomView.click_through(at: Vector2, shift: bool) -> void` calls it. `WarPlanTool.cancel() -> void` ends a drag without a stroke (`drawing = false`, samples cleared, kind kept).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_click_with_a_front_in_hand_selects_our_piece() -> void:
	# red front picked; a press+release (no motion) on a land piece's drawn spot
	# assert code in sel, no stroke written (war_plans.strokes empty), tool still in hand
func test_a_click_on_open_table_with_a_stick_lets_the_selection_go() -> void:
func test_a_drag_from_a_piece_with_the_blue_arrow_draws() -> void:
	# piece selected, blue arrow picked, a drag starting ON the piece to land beyond
	# assert orders().aiming() == code
func test_the_blue_arrow_is_laid_down_once_its_march_is_drawn() -> void:
	# after the drag above: assert not tool.in_hand(); a red front drawn twice stays in hand
```

- [ ] **Step 2: Run the file.** Expected: the click tests and the lay-down test FAIL.

- [ ] **Step 3: Implement**
  - `_press` with a stick in hand records `_click_from = pos` and `_click_shift` and starts the drag as today.
  - `_release` while drawing: when the pointer travelled less than `war_rake_min_px` from `_click_from`, `tool.cancel()`, redraw, then route the click: a supposed piece under it → `choose` + `select("red", [pid], shift)`; an intel hint → `select("red", [hint], shift)`; else `_view.click_through(pos, shift)`. Return true.
  - After `order_drawn.emit(...)`, when `_view.aiming`, `tool.put_down()` and `tool_changed.emit()`.

- [ ] **Step 4: Run the file**, then `tests/ui/test_war_room_screen.gd` (its real blue-arrow tests) and `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(war room): a click still picks with a stick in hand; the blue arrow is laid down after its march`

---

### Task 5: The hand carries only the chosen stroke; red and blue alike (A7, A8)

**Files:**
- Modify: `scripts/war_room/war_plan_input.gd` (`_press` stroke hit, `_release`, the order branch, the red-arrow branch)
- Modify: `scripts/war_room/war_room_view.gd` (new `forget_press`)
- Modify: `scripts/engine/war_room.gd:41-60` (hint id)
- Modify: `tests/engine/test_war_room.gd:257-265`, `tools/snapshot_screen.gd:1523` if it parses the id
- Test: `tests/ui/test_war_room_tools.gd`, `tests/engine/test_war_room.gd`

**Interfaces:**
- Produces: `WarRoomView.forget_press() -> void` (wraps `_pointer.forget_press()`). Hint ids become `"h%d_%d" % [key.x, key.y]` (the place's rounded pack px), one per place.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_drag_from_an_unchosen_stroke_pans_and_a_click_chooses_it() -> void:
	# a phase line drawn via Game.draw_plan; hand in hand; drag from its middle 120 px
	# assert camera target moved and the stroke's points unchanged; then a click on it:
	# assert plan_input().chosen_id == its id; a drag on it now moves it (points shifted)
func test_a_shift_drawn_blue_arrow_marches_straight() -> void:
	# Shift held through the drag: assert orders' armed route has no waypoints
func test_a_red_arrow_for_two_selected_pieces_draws_two() -> void:
	# two supposed pieces Shift-clicked, red arrow dragged: two arrow strokes, `of` each id,
	# each starting at its piece
```
In `tests/engine/test_war_room.gd`: a newer report on the same place keeps the same id (`"h400_300"` for subject x 400, y 300).

- [ ] **Step 2: Run** the UI file and `tests/engine/test_war_room.gd`. Expected: FAIL.

- [ ] **Step 3: Implement**
  - `_press`: a stroke hit whose id is not `chosen_id` (and no handle) sets `_pending_choose = id` and returns false (the pointer and the gestures see the press: a drag pans). In `_release` with no drag: if `_pending_choose != ""` and the release is within `war_rake_min_px` of the press, `choose(it)`, `_view.forget_press()` and return false; always clear `_pending_choose`.
  - The order branch: with `mb.shift_pressed` send `PackedVector2Array([samples[0], samples[-1]])`.
  - The red arrow: one `drawn` per selected id, `pts[0]` replaced by that id's spot (a supposed piece's `WarPlans.at_px`, a hint's `at`), `of` its id.
  - `WarRoom.intel_hints`: the id from the place key. Remove the "removing a hint's place's last report takes its arrows" clause from the spec's A8 (no report is ever removed).

- [ ] **Step 4: Run** both files, then `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `fix(war room): the hand drags only the chosen stroke; Shift straight blue arrows; a red arrow per host; hints keyed by place`

---

### Task 6: The name box never traps the keys; no flicker on release (A9, A11)

**Files:**
- Modify: `scripts/ui/war_plan_name.gd` (`commit`, `focus_exited`)
- Modify: `scripts/war_room/war_room_view.gd` (signal `table_pressed`, `plan_key_shown`, `hide_plan_stroke`)
- Modify: `scripts/war_room/war_room_ink.gd:184-215` (`plan_for(..., hidden := "")`, cache by key and hidden)
- Modify: `scripts/war_room/war_plan_ink.gd` (`strokes(...)` skips `hidden`)
- Modify: `scripts/war_room/war_plan_input.gd` (`_ghost`, drag start/end)
- Modify: `scripts/ui/war_plan_desk.gd` (`bind`: commit the name on `table_pressed`)
- Test: `tests/ui/test_war_room_tools.gd`

**Interfaces:**
- Produces: `WarPlanName.commit() -> void` (= `_done(_edit.text)`); `signal WarRoomView.table_pressed` (emitted at the top of `_gui_input` for any mouse button press in table mode); `WarRoomView.plan_key_shown() -> int` (the `WarPlanInk.cache_key` of the `plan_tex` on the table, -1 none); `WarRoomView.hide_plan_stroke(id: String) -> void` ("" shows all; repaints the plan layer).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_a_table_press_commits_the_name_and_keys_work_again() -> void:
	# draw a phase line (name box opens); _button(view, open land, true/false)
	# assert name box hidden, stroke's name == the default; then KEY_TAB reaches the desk
func test_a_released_stroke_stays_drawn_until_its_layer_is_painted() -> void:
	# draw a front; right after release assert (view.get_node("%PlanHud") as WarPlanHud).drawing()
	# wait_until plan_key_shown() == WarPlanInk.cache_key(state, sheet); then drawing() is false
```

- [ ] **Step 2: Run the file.** Expected: FAIL.

- [ ] **Step 3: Implement**
  - `WarPlanName`: `commit()`; `_edit.focus_exited` → `commit()`. Desk: `view.table_pressed.connect(func() -> void: if _name.visible: _name.commit())`.
  - `plan_for` takes `hidden` and caches on `{key, hidden}`; `WarPlanInk.strokes` leaves the stroke with id `hidden` out. The view keeps `_plan_hidden`, passes it, records `plan_key_shown` when it sets `plan_tex`, and calls `_plan_input.redraw_live()` after.
  - `WarPlanInput`: after a `drawn` / `stroke_shifted` / `stroke_reshaped` emit, keep `_ghost = {"row": the stroke in pack px, "key": WarPlanInk.cache_key(state, sheet)}`; `redraw_live` draws the ghost while `_view.plan_key_shown() != _ghost["key"]`, then drops it. A stroke/handle drag calls `_view.hide_plan_stroke(id)` when it first moves and `hide_plan_stroke("")` on release.

- [ ] **Step 4: Run the file**, `tests/war_room/test_war_plan_ink.gd`, then `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `fix(war room): the name box commits on a table press; a stroke never blinks out on release or shows twice while dragged`

---

### Task 7: Undo — the session's stack, refused writes push nothing, a march undone (A12, A13)

**Files:**
- Modify: `scripts/war_room/war_plan_tool.gd:186-206` (entries, `own`, `remember_drafts`)
- Create: `WarDrafts.restore` in `scripts/engine/war_drafts.gd`
- Modify: `scripts/ui/game.gd` (new `restore_drafts`)
- Modify: `scripts/ui/army_order_menu.gd:~395, ~476` (signal `drafts_planting`)
- Modify: `scripts/ui/war_plan_desk.gd` (`_write`, the Cmd-Z branch, `bind` takes the order menu)
- Modify: `scripts/ui/war_room_screen.gd:127` (pass `_orders` to `_plans.bind`)
- Test: `tests/war_room/test_war_plan_tool.gd`, `tests/engine/test_war_drafts.gd`, `tests/ui/test_war_room_tools.gd`

**Interfaces:**
- Produces:
  - `WarPlanTool.remember(before: Dictionary)` unchanged for plans (stored as `{"plans": before}`); `WarPlanTool.remember_drafts(before: Dictionary)` (`{"drafts": {code: draft or {}}}`); `WarPlanTool.undo(now_of: Callable) -> Dictionary` and `redo(now_of: Callable) -> Dictionary` return an entry (`{"plans": …}` or `{"drafts": …}`), `now_of(entry) -> Dictionary` giving the present counterpart; `WarPlanTool.own(state_id: int) -> void` empties both stacks when `state_id` differs from the last one seen.
  - `WarDrafts.restore(state: GameState, drafts: Dictionary) -> void` — each code: `{}` erases its draft, else sets a deep copy.
  - `Game.restore_drafts(drafts: Dictionary) -> void` → `WarDrafts.restore` then `state_changed.emit()`.
  - `signal ArmyOrderMenu.drafts_planting(codes: Array)` — emitted in drafting mode just before the march's `plant_draft` loop and before a pencilled halt.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/war_room/test_war_plan_tool.gd
func test_undo_holds_plans_and_drafts_in_one_stack() -> void:
	tool.remember({"rev": 1})
	tool.remember_drafts({"u1": {}})
	var now := func(e: Dictionary) -> Dictionary: return {"drafts": {"u1": {"order": "march"}}} if e.has("drafts") else {"plans": {"rev": 2}}
	assert_eq(tool.undo(now), {"drafts": {"u1": {}}})
	assert_eq(tool.undo(now), {"plans": {"rev": 1}})
	assert_eq(tool.redo(now), {"plans": {"rev": 2}})
func test_a_new_state_empties_the_stacks() -> void:
	tool.own(1); tool.remember({"rev": 1}); tool.own(2)
	assert_eq(tool.undo(func(e: Dictionary) -> Dictionary: return e), {})
# tests/engine/test_war_drafts.gd
func test_restore_puts_back_and_erases() -> void:
	# plant a march for A; restore({"A": {}, "B": {"order": "garrison", ...}})
	# assert A has no draft, B's equals the given dict and is a copy
# tests/ui/test_war_room_tools.gd
func test_cmd_z_strikes_a_drawn_march() -> void:
	# select, blue arrow, confirm (as test_a_real_blue_arrow_drawn_for_a_selected_piece_pencils_its_march)
	# Cmd-Z: WarDrafts.of(state, code).is_empty(); a front drawn earlier still there
func test_undo_after_a_new_campaign_does_nothing() -> void:
	# draw a front, Game.start_campaign(45) (the room still bound), Cmd-Z: war_plans unchanged
func test_a_refused_write_leaves_no_undo_step() -> void:
	# drag a supposed piece into the sea (refused), then Cmd-Z undoes the PREVIOUS mark
```

- [ ] **Step 2: Run** the three files. Expected: FAIL.

- [ ] **Step 3: Implement**
  - Desk: `_write(f: Callable) -> Variant` takes the plans' deep copy, calls `f`, and remembers only when the result lands (true / non-empty String / int > 0 — `Game._plans`' rule). Every `_remember(); Game.x(...)` becomes `_write(func() -> Variant: return Game.x(...))`. Before every remember and every undo, `_input.tool.own(Game.state.get_instance_id())`.
  - Desk listens to `drafts_planting`: `remember_drafts({code: WarDrafts.of(Game.state, code).duplicate(true) …})`.
  - Cmd-Z / Shift-Cmd-Z: apply the entry — `Game.restore_plans(e["plans"])` or `Game.restore_drafts(e["drafts"])`.
  - CLAUDE.md Screen bullet: "Cmd-Z (the session's undo of marks AND drawn marches, emptied on a load)".

- [ ] **Step 4: Run** the three files, then `--fast`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(war room): one undo for marks and drawn marches, the session's own; refused writes push nothing`

---

### Task 8: Spec alignment — Tab takes the other side's last kind; the front's note (A14, A15)

**Files:**
- Modify: `scripts/war_room/war_plan_tool.gd:73-80` (`switch_side`), `scripts/war_room/war_plan_input.gd:96-101`
- Modify: `data/war_plan_kinds.csv` row `front` notes: "(the drawer's left by default; Flip the teeth moves them)"
- Modify: `tests/war_room/test_war_plan_tool.gd:47-49`, `tests/ui/test_war_room_plans.gd:144-146`

- [ ] **Step 1: Change the two existing assertions to the ruling**: `tool.switch_side()` with nothing in hand gives `["blue", "phase"]` (the side's last kind) in the tool test; the UI test's first Tab gives `["blue", "front"]` in hand.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** `switch_side` with `kind == ""` → `pick(to, fallback if fallback != "" else last_kind(to))`; `WarPlanInput.switch_side` computes the fallback from `tool.kind if tool.kind != "" else tool.last_kind(to)` (a front when that arrow cannot be used). Edit the CSV note.
- [ ] **Step 4: Run** both files and `tests/engine/test_war_room_data.gd`. Expected: PASS.
- [ ] **Step 5: Full suite** `./run_tests.sh` — expected error count only.
- [ ] **Step 6: Commit** `fix(war room): Tab takes the other side's last kind; the front's note says the left`

---

### Task 9: Shots and the guide

- [ ] Real-window shots (`--resolution 1920x1080`): `--war-spread 3 --war-zoom 1.2 --war-box --war-drag 0.7,0.45 --war-supply` and `--war-plans-demo --war-hint --war-plan-select hint --war-plan-draw "red:arrow,sel,_,0.35,0.6"`; check the selection rings, the drawn march and the red arrow are as before (no visual change intended).
- [ ] `scripts/war_room/CLAUDE.md`: every bullet touched above reads as the rule now stands; `tests/engine/test_claude_md_size.gd` passes.
- [ ] Commit `docs(war room): the tools' rules after batch A`.
