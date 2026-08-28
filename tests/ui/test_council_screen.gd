extends GutTest

# Script-level (not function-local): GDScript lambdas capture local variables
# by value, so a reassignment like `func(res): got = res` inside a lambda
# would not be visible to the enclosing function once it's a local var.
# Reassigning a member variable through the implicit `self` does propagate.
# (Same reasoning as tests/llm/test_voicer_fallback.gd's `got`.)
var got: Dictionary = {}
var _end_turn_emitted := false

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
	_end_turn_emitted = false
	screen.end_turn_requested.connect(func(): _end_turn_emitted = true)
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_true(_end_turn_emitted)
	assert_eq(Game.state.tick, 1)  # GameRoot owns advancing now

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

## Game-level coverage (no screen needed) for Game.submit_free_text's
## EVENT_CHOICE branch when the parsed choice_id doesn't match any of the
## pending event's actual choices: apply_event_choice returns {} (see
## EventSystem.apply_choice), which submit_free_text must surface as a
## rejected entry rather than silently dropping it or clearing the event.
func test_free_text_event_choice_invalid_id_is_rejected_and_event_stays_pending() -> void:
	Game.start_campaign(42)
	Game.engine.events._fire("ev_01", Game.state)
	assert_false(Game.state.pending_event.is_empty())
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "not_a_real_choice"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	got = {}
	Game.submit_free_text("do something not offered", func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(got["executed"].size(), 0)
	assert_eq(got["rejected"].size(), 1)
	assert_string_contains(got["rejected"][0]["error"], "no such choice awaits")
	assert_false(Game.state.pending_event.is_empty(), "event still awaits a valid choice")

## Reads back each _say frame as a {speaker, text} dict, in transcript order.
## _say's structure is frame(PanelContainer) > row(HBoxContainer) >
## [pic?, col(VBoxContainer)] > col > [name_label, text_label] — col is
## always row's LAST child (the optional portrait, when present, comes
## first), so indexing from the end avoids assuming a portrait is present.
## Deliberately narrower than a blind recursive Label search: CharacterPortrait
## itself contains Labels (initials/badges — see character_portrait.gd), so
## scanning all descendant Labels for a bare text match risks false
## positives/negatives; pairing each frame's own name+text label does not.
func _transcript_lines(screen: Node) -> Array:
	var out: Array = []
	for frame in screen.transcript_box.get_children():
		var row: Node = frame.get_child(0)
		var col: Node = row.get_child(row.get_child_count() - 1)
		var name_label: Label = col.get_child(0)
		var text_label: Label = col.get_child(1)
		out.append({"speaker": name_label.text, "text": text_label.text})
	return out

## FIX 1 (voicer busy-collision starves event voicing): drives the real
## _render_report path (not _render_event directly, like the older event
## tests above) with a FakeClient wired for a canned response, and a pending
## mini-voice event (ev_02) forced onto the report ahead of Game.next_tick()
## so EventSystem.roll's pending_event short-circuit hands it straight back
## as report.event, deterministically (no dependence on the RNG roll).
## Before the fix, _render_report voiced the LLM briefing first, which held
## Voicer._busy for the whole async round-trip, so voice_event_scene's call
## below would always hit the busy guard and degrade to template — the
## Herald's event line would carry template text, not the canned client text.
## Asserted specifically as (speaker "Herald", text == canned_text): the
## FakeClient hands back the same canned text to ANY caller, so on the old
## buggy path the briefing call (which went first and won the race) would
## itself surface that same string under speaker "Council" — a bare
## "does this text appear anywhere in the transcript" check would false-pass
## on that coincidence. Pairing speaker+text closes that hole.
func test_event_voicing_reaches_client_not_starved_by_briefing() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "The rider speaks of dark omens."
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.engine.events._fire("ev_02", Game.state)  # mini-voice event
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	var report := Game.next_tick()
	assert_eq(String(report.event.get("event_id", "")), "ev_02",
		"pre-set pending_event must short-circuit the roll")
	screen._render_report(report)
	await wait_frames(3)
	var found := false
	for line in _transcript_lines(screen):
		if line["speaker"] == "Herald" and line["text"] == "The rider speaks of dark omens.":
			found = true
	assert_true(found,
		"voice_event_scene's canned client text must reach the Herald's transcript line, not degrade to template")

## FIX 2 (event-choice effects are never narrated): resolving ev_01's
## "accept" choice via its button must narrate the metric effect
## (peasant_contentment) in the Chancellor's voice, the same way
## _on_suggestion already narrates ordinary action effects.
func test_event_choice_effects_are_narrated_after_resolution() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	screen.begin()
	await wait_frames(2)
	Game.engine.events._fire("ev_01", Game.state)
	screen._render_event(Game.state.pending_event)
	await wait_frames(2)
	# ev_01's choices load in CSV order (data/event_choices.csv): accept,
	# feast, refuse — button 0 is "accept" (effects: metric:peasant_contentment:2).
	screen.event_buttons()[0].pressed.emit()
	await wait_frames(2)
	var found := false
	for line in _transcript_lines(screen):
		if "peasant_contentment" in line["text"]:
			found = true
	assert_true(found,
		"the accept choice's metric effect (peasant_contentment) must be narrated")

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
