extends GutTest

var _finished := false

func _scene_with(beats: Array, report: TickReport) -> ConversationScene:
	var c: ConversationScene = load("res://scenes/conversation.tscn").instantiate()
	add_child_autofree(c)
	_finished = false
	c.finished.connect(func(): _finished = true)
	c.start(beats, report)
	return c

func test_one_portrait_per_beat_and_continue_advances() -> void:
	Game.start_campaign(42)
	var beats := [
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt of Harrow",
			"text": "The levies grow soft.", "suggestions": []},
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"},
	]
	var c := _scene_with(beats, TickReport.new())
	await wait_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "char_marshal")
	# R4: ONE portrait - char_marshal has full-body art, so the stage shows a
	# single FullArt TextureRect instead of the pixel-chip CharacterPortrait.
	assert_not_null(c.find_child("FullArt", true, false))
	assert_eq(c.find_children("*", "CharacterPortrait", true, false).size(), 0)
	assert_string_contains(c.dialogue_text(), "levies")
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "round_table")
	# round_table has no full-body art: falls back to ONE pixel-chip portrait.
	assert_null(c.find_child("FullArt", true, false))
	assert_eq(c.find_children("*", "CharacterPortrait", true, false).size(), 1)
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_true(_finished)

func test_quick_reply_executes_suggestion_and_speaks_prose() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Fresh levies, my lord?",
		"suggestions": [sug]}]
	var c := _scene_with(beats, report)
	await wait_frames(2)
	assert_gt(c.reply_buttons().size(), 0)
	var army0: float = Game.state.metrics["army_quality"]
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_gt(Game.state.metrics["army_quality"], army0)
	assert_string_contains(c.dialogue_text(), "muster")  # outcome prose, not numbers

func test_event_beat_gates_continue_until_choice() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	assert_false(c.continue_button().visible)
	assert_gt(c.reply_buttons().size(), 1)  # event choices render as replies
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(3)
	assert_true(Game.state.pending_event.is_empty())
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_true(_finished)

## User ruling (2026-08-29): the dialogue box is a fixed-height strip pinned
## to the bottom of the view. Long content scrolls inside it instead of
## growing the box over the minister dossier card, which stays fully visible
## (UI_example chrome: card left, dialogue bottom-right of it).
func test_dialogue_box_fixed_bottom_strip_clear_of_dossier() -> void:
	Game.start_campaign(42)
	var beats := [
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt of Harrow",
			"text": "The levies grow soft.", "suggestions": []},
	]
	var c := _scene_with(beats, TickReport.new())
	await wait_frames(3)
	var panel := c.dialogue_panel()
	assert_lt(c.size.y - (panel.global_position.y + panel.size.y), 16.0,
		"the box hugs the bottom edge")
	assert_not_null(c.find_child("FullArt", true, false),
		"the marshal's full-body art fills the dossier portrait box")
	assert_false(c.minister_panel().get_global_rect().intersects(panel.get_global_rect()),
		"the dialogue box must never cover the dossier card")

## Same ruling, worst case: a long event text plus three choice buttons must
## scroll inside the fixed box rather than grow it over the portrait.
func test_long_event_content_scrolls_inside_fixed_box() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	# A second stage showing only a one-line minister beat: the box height
	# must be content-independent, so both must measure identical.
	var small := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Aye.", "suggestions": []}],
		TickReport.new())
	await wait_frames(3)
	assert_almost_eq(c.dialogue_panel().size.y, small.dialogue_panel().size.y, 1.0,
		"event content must not grow the box")
	var scroll := c.dialogue_scroll()
	assert_not_null(scroll, "dialogue content lives in a ScrollContainer")
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y,
		"the overflowing event content is reachable by scrolling")
	# Non-character beats (the round table) fall back to ONE chip portrait
	# inside the dossier card's portrait box.
	assert_eq(c.find_children("*", "CharacterPortrait", true, false).size(), 1)

## User ruling (2026-08-29, UI_example chrome): the TopBar metrics strip
## spans the top of every gameplay screen, the conversation stage included,
## the dossier card shows the speaker's identity, and both reflect an order
## taken here (dossier via the trait/opinion fields, TopBar via
## Game.state_changed).
func test_top_bar_and_dossier_reflect_speaker_and_order() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Fresh levies, my lord?",
		"suggestions": [sug]}]
	var c := _scene_with(beats, report)
	await wait_frames(2)
	assert_lt(c.top_bar().global_position.y, 5.0, "TopBar hugs the top edge")
	var name_label: Label = c.find_child("MinisterName", true, false)
	assert_eq(name_label.text, Game.state.characters["char_marshal"].display_name,
		"the dossier names the speaking minister")
	var title_label: Label = c.find_child("MinisterTitle", true, false)
	assert_eq(title_label.text, "MARSHAL", "the dossier shows the seat title")
	assert_gt(c.find_child("TraitChips", true, false).get_child_count(), 0,
		"the dossier shows the minister's trait chips")
	var gold_before := c.top_bar().metric_text("treasury")
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_ne(c.top_bar().metric_text("treasury"), gold_before,
		"the TopBar's Gold value must refresh after the order executes")

## FIX 2 (post-Task-5 review): a quick-reply taken earlier in THIS
## conversation must show up in the summary as "resolved this session"
## (council_summary_now), not be silently missed with the idle line - the
## old build-time-baked summary text would have said "No orders were given"
## right after the player just gave one.
func test_summary_shows_this_session_resolution_after_quick_reply() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var beats := [
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt of Harrow",
			"text": "Fresh levies, my lord?", "suggestions": [sug]},
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"},
	]
	var c := _scene_with(beats, report)
	await wait_frames(2)
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(2)
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_string_contains(c.dialogue_text(), "Raise fresh levies")
	assert_false("Nothing was ordered" in c.dialogue_text(),
		"a same-session decision must not be summarized as idle")

