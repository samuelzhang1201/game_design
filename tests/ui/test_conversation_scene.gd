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
	# Scoped to the dossier stage: the location panel's occupant chips
	# (2026-08-30) are CharacterPortraits by design and don't count.
	assert_eq(c.find_child("PortraitBox", true, false).find_children("*", "CharacterPortrait", true, false).size(), 0)
	assert_string_contains(c.dialogue_text(), "levies")
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "round_table")
	# round_table shows the council medallion art (user-provided, replaces
	# the old pixel chip) - still exactly ONE portrait, no chip.
	assert_not_null(c.find_child("FullArt", true, false))
	# Scoped to the dossier stage: the location panel's occupant chips
	# (2026-08-30) are CharacterPortraits by design and don't count.
	assert_eq(c.find_child("PortraitBox", true, false).find_children("*", "CharacterPortrait", true, false).size(), 0)
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

## User request 2026-08-31 (change 1): a beat's default reply options belong
## to the minister who raised them — selecting people who do NOT include that
## minister hides the options; adding them back restores them.
func test_selection_gates_the_beats_reply_options() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling.",
		"source": "concern"}
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "Fresh levies, my lord?",
		"suggestions": [sug]}]
	var c := _scene_with(beats, report)
	await wait_frames(2)
	var box: Control = c.find_child("RepliesBox", true, false)
	assert_true(box.visible, "no selection: the minister's options stand")
	c.find_child("Occupant_char_steward", true, false).pressed.emit()
	await wait_frames(1)
	assert_false(box.visible,
		"talking to the steward: the marshal's options step aside")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_frames(1)
	assert_true(box.visible, "the marshal joins the selection: options return")

## User request 2026-08-31 ("the prompt input box disappeared"): a quiet
## tick opens straight on the summary beat (standing suggestions no longer
## manufacture minister beats), and the box must still be there to talk to
## whoever is in the room.
func test_prompt_box_available_on_summary_beat() -> void:
	Game.start_campaign(42)
	var beats := [{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}]
	var c := _scene_with(beats, TickReport.new())
	await wait_frames(2)
	assert_true(c.free_text_field().visible,
		"the prompt box stays on the summary beat")

## User request 2026-08-31 (change 2): with a person singled out, the box
## shows only the conversation between them and the player.
func test_transcript_narrows_to_the_selected_person() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var beats := [{"kind": "minister", "portrait_id": "char_chancellor",
		"speaker": "Aldwin Reeve", "text": "The ledgers weigh heavy, my lord.",
		"suggestions": []}]
	var c := _scene_with(beats, report)
	await wait_frames(2)
	c._say("You", "how stand the borders?")
	c._say("Ser Brandt of Harrow", "The border holds.")
	assert_string_contains(c.dialogue_text(), "ledgers")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_frames(1)
	assert_string_contains(c.dialogue_text(), "The border holds.")
	assert_string_contains(c.dialogue_text(), "how stand the borders?")
	assert_false("ledgers" in c.dialogue_text(),
		"only the selected person's exchange with you is shown")
	c._say("Herald", "It is done, my lord.")
	assert_string_contains(c.dialogue_text(), "It is done, my lord.",
		"the Herald's outcome narration is never swallowed by the filter")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_frames(1)
	assert_string_contains(c.dialogue_text(), "ledgers",
		"deselecting widens the box back to the whole room")

## User request 2026-08-31 (change 5): the SKILLS tab lists the tools this
## courtier can be called on to use, human-readable, kingdom operations in
## gold and personal tools in teal.
func test_skills_tab_lists_tools_with_kind_colors() -> void:
	Game.start_campaign(42)
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "My lord.", "suggestions": []}]
	var c := _scene_with(beats, TickReport.new())
	await wait_frames(2)
	var tools: VBoxContainer = c.find_child("ToolsList", true, false)
	assert_gt(tools.get_child_count(), 0, "a minister's dossier lists tools")
	var kingdom_color := Color.TRANSPARENT
	var personal_color := Color.TRANSPARENT
	for row in tools.get_children():
		if row.text == "Raise fresh levies":
			kingdom_color = row.get_theme_color("font_color")
		if row.text == "Confide in a courtier":
			personal_color = row.get_theme_color("font_color")
		assert_false("_" in row.text, "labels are human-readable, never codes")
	assert_eq(kingdom_color, UiPalette.TOOL_KINGDOM,
		"the seat's kingdom operation shows in the kingdom color")
	assert_eq(personal_color, UiPalette.TOOL_PERSONAL,
		"the personal tool shows in the personal color")
	assert_ne(UiPalette.TOOL_KINGDOM, UiPalette.TOOL_PERSONAL,
		"the two kinds are visually distinct")

