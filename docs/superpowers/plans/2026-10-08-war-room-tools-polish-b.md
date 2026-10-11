# War Room Tools Polish — Batch B (the sheet's layout and ink) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the war room's sheet readable and its HUD pieces sit where they belong (spec items B1–B8).

**Architecture:** Presentation only — `WarPlanInput.redraw_live` / `WarPlanHud` (the supply preview), `WarMarginKey` (the key slip), `WarRoomWall` / balance keys (the index chart), `WarInkPainter` / `WarSheetInk` / `war_table.gdshader` uniforms (the sheet's ink), `MarchConfirmPanel.place_near` (the confirm), `WarInkPainter._draw_intel` (spy notes), the hover dwell path, and the screen scene's title (editor). No engine rule changes.

**Tech Stack:** Godot 4.7, GDScript (typed), GUT, `tools/snapshot_screen.gd` real-window shots, `.claude/skills/visual-review/contact_sheet.py`.

**Spec:** `docs/superpowers/specs/2026-10-08-war-room-tools-polish-design.md` (Batch B).

## Global Constraints

- Every visual change follows `.claude/skills/visual-review/SKILL.md`: read `taste.md` (the war room rulings near "The plotting map is a flat tactical chart on parchment" and "The staff's plans are wax crayon"), a BEFORE shot, 2–3 variants, a contact sheet with a zoomed crop. Shots: `/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn -- --resolution 1920x1080 --out <png> --screen root --quiet --war-room …` (never `--headless`, never `--still` with `--war-room`). Variants of a balance value use `--bal key=value` (no file edited). Shots and sheets go in `assets/flux/out/war_tools_b/` (git-ignored).
- Design numbers live in `data/balance.csv` (`war_*` keys, each with its note); colours in the war palette table the painter already reads. No `res://` path in a CSV.
- The LOOK lives in the editor: a `.tscn` / `.tres` change is made through the Godot editor (gdai MCP `execute_editor_script`), never by text-editing it — recipe for a worktree file through the owner's editor in memory note "Saving a WORKTREE's scene/theme through the owner's (main checkout) editor": `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)`, edit, `ResourceSaver.save(res, "<worktree absolute path>")`, then semantic-diff the saved file.
- `scripts/war_room/` never reads the `Game` autoload; typed GDScript; tests from `tests/suite_data.gd` / the existing room helpers in `tests/ui/test_war_room_tools.gd`; `wait_process_frames`, never `wait_frames`.
- Work only in `/Users/samuelzhang/game_design/.claude/worktrees/war-tools-b` (branch `feat/war-tools-b`). Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage only your own files.
- Update `scripts/war_room/CLAUDE.md` where a rule it states changes, written as it stands now.

## Review Focus

1. A supply town ON the laid sheet: the preview must still be drawn whole, with no exit arrow — Task 2 test `test_a_supply_road_inside_the_sheet_has_no_exit_mark`.
2. The supply road leaving and re-entering the sheet (a road that bends out over the collar): drawn as separate on-sheet runs, one exit mark at the run nearest the town — Task 2 test `test_a_road_that_leaves_and_returns_draws_two_runs`.
3. The key slip at 2560×1440 as well as 1920×1080 — Task 3 shots at both sizes.
4. The confirm when every candidate spot is blocked: it must still open (least overlap), never off-screen — Task 4 test `test_the_confirm_opens_somewhere_when_every_spot_is_blocked`.
5. A town whose name is pushed off a plinth must not land on another town's name (the painter's existing knock-out boxes) — Task 6 crop check on a sheet with a garrisoned town cluster.

---

### Task 1: The hover slip shows (B7)

**Files:** `scripts/war_room/war_room_view.gd` (`_process` dwell, `hover_allowed`), `scripts/war_room/war_hover_dwell.gd`, `tools/snapshot_screen.gd` (the `--war-hover` wait), `scripts/ui/war_room_screen.gd` (`_on_ground_hovered`); test `tests/ui/test_war_room_tools.gd`.

