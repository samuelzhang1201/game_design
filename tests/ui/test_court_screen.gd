extends GutTest
## Migrated from the old council screen's test suite (Task 6): CourtScreen is
## the trimmed order screen - numbers + orders only, no event panel/portraits
## (R10, that's the conversation stage's job now - Task 5). Each test below
## comments which old test it migrates and what changed and why.

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
	await wait_process_frames(2)
	var buttons: Array = screen.suggestion_buttons()
	assert_between(buttons.size(), 2, 3)
	for b in buttons:
		assert_false("LEVY_RAISE" in b.text, "label must not be a bare action code")
		assert_false("_" in b.text, "label must be natural-language prose, not a code (R8)")
	buttons[0].pressed.emit()
	await wait_process_frames(2)
	assert_ne(Game.state.recent_outcomes, [], "the click must actually execute an order")
	# There is no End Turn (owner 2026-09-14): an order never moves the month.
	assert_null(screen.find_child("EndTurn", true, false))
	assert_eq(Game.state.tick, 1)

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
	await wait_process_frames(3)
	assert_eq(Game.state.metrics["tax_rate"], 4.0)
	assert_string_contains(
		Game.state.characters["char_steward"].opinion_log[-1]["reason"], "tone")

## Migrates the old council screen's
## test_end_turn_disabled_while_free_text_parse_in_flight (FIX 6): End Turn
## must not be clickable while a free-text order is being parsed. Unchanged
## logic/assertions; only the event-resolution setup changed (no court event
## button any more - see _report_after_resolving_pending_event).
func test_free_text_disabled_while_parse_in_flight() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_process_frames(2)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [], "court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("do nothing in particular")
	assert_false(screen.free_text.editable, "free_text also disabled while parse is in flight")
	await wait_process_frames(3)
	assert_true(screen.free_text.editable)

## Migrates the gating half of the old council screen's
## test_free_text_during_event_keeps_end_turn_gated_then_choice_resolves
## (the slice-2 End-Turn gap closure: a free-text NORMAL action resolving
## must NOT re-enable End Turn while an event is still pending). The
## resolution half (clicking an event choice button) is dropped - event
## RESOLUTION now belongs to the conversation stage
## (test_conversation_scene.gd's event beat test), and court has no event
## button to click any more.
func test_free_text_during_pending_event_leaves_the_event_pending() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_process_frames(2)
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
	await wait_process_frames(3)
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
	await wait_process_frames(2)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "not_a_real_choice"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	screen.free_text.text_submitted.emit("do something not offered")
	await wait_process_frames(3)
	assert_false(Game.state.pending_event.is_empty(), "event still awaits a valid choice")
	var found := false
	for child in screen.log_box.get_children():
		if "no such choice awaits" in String(child.text):
			found = true
	assert_true(found, "the rejection must reach the court log")

## User ruling (2026-08-29, UI_example chrome, supersedes R1's card dock):
## metrics live in the TopBar strip along the top edge; the lettered
## suggestion buttons live in the right advice panel.
func test_top_bar_up_top_and_lettered_suggestions_in_side_panel() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_process_frames(2)
	assert_not_null(screen.top_bar())
	assert_lt(screen.top_bar().global_position.y, 5.0, "TopBar hugs the top edge")
	assert_gt(screen.suggestion_buttons().size(), 0)
	assert_true(String(screen.suggestion_buttons()[0].text).begins_with("A."),
		"suggestions are lettered like the mock's responses")
	var side: Control = screen.find_child("SidePanel", true, false)
	assert_true(side.is_ancestor_of(screen.suggestion_buttons()[0]),
		"the suggestions live in the right advice panel")

## New CourtScreen-specific coverage (R1/R7/R9): the TopBar must reflect
## state immediately after an executed order, not just at enter_court time.
func test_top_bar_refreshes_after_suggestion_executes() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_process_frames(2)
	var idx := -1
	for i in report.suggestions.size():
		if "raise_levies" in String(report.suggestions[i]["pitch_key"]):
			idx = i
			break
	assert_ne(idx, -1, "seed 42's standing menu always offers LEVY_RAISE")
	var gold_before := screen.top_bar().metric_text("treasury")
	screen.suggestion_buttons()[idx].pressed.emit()
	await wait_process_frames(2)
	assert_ne(screen.top_bar().metric_text("treasury"), gold_before,
		"the TopBar's Gold value must refresh after the order executes")

## Hovering a country swaps the left column to its card and restores the
## council log on the way out (user request 2026-09-09).
func test_hovering_a_country_swaps_the_left_column() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	await wait_process_frames(1)
	var panel := screen.country_panel()
	assert_not_null(panel, "court owns a country panel")
	assert_false(panel.visible, "nothing hovered: the log has the column")
	var log_visible: bool = screen.log_box.get_parent().visible
	var mine := Game.data.resolve_realm("player_realm")
	panel.show_country(mine)
	assert_true(panel.visible, "hovering a country shows its card")
	assert_eq(panel.title_label().text, String(Game.data.kingdoms[mine]["label"]))
	assert_gt(panel.rows().get_child_count(), 0, "with its facts")
	panel.show_country("")
	assert_false(panel.visible, "leaving the country puts the log back")
	assert_eq(screen.log_box.get_parent().visible, log_visible,
		"and the log is exactly as it was")

## The card reports who holds the land now, not the pack's starting map.
func test_the_country_card_follows_conquest() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	await wait_process_frames(1)
	var panel := screen.country_panel()
	var mine := Game.data.resolve_realm("player_realm")
	panel.show_country(mine)
	var before: Array[String] = []
	for child in panel.rows().get_children():
		before.append(child.text)
	var held := MapOwnership.provinces_of(Game.data, Game.state, mine)
	MapOwnership.set_owner(Game.data, Game.state, held[0],
		Game.data.resolve_realm("raider_realm"), "test")
	# No leave/re-enter: the card must notice the conquest on its own.
	panel.show_country(mine)
	var after: Array[String] = []
	for child in panel.rows().get_children():
		after.append(child.text)
	assert_ne(after, before, "losing a province changed the card")