## Layout (user rulings 2026-09-09, ScreenLayout): the dossier/dashboard
## column on the left, the map in the middle running to the right edge, and
## nothing on the right until the player enters the council (the handle) or
## clicks a map element (the detail column); the two share the slot.
func test_right_slot_is_empty_until_the_council_or_a_map_click_takes_it() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var c := _scene_with([{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}], report)
	await wait_frames(2)
	var left := c.minister_panel().get_global_rect()
	var map_rect := c.map_panel().get_global_rect()
	var top := c.top_bar().get_global_rect().end.y
	assert_gte(left.position.y, top, "the left column starts under the top bar, never over it")
	assert_gte(map_rect.position.y, top, "so does the map")
	assert_lt(map_rect.position.x - left.end.x, 16.0, "the map starts where the left column ends")
	assert_false(c.dialogue_panel().visible, "the council column is hidden by default")
	assert_false(c.detail_panel().visible, "nothing selected: no detail column")
	assert_true(c.council_handle().visible, "the ENTER THE COUNCIL handle shows on the right")
	var wide := map_rect.end.x
	assert_gt(wide, c.size.x - 12.0, "the map runs to the right edge")
	c.council_handle().pressed.emit()
	await wait_frames(2)
	assert_true(c.council_open())
	assert_true(c.dialogue_panel().visible, "the handle opens the council column")
	assert_false(c.council_handle().visible, "and the handle steps aside")
	assert_lt(c.map_panel().get_global_rect().end.x, wide, "the map gives it room")
	assert_lt(c.map_panel().get_global_rect().end.x,
		c.dialogue_panel().get_global_rect().position.x + 1.0, "and never runs under it")
	var capital: Dictionary = Game.data.burgs[String(
		Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])]
	c.world_map().select_object({"kind": "burg", "code": String(capital["burg_code"])})
	await wait_frames(2)
	assert_true(c.detail_panel().visible, "a map click takes the slot for the detail column")
	assert_false(c.dialogue_panel().visible, "the council steps behind it")
	c.detail_panel().close_button().pressed.emit()
	await wait_frames(2)
	assert_false(c.detail_panel().visible, "CLOSE hides the detail column")
	assert_true(c.dialogue_panel().visible, "and the council comes back")
	c.find_child("LeaveButton", true, false).pressed.emit()
	await wait_frames(2)
	assert_false(c.dialogue_panel().visible, "LEAVE hides the council")
	assert_true(c.council_handle().visible)
	assert_almost_eq(c.map_panel().get_global_rect().end.x, wide, 1.0, "and the map widens again")

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
	assert_not_null(scroll,
		"dialogue lives in a ScrollContainer: overflow scrolls, never grows")
	# The council beat shows the round-table medallion art (user-provided,
	# replaces the old pixel chip) in the dossier's portrait box.
	assert_not_null(c.find_child("FullArt", true, false),
		"the council medallion fills the dossier portrait box")
	# Scoped to the dossier stage: the location panel's occupant chips
	# (2026-08-30) are CharacterPortraits by design and don't count.
	assert_eq(c.find_child("PortraitBox", true, false).find_children("*", "CharacterPortrait", true, false).size(), 0)

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
	var rows: VBoxContainer = c.find_child("SkillRows", true, false)
	assert_true(rows.visible, "a minister's dossier shows the skill bars")
	assert_eq(rows.get_child_count(), CharacterFactory.SKILLS.size(),
		"one colored bar per council skill, mock-style")
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