- [ ] **Step 1: Reproduce** in a real window: `--war-room --war-hover 0.45,0.55 --war-wait 200` shows no slip (seen 2026-10-08). Use superpowers:systematic-debugging: print from `WarRoomView._process` whether `hover_allowed()` holds and what the dwell holds after the move, and from `_on_ground_hovered` whether it is reached and how many lines `WarGround.lines` returns.
- [ ] **Step 2: Write the failing test** `test_a_resting_pointer_on_open_table_shows_the_slip`: room open, a motion event (no button) to open land via `view._gui_input`, then `wait_until(func(): return (screen.get_node("%HoverSlip") as Control).visible, 3.0)` → true. If the bug is only in the snapshot tool, the test pins the room's behaviour and the tool is fixed to wait in SECONDS (`war_hover_delay_s` + margin of real time), not frames.
- [ ] **Step 3: Fix the cause** found in Step 1 (likely suspects: the dwell cleared on a disallowed frame and never re-armed without a new motion; the shot's 52-frame wait at a low frame rate).
- [ ] **Step 4:** the test passes; the real-window shot shows the slip; `tests/ui/test_war_hover_slip.gd` and `test_war_room_tools.gd` pass.
- [ ] **Step 5: Commit** `fix(war room): the hover slip shows for a resting pointer`

### Task 2: The supply preview stays on the sheet (B1)

**Files:** `scripts/war_room/war_plan_input.gd:~648-662` (the road built in `redraw_live`), new pure `WarPlanGeometry.clip_to_rect(pts: PackedVector2Array, rect: Rect2) -> Array` (runs of PackedVector2Array inside the rect, cut exactly at the rect's edge), `scripts/war_room/war_plan_hud.gd` (`show_road` takes runs and an optional exit mark `{at: Vector2, dir: Vector2, text: String}`); tests `tests/war_room/test_war_plan_geometry.gd`, `tests/ui/test_war_room_tools.gd`.

**Interfaces:** Produces `WarPlanGeometry.clip_to_rect` (pack px in, pack px out). The exit text is `"from %s · %s" % [town name, the sheet id holding the town (WarSheets.sheet_of)]`, drawn in the edge arrows' font and ink at the clipped end nearest the town, with a small arrowhead pointing off the sheet.

- [ ] **Step 1: Failing tests:** `test_clip_to_rect_cuts_at_the_edge` (a segment from (−10,5) to (10,5) in Rect2(0,0,20,20) → one run [(0,5),(10,5)]); `test_a_road_that_leaves_and_returns_draws_two_runs`; `test_a_supply_road_inside_the_sheet_has_no_exit_mark`; `test_a_supply_road_from_off_the_sheet_ends_at_its_edge_with_the_towns_name` (UI: the drawn road's screen points all project inside the sheet rect's screen quad; the HUD's exit text contains the town's name).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement; clip against `_view.sheet_rect()` in pack px BEFORE projecting. **Step 4:** tests pass; real-window shot `--war-spread 3 --war-zoom 1.2 --war-box --war-drag 0.7,0.45 --war-supply` shows no gold on the oak; crop the exit mark at ×3 and look.
- [ ] **Step 5: Commit** `fix(war room): the supply preview stays on the sheet, its exit named`

### Task 3: The key slip keeps every word; a spy's note is legible (B2, B6)

**Files:** `scripts/ui/war_margin_key.gd:~107-122` (label x and max width from the same numbers), `scripts/war_room/war_ink_painter.gd:~359-365` (spy label: size and a parchment halo like the hazard labels'), `data/balance.csv` (`war_intel_label_px` → the hazard label size `war_intel_hazard_label_px`'s value, or a new halo key if one is needed); test `tests/ui/test_war_margin_key.gd`.

- [ ] **Step 1: Failing test** `test_every_legend_word_fits_its_column`: for each legend entry the font's `get_string_size(label, …, war_key_font_px)` ≤ the width the slip gives it.
- [ ] **Step 2:** FAIL. **Step 3:** fix the layout (text start and width budget from one expression; if a word still does not fit three columns at `war_key_width_px`, raise `war_key_width_px` or set `war_key_columns` 2 — choose by the shots). Spy note: draw it on a halo the way `_draw_intel` draws hazard labels, at the hazard size.
- [ ] **Step 4:** test passes; shots at 1920×1080 and 2560×1440 of the key slip (crop ×2) and of a spy ring (`--war-hint --war-zoom 1.0`, crop ×3).
- [ ] **Step 5: Commit** `fix(war room): the key slip keeps every word; a spy's note reads on a halo`

### Task 4: The march's confirm never covers the room's slips (B5)

**Files:** `scripts/ui/march_confirm_panel.gd:~215` (`place_near(at, route_rect, bounds, blocked: Array[Rect2] = [])` — each blocked rect costs its overlap like the route box), `scripts/ui/army_order_menu.gd:~210` (`_open_confirm` passes the blocked rects its map gives), `scripts/ui/war_room_screen.gd` (provides the room's blocked rects: `%Slip` when visible, `%KeySlip`, `%ToolRoll`, the folio's `book_rect()` when open — in the view's coordinates); test `tests/ui/test_war_room_tools.gd` or `tests/ui/test_march_confirm_panel.gd` if it exists.

**Interfaces:** `ArmyOrderMenu` asks its followed map for `blocked_rects() -> Array[Rect2]` only `if map.has_method("blocked_rects")` (the 3D map need not have one); `WarRoomView` forwards to a Callable the screen sets, or the screen hands the menu the rects directly — keep `scripts/war_room/` free of `Game`.

- [ ] **Step 1: Failing tests:** `test_the_confirm_does_not_cover_the_margin_slip` (a march drawn so the old placement chose the top-left corner; `confirm.get_global_rect().intersects(%Slip.get_global_rect())` is false); `test_the_confirm_opens_somewhere_when_every_spot_is_blocked` (unit test of `place_near` with blocked rects covering all candidates → returns the least-overlap spot inside bounds).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** pass; real-window shot of the confirm open (`--war-spread 3 --war-zoom 1.2 --war-box --war-drag 0.7,0.45`).
- [ ] **Step 5: Commit** `fix(war room): the march's confirm keeps clear of the room's slips`

### Task 5: The sheet's title on paper (B8)

**Files:** `scenes/screens/war_room_screen.tscn` (`%Title`), possibly `assets/2D/ui/theme/paper_theme.tres` / `game_theme.tres` (a label kind with the slip's paper stylebox) — EDITOR ONLY (see Global Constraints recipe); `tests/ui/test_editor_owned_look.gd` must stay green.

- [ ] **Step 1:** BEFORE shot leaning in so the sheet lies under the title (`--war-zoom 0.6 --war-focus-px <a point near the sheet's north-west corner>`), crop the title ×2.
- [ ] **Step 2:** two variants made in the editor and shot: (a) the title inside a PanelContainer wearing `war_slip.tres` (the margin slip's paper); (b) the title as the margin slip's own header row. Contact sheet.
- [ ] **Step 3:** report the sheet; the controller's critic picks; apply the pick in the editor, semantic-diff the `.tscn`, run `tests/ui/test_editor_owned_look.gd`, `tests/ui/test_war_room_screen.gd`.
- [ ] **Step 4: Commit** `style(war room): the sheet's title on the slip's paper`

### Task 6: The index chart, smaller and sepia (B3)

**Files:** `data/balance.csv` (`war_chart_w_m`, `war_chart_z_m`, `war_chart_numeral_font_px`, `war_chart_numeral_pixel_m`, `war_chart_label_every`), `scripts/war_room/war_room_wall.gd` (label ink: palette `ink` or a new palette key `chart_label`, not `rubric`).

- [ ] **Step 1:** BEFORE shots at the default zoom and `--war-zoom 1.0` / `0.6` near the sheet's north edge (`--war-focus-px`).
- [ ] **Step 2:** three variants by `--bal`: narrow (w 0.56, labels every 1 at a size that fits a 15.5 mm column), middle (w 0.66, every 2), unchanged — each at the three zooms; contact sheet with a crop of the chart ×2.
- [ ] **Step 3:** report; the controller's critic picks; set the picked values in `balance.csv` with notes saying what they serve; the label ink change in code; `tests/war_room/test_war_index_chart.gd` and `tests/war_room/test_war_room_view.gd` pass (update any value-pinned assertion to the new keys' values, never to literals).
- [ ] **Step 4: Commit** `style(war room): a smaller index chart, every column lettered in sepia`

### Task 7: The sheet's ink leads with what matters (B4)

**Files:** `scripts/war_room/war_ink_painter.gd:~135` (town names: halo, size, placed clear of a plinth), `scripts/war_room/war_sheet_ink.gd` (label placement: a town whose name box would meet a standing piece's plinth footprint — `war_piece_plinth_mm` on the table — takes the next free side), `scripts/war_room/war_ink_painter.gd:~285` (graticule figures: size and alpha keys instead of the hard-coded 0.6 knock-out), `data/balance.csv` (`war_ink_label_px`, new `war_ink_label_halo_px`, `war_grid_label_px`, new `war_grid_label_alpha`, `war_sea_hatch_reach_m`, `war_sea_hatch_alpha`, `war_sea_wash`); tests `tests/war_room/test_war_sheet_ink.gd` (placement rule), `tests/war_room/test_war_room_view.gd`.

Note: the sheet's ink is cached per sheet by the ownership signature; a piece's plinth is a STATE fact — if placing names by pieces would force a redraw on every march, place them clear of the TOWN's own garrison spot (where the seat's unit stands) instead, which is static. Rule: names avoid the town's own seat-piece footprint (static), not moving pieces.

- [ ] **Step 1: Failing test** `test_a_town_name_clears_its_seat_piece`: the label box of a town with a seat never intersects the plinth circle at its point.
- [ ] **Step 2:** FAIL. **Step 3:** implement the placement and the halo; expose the graticule alpha.
- [ ] **Step 4:** BEFORE / variant shots (default zoom, `--war-zoom 1.0`, `0.6`): v1 town 52 px + halo, grid figures 48 px α 0.55, hatch reach 0.06 m α 0.5; v2 town 60 px, grid 40 px α 0.45, hatch reach 0.04 m α 0.35; v3 between. Contact sheet + crops ×3 of a town cluster, a graticule corner and a coast.
- [ ] **Step 5:** report; the controller's critic picks; set the values in `balance.csv` with notes; tests pass.
- [ ] **Step 6: Commit** `style(war room): towns lead the sheet; the graticule and the sea step back`

### Task 8: The batch's before/after and the guide

- [ ] Contact sheet BEFORE (main) vs AFTER (branch) at 1920×1080 for: the default view, the box + blue march + supply, the red arrow on a hint, the hover slip, leaning in near the north edge; crops of the key slip, a town cluster, the confirm.
- [ ] The controller's independent critic over the sheet (rubric in the visual-review skill). Fix any defect that breaks a `taste.md` principle in one follow-up commit.
- [ ] `scripts/war_room/CLAUDE.md` bullets reflect the new rules (supply preview clipped with its exit mark; the confirm's blocked rects; names clear of the seat piece; the chart's size); `tests/engine/test_claude_md_size.gd` green.
- [ ] Full `./run_tests.sh` (expected error count only). Commit `docs(war room): the sheet's layout and ink after batch B`.
