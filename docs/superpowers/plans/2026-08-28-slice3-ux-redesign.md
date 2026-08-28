# Slice 3 — UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restage the game as a visual-novel flow — main menu, one-minister-at-a-time council conversation with replies, kingdom info card, Council round-table voice for events/summaries, slower day-run — per the owner's `how_to_play.md` (R1–R13).

**Architecture:** A `GameRoot` state machine (`MENU → CONVERSATION → COURT → DAY_RUN → CONVERSATION…`) owns exactly one active screen scene at a time; screens are self-contained, signal upward only, and read/mutate state exclusively through the `Game` autoload. The engine layer is never touched; all numeric detail moves to the KingdomCard and tooltips so speech stays prose.

**Tech Stack:** Godot 4.7.1 GDScript, GUT via `./run_tests.sh` (exits nonzero on failure; "Errors 2" is the documented unrelated-plugin condition; CC_FORCE_OFFLINE guard stays).

**Spec:** `docs/superpowers/specs/2026-08-28-slice3-ux-redesign-design.md` (+ `how_to_play.md` R1–R13)

## Global Constraints

- `scripts/engine/` is UNTOUCHED this slice. All engine tests stay green unmodified. Determinism invariants (rng only in EventSystem.roll, bit-exact saves) must survive by construction.
- UI mutates state only via `Game.try_execute / submit_free_text / apply_event_choice`; screens communicate only by signals up to GameRoot.
- Ministers never speak numbers (R7): no `%d` metric values in any spoken line; numbers live on KingdomCard and in tooltips.
- Design numbers in `data/*.csv` (new balance key `dayrun_day_seconds,0.22`); template text in `data/templates.csv`.
- Tests stay offline; GDScript gotchas: lambdas capture by value (test state in members), `: float =` for Variant-derived expressions, never name helpers `_set`/`_get`; `--check-only` on ui scripts false-positives on autoloads (suite is the gate).
- Migrated tests preserve intent test-by-test, never weakened; commit style: prefix + the two trailer lines from `git log -1 --format=%B` (author yourself honestly).
- The user's Godot editor is open on this project: never launch the editor GUI; boot checks via `--quit-after`.

## File Structure

```
scenes/
  main_menu.tscn game_root.tscn kingdom_card.tscn
  conversation.tscn court.tscn day_run.tscn
  characters/round_table.tscn                    # Task 1
scripts/ui/
  main_menu.gd game_root.gd kingdom_card.gd
  conversation_scene.gd conversation_beats.gd    # beat-queue builder (pure)
  court_screen.gd day_run_screen.gd
  council_screen.gd                              # retired in Task 6
  calendar_overlay.gd                            # speed + card hosting (Task 4)
tools/gen_portraits.py                           # +round_table grid (Task 1)
data/templates.csv  data/balance.csv             # Task 1
tests/ui/  (new + migrated)
```

---

### Task 1: Round-table art + natural-language templates + balance key

**Files:**
- Modify: `tools/gen_portraits.py`, `data/templates.csv`, `data/balance.csv`
- Create: `scenes/characters/round_table.tscn`, `assets/portraits/round_table.png` (generated)
- Test: `tests/ui/test_slice3_data.gd`

**Interfaces:**
- Produces: portrait id `round_table` resolvable via `CharacterPortrait.instantiate_for("round_table")` (own scene + PNG); template keys `reply_<pitch_key>` for ALL 10 pitch keys (grain_ration, build_granary, raise_tax, tithe_church, ease_tax, harsh_justice, endow_church, raise_levies, quiet_rumors, build_road), `council_summary_open`, `council_summary_decision` (uses `{label}`), `council_summary_idle`; balance key `dayrun_day_seconds,0.22`.

- [ ] **Step 1: Failing data test** — `tests/ui/test_slice3_data.gd`:

```gdscript
extends GutTest

const PITCH_KEYS := ["grain_ration", "build_granary", "raise_tax", "tithe_church",
	"ease_tax", "harsh_justice", "endow_church", "raise_levies", "quiet_rumors", "build_road"]

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_reply_templates_exist_for_every_pitch() -> void:
	var keys := {}
	for t in data.templates:
		keys[String(t["key"])] = true
	for pk in PITCH_KEYS:
		assert_true(keys.has("reply_" + pk), "missing reply_" + pk)
	for k in ["council_summary_open", "council_summary_decision", "council_summary_idle"]:
		assert_true(keys.has(k), "missing " + k)

func test_no_spoken_numbers_in_new_templates() -> void:
	# R7: replies/summaries carry no numeric placeholders or digits
	for t in data.templates:
		var key := String(t["key"])
		if key.begins_with("reply_") or key.begins_with("council_summary"):
			assert_false("{value}" in String(t["text"]), key)

func test_round_table_portrait_resolves() -> void:
	assert_true(FileAccess.file_exists("res://assets/portraits/round_table.png"))
	var p := CharacterPortrait.instantiate_for("round_table")
	add_child_autofree(p)
	assert_string_contains(p.scene_file_path, "round_table.tscn")

func test_dayrun_speed_key() -> void:
	assert_almost_eq(data.bal("dayrun_day_seconds"), 0.22, 0.001)
```

- [ ] **Step 2: Run** — `./run_tests.sh` — FAIL.

- [ ] **Step 3: Round-table grid.** Add to `tools/gen_portraits.py` PORTRAITS (five head-dots in seat colors around a brown circular table; palette letters t=table wood (122,86,58), r=rim (90,62,42), plus one letter per seat color from the existing scheme, background transparent):