## The detail column's Ask drops the question into the order box; nothing sends.
func test_map_ask_fills_the_order_box_without_sending() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	await wait_process_frames(1)
	var map := screen.map3d_view()
	# The pack is generated: ask about the bound realm's own capital. What the
	# map sends for a click on it (a headless run does not load the 3D world).
	var capital: Dictionary = Game.data.burgs[String(
		Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])]
	map.object_selected.emit({"title": String(capital["label"]),
		"obj": {"kind": "burg", "code": String(capital["burg_code"])}})
	await wait_process_frames(1)
	assert_true(screen.detail_panel().visible, "the click opens the detail column")
	assert_true(screen.detail_panel().ask_button().visible, "court owns an order box, so Ask shows")
	screen.detail_panel().ask_button().pressed.emit()
	assert_eq(screen.free_text.text, "What do we know of %s?" % String(capital["label"]))
	assert_eq(screen.log_box.get_child_count(), 0, "nothing was sent")
## The two-part order (spec 2026-09-09 §4): the speaker's narrative prints
## under their name, then the ledger lines that actually applied.
func test_free_text_prints_the_narrative_and_the_ledger() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "The granaries open a crack.",
		"impacts": {"actions": [], "world": [{"path": "metrics.grain", "delta": 5,
		"reason": "a gift"}], "court_reaction": {}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	var grain: float = Game.state.metrics["grain"]
	screen.free_text.text_submitted.emit("open the granaries a little")
	await wait_process_frames(3)
	assert_eq(fake.calls, 1, "one call carries the narrative and the impacts")
	assert_eq(Game.state.metrics["grain"], grain + 5.0)
	var texts: Array[String] = []
	for l in screen.log_box.get_children():
		texts.append((l as Label).text)
	var joined := "\n".join(texts)
	assert_string_contains(joined, "The granaries open a crack.")
	assert_string_contains(joined, "grain +5")
	assert_string_contains(joined, "clerks", "a gift with no cost is charged the generic cost")

## Who answers is chosen before the call: a present character named in the
## text speaks, else the Chancellor.
func test_free_text_names_the_speaker_before_the_call() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "The levies will hold.",
		"impacts": {"actions": [], "world": [], "court_reaction": {}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	var marshal: Character = Game.state.characters[Game.state.council["marshal"]]
	screen.free_text.text_submitted.emit("Marshal, how stand the levies?")
	await wait_process_frames(3)
	var found := false
	for l in screen.log_box.get_children():
		if (l as Label).text.begins_with(marshal.display_name + ":"):
			found = true
	assert_true(found, "the marshal answered under his own name")

## Province view (user request 2026-09-09): selecting one of the player's own
## provinces shows its CARD in the right detail column (a field grid after
## Azgaar's burg editor); a foreign one shows only what is commonly known;
## water clears the column.
func test_selecting_a_province_shows_its_card_in_the_detail_column() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	await wait_process_frames(2)
	# What the map sends for a click on a province (see above).
	var map := screen.map3d_view()
	var mine := MapOwnership.provinces_of(Game.data, Game.state, Game.data.resolve_realm("player_realm"))[0]
	map.province_selected.emit(mine)
	await wait_process_frames(1)
	var panel := screen.detail_panel()
	assert_true(panel.visible, "the detail column opens")
	assert_eq(panel.shown_province(), mine)
	var texts: Array[String] = []
	for l in panel.fields().get_children():
		texts.append((l as Label).text)
	assert_has(texts, "Population")
	assert_has(texts, "Held by")
	assert_true(panel.preview().visible, "a window onto the province")
	var foreign := ""
	for code: String in Game.data.provinces:
		if String(Game.data.provinces[code]["kingdom_code"]) != Game.data.resolve_realm("player_realm"):
			foreign = code
			break
	map.province_selected.emit(foreign)
	await wait_process_frames(1)
	texts.clear()
	for l in panel.fields().get_children():
		texts.append((l as Label).text)
	assert_false(texts.has("Population"), "no details abroad")
	assert_has(texts, "Held by")
	assert_string_contains(panel.hint_label().text, "Little more is known")
	map.province_selected.emit("")
	await wait_process_frames(1)
	assert_false(panel.visible, "clearing the selection closes the column")

## The court's council column (record, order box, suggestions) is
## hidden until the player enters it (user ruling 2026-09-09).
func test_council_column_opens_from_the_handle_and_leaves() -> void:
	Game.start_campaign(42)
	var report := _report_after_resolving_pending_event()
	var screen := _screen()
	screen.enter_court(report)
	await wait_process_frames(2)
	var side: Control = screen.find_child("SidePanel", true, false)
	assert_false(side.visible, "hidden by default")
	assert_true(screen.council_handle().visible)
	var wide: float = screen.find_child("MapPanel", true, false).get_global_rect().end.x
	screen.council_handle().pressed.emit()
	await wait_process_frames(2)
	assert_true(side.visible, "the handle opens it")
	assert_true(side.is_ancestor_of(screen.free_text), "the order box lives in it")
	assert_lt(screen.find_child("MapPanel", true, false).get_global_rect().end.x, wide)
	screen.find_child("LeaveButton", true, false).pressed.emit()
	await wait_process_frames(2)
	assert_false(side.visible, "LEAVE hides it")
	assert_almost_eq(screen.find_child("MapPanel", true, false).get_global_rect().end.x, wide, 1.0)
