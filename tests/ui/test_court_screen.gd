extends GutTest
## Migrated from the old council screen's test suite (Task 6): CourtScreen is
## the trimmed order screen - numbers + orders only, no event panel/portraits
## (R10, that's the conversation stage's job now - Task 5). Each test below
## comments which old test it migrates and what changed and why.

# Script-level (not function-local): GDScript lambdas capture local variables
# by value, so a reassignment like `func(): end_turn_emitted = true` inside a
# lambda would not be visible to the enclosing test function once it's a
# local var. Reassigning a member variable through the implicit `self` does
# propagate. (Same reasoning as the old council screen test suite's
# `_end_turn_emitted` and tests/llm/test_voicer_fallback.gd's `got`.)
var _end_turn_emitted := false

func _report_after_resolving_pending_event() -> TickReport:
	var report := Game.next_tick()
	# Seed 42's first tick can itself roll a pending event (ev_08). Resolved
	# directly on state (no court event panel exists any more) so each test
	# below starts from a clean, deterministic pending_event == {} baseline,
	# same convention test_conversation_scene.gd already uses.
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	return report

func _screen() -> CourtScreen:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	return screen

## Migrates the old council screen's test_screen_builds_and_click_executes,
## adapted for R8 (natural-language suggestion labels replace bare action
## codes - old assertion was `assert_between(buttons.size(), 2, 3)` plus a
## click/state-change/end-turn-emit check; new assertions add the label
## checks) and R10 (no court event panel any more - the incidental pending
## event is resolved directly on state, not via a court event button).
func test_screen_builds_suggestion_executes_and_labels_are_natural_language() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	var buttons: Array = screen.suggestion_buttons()
	assert_between(buttons.size(), 2, 3)
	for b in buttons:
		assert_false("LEVY_RAISE" in b.text, "label must not be a bare action code")
		assert_false("_" in b.text, "label must be natural-language prose, not a code (R8)")
	buttons[0].pressed.emit()
	await wait_frames(2)
	assert_ne(Game.state.recent_outcomes, [], "the click must actually execute an order")
	_end_turn_emitted = false
	screen.end_turn_requested.connect(func(): _end_turn_emitted = true)
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_true(_end_turn_emitted)
	assert_eq(Game.state.tick, 1)  # GameRoot owns advancing, not the screen

## Migrates the old council screen's test_free_text_path_executes_via_fake_client
## verbatim (same seed, same canned payload, same tax_rate/tone assertions),
## routed through CourtScreen's free_text input row (text_submitted.emit)
## instead of calling Game.submit_free_text directly, so the screen's own
## submit path is what's actually under test here.
func test_free_text_executes_via_fake_client_and_tone_applied() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_steward"], "tone": "respectful", "promises": []}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	screen.free_text.text_submitted.emit("ease the taxes a little")
	await wait_frames(3)
	assert_eq(Game.state.metrics["tax_rate"], 4.0)
	assert_string_contains(
		Game.state.characters["char_steward"].opinion_log[-1]["reason"], "tone")

## Migrates the old council screen's
## test_end_turn_disabled_while_free_text_parse_in_flight (FIX 6): End Turn
## must not be clickable while a free-text order is being parsed. Unchanged
## logic/assertions; only the event-resolution setup changed (no court event
## button any more - see _report_after_resolving_pending_event).
func test_end_turn_and_free_text_disabled_while_parse_in_flight() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [], "court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("do nothing in particular")
	assert_true(screen.end_turn_button().disabled, "disabled while parse is in flight")
	assert_false(screen.free_text.editable, "free_text also disabled while parse is in flight")
	await wait_frames(3)
	assert_false(screen.end_turn_button().disabled, "re-enabled once the parse resolves")
	assert_true(screen.free_text.editable)