## The author's own scene reaches the stage, and no model is consulted to get
## it there (user ruling 2026-08-31). This replaces the former
## test_event_beat_voices_canned_text_non_degraded, which proved the opposite
## guarantee — that the LLM's rewrite surfaced — a behaviour deliberately
## removed. A canned reply is armed here precisely so that its ABSENCE from
## the transcript is meaningful: if any model path survived, this fails.
func test_event_beat_shows_authored_scene_without_calling_the_model() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "A rider brings word of omens."
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_02", Game.state)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	assert_string_contains(c.dialogue_text(), "fur-lined cloak",
		"the scene is the prose written in RANDOM_EVENTS.md")
	assert_false(c.dialogue_text().contains("A rider brings word of omens."),
		"the model's words must never appear in an event scene")
	assert_eq(fake.calls, 0, "an event scene costs no API call at all")

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
	assert_true(c.free_text_field().visible,
		"free text stays after resolution — the player can keep talking (user request 2026-08-31)")
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

## Same Ask hook on the conversation stage: the card's question lands in the
## talk box for the player to send or edit.
## The conversation stage's left column is the minister dossier; a hovered
## country borrows it and gives it straight back.
func test_hovering_a_country_borrows_the_minister_column() -> void:
	Game.start_campaign(42)
	var c := _scene_with([{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}], TickReport.new())
	await wait_frames(1)
	var panel := c.country_panel()
	assert_not_null(panel, "the stage owns a country panel")
	assert_false(panel.visible)
	var mine := Game.data.resolve_realm("player_realm")
	panel.show_country(mine)
	assert_true(panel.visible, "the country card takes the column")
	assert_eq(panel.shown_country(), mine)
	panel.show_country("")
	assert_false(panel.visible, "and hands it back")

## The detail column's Ask pre-fills the talk box, brings the council up so
## it can be sent, and never sends by itself.
func test_map_ask_fills_the_talk_box() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var c := _scene_with([{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}], report)
	await wait_frames(2)
	var capital: Dictionary = Game.data.burgs[String(
		Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])]
	c.world_map().select_object({"kind": "burg", "code": String(capital["burg_code"])})
	await wait_frames(1)
	assert_true(c.detail_panel().ask_button().visible, "the stage owns a talk box, so Ask shows")
	c.detail_panel().ask_button().pressed.emit()
	await wait_frames(1)
	assert_true(c.council_open(), "Ask brings the council up to send from")
	assert_eq(c.free_text_field().text, "What do we know of %s?" % String(capital["label"]))
	assert_false(c.dialogue_text().contains("What do we know"), "nothing was sent")
## The two-part order on the conversation stage (spec 2026-09-09 §4): the
## narrative under the speaker's name, then the ledger lines.
func test_free_text_prints_narrative_then_ledger_on_the_stage() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "Coin for the whisperers, then.",
		"impacts": {"actions": [{"action_code": "SPY_MISSION", "params": {}, "target": ""}],
		"world": [], "court_reaction": {}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var beats := [{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council",
		"text": "The court waits."}]
	var c := _scene_with(beats, report)
	await wait_frames(3)
	var gold: float = Game.state.metrics["treasury"]
	c.free_text_field().text_submitted.emit("send out the whisperers")
	await wait_frames(3)
	assert_lt(Game.state.metrics["treasury"], gold, "the mission was paid for")
	assert_string_contains(c.dialogue_text(), "Coin for the whisperers, then.")
	assert_string_contains(c.dialogue_text(), "treasury -")

## The left column shows the realm dashboard by default and the dossier only
## while a person speaks or is singled out (user ruling 2026-09-09).
func test_left_column_is_the_dashboard_unless_a_person_speaks() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var c := _scene_with([
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"},
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt",
			"text": "hm", "suggestions": []},
	], report)
	await wait_frames(2)
	assert_true(c.dashboard().visible, "the council beat shows the realm")
	assert_false(c.dossier_up())
	c.continue_button().pressed.emit()
	await wait_frames(2)
	assert_true(c.dossier_up(), "a minister speaking brings the dossier")
	assert_false(c.dashboard().visible)
	assert_true(c.tab_page(0).visible, "on its BIO tab")
