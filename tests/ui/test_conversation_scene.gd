extends GutTest

var _finished := false

func _scene_with(beats: Array, report: TickReport) -> ConversationScene:
	var c: ConversationScene = load("res://scenes/screens/conversation.tscn").instantiate()
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
	await wait_process_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "char_marshal")
	# R4: ONE portrait - char_marshal has full-body art, so the stage shows a
	# single FullArt TextureRect instead of the pixel-chip CharacterPortrait.
	assert_not_null(c.find_child("FullArt", true, false))
	# Scoped to the dossier stage: the location panel's occupant chips
	# (2026-08-30) are CharacterPortraits by design and don't count.
	assert_eq(c.find_child("PortraitBox", true, false).find_children("*", "CharacterPortrait", true, false).size(), 0)
	assert_string_contains(c.said_text(), "levies")
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
	assert_eq(String(c.current_beat()["portrait_id"]), "round_table")
	# round_table shows the council medallion art (user-provided, replaces
	# the old pixel chip) - still exactly ONE portrait, no chip.
	assert_not_null(c.find_child("FullArt", true, false))
	# Scoped to the dossier stage: the location panel's occupant chips
	# (2026-08-30) are CharacterPortraits by design and don't count.
	assert_eq(c.find_child("PortraitBox", true, false).find_children("*", "CharacterPortrait", true, false).size(), 0)
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
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
	await wait_process_frames(2)
	assert_gt(c.reply_buttons().size(), 0)
	var army0: float = Game.state.metrics["army_quality"]
	c.reply_buttons()[0].pressed.emit()
	await wait_process_frames(2)
	assert_gt(Game.state.metrics["army_quality"], army0)
	assert_string_contains(c.said_text(), "drill")  # outcome prose, not numbers

func test_event_beat_gates_continue_until_choice() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var beats := [{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}]
	var c := _scene_with(beats, report)
	await wait_process_frames(3)
	assert_false(c.continue_button().visible)
	assert_gt(c.reply_buttons().size(), 1)  # event choices render as replies
	c.reply_buttons()[0].pressed.emit()
	await wait_process_frames(3)
	assert_true(Game.state.pending_event.is_empty())
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
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
	await wait_process_frames(2)
	var box: Control = c.find_child("RepliesBox", true, false)
	assert_true(box.visible, "no selection: the minister's options stand")
	c.find_child("Occupant_char_steward", true, false).pressed.emit()
	await wait_process_frames(1)
	assert_false(box.visible,
		"talking to the steward: the marshal's options step aside")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_process_frames(1)
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
	await wait_process_frames(2)
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
	await wait_process_frames(2)
	c._say("You", "how stand the borders?")
	c._say("Ser Brandt of Harrow", "The border holds.")
	assert_string_contains(c.said_text(), "ledgers")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_process_frames(1)
	assert_string_contains(c.said_text(), "The border holds.")
	assert_string_contains(c.said_text(), "how stand the borders?")
	assert_false("ledgers" in c.said_text(),
		"only the selected person's exchange with you is shown")
	c._say("Herald", "It is done, my lord.")
	assert_string_contains(c.said_text(), "It is done, my lord.",
		"the Herald's outcome narration is never swallowed by the filter")
	c.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_process_frames(1)
	assert_string_contains(c.said_text(), "ledgers",
		"deselecting widens the box back to the whole room")