## Migrates the gating half of the old council screen's
## test_free_text_during_event_keeps_end_turn_gated_then_choice_resolves
## (the slice-2 End-Turn gap closure: a free-text NORMAL action resolving
## must NOT re-enable End Turn while an event is still pending). The
## resolution half (clicking an event choice button) is dropped - event
## RESOLUTION now belongs to the conversation stage
## (test_conversation_scene.gd's event beat test), and court has no event
## button to click any more.
func test_free_text_during_pending_event_keeps_end_turn_gated() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	Game.engine.events._fire("ev_01", Game.state)
	assert_false(Game.state.pending_event.is_empty())
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("also lower taxes a bit")
	await wait_frames(3)
	assert_true(screen.end_turn_button().disabled,
		"NORMAL free-text action resolves but the event is still pending")
	assert_false(Game.state.pending_event.is_empty(), "event still awaits a choice")
	assert_true(screen.free_text.editable, "free_text itself always re-enables")

## Migrates the old council screen's
## test_free_text_event_choice_invalid_id_is_rejected_and_event_stays_pending.
## The old test was Game-level only (Game.submit_free_text, no screen); this
## version adds a CourtScreen-level assertion that the rejection actually
## reaches the court log (per the Task 6 brief's "EVENT_CHOICE ... rejected
## ... log contains ... or the rejection reaches the log").
func test_free_text_event_choice_invalid_id_rejected_and_logged() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	Game.engine.events._fire("ev_01", Game.state)
	assert_false(Game.state.pending_event.is_empty())
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "not_a_real_choice"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("do something not offered")
	await wait_frames(3)
	assert_false(Game.state.pending_event.is_empty(), "event still awaits a valid choice")
	var found := false
	for child in screen.log_box.get_children():
		if "no such choice awaits" in String(child.text):
			found = true
	assert_true(found, "the rejection must reach the court log")

## User ruling (2026-08-29, UI_example chrome, supersedes R1's card dock):
## metrics live in the TopBar strip along the top edge; the lettered
## suggestion buttons live in the right advice panel with End Turn.
func test_top_bar_up_top_and_lettered_suggestions_in_side_panel() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	assert_not_null(screen.top_bar())
	assert_lt(screen.top_bar().global_position.y, 5.0, "TopBar hugs the top edge")
	assert_gt(screen.suggestion_buttons().size(), 0)
	assert_true(String(screen.suggestion_buttons()[0].text).begins_with("A."),
		"suggestions are lettered like the mock's responses")
	var side: Control = screen.find_child("SidePanel", true, false)
	assert_true(side.is_ancestor_of(screen.end_turn_button()),
		"End Turn lives in the right advice panel")

## New CourtScreen-specific coverage (R1/R7/R9): the TopBar must reflect
## state immediately after an executed order, not just at enter_court time.
func test_top_bar_refreshes_after_suggestion_executes() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	var idx := -1
	for i in report.suggestions.size():
		if "raise_levies" in String(report.suggestions[i]["pitch_key"]):
			idx = i
			break
	assert_ne(idx, -1, "seed 42's standing menu always offers LEVY_RAISE")
	var gold_before := screen.top_bar().metric_text("treasury")
	screen.suggestion_buttons()[idx].pressed.emit()
	await wait_frames(2)
	assert_ne(screen.top_bar().metric_text("treasury"), gold_before,
		"the TopBar's Gold value must refresh after the order executes")

## Migration-map item 16 (guard-holds): the End-Turn pending-event guard
## lives entirely inside CourtScreen._on_end_turn's early return - proven
## here in isolation, with no free-text order involved (the free-text path's
## own re-enable interaction with the guard is already covered by
## test_free_text_during_pending_event_keeps_end_turn_gated above). Asserts
## on the signal + tick, not on end_turn.disabled: the early return leaves
## `disabled` at whatever it already was (false here, since nothing has
## disabled it yet), so `disabled` is not a reliable witness of the guard -
## the guard's only observable effect is that end_turn_requested never fires
## and the tick never advances.
func test_end_turn_guard_holds_with_pending_event_no_free_text() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_frames(2)
	Game.engine.events._fire("ev_01", Game.state)
	assert_false(Game.state.pending_event.is_empty())
	var tick_before := Game.state.tick
	_end_turn_emitted = false
	screen.end_turn_requested.connect(func(): _end_turn_emitted = true)
	screen.end_turn_button().pressed.emit()
	await wait_frames(1)
	assert_false(_end_turn_emitted, "End Turn must not fire while an event is pending")
	assert_eq(Game.state.tick, tick_before, "the guard must not let a tick slip through")