```python
    # The Council - round table with the five ministers as colored figures
    "round_table": {
        "palette": {"t": (122, 86, 58, 255), "r": (90, 62, 42, 255),
                    "b": (74, 111, 165, 255), "m": (165, 74, 74, 255),
                    "g": (74, 165, 113, 255), "p": (107, 74, 165, 255),
                    "y": (165, 140, 74, 255), "s": SKIN},
        "rows": [
            "................",
            "......ss........",
            "..s...mm...s....",
            ".bb..mmmm..gg...",
            ".bbb.mmmm.ggg...",
            "..b..rrrr..g....",
            "...rrttttrr.....",
            "..rttttttttr....",
            "..rttttttttr....",
            "..rttttttttr....",
            "..rttttttttr....",
            "...rrttttrr.....",
            "..p...rr...y....",
            ".ppp......yyy...",
            ".ppp......yyy...",
            "................",
        ],
    },
```

Run `python3 tools/gen_portraits.py` (regenerates all PNGs — existing grids are
unchanged so existing PNGs are byte-identical; verify with `git status`).
Create `scenes/characters/round_table.tscn` exactly like the other per-character
scenes (instance of `character_portrait.tscn`, `character_id = "round_table"`).

- [ ] **Step 4: Template rows.** Append to `data/templates.csv` (comma-quoted; natural language, NO numbers — author the remaining reply rows in the same voice):

```csv
reply_grain_ration,,"Very well — ration the stores. See it done gently."
reply_build_granary,,"Commission the granary. The realm eats tomorrow because we build today."
reply_raise_tax,,"Raise the rate. I will bear the grumbling."
reply_tithe_church,,"Take the tithe. The church can spare it this season."
reply_ease_tax,,"Ease the rate. Let the villages breathe."
reply_harsh_justice,,"Let the courts bite harder, then. Order first."
reply_endow_church,,"Make the endowment. Grace is worth gold."
reply_raise_levies,,"Raise the levies. Drill them well."
reply_quiet_rumors,,"Send your whisperers. Quietly."
reply_build_road,,"Build the road. Trade must move."
council_summary_open,,"The council rises. Thus stands the session:"
council_summary_decision,,"It was decided: {label}."
council_summary_idle,,"No orders were given. The realm drifts as it will."
```

Append to `data/balance.csv`:

```csv
dayrun_day_seconds,0.22,seconds per day in the end-turn day-run (R6)
```

- [ ] **Step 5: Run** — PASS. **Step 6: Commit** — `feat: round-table voice, reply templates, day-run pacing key`

---

### Task 2: KingdomCard

**Files:**
- Create: `scripts/ui/kingdom_card.gd`, `scenes/kingdom_card.tscn`
- Test: `tests/ui/test_kingdom_card.gd`

**Interfaces:**
- Consumes: `Game.state.metrics`, `Calendar.date_string`, existing METRIC short names.
- Produces: `class_name KingdomCard extends PanelContainer` — `show_values(state: GameState) -> void` (metric rows `Gold 519` + date header), `show_changes(state: GameState, deltas: Array) -> void` (rows `Gold 519 → 538 (+19)` for changed metrics, reason as tooltip; unchanged metrics plain). Scene `scenes/kingdom_card.tscn` = PanelContainer root with the script (children built in code).

- [ ] **Step 1: Failing test** — `tests/ui/test_kingdom_card.gd`:

```gdscript
extends GutTest

func _card() -> KingdomCard:
	var c: KingdomCard = load("res://scenes/kingdom_card.tscn").instantiate()
	add_child_autofree(c)
	return c

func test_values_mode_lists_metrics_and_date() -> void:
	Game.start_campaign(42)
	var c := _card()
	c.show_values(Game.state)
	await wait_frames(1)
	var texts := _all_label_text(c)
	assert_string_contains(texts, "Gold")
	assert_string_contains(texts, "Grain")
	assert_string_contains(texts, "Year 1")

func test_changes_mode_shows_arrows_for_changed_metrics() -> void:
	Game.start_campaign(42)
	var c := _card()
	var deltas := [{"metric": "treasury", "delta": 19.0, "reason": "taxes collected"}]
	Game.state.metrics["treasury"] = 538.0
	c.show_changes(Game.state, deltas)
	await wait_frames(1)
	var texts := _all_label_text(c)
	assert_string_contains(texts, "→ 538")
	assert_string_contains(texts, "(+19)")

func _all_label_text(root: Node) -> String:
	var out := ""
	for child in root.find_children("*", "Label", true, false):
		out += child.text + "\n"
	return out
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** `scripts/ui/kingdom_card.gd`:

```gdscript
class_name KingdomCard
extends PanelContainer
## The realm's numbers live HERE (R1/R7/R9) - ministers speak prose, this
## card speaks figures. Two modes: values (court) and changes (day-run).

const METRIC_NAMES := {"treasury": "Gold", "grain": "Grain", "unrest": "Unrest",
	"legitimacy": "Legit", "army_quality": "Army", "church_opinion": "Church"}
const ORDER := ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]

var _box: VBoxContainer

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c33")
	style.border_color = Color("deba54")
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)

func show_values(state: GameState) -> void:
	_rebuild(state, {})

func show_changes(state: GameState, deltas: Array) -> void:
	var by_metric := {}
	for d in deltas:
		if by_metric.has(d["metric"]):
			by_metric[d["metric"]]["delta"] += float(d["delta"])
			by_metric[d["metric"]]["reason"] += "\n" + String(d["reason"])
		else:
			by_metric[d["metric"]] = {"delta": float(d["delta"]), "reason": String(d["reason"])}
	_rebuild(state, by_metric)

