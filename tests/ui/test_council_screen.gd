extends GutTest

# Script-level (not function-local): GDScript lambdas capture local variables
# by value, so a reassignment like `func(res): got = res` inside a lambda
# would not be visible to the enclosing function once it's a local var.
# Reassigning a member variable through the implicit `self` does propagate.
# (Same reasoning as tests/llm/test_voicer_fallback.gd's `got`.)
var got: Dictionary = {}

func test_screen_builds_and_click_executes() -> void:
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.start_campaign(42)
	screen.begin()          # renders first tick
	await wait_frames(2)
	var buttons: Array = screen.suggestion_buttons()
	assert_between(buttons.size(), 2, 3)
	var treasury_before: float = Game.state.metrics["treasury"]
	buttons[0].pressed.emit()
	await wait_frames(2)
	assert_ne(Game.state.recent_outcomes, [])
	# Seed 42's first tick also rolls a pending event (ev_08). End Turn is now
	# correctly gated while an event awaits a decision (mid-event End-Turn
	# gap closure), so resolve it first — same as a real player would.
	if not Game.state.pending_event.is_empty():
		screen.event_buttons()[0].pressed.emit()
		await wait_frames(2)
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_eq(Game.state.tick, 2)

func test_free_text_path_executes_via_fake_client() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_steward"], "tone": "respectful", "promises": []}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	got = {}
	Game.submit_free_text("ease the taxes a little", func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(got["executed"].size(), 1)
	assert_eq(Game.state.metrics["tax_rate"], 4.0)
	assert_string_contains(
		Game.state.characters["char_steward"].opinion_log[-1]["reason"], "tone")

# Additive coverage for the carried Task 11 acceptance criterion (spec §6):
# one 48x48 placeholder portrait panel per seated minister, in the row between
# the metrics strip and the transcript. Not part of the brief's verbatim test;
# added to give the portraits requirement real automated evidence beyond
# "it compiles" (visual layout/color still needs a human's eyes at 640x360).
func test_portraits_render_one_per_seated_minister() -> void:
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.start_campaign(42)
	screen.begin()
	await wait_frames(2)
	# The row holds one portrait per seated minister plus the DateLabel
	# (calendar feature); count only the portrait panels.
	var portrait_count := 0
	for child in screen.portraits_box.get_children():
		if child.name != "DateLabel":
			portrait_count += 1
	assert_eq(portrait_count, Game.state.council.size())
	assert_gt(Game.state.council.size(), 0)  # guard against a vacuous pass

## FIX 6: End Turn must not be clickable while a free-text order is being
## parsed — a mid-parse tick advance would race the pending action against
## whatever the parse eventually returns. Mirrors the existing free_text
## disable/re-enable coverage.
func test_end_turn_disabled_while_free_text_parse_in_flight() -> void:
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.start_campaign(42)
	screen.begin()
	await wait_frames(2)
	# Seed 42's first tick also rolls a pending event (ev_08); resolve it
	# first so the assertions below isolate End Turn's free-text-parse gating
	# from its (now correct) event gating — see the mid-event End-Turn gap
	# closure, covered separately in test_free_text_during_event_keeps_end_turn_gated_then_choice_resolves.
	if not Game.state.pending_event.is_empty():
		screen.event_buttons()[0].pressed.emit()
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

func test_pending_event_gates_turn_and_choice_resolves() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	screen.begin()
	await wait_frames(2)
	# Force a known event deterministically (bypasses the roll)
	Game.engine.events._fire("ev_01", Game.state)
	screen._render_event(Game.state.pending_event)
	await wait_frames(2)
	assert_true(screen.end_turn_button().disabled)
	assert_gt(screen.event_buttons().size(), 1)
	var pc0: float = Game.state.metrics["peasant_contentment"]
	screen.event_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_true(Game.state.pending_event.is_empty())
	assert_false(screen.end_turn_button().disabled)
	assert_ne(Game.state.metrics["peasant_contentment"], pc0)

## Controller ruling (Task 7 review, closed in Task 8): a free-text order
## submitted while an event is pending must not re-enable End Turn merely
## because the parse finished — the event still gates the turn until it is
## actually resolved. Resolving it (here, via an event button) must then
## re-enable End Turn. This also covers the EVENT_CHOICE-via-free-text path
## indirectly: council_screen._finish_event is exercised either way.
func test_free_text_during_event_keeps_end_turn_gated_then_choice_resolves() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	screen.begin()
	await wait_frames(2)
	Game.engine.events._fire("ev_01", Game.state)
	screen._render_event(Game.state.pending_event)
	await wait_frames(2)
	assert_true(screen.end_turn_button().disabled, "gated once the event renders")
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
	screen.event_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_true(Game.state.pending_event.is_empty())
	assert_false(screen.end_turn_button().disabled, "re-enabled once the event resolves")

## New Task 8 path: free text itself carries the EVENT_CHOICE pseudo-action
## (the model resolved the event instead of the player clicking a button).
## Game.submit_free_text routes it to apply_event_choice; council_screen's
## completion callback must detect the resolved event and run the same
## cleanup as a button click (_finish_event), not the generic "It is done"
## narration.
func test_free_text_event_choice_resolves_and_cleans_up_event_panel() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	screen.begin()
	await wait_frames(2)
	Game.engine.events._fire("ev_01", Game.state)
	screen._render_event(Game.state.pending_event)
	await wait_frames(2)
	assert_true(screen.end_turn_button().disabled)
	assert_gt(screen.event_buttons().size(), 0)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "accept"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("accept the geese with thanks")
	await wait_frames(3)
	assert_true(Game.state.pending_event.is_empty(), "event resolved via free text")
	assert_false(screen.end_turn_button().disabled, "re-enabled once resolved")
	assert_eq(screen.event_buttons().size(), 0, "event panel cleaned up")
	assert_true(screen.free_text.editable)

func test_roster_shows_opinion_and_reasons() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.next_tick()
	Game.try_execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}))
	screen._render_portraits()
	await wait_frames(2)
	var found_reason := false
	for p in screen.portraits_box.get_children():
		if "opposes, orthodoxy" in p.tooltip_text:
			found_reason = true
	assert_true(found_reason)