## User request 2026-08-31 (change 5): the SKILLS tab lists the tools this
## courtier can be called on to use, human-readable, kingdom operations in
## gold and personal tools in teal.
func test_skills_tab_lists_tools_with_kind_colors() -> void:
	Game.start_campaign(42)
	var beats := [{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "My lord.", "suggestions": []}]
	var c := _scene_with(beats, TickReport.new())
	await wait_process_frames(2)
	var tools: VBoxContainer = c.find_child("ToolsList", true, false)
	assert_gt(tools.get_child_count(), 0, "a minister's dossier lists tools")
	var kingdom_color := Color.TRANSPARENT
	var personal_color := Color.TRANSPARENT
	for row in tools.get_children():
		if row.text == "Train the standing army":
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
	await wait_process_frames(2)
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
	assert_gt(wide, c.size.x - ScreenLayout.margin() - 4.0, "the map runs to the right edge")
	c.council_handle().pressed.emit()
	await wait_process_frames(2)
	assert_true(c.council_open())
	assert_true(c.dialogue_panel().visible, "the handle opens the council column")
	assert_false(c.council_handle().visible, "and the handle steps aside")
	assert_lt(c.map_panel().get_global_rect().end.x, wide, "the map gives it room")
	assert_lt(c.map_panel().get_global_rect().end.x,
		c.dialogue_panel().get_global_rect().position.x + 1.0, "and never runs under it")
	# Owner ruling 2026-09-10: the fact card belongs to the LEFT column, so a
	# map click never displaces the council on the right.
	var capital: Dictionary = Game.data.burgs[String(
		Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])]
	# What the map sends for a click on the town (a headless run does not load
	# the 3D world, so the view's signal stands in for the click).
	c.map3d_view().object_selected.emit({"title": String(capital["label"]),
		"obj": {"kind": "burg", "code": String(capital["burg_code"])}})
	await wait_process_frames(2)
	assert_true(c.detail_panel().visible, "a map click opens the card")
	assert_true(c.dialogue_panel().visible, "and the council stays where it is")
	assert_lt(c.detail_panel().get_global_rect().position.x,
		c.map_panel().get_global_rect().position.x, "the card is in the left column")
	assert_false(c.dashboard().visible, "which the card takes from the dashboard")
	c.detail_panel().close_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(c.detail_panel().visible, "CLOSE closes the card")
	assert_true(c.dashboard().visible, "and the left column goes back to the realm")
	assert_true(c.dialogue_panel().visible, "the council never moved")
	c.find_child("LeaveButton", true, false).pressed.emit()
	await wait_process_frames(2)
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
	await wait_process_frames(3)
	assert_almost_eq(c.dialogue_panel().size.y, small.dialogue_panel().size.y, 1.0,
		"event content must not grow the box")
	var scroll := c.dialogue_scroll()
	assert_not_null(scroll,
		"dialogue lives in a ScrollContainer: overflow scrolls, never grows")
	# (the portrait box's art is test_one_portrait_per_beat_and_continue_advances')

## User ruling (2026-08-29, UI_example chrome): the TopBar metrics strip
## spans the top of every gameplay screen, the conversation stage included,
## the dossier card shows the speaker's identity, and both reflect an order
## taken here (dossier via the trait/opinion fields, TopBar via
## Game.state_changed).
## The name plate wears the speaker's house arms (owner 2026-09-15); a
## person whose family holds no seat shows none.
func test_the_name_plate_wears_the_speakers_house_arms() -> void:
	Game.start_campaign(42)
	var beats := [{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt of Harrow",
		"text": "The levies grow soft.", "suggestions": []}]
	var c := _scene_with(beats, TickReport.new())
	await wait_process_frames(2)
	var arms: HeraldicShield = c.find_child("PlateArms", true, false)
	var family: String = Game.state.characters["char_marshal"].family_name
	assert_true(arms.visible)
	assert_not_null(arms.texture)
	assert_same(arms.texture, HouseArms.texture_of_house(Game.data, Game.state, family))
	assert_eq(c.find_child("MinisterName", true, false).get_parent(), arms.get_parent(), "beside the name")
	var seatless := ""
	for id: String in Game.state.characters:
		if HouseArms.key_of_house(Game.data, Game.state, Game.state.characters[id].family_name) == "":
			seatless = id
			break
	assert_ne(seatless, "", "some character's family holds no province")
	c._show_speaker({"portrait_id": seatless, "speaker": "x"})
	assert_false(arms.visible, "no seat, no arms")

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
	await wait_process_frames(2)
	assert_lt(c.top_bar().global_position.y, 5.0, "TopBar hugs the top edge")
	var name_label: Label = c.find_child("MinisterName", true, false)
	assert_eq(name_label.text, Game.state.characters["char_marshal"].display_name,
		"the dossier names the speaking minister")
	var title_label: Label = c.find_child("MinisterTitle", true, false)
	assert_eq(title_label.text, String(Game.data.seats["marshal"]["label"]),
		"the dossier shows the seat title, in its own case under the name (2026-09-28)")
	assert_gt(c.find_child("TraitChips", true, false).get_child_count(), 0,
		"the dossier shows the minister's trait chips")
	c.select_tab(1)
	await wait_process_frames(1)
	var rows: VBoxContainer = c.find_child("SkillRows", true, false)
	assert_true(rows.visible, "a minister's dossier shows the skill bars on its SKILLS page")
	assert_eq(rows.get_child_count(), CharacterFactory.SKILLS.size(),
		"one colored bar per council skill, mock-style")
	var gold_before := c.top_bar().metric_text("treasury")
	c.reply_buttons()[0].pressed.emit()
	await wait_process_frames(2)
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
	await wait_process_frames(2)
	c.reply_buttons()[0].pressed.emit()
	await wait_process_frames(2)
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
	assert_string_contains(c.said_text(), "Train the standing army")
	assert_false("Nothing was ordered" in c.said_text(),
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
	await wait_process_frames(2)
	c.reply_buttons()[0].pressed.emit()
	await wait_process_frames(2)
	assert_string_contains(c.said_text(), "a promise kept")

## Same Ask hook on the conversation stage: the card's question lands in the
## talk box for the player to send or edit.
## The conversation stage's left column is the minister dossier; a hovered
## country borrows it and gives it straight back.
func test_hovering_a_country_borrows_the_minister_column() -> void:
	Game.start_campaign(42)
	var c := _scene_with([{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}], TickReport.new())
	await wait_process_frames(1)
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
	await wait_process_frames(2)
	var capital: Dictionary = Game.data.burgs[String(
		Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])]
	# What the map sends for a click on the town (a headless run does not load
	# the 3D world, so the view's signal stands in for the click).
	c.map3d_view().object_selected.emit({"title": String(capital["label"]),
		"obj": {"kind": "burg", "code": String(capital["burg_code"])}})
	await wait_process_frames(1)
	assert_true(c.detail_panel().ask_button().visible, "the stage owns a talk box, so Ask shows")
	c.detail_panel().ask_button().pressed.emit()
	await wait_process_frames(1)
	assert_true(c.council_open(), "Ask brings the council up to send from")
	assert_eq(c.free_text_field().text, "What do we know of %s?" % String(capital["label"]))
	assert_false(c.dialogue_text().contains("What do we know"), "nothing was sent")
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
	await wait_process_frames(2)
	assert_true(c.dashboard().visible, "the council beat shows the realm")
	assert_false(c.dossier_up())
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
	assert_true(c.dossier_up(), "a minister speaking brings the dossier")
	# Owner ruling 2026-09-10: the dossier is a person, so it stands in the
	# RIGHT column over their words; the left column keeps the realm.
	assert_true(c.dashboard().visible, "and the left column still holds the realm")
	assert_false(c.tab_page(0).visible, "its pages rest closed over the talk")
	var head: Control = c.find_child("DossierHead", true, false)
	assert_true(head.visible, "the head is up")
	assert_gt(head.get_global_rect().position.x,
		c.map_panel().get_global_rect().position.x,
		"on the right of the map, not the left")