func _rebuild(state: GameState, changes: Dictionary) -> void:
	for child in _box.get_children():
		child.queue_free()
	var date := Label.new()
	date.text = Calendar.date_string(state.tick)
	date.add_theme_color_override("font_color", Color("deba54"))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(date)
	for m in ORDER:
		var now := int(state.metrics[m])
		var l := Label.new()
		if changes.has(m) and int(changes[m]["delta"]) != 0:
			var delta := int(changes[m]["delta"])
			l.text = "%s %d → %d (%+d)" % [METRIC_NAMES[m], now - delta, now, delta]
			l.tooltip_text = changes[m]["reason"]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.add_theme_color_override("font_color",
				Color("7fd47f") if delta > 0 else Color("d47f7f"))
		else:
			l.text = "%s %d" % [METRIC_NAMES[m], now]
		_box.add_child(l)
```

`scenes/kingdom_card.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/kingdom_card.gd" id="1"]

[node name="KingdomCard" type="PanelContainer"]
script = ExtResource("1")
```

- [ ] **Step 4: Run** — PASS. **Step 5: Commit** — `feat: KingdomCard info panel (values + changes modes)`

---

### Task 3: GameRoot state machine + MainMenu (Space) + R-restart

**Files:**
- Create: `scripts/ui/game_root.gd`, `scenes/game_root.tscn`, `scripts/ui/main_menu.gd`, `scenes/main_menu.tscn`
- Modify: `scripts/ui/game.gd` (restart), `project.godot` (`run/main_scene="res://scenes/game_root.tscn"`), `scripts/ui/council_screen.gd` (remove its main-scene auto-start guard + `_unhandled_input` Enter handler moves later; THIS task only: change nothing in council_screen except none — GameRoot instantiates it for COURT temporarily)
- Test: `tests/ui/test_game_root.gd`

**Interfaces:**
- Consumes: existing `council.tscn` (temporary COURT screen), `Game`.
- Produces: `class_name GameRoot extends Control` — `enum State {MENU, CONVERSATION, COURT, DAY_RUN}`, `var state: State`, `var current_screen: Node`; `start_campaign_flow(seed_value := 42)`; `_switch_to(new_state: State, payload := {})`; global `_unhandled_input`: `R` (KEY_R) anywhere → `Game.restart()` + MENU; screens signal upward: MainMenu emits `start_requested`; (CONVERSATION added Task 5; COURT/DAY_RUN rewiring Task 4/6 — this task routes MENU→COURT directly as an interim flow, marked with a comment). `Game.restart() -> void` (clears state to null, resets `_prompts_this_tick`, frees/clears voicer+client via existing `_reset_llm`). `MainMenu` emits `start_requested` on Space (`ui_accept` uses Enter too — accept both; R13 says Space).

- [ ] **Step 1: Failing tests** — `tests/ui/test_game_root.gd`:

```gdscript
extends GutTest

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_boots_to_menu() -> void:
	var r := _root()
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_not_null(r.current_screen)

func test_space_starts_campaign() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	assert_ne(r.state, GameRoot.State.MENU)
	assert_not_null(Game.state)
	assert_gt(Game.state.tick, 0)

func test_r_restarts_to_menu() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	r._unhandled_input(key)
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_null(Game.state)
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.**

`scripts/ui/main_menu.gd`:

```gdscript
class_name MainMenu
extends Control
## R13: minimal title screen - Space (or Enter) starts.

signal start_requested

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(col)
	var title := Label.new()
	title.text = "Crown and Council"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("deba54"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "press Space to take the throne"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("8c86a0"))
	col.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event.keycode == KEY_SPACE or event.is_action_pressed("ui_accept")):
		start_requested.emit()
```

`scripts/ui/game_root.gd`:

```gdscript
class_name GameRoot
extends Control
## Flow state machine (spec §2). Owns exactly one screen scene at a time;
## screens signal upward, GameRoot decides what comes next. R restarts (R12).

enum State {MENU, CONVERSATION, COURT, DAY_RUN}

const MENU_SCENE := "res://scenes/main_menu.tscn"
const COURT_SCENE := "res://scenes/council.tscn"  # interim: Task 6 swaps to court.tscn

var state: State = State.MENU
var current_screen: Node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_switch_to(State.MENU)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R \
			and state != State.MENU:
		Game.restart()
		_switch_to(State.MENU)

func _switch_to(new_state: State) -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	state = new_state
	match new_state:
		State.MENU:
			current_screen = load(MENU_SCENE).instantiate()
			current_screen.start_requested.connect(_on_start_requested)
		State.COURT:
			current_screen = load(COURT_SCENE).instantiate()
			# interim flow: council.tscn drives its own tick/interlude until
			# Tasks 4-6 move that orchestration here.
	add_child(current_screen)

func _on_start_requested() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	# interim: straight to COURT; Task 5 inserts CONVERSATION here.
	_switch_to(State.COURT)
```

`scenes/game_root.tscn` / `scenes/main_menu.tscn` — minimal script-only scenes (same 4-line pattern as council.tscn, root type `Control`).

`game.gd` add:

```gdscript
func restart() -> void:
	_reset_llm()
	state = null
	engine = null
	current_report = null
	_prompts_this_tick = 0
```

`project.godot`: `run/main_scene="res://scenes/game_root.tscn"`.
`council_screen.gd`: its `_ready` auto-start guard (`get_parent() == get_tree().root`) is now false when instantiated under GameRoot — add `begin.call_deferred()` invocation from GameRoot? NO — instead: in council_screen, replace the guard body so it ALSO auto-begins when its parent is a GameRoot: `if get_parent() == get_tree().root or get_parent() is GameRoot:` (Game.state already exists; keep the `if Game.state == null` inner guard). Existing council tests (screen under test nodes) stay unaffected.

