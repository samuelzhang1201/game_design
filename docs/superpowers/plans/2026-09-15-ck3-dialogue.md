# CK3 Audience Window and Dark Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The conversation stage becomes a CK3-style centred audience window over the map, and the whole UI goes dark (leather, wood, gold).

**Architecture:** `UiPalette` constants flip to a dark register (plus the few literal light colours outside it); `VellumPanelStyle` gets a tint so the ornament shows on dark. In `conversation.tscn` the dossier, speech, replies and talk row move out of the right column into `%AudienceWindow` inside `%AudienceLayer`, which `ConversationScene._layout` places over the map; a small `AudienceBackdrop` Control draws the scene behind the portrait. Events and narration render in the same window. No engine file changes.

**Tech Stack:** Godot 4.x, typed GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-09-15-ck3-dialogue-design.md`

## Global Constraints

- Typed GDScript everywhere; UI never mutates state except through `Game`.
- Design values live in CSVs: the backdrop painting path is a `data/locations.csv` column, not a script constant.
- Every existing test seam on `ConversationScene` keeps its name and meaning (`reply_buttons`, `dialogue_text`, `free_text_field`, `continue_button`, `dialogue_panel`, `dialogue_scroll`, `event_popup`, `select_tab`, `tab_page`, `dossier_up`, …).
- `./run_tests.sh` must report the expected error count (2 with the gdai plugin installed, else 0).
- Design viewport 1280×720; verify with `tools/snapshot_screen.gd --resolution`.

---

### Task 1: Dark palette

**Files:**
- Modify: `scripts/ui/ui_palette.gd`, `scripts/ui/vellum_panel_style.gd`, `scripts/ui/location_view.gd`, `scripts/ui/conversation_scene.gd` (`SPEAKER_PALETTE`), `scripts/ui/map_detail_panel.gd` (`_work_style`), `data/chart_palette.csv`
- Test: `tests/ui/test_ui_palette_dark.gd`

**Interfaces:**
- Produces: `UiPalette.CHIP_HOVER`, `CHIP_PRESSED`, `INPUT_BG`, `TROUGH`, `ORNAMENT_TINT`: `Color`; `UiPalette.button_looks() -> Dictionary` (state → `StyleBoxFlat`); `VellumPanelStyle.tint: Color`.

- [ ] **Step 1: failing contrast test**

```gdscript
extends GutTest
## The dark CK3 theme (owner 2026-09-15): light ink on dark leather, gold accent.

func test_panels_are_dark_and_ink_is_light() -> void:
	assert_lt(UiPalette.PANEL_BG.get_luminance(), 0.15, "the card is dark")
	assert_lt(UiPalette.BG_SCREEN.get_luminance(), UiPalette.PANEL_BG.get_luminance() + 0.01)
	assert_gt(UiPalette.TEXT_SOFT.get_luminance(), 0.75, "body ink is light")
	assert_gt(UiPalette.GOLD.get_luminance() - UiPalette.PANEL_BG.get_luminance(), 0.45,
		"the accent reads on the card")
	assert_gt(UiPalette.TEXT_DIM.get_luminance() - UiPalette.CHIP_BG.get_luminance(), 0.25,
		"even a hint reads on a button")

func test_theme_has_no_light_boxes() -> void:
	var theme := UiPalette.build_theme()
	for pair in [["normal", "Button"], ["hover", "Button"], ["normal", "LineEdit"],
			["panel", "TooltipPanel"]]:
		var box := theme.get_stylebox(pair[0], pair[1]) as StyleBoxFlat
		assert_lt(box.bg_color.get_luminance(), 0.2, "%s %s is dark" % pair)
```

- [ ] **Step 2:** run `./run_tests.sh` (or GUT on this file) — FAIL on luminance.
- [ ] **Step 3:** flip the constants per spec §1; replace the literal `Color("e3ecf8")` / `Color("dbe6f6")` / `Color.WHITE` / `Color("e6ebf1")` uses with the new constants through one `button_looks()`; shadows to `Color(0,0,0,0.45)`; `VellumPanelStyle._draw` draws with `tint` and `panel_style` sets `ORNAMENT_TINT`; skill colours brightened; `TOOL_PERSONAL` `#3fc1ae`; chart palette `cat_2 #5aa2ec`, `cat_3 #6cc36a`, `cat_4 #a383ee`, `cat_5 #e5665a`, `sequential #5aa2ec`, `track #2d251d`; location kind tints dark; speaker palette bright; work box `Color(1,1,1,0.08)`.
- [ ] **Step 4:** tests pass.
- [ ] **Step 5:** commit `ui(theme): the whole UI goes dark — leather, wood and gold (owner 2026-09-15)`.

### Task 2: Audience window

**Files:**
- Create: `scripts/ui/audience_backdrop.gd`
- Modify: `scenes/conversation.tscn`, `scripts/ui/conversation_scene.gd`, `scripts/ui/screen_layout.gd` (`apply` takes `right_width`), `scripts/ui/character_portrait.gd` (static `opinion_summary`), `data/locations.csv` (`backdrop` column, empty)
- Test: `tests/ui/test_conversation_scene.gd`, `tests/ui/test_ui_rework.gd`