## Owner ruling 2026-09-15 (replacing 2026-09-10's dossier over the talk in
## the right column): the person stands in the CK3 audience window with their
## words, and a page takes the speech's space only while it is open — the
## options and the talk box are never pushed out of the window.
func test_the_dossier_stands_in_the_audience_window() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "hm", "suggestions": []}], report)
	c.enter_council()
	await wait_process_frames(2)
	var head: Control = c.find_child("DossierHead", true, false)
	var pages: Control = c.find_child("DossierPages", true, false)
	var win := c.audience_window()
	assert_true(head.visible, "a person on stage brings the head up")
	assert_true(win.get_global_rect().encloses(head.get_global_rect()),
		"inside the audience window, with their words")
	assert_false(c.dialogue_panel().get_global_rect().intersects(head.get_global_rect()),
		"and no longer in the council column")
	assert_false(pages.visible, "the pages rest closed")
	assert_true(c.speech_scroll().visible, "so the speech has the room")
	# A page takes the speech's space, and hands it back.
	c.select_tab(1)
	await wait_process_frames(2)
	assert_true(pages.visible, "SKILLS opens")
	assert_false(c.speech_scroll().visible, "the speech stands aside for it")
	assert_true(head.visible, "the head stays: you still see who you are dealing with")
	c.select_tab(1)
	await wait_process_frames(2)
	assert_false(pages.visible, "the same tab closes it")
	assert_true(c.speech_scroll().visible, "and the speech is back")
	# The window still fits what it holds, with the council column open.
	assert_lte(win.get_combined_minimum_size().y, c.map_panel().size.y + 1.0,
		"the window fits the map it stands over")

## Owner 2026-09-15 (CK3): the audience window stands centred over the map
## while a person holds the stage, their portrait and their words inside it.
func test_the_audience_window_stands_over_the_map() -> void:
	Game.start_campaign(42)
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "The levies grow soft.", "suggestions": []}],
		TickReport.new())
	await wait_process_frames(3)
	var win := c.audience_window()
	assert_true(win.is_visible_in_tree(), "a person on stage opens the audience")
	assert_true(c.map_panel().get_global_rect().grow(1.0).encloses(win.get_global_rect()),
		"centred over the map, inside it")
	assert_true(win.get_global_rect().encloses(
		c.find_child("PortraitBox", true, false).get_global_rect()), "the portrait is in it")
	assert_string_contains(c.speech_text(), "levies", "and so are their words")
	c.enter_council()
	await wait_process_frames(3)
	assert_true(c.map_panel().get_global_rect().grow(1.0).encloses(win.get_global_rect()),
		"a narrower map keeps the window inside it")