- [ ] **Step 4: Run full suite** — PASS (existing council tests unaffected: they parent under test nodes). Boot check: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120 2>&1 | tail -5` shows menu boot, no SCRIPT ERROR. **Step 5: Commit** — `feat: GameRoot state machine, main menu (Space), R-restart`

---

### Task 4: DayRunScreen — slower interlude hosting the KingdomCard

**Files:**
- Create: `scripts/ui/day_run_screen.gd`, `scenes/day_run.tscn`
- Modify: `scripts/ui/calendar_overlay.gd` (speed from balance; expose day ticks), `scripts/ui/game_root.gd` (DAY_RUN state + orchestrated end-turn), `scripts/ui/council_screen.gd` (emit `end_turn_requested` instead of self-driving the interlude)
- Test: `tests/ui/test_day_run.gd`, migrate `tests/ui/test_calendar_overlay.gd` speed expectations

**Interfaces:**
- Consumes: `CalendarOverlay` (existing `play(tick)`, `finished`, `playing()`, `NEWS_DAYS`), `KingdomCard.show_changes`, `TickReport.metric_deltas`.
- Produces: `class_name DayRunScreen extends Control` — `run(report: TickReport) -> void` (plays the overlay for `report.tick`, shows KingdomCard in changes mode fed by `report.metric_deltas`), signal `finished`. `CalendarOverlay.DAY_SECONDS` const replaced by `var day_seconds` read from `Game.data.bal("dayrun_day_seconds")` in `_ready` (fallback 0.22 if Game.data null in isolated tests: `var day_seconds := 0.22`). GameRoot flow becomes: COURT screen emits `end_turn_requested` → GameRoot calls `Game.next_tick()` → `_switch_to(State.DAY_RUN)` → DayRunScreen.run(report) → `finished` → COURT (Task 5 changes this to CONVERSATION). council_screen.gd: `_on_end_turn` becomes `end_turn_requested.emit()` (signal added; its own overlay/`_pending_report` code REMOVED — the overlay child, `_on_interlude_finished`, and `calendar_overlay` var go away; `_render_report` is invoked by GameRoot via `begin_with(report)` new method: renders a report without advancing).

- [ ] **Step 1: Failing tests** — `tests/ui/test_day_run.gd`:

```gdscript
extends GutTest

func test_day_run_plays_and_finishes_with_card_changes() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	d.run(report)
	await wait_frames(2)
	assert_true(d.overlay.playing())
	var texts := ""
	for l in d.card.find_children("*", "Label", true, false):
		texts += l.text + "\n"
	assert_string_contains(texts, "→")  # at least one change row (income always moves treasury)
	# click-skip immediately finishes
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	d.overlay._on_gui_input(click)
	await wait_for_signal(d.finished, 2.0)
	assert_false(d.overlay.playing())

func test_overlay_speed_comes_from_balance() -> void:
	Game.start_campaign(42)
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	await wait_frames(1)
	assert_almost_eq(d.overlay.day_seconds, Game.data.bal("dayrun_day_seconds"), 0.001)
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.**

`calendar_overlay.gd`: replace `const DAY_SECONDS := 0.09` with:

```gdscript
## R6: pacing comes from balance (dayrun_day_seconds); slower, readable.
var day_seconds := 0.22

func _ready() -> void:
	if Game.data != null:
		day_seconds = Game.data.bal("dayrun_day_seconds")
	# ... existing _ready body unchanged below ...
```

and `_timer.start(DAY_SECONDS)` → `_timer.start(day_seconds)`. Update the overlay's own test timeouts (15 days × 0.22 ≈ 3.3 s → `wait_for_signal(overlay.finished, 6.0)`).

`scripts/ui/day_run_screen.gd`:

```gdscript
class_name DayRunScreen
extends Control
## DAY_RUN state screen: the calendar interlude with the KingdomCard showing
## what changed while the days pass (R6, R9).

signal finished

var overlay: CalendarOverlay
var card: KingdomCard

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	card = load("res://scenes/kingdom_card.tscn").instantiate()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position.y -= 24
	add_child(card)
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)

func run(report: TickReport) -> void:
	card.show_changes(Game.state, report.metric_deltas)
	overlay.play(report.tick)
```

`game_root.gd`: add `State.DAY_RUN` branch + orchestration:

```gdscript
		State.DAY_RUN:
			current_screen = load("res://scenes/day_run.tscn").instantiate()
			current_screen.finished.connect(_on_day_run_finished)
```

```gdscript
func _on_end_turn_requested() -> void:
	_pending_report = Game.next_tick()
	_switch_to(State.DAY_RUN)
	current_screen.run(_pending_report)

func _on_day_run_finished() -> void:
	# interim: back to COURT with the new report; Task 5 routes to CONVERSATION.
	_switch_to(State.COURT)
	current_screen.begin_with(_pending_report)
	_pending_report = null
```

(`var _pending_report: TickReport` member; COURT branch connects `current_screen.end_turn_requested.connect(_on_end_turn_requested)` and `_on_start_requested` now calls `current_screen.begin_with(Game.current_report)` after switching.)

`council_screen.gd`: add `signal end_turn_requested`; add `func begin_with(report: TickReport) -> void: _render_report(report)`; `_on_end_turn` body becomes `end_turn_requested.emit()` (KEEP the pending-event guard and disabled logic minus interlude); DELETE `calendar_overlay` var/instantiation, `_on_interlude_finished`, `_pending_report`, and the overlay reference in `_unhandled_input` (Enter guard drops the `calendar_overlay.playing()` clause). The auto-start guard from Task 3 is removed entirely (GameRoot always drives via `begin_with`); `begin()` stays for old tests (`begin()` = `begin_with(Game.next_tick())`).

