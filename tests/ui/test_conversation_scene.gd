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