## The window shows this beat's exchange; the record keeps every beat.
func test_the_speech_is_this_beat_and_the_record_is_all() -> void:
	Game.start_campaign(42)
	var c := _scene_with([
		{"kind": "minister", "portrait_id": "char_marshal", "speaker": "Ser Brandt",
			"text": "The levies grow soft.", "suggestions": []},
		{"kind": "minister", "portrait_id": "char_chancellor", "speaker": "Aldwin Reeve",
			"text": "The ledgers weigh heavy.", "suggestions": []},
	], TickReport.new())
	await wait_process_frames(2)
	c.continue_button().pressed.emit()
	await wait_process_frames(2)
	assert_string_contains(c.speech_text(), "ledgers")
	assert_false("levies" in c.speech_text(), "the last beat's words left the window")
	assert_string_contains(c.dialogue_text(), "levies", "but stay in the record")

## Invariant 4 where CK3 puts it: hover the opinion and read why.
func test_opinion_tooltip_gives_the_reasons() -> void:
	Game.start_campaign(42)
	var m: Character = Game.state.characters["char_marshal"]
	m.opinion_log.append({"delta": -8, "reason": "revoked the noble tax exemption"})
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": m.display_name, "text": "hm", "suggestions": []}], TickReport.new())
	await wait_process_frames(2)
	var value: Label = c.find_child("OpinionValue", true, false)
	assert_string_contains(value.tooltip_text, "revoked the noble tax exemption")
	assert_string_contains(value.tooltip_text, "-8")
	var badges: Control = c.find_child("SkillBadges", true, false)
	assert_eq(badges.get_child_count(), CharacterFactory.SKILLS.size(),
		"CK3's row of skills under the portrait")

## CK3's events and interactions share a frame: an event opens the same
## window, its choices are the window's options.
func test_an_event_uses_the_same_window() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	var c := _scene_with([{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": Game.state.pending_event.duplicate(true)}],
		TickReport.new())
	await wait_process_frames(3)
	assert_eq(c.event_popup(), c.audience_window())
	assert_true(c.audience_window().is_visible_in_tree())
	assert_ne((c.find_child("AudienceTitle", true, false) as Label).text, "",
		"the event's title stands in the banner")
	assert_gt(c.reply_buttons().size(), 0)
	for b in c.reply_buttons():
		assert_true(c.audience_window().is_ancestor_of(b), "choices are options in the window")

## An option says what it trades before it is taken.
func test_an_option_tells_its_tradeoff() -> void:
	Game.start_campaign(42)
	var sug := {"seat": "marshal", "request": ActionRequest.make("LEVY_RAISE"),
		"pitch_key": "raise_levies", "tradeoff": "Gold and grumbling."}
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "Fresh levies?", "suggestions": [sug]}], TickReport.new())
	await wait_process_frames(2)
	assert_string_contains(c.reply_buttons()[0].tooltip_text, "Gold and grumbling.")

## A decree's option quotes what the decree really costs: the order, the
## law's own gold and one fee a courier (LawSystem.preview), not the order
## row's single gold piece.
func test_a_law_option_quotes_the_whole_decree() -> void:
	Game.start_campaign(42)
	var now := int(LawSystem.decreed(Game.data, Game.state, "justice_severity"))
	var req := ActionRequest.make("LAW_SET", {"law": "justice_severity", "value": str(now + 1)})
	var pv := LawSystem.preview(Game.data, Game.state, "justice_severity", str(now + 1))
	assert_gt(int(pv["fee"]), 0, "couriers ride with a decree")
	var sug := {"seat": "chancellor", "request": req,
		"pitch_key": "harsh_justice", "tradeoff": "Order through fear."}
	var c := _scene_with([{"kind": "minister", "portrait_id": "char_chancellor",
		"speaker": "The Chancellor", "text": "The courts?", "suggestions": [sug]}], TickReport.new())
	await wait_process_frames(2)
	assert_string_contains(c.reply_buttons()[0].tooltip_text,
		"Costs %d gold" % (int(pv["gold"]) + int(pv["fee"])))

## A narration or council beat has no person, so no dossier — the talk takes
## the whole right column.
func test_no_dossier_without_a_person() -> void:
	Game.start_campaign(42)
	var c := _scene_with([{"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council"}], Game.next_tick())
	c.enter_council()
	await wait_process_frames(2)
	assert_false(c.find_child("DossierHead", true, false).visible)
	assert_false(c.find_child("TabsRow", true, false).visible)
	assert_true(c.dialogue_scroll().visible)