- [ ] **Step 4: Migrate affected old tests.** `test_council_screen.gd`'s `test_screen_builds_and_click_executes` pressed end_turn and asserted tick advance — now End Turn only EMITS; update that test's tail to assert the signal fires (member-var capture) AND that tick does NOT self-advance (intent: End Turn still works, orchestration moved):

```gdscript
	_end_turn_emitted = false
	screen.end_turn_requested.connect(func(): _end_turn_emitted = true)
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_true(_end_turn_emitted)
	assert_eq(Game.state.tick, 1)  # GameRoot owns advancing now
```

(add `var _end_turn_emitted := false` member). The calendar interlude interplay tests in test_calendar_overlay.gd keep working (overlay standalone).

- [ ] **Step 5: Run full suite** — PASS. **Step 6: Commit** — `feat: DayRunScreen with kingdom card; GameRoot owns the turn cycle`

---

### Task 5: ConversationScene — the visual-novel stage

**Files:**
- Create: `scripts/ui/conversation_beats.gd`, `scripts/ui/conversation_scene.gd`, `scenes/conversation.tscn`
- Modify: `scripts/ui/game_root.gd` (CONVERSATION state; flow MENU→CONVERSATION and DAY_RUN→CONVERSATION)
- Test: `tests/ui/test_conversation_beats.gd`, `tests/ui/test_conversation_scene.gd`