**Interfaces:**
- Consumes: Task 1 colours.
- Produces: `AudienceBackdrop` (`extends Control`, `var location_code: String`, `func painting() -> Texture2D`); `CharacterPortrait.opinion_summary(c: Character, count: int = 5) -> String`; `ConversationScene.audience_window() -> PanelContainer`, `speech_scroll() -> ScrollContainer`, `speech_text() -> String`; `ScreenLayout.TALK_WIDTH := 320.0`; `ScreenLayout.apply(top, left, map, right_panels, right_open, right_width := RIGHT_WIDTH)`.

- [ ] **Step 1: failing tests** (appended to `test_conversation_scene.gd`)

```gdscript
func test_the_audience_window_stands_over_the_map() -> void:
	Game.start_campaign(42)
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "The levies grow soft.", "suggestions": []}],
		TickReport.new())
	await wait_frames(3)
	var win := c.audience_window()
	assert_true(win.visible, "a person on stage opens the audience")
	assert_true(c.map_panel().get_global_rect().grow(1.0).encloses(win.get_global_rect()),
		"centred over the map, inside it")
	assert_true(win.get_global_rect().encloses(
		c.find_child("PortraitBox", true, false).get_global_rect()), "the portrait is in it")
	assert_string_contains(c.speech_text(), "levies", "and so are their words")

func test_opinion_tooltip_gives_the_reasons() -> void:
	Game.start_campaign(42)
	var m: Character = Game.state.characters["char_marshal"]
	m.opinion_log.append({"delta": -8, "reason": "revoked the noble tax exemption"})
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": m.display_name, "text": "hm", "suggestions": []}], TickReport.new())
	await wait_frames(2)
	var value: Label = c.find_child("OpinionValue", true, false)
	assert_string_contains(value.tooltip_text, "revoked the noble tax exemption")

func test_an_event_uses_the_same_window() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var c := _scene_with([{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}],
		TickReport.new())
	await wait_frames(3)
	assert_eq(c.event_popup(), c.audience_window())
	assert_true(c.audience_window().visible)
	for b in c.reply_buttons():
		assert_true(c.audience_window().is_ancestor_of(b), "choices are options in the window")

func test_an_option_tells_its_tradeoff() -> void:
	Game.start_campaign(42)
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "Fresh levies?", "suggestions": [sug]}], TickReport.new())
	await wait_frames(2)
	assert_string_contains(c.reply_buttons()[0].tooltip_text, "Gold and grumbling.")
```

Rewrite `test_the_dossier_stands_over_the_talk_in_the_right_column` as `test_the_dossier_stands_in_the_audience_window` (head inside `audience_window()`; a page replaces `speech_scroll()` and hands it back; the window's minimum size fits its size). In `test_ui_rework.gd`, the narration test measures `AudienceWindow` and finds `SpeechScroll`; the event test asserts `AudienceTitle` is non-empty.

- [ ] **Step 2:** run — FAIL (`audience_window` missing).
- [ ] **Step 3:** restructure `conversation.tscn` per spec §2/§3; in the script: `_layout` copies the map's anchors/offsets onto `%AudienceLayer` and sizes the window (`min(780, w-32)`, `min(540, h-32)`); `_render_history` also renders `%SpeechLabel` from `_beat_start`; `_advance` sets `_beat_start`, the banner, and shows the window for every kind (narration hides `%PortraitSide`); event/narration choices go to `%RepliesBox`; `event_popup()` returns the window; the MOVE popup keeps `%EventPopup`; option buttons get `UiPalette.option_looks()` and a tooltip (tradeoff + `OrderCosts.gold_of`); trait chips get notes tooltips; `%SkillBadges`; `%OpinionValue.tooltip_text = CharacterPortrait.opinion_summary(c)`; `AudienceBackdrop` draws the wash/glow/vignette or the painting.
- [ ] **Step 4:** full suite passes with the expected error count.
- [ ] **Step 5:** commit `ui(conversation): the CK3 audience window — portrait on its scene, name plate, reasons on hover, options`.

### Task 3: Verify, document, push

**Files:**
- Modify: `CLAUDE.md` (invariant 10 and the theme paragraph), `scripts/ui/screen_layout.gd` header comment

- [ ] **Step 1:** snapshots: `--screen conversation --speaker char_chancellor --resolution 1280x720`, `--tab 1`, and `--resolution 2560x1600`; `--screen root --resolution 1280x720` (court, dark chrome); look at each and fix what reads wrong.
- [ ] **Step 2:** update CLAUDE.md: the audience window ruling (2026-09-15) and the dark theme reversing 2026-09-13.
- [ ] **Step 3:** `./run_tests.sh` once more; commit `docs: the audience window and the dark theme`; `git push -u origin ck3-dialogue`.