## "Also" item (post-Task-5 review): a quick-reply that fulfills an open
## promise carries a "promise" pseudo-effect (ActionSystem.execute) whose
## reason string ("a promise kept: ...") must reach the spoken dialogue, the
## same narration parity the old council screen already had via _narrate_effects.
func test_quick_reply_narrates_kept_promise_effect() -> void:
	Game.start_campaign(42)
	Game.state.promises.append({"character_id": "char_marshal", "promise_code": "LEVY_RAISE",
		"made_tick": 0, "tick_due": 999, "status": "open"})
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Fresh levies, my lord?",
		"suggestions": [sug]}]
	var c := _scene_with(beats, TickReport.new())
	await wait_frames(2)
	c.reply_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_string_contains(c.dialogue_text(), "a promise kept")

## Migrates the real gap in the deleted council-screen test
## test_event_voicing_reaches_client_not_starved_by_briefing: proves the
## conversation stage's event beat surfaces the LLM's canned text verbatim
## (non-degraded), not the template fallback, when the voicer is free to
## call the client. ev_02 is voice=mini (see data/events.csv), so
## Voicer.voice_event actually calls the client rather than short-circuiting
## to the template tier - this is the successful non-degraded path, not the
## busy/fallback path already covered elsewhere.
func test_event_beat_voices_canned_text_non_degraded() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "A rider brings word of omens."
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_02", Game.state)  # mini-voice event: the client IS called
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	assert_eq(c.dialogue_text(), "A rider brings word of omens.",
		"the canned text must surface verbatim, not degrade to the template fallback")

## F1 (final-review fix wave): Game.submit_free_text's EVENT_CHOICE branch was
## unreachable in real play because the free-text box was hidden on event
## beats. Proves the box is shown while the event is unresolved, and that a
## free-text reply parsing to EVENT_CHOICE for a real choice of the pending
## event resolves it exactly as clicking the matching choice button does:
## outcome line shown, buttons cleared, advance enabled, pending_event clear.
func test_event_beat_free_text_resolves_via_event_choice() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "accept"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	assert_true(c.free_text_field().visible,
		"free text must be reachable on an unresolved event beat")
	c.free_text_field().text_submitted.emit("I shall accept them with thanks")
	await wait_frames(3)
	assert_true(Game.state.pending_event.is_empty(), "event resolves via free text")
	assert_string_contains(c.dialogue_text(), "thanks")  # event_ev_01_accept template line
	assert_false(c.free_text_field().visible, "free text hides once the event resolves")
	assert_true(c.continue_button().visible, "advance re-enabled once resolved")
	assert_eq(c.reply_buttons().size(), 0, "choice buttons cleared once resolved")

## F1 "must NOT resolve" half of the ruling: a free-text reply during an event
## beat that parses to a rejected EVENT_CHOICE (no such choice awaits) leaves
## the event pending and the free-text box reachable - same shape as the
## existing minister-beat free-text behavior (result line shown, no state
## mutation beyond that).
func test_event_beat_free_text_invalid_choice_leaves_event_pending() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "not_a_real_choice"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	c.free_text_field().text_submitted.emit("do something not offered")
	await wait_frames(3)
	assert_false(Game.state.pending_event.is_empty(), "event still awaits a valid choice")
	assert_true(c.free_text_field().visible, "free text stays reachable while the event is pending")
	assert_false(c.continue_button().visible, "advance stays gated while the event is pending")

## F2 (final-review fix wave): choice buttons render while the event's voice
## call is still in flight. If the player resolves the event before that call
## returns, the late callback must not overwrite the outcome line already
## shown with stale scene-setting narration.
func test_event_voice_callback_ignored_after_event_resolved() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_02", Game.state)  # mini-voice: client call stays in flight
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "A rider brings word of omens."
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	# Resolve synchronously, before the FakeClient's deferred `completed` signal
	# (scheduled by voice_event_scene above) has a chance to fire.
	c.reply_buttons()[0].pressed.emit()
	var resolved_text := c.dialogue_text()
	assert_ne(resolved_text, "...", "the event must already show its outcome line")
	await wait_frames(3)  # let the stale voice callback fire
	assert_eq(c.dialogue_text(), resolved_text,
		"the stale voice callback must not overwrite the already-shown outcome")
	assert_false("omens" in c.dialogue_text())

## Re-review of the final fix wave: with both input paths live on an event
## beat, a choice button can resolve the event while a free-text parse is
## still in flight. The stale parse callback must not clobber the outcome
## line (it would otherwise fall through to "So noted." on the rejected
## re-apply), and must still restore the field for later beats.
func test_stale_free_text_callback_ignored_after_button_resolves_event() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)  # template-voiced: only the parse hits the client
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "accept"}, "target": ""}],
		"court_reaction": {}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	c.free_text_field().text_submitted.emit("I shall accept them with thanks")
	# The parse is now in flight (FakeClient replies deferred). Resolve via the
	# button first, synchronously.
	c.reply_buttons()[0].pressed.emit()
	var resolved_text := c.dialogue_text()
	await wait_frames(3)  # let the stale parse callback fire
	assert_eq(c.dialogue_text(), resolved_text,
		"the stale free-text parse callback must not overwrite the resolution line")
	assert_true(c.free_text_field().editable,
		"the field must be restored for later beats")