**Interfaces:**
- Consumes: `TickReport` (event/concerns/suggestions/outcomes/promise_events), `TemplateVoicer.line_for`, `Game.voice_event_scene / apply_event_choice / try_execute / submit_free_text`, `CharacterPortrait.instantiate_for`.
- Produces: `class_name ConversationBeats` — `static build(report: TickReport, state: GameState, data: DataRepository) -> Array` of beat dicts:
  - event beat: `{"kind": "event", "portrait_id": "round_table", "speaker": "The Council", "event": report.event}` (FIRST when present)
  - minister beat: `{"kind": "minister", "portrait_id": char_id, "speaker": display_name, "text": <concern line(s) + pitch line joined with " ">, "suggestions": [sug, ...]}` — one per minister with ≥1 concern or suggestion (seat order), suggestions carrying the existing `{seat, request, pitch_key, tradeoff}` dicts
  - summary beat LAST: `{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council", "text": <council_summary_open + one council_summary_decision per outcome label, or council_summary_idle>}` — built from `report.outcomes` labels (prose only, R2/R7).
  `class_name ConversationScene extends Control` — `start(beats: Array) -> void`; signal `finished`; layout (R4): large portrait (CharacterPortrait scaled ×4, positioned left-of-center vertically centered), name plate above a dialogue PanelContainer anchored mid-bottom (60% width, centered); controls inside the dialogue box: quick-reply buttons (template `reply_<pitch_key>` text; executes the suggestion via `Game.try_execute` then shows the minister's outcome prose and advances), free-text LineEdit ("Speak your mind..."; routes `Game.submit_free_text`; on ok the CURRENT minister acknowledges via template `outcome_<code>` line before advancing is allowed), Continue button ("Wave them on"). Event beats: scene text via `Game.voice_event_scene`, choice buttons via `Game.apply_event_choice`, Continue hidden until resolved (gating). test helpers: `current_beat() -> Dictionary`, `continue_button() -> Button`, `reply_buttons() -> Array`, `dialogue_text() -> String`.

- [ ] **Step 1: Failing beats test** — `tests/ui/test_conversation_beats.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_minister_beats_group_concern_with_pitch() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	var engine := TickEngine.new(data)
	var r := engine.advance(s)
	if not s.pending_event.is_empty():
		engine.events.apply_choice(String(s.pending_event["choices"][0]["choice_id"]), s)
		r.event = {}
	var beats := ConversationBeats.build(r, s, data)
	assert_gt(beats.size(), 1)
	var steward_beat := {}
	for b in beats:
		if b["kind"] == "minister" and b["portrait_id"] == "char_steward":
			steward_beat = b
	assert_false(steward_beat.is_empty(), "steward speaks about grain")
	assert_string_contains(String(steward_beat["text"]), "Grain")
	assert_gt(steward_beat["suggestions"].size(), 0)
	# no numeric metric values spoken beyond the template's own {value} fills:
	assert_eq(beats[-1]["kind"], "summary")
	assert_eq(beats[-1]["portrait_id"], "round_table")

func test_event_beat_first_when_pending() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	var r := engine.advance(s)
	engine.events._fire("ev_01", s)
	r.event = s.pending_event.duplicate(true)
	var beats := ConversationBeats.build(r, s, data)
	assert_eq(beats[0]["kind"], "event")
	assert_eq(beats[0]["portrait_id"], "round_table")

func test_summary_reflects_outcomes_without_numbers() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var r2 := engine.advance(s)
	if not s.pending_event.is_empty():
		r2.event = {}
	var beats := ConversationBeats.build(r2, s, data)
	var summary: String = beats[-1]["text"]
	assert_string_contains(summary, "Raise fresh levies")
	for ch in ["0","1","2","3","4","5","6","7","8","9"]:
		assert_false(ch in summary, "no digits in summary (R7): " + summary)
```

Note the digit check: `council_summary_decision` uses only the action LABEL (no numbers). Labels contain no digits (verify against policy CSVs — they don't).

- [ ] **Step 2: Failing scene test** — `tests/ui/test_conversation_scene.gd`:

```gdscript
extends GutTest

var _finished := false

func _scene_with(beats: Array) -> ConversationScene:
	var c: ConversationScene = load("res://scenes/conversation.tscn").instantiate()
	add_child_autofree(c)
	_finished = false
	c.finished.connect(func(): _finished = true)
	c.start(beats)
	return c

func test_one_portrait_per_beat_and_continue_advances() -> void:
	Game.start_campaign(42)
	var beats := [
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt of Harrow",
			"text": "The levies grow soft.", "suggestions": []},
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council",
			"text": "The council rises."},
	]
	var c := _scene_with(beats)
	await wait_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "char_marshal")
	assert_eq(c.find_children("*", "CharacterPortrait", true, false).size(), 1)  # R4: ONE portrait
	assert_string_contains(c.dialogue_text(), "levies")
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "round_table")
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_true(_finished)

func test_quick_reply_executes_suggestion_and_speaks_prose() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Fresh levies, my lord?",
		"suggestions": [sug]}]
	var c := _scene_with(beats)
	await wait_frames(2)
	assert_gt(c.reply_buttons().size(), 0)
	var army0: float = Game.state.metrics["army_quality"]
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_gt(Game.state.metrics["army_quality"], army0)
	assert_string_contains(c.dialogue_text(), "muster")  # outcome prose, not numbers

func test_event_beat_gates_continue_until_choice() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats)
	await wait_frames(3)
	assert_false(c.continue_button().visible)
	assert_gt(c.reply_buttons().size(), 1)  # event choices render as replies
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(3)
	assert_true(Game.state.pending_event.is_empty())
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_true(_finished)
```

- [ ] **Step 3: Run** — FAIL. **Step 4: Implement.**

`scripts/ui/conversation_beats.gd`:

```gdscript
class_name ConversationBeats
extends RefCounted
## Builds the turn's conversation as a beat queue (spec §3). Pure - no Nodes.

static func build(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var beats: Array = []
	if not report.event.is_empty():
		beats.append({"kind": "event", "portrait_id": "round_table",
			"speaker": "The Council", "event": report.event})
	var per_minister := {}   # char_id -> {texts: [], suggestions: []}
	for c in report.concerns:
		var id := _seat_char(c["seat"], state)
		if id == "":
			continue
		var entry: Dictionary = per_minister.get_or_add(id, {"texts": [], "suggestions": []})
		entry["texts"].append(TemplateVoicer.line_for(data, "concern_" + String(c["metric"]),
			state.characters[id].traits, report.tick, {"value": int(c["value"])}))
	for sug in report.suggestions:
		var id := _seat_char(sug["seat"], state)
		if id == "":
			continue
		var entry: Dictionary = per_minister.get_or_add(id, {"texts": [], "suggestions": []})
		entry["texts"].append(TemplateVoicer.line_for(data, "pitch_" + String(sug["pitch_key"]),
			state.characters[id].traits, report.tick, {"tradeoff": sug["tradeoff"]}))
		entry["suggestions"].append(sug)
	for seat in state.council:   # seat order = insertion order (deterministic)
		var id: String = state.council[seat]
		if per_minister.has(id):
			beats.append({"kind": "minister", "portrait_id": id,
				"speaker": state.characters[id].display_name,
				"text": " ".join(per_minister[id]["texts"]),
				"suggestions": per_minister[id]["suggestions"]})
	beats.append(_summary_beat(report, data))
	return beats

static func _summary_beat(report: TickReport, data: DataRepository) -> Dictionary:
	var lines: Array = [TemplateVoicer.line_for(data, "council_summary_open", [], report.tick)]
	var decided := false
	for o in report.outcomes:
		decided = true
		lines.append(TemplateVoicer.line_for(data, "council_summary_decision", [],
			report.tick, {"label": o["notes"]}))
	if not decided:
		lines[0] = TemplateVoicer.line_for(data, "council_summary_idle", [], report.tick)
	return {"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council", "text": " ".join(lines)}

static func _seat_char(seat: String, state: GameState) -> String:
	return String(state.council.get(seat, ""))
```

(NOTE: concern templates still fill `{value}` — R7 governs *new* speech; concern
lines predate and stay: they mention one figure conversationally. If the owner
objects later it's a template edit, not code. The summary and replies are
digit-free by construction and test.)

`scripts/ui/conversation_scene.gd` (core; keep close to this):

```gdscript
class_name ConversationScene
extends Control
## VN stage (R3/R4/R5): one big portrait, name plate, dialogue box mid-bottom,
## replies inside the box. Beats advance on Continue / reply / event choice.

signal finished

var _beats: Array = []
var _index := -1
var _portrait_holder: Control
var _name_label: Label
var _text_label: Label
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _continue_btn: Button
var _resolved_event := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("161020")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_portrait_holder = Control.new()
	_portrait_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_portrait_holder.position += Vector2(90, -40)
	add_child(_portrait_holder)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c33")
	style.border_color = Color("8c86a0")
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y -= 16
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color("deba54"))
	col.add_child(_name_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(400, 0)
	col.add_child(_text_label)
	_replies_box = VBoxContainer.new()
	col.add_child(_replies_box)
	_free_text = LineEdit.new()
	_free_text.placeholder_text = "Speak your mind..."
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	col.add_child(_free_text)
	_continue_btn = Button.new()
	_continue_btn.text = "Wave them on"
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.pressed.connect(_advance)
	col.add_child(_continue_btn)

func start(beats: Array) -> void:
	_beats = beats
	_index = -1
	_advance()

func current_beat() -> Dictionary:
	return {} if _index < 0 or _index >= _beats.size() else _beats[_index]

func continue_button() -> Button:
	return _continue_btn

func reply_buttons() -> Array:
	return _replies_box.get_children()

func dialogue_text() -> String:
	return _text_label.text

func _advance() -> void:
	_index += 1
	if _index >= _beats.size():
		finished.emit()
		return
	var b := current_beat()
	_show_portrait(String(b["portrait_id"]))
	_name_label.text = String(b["speaker"])
	for child in _replies_box.get_children():
		child.free()
	_resolved_event = false
	match String(b["kind"]):
		"event":
			_continue_btn.visible = false
			_text_label.text = "..."
			Game.voice_event_scene(b["event"], func(res: Dictionary):
				_text_label.text = String(res["text"]))
			for ch in b["event"]["choices"]:
				_add_reply(String(ch["label"]), _on_event_choice.bind(String(ch["choice_id"])))
		"minister":
			_continue_btn.visible = true
			_text_label.text = String(b["text"])
			for sug in b["suggestions"]:
				var label := TemplateVoicer.line_for(Game.data,
					"reply_" + String(sug["pitch_key"]), [], Game.state.tick)
				_add_reply(label, _on_quick_reply.bind(sug))
		"summary":
			_continue_btn.visible = true
			_text_label.text = String(b["text"])
	_free_text.visible = String(b["kind"]) == "minister"

func _add_reply(label: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	_replies_box.add_child(btn)

func _show_portrait(portrait_id: String) -> void:
	for child in _portrait_holder.get_children():
		child.free()
	var p := CharacterPortrait.instantiate_for(portrait_id, false)
	p.scale = Vector2(4, 4)
	_portrait_holder.add_child(p)

func _on_quick_reply(sug: Dictionary) -> void:
	var result: Dictionary = Game.try_execute(sug["request"])
	if not result["ok"]:
		_text_label.text = String(result["error"])
		return
	for child in _replies_box.get_children():
		child.queue_free()
	_text_label.text = TemplateVoicer.line_for(Game.data,
		"outcome_" + String(sug["request"].action_code), [], Game.state.tick)

func _on_event_choice(choice_id: String) -> void:
	var out: Dictionary = Game.apply_event_choice(choice_id)
	if out.is_empty():
		return
	for child in _replies_box.get_children():
		child.queue_free()
	_resolved_event = true
	_continue_btn.visible = true
	_text_label.text = TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [String(out["event_id"]), String(out["choice_id"])], [],
		Game.state.tick)

func _on_free_text(text: String) -> void:
	if text.strip_edges() == "":
		return
	_free_text.editable = false
	Game.submit_free_text(text, func(res: Dictionary):
		_free_text.editable = true
		_free_text.clear()
		if not res["ok"]:
			_text_label.text = "The council doesn't follow. (%s)" % String(res["error"])
			return
		var spoken := ""
		for outcome in res["executed"]:
			spoken += TemplateVoicer.line_for(Game.data,
				"outcome_" + String(outcome["action_code"]), [], Game.state.tick) + " "
		_text_label.text = spoken if spoken != "" else "So noted."
	)
```

`scenes/conversation.tscn` = the standard 4-line script-only scene.

`game_root.gd`: add CONVERSATION state:

```gdscript
		State.CONVERSATION:
			current_screen = load("res://scenes/conversation.tscn").instantiate()
			current_screen.finished.connect(_on_conversation_finished)
```

`_on_start_requested` and `_on_day_run_finished` now route: `Game.next_tick()` (start) / captured report (day run) → `_switch_to(State.CONVERSATION)` → `current_screen.start(ConversationBeats.build(report, Game.state, Game.data))`. `_on_conversation_finished` → `_switch_to(State.COURT)` → `current_screen.begin_with(report_without_rerendered_briefing)`: COURT after a conversation shows ONLY the order bar state — call a new lightweight `council_screen.enter_court()` that renders metrics+suggestions but NOT outcomes/briefing (those were spoken in conversation). Add to council_screen:

```gdscript
## Post-conversation court entry: numbers + orders only; speech already
## happened on the conversation stage (R2).
func enter_court(report: TickReport) -> void:
	_render_metrics(report)
	_render_suggestions(report)
```

- [ ] **Step 5: Run full suite** — PASS. **Step 6: Commit** — `feat: conversation stage — beats, replies, event gating`

---

### Task 6: CourtScreen — the trimmed order screen (retire council_screen)

**Files:**
- Create: `scripts/ui/court_screen.gd`, `scenes/court.tscn`
- Modify: `scripts/ui/game_root.gd` (COURT_SCENE → court.tscn; wire signals), delete `scripts/ui/council_screen.gd` + `scenes/council.tscn` at the END of this task
- Test: `tests/ui/test_court_screen.gd` (migrated intents), delete `tests/ui/test_council_screen.gd`

**Interfaces:**
- Consumes: `KingdomCard`, `Game.*`, `TemplateVoicer.line_for`, suggestion dicts.
- Produces: `class_name CourtScreen extends Control` — signals `end_turn_requested`; `enter_court(report: TickReport) -> void` (KingdomCard values mode docked right (R1), natural-language suggestion buttons (pitch template text as label, tradeoff as tooltip — R8), order bar + End Turn + Enter); a small log `VBoxContainer` for Herald/court lines (free-text results, refusals) — plain labels, no portraits (R10: no roster anywhere). Free-text/EVENT_CHOICE/End-Turn gating behavior carried over 1:1 from council_screen (pending-event guard, in-flight disable, prompt caps).

- [ ] **Step 1: Write `tests/ui/test_court_screen.gd`** by MIGRATING each old test's intent (old file: `tests/ui/test_council_screen.gd`). Migration map (write all of these; adapt names/surfaces to CourtScreen):
  - builds + suggestion click executes + end_turn emits (old test 1) — suggestions now labeled with pitch text: assert button text contains no `_` and no ALL-CAPS action code (R8 check: `assert_false("LEVY_RAISE" in b.text)`).
  - free-text via FakeClient executes + tone applied (unchanged mechanics).
  - end-turn disabled while parse in flight (unchanged).
  - pending event: End Turn guard holds (court can still be entered with a pending event via free-text edge — the guard stays; event RESOLUTION tests now live in conversation tests, drop the court event-panel assertions).
  - free-text during pending event keeps gate (unchanged logic).
  - EVENT_CHOICE invalid id rejection (unchanged).
  - event effects narration + voicing reach tests: DELETE here — equivalents exist in `test_conversation_scene.gd` (voicing reach: the event-beat test exercises `voice_event_scene`; add there if missing: a FakeClient canned-text assertion mirroring the old `test_event_voicing_reaches_client_not_starved_by_briefing`, now trivially unstarved since conversation voices events with no briefing call at all — assert canned text lands in `dialogue_text()`).
  - roster/portrait tooltip tests: DELETE (roster removed, R10); opinion visibility now lives on conversation portraits — add to `test_conversation_scene.gd`: minister beat portrait tooltip contains display_name (badge suppressed with `with_badge=false`? NO — conversation portraits SHOULD show opinion: instantiate with badge; assert `Gen_Badge` exists on the beat portrait).

- [ ] **Step 2: Run** — new file FAILS (no CourtScreen). **Step 3: Implement `court_screen.gd`** — port from council_screen.gd: keep `_render_metrics`→ REPLACED by KingdomCard instance (`card.show_values(Game.state)` on enter_court + after every executed order), `_render_suggestions` (button label = `TemplateVoicer.line_for(Game.data, "pitch_" + sug["pitch_key"], [], tick, {"tradeoff": ""})`... the pitch templates embed `{tradeoff}` — strip by passing `{"tradeoff": ""}` and `strip_edges()`; tooltip = the tradeoff), `_on_free_text_submitted` + `submit_free_text` handling + `_finish_event`-adjacent cleanup (event UI is gone from court — on EVENT_CHOICE resolution just log + re-enable), End Turn + Enter + guards, `_say`-style log as plain Labels appended to the log box (cap at last 8 lines, `queue_free` older). Delete council_screen.gd/council.tscn + old test file; update `game_root.gd` `COURT_SCENE := "res://scenes/court.tscn"` and connect `end_turn_requested`.

- [ ] **Step 4: Full suite + boot check** — PASS, no SCRIPT ERROR; grep the tree for `council_screen` references (must be zero outside docs/history). **Step 5: Commit** — `feat: CourtScreen replaces council screen; roster retired`

---

### Task 7: Closeout — acceptance loop, CLAUDE.md, polish

**Files:**
- Modify: `CLAUDE.md` (scene architecture note), `docs` none else
- Test: temporary acceptance scratch (delete after), full suite

**Interfaces:** none new.

- [ ] **Step 1: Full-cycle acceptance (automated).** Scratch GUT test (delete after evidencing) driving GameRoot end-to-end: boot → MENU; `start_requested` → CONVERSATION (beats non-empty, one CharacterPortrait visible); resolve any event beat via first reply; Continue through to `finished` → COURT (KingdomCard present, suggestion labels natural-language); click a suggestion; End Turn → DAY_RUN (overlay playing, card shows a `→` row); skip-click → CONVERSATION again (tick 2's beats). Then press R (synthesize InputEventKey) → MENU with `Game.state == null`. Record each R1–R13 as machine-verified / visually-deferred in the report (R4 layout positions, R6 feel are visual — deferred to the human).
- [ ] **Step 2: CLAUDE.md** — under Planned layout, replace the stale scene list with: `scenes/game_root.tscn (state machine: MENU→CONVERSATION→COURT→DAY_RUN), main_menu, conversation, court, day_run, kingdom_card, characters/*`; one line: "UI screens are self-contained scenes signaling up to GameRoot; state mutations only via Game."
- [ ] **Step 3: Full suite + boot check green; commit** — `feat: slice 3 complete — VN flow acceptance + docs`

---

## Self-review notes (applied)

- Spec coverage: R1/R9→T2+T4; R2→T5 summary beat + T5 `enter_court` (no re-briefing); R3/R4→T5; R5→T1+T5 event/summary beats; R6→T1 key+T4; R7→T1 digit-lint + T5 summary test + card carries numbers; R8→T1 reply templates + T6 natural suggestion labels; R10→T6 (roster deleted with council_screen); R11→spec §2 + T3 skeleton; R12/R13→T3; architecture implement→T3–T6.
- Type consistency: beat dict shapes, `enter_court(report)`, `end_turn_requested`, `DayRunScreen.run(report)`, `KingdomCard.show_values/show_changes` used identically across T3–T7. `get_or_add` exists on Godot 4.7 Dictionary; if not, implementers use the has/set idiom (note: verify—4.3+ has it).
- Known judgment calls recorded: concern templates keep their `{value}` figure (pre-existing voice; R7 interpreted as no NEW numeric reporting and no numeric OUTCOME reporting — outcome/summary/reply lines are digit-free by construction and lint); minister beats are template-voiced this slice (LLM voicing stays for event scenes; `Voicer.voice_briefing` becomes flow-unused pending the debates slice — flag, don't delete).
- Cross-file deletion risk: council_screen retirement happens ONLY in T6 after conversation+day-run absorb its duties; T3–T5 keep it functional so the game is playable after every task.


