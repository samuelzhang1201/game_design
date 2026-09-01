extends GutTest
## The 2026-08-30 UI change batch: menu buttons + character creation,
## opening narration popup, centered event popup, dossier tabs, bottom tab
## bar with info tables, colored transcript names, top-bar event chip out of
## the metrics row.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_main_menu_has_start_load_quit_and_setup_flow() -> void:
	var r := _root()
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	var col := menu.menu_column()
	assert_not_null(col.get_node("StartGame"))
	assert_not_null(col.get_node("LoadGame"))
	assert_not_null(col.get_node("Quit"))
	# Start Game opens character creation instead of starting directly.
	col.get_node("StartGame").pressed.emit()
	await wait_frames(1)
	assert_true(menu.setup_panel().visible)
	assert_false(col.visible)

func test_begin_reign_applies_chosen_identity() -> void:
	var r := _root()
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	menu.menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(1)
	var panel := menu.setup_panel()
	panel.find_child("FirstName", true, false).text = "Edmund"
	panel.find_child("FamilyName", true, false).text = "Blackwood"
	panel.find_child("BeginReign", true, false).pressed.emit()
	await wait_frames(2)
	assert_eq(Game.state.characters["you"].display_name, "King Edmund Blackwood")
	assert_eq(String(Game.state.player_setup.get("flag", "")), "sun")

func test_campaign_opens_with_nameless_background_narration() -> void:
	var r := _root()
	await wait_frames(2)
	Game.player_setup = {}
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	var scene: ConversationScene = r.current_screen
	assert_eq(String(scene.current_beat()["kind"]), "narration")
	assert_eq(String(scene.current_beat()["speaker"]), "", "narration is nameless")
	assert_true(scene.event_popup().visible, "narration pops centered")
	assert_string_contains(scene.dialogue_text(), "ascended to the throne")
	# Regression (user bug 2026-08-30): the full background text made the
	# centered popup taller than the 360px viewport, pushing the continue
	# button off screen with no way to scroll. The text now scrolls inside
	# a capped box, so the popup must fit and the button must be on screen.
	var panel: PanelContainer = scene.find_child("PopupPanel", true, false)
	var viewport_h := scene.get_viewport_rect().size.y
	assert_lt(panel.size.y, viewport_h, "popup fits the viewport")
	var scroll: ScrollContainer = scene.find_child("PopupScroll", true, false)
	assert_not_null(scroll, "narration text scrolls inside the popup")
	# One continue choice advances past the narration; it must sit fully
	# inside the viewport once revealed.
	var replies := scene.reply_buttons()
	assert_eq(replies.size(), 1)
	var btn: Button = replies[0]
	assert_true(btn.visible, "continue button revealed")
	var btn_bottom: float = btn.get_global_rect().position.y + btn.get_global_rect().size.y
	assert_between(btn.get_global_rect().position.y, 0.0, viewport_h, "button on screen")
	assert_lt(btn_bottom, viewport_h, "button bottom on screen")
	btn.pressed.emit()
	await wait_frames(2)
	assert_ne(String(scene.current_beat()["kind"]), "narration")

func test_event_beat_pops_centered_with_art_placeholder() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template",
		"choices": [{"choice_id": "accept", "label": "Accept"}]}
	Game.state.pending_event = ev.duplicate(true)
	scene.start([{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": ev}], TickReport.new())
	await wait_frames(3)
	assert_true(scene.event_popup().visible, "events pop centered")
	var art: Label = scene.find_child("PopupArtText", true, false)
	assert_string_contains(art.text, "event art", "art placeholder present")
	assert_gt(scene.reply_buttons().size(), 0, "choices live in the popup")

func test_dossier_tabs_switch_pages() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	scene.start([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "hm", "suggestions": []}], report)
	await wait_frames(2)
	assert_true(scene.tab_page(0).visible, "BIO tab default")
	assert_false(scene.tab_page(1).visible)
	scene.select_tab(2)
	assert_false(scene.tab_page(0).visible)
	assert_true(scene.tab_page(2).visible, "TIES tab selected")

func test_bottom_bar_tabs_and_info_tables() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	assert_false(r.bottom_bar().visible, "hidden on the title screen")
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	assert_true(r.bottom_bar().visible, "shown on gameplay screens")
	for tab in BottomBar.TABS:
		assert_not_null(r.bottom_bar().button(tab), tab + " button exists")
	r.bottom_bar().button("REALM").pressed.emit()
	await wait_frames(2)
	assert_true(r.info_screen().visible)
	assert_eq(r.info_screen().current_tab(), "REALM")
	var names := []
	for i in range(0, r.info_screen().table().get_child_count(), 2):
		names.append(r.info_screen().table().get_child(i).text)
	assert_has(names, "Treasury")
	r.bottom_bar().button("RELATIONSHIP").pressed.emit()
	await wait_frames(1)
	assert_false(r.info_screen().visible, "info yields to the graph")
	assert_true(r.relations_screen().visible)
	r.bottom_bar().button("MAP").pressed.emit()
	await wait_frames(1)
	assert_false(r.relations_screen().visible, "MAP closes overlays")

func test_top_bar_has_no_relations_button_and_chip_off_row() -> void:
	var bar: TopBar = load("res://scenes/top_bar.tscn").instantiate()
	add_child_autofree(bar)
	await wait_frames(2)
	assert_null(bar.find_child("RelationsButton", true, false),
		"RELATIONS moved to the bottom bar")
	var chip: Label = bar.find_child("EventChip", true, false)
	# The chip floats below the bar, no longer widening the metrics row
	# (the distortion that pushed MENU off screen).
	assert_ne(chip.get_parent().name, "Row")

func test_location_panel_shows_occupants_and_moves_freely() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	scene.start([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt", "text": "hm", "suggestions": []}], report)
	await wait_frames(2)
	# The upper right container names where you stand and who is present.
	var slot: Control = scene.find_child("LocationSlot", true, false)
	assert_eq(slot.get_child(0).location_code, "council_chamber")
	var occupants: Control = scene.find_child("OccupantsRow", true, false)
	assert_eq(occupants.get_child_count(), 5, "five ministers present")
	# MOVE lists every location in the region; moving costs no tick.
	var tick_before: int = Game.state.tick
	scene.find_child("MoveButton", true, false).pressed.emit()
	await wait_frames(1)
	var field: Button = scene.find_child("Move_mustering_field", true, false)
	assert_not_null(field, "the region's locations are listed")
	field.pressed.emit()
	await wait_frames(2)
	assert_eq(Game.state.current_location, "mustering_field")
	assert_eq(Game.state.tick, tick_before, "no time cost")
	assert_eq(scene.find_child("OccupantsRow", true, false).get_child_count(), 1,
		"Nora alone on the field")
	# Clicking an occupant singles them out (the old "visit" flow became the
	# selection model, user request 2026-08-31): typed words go to them and
	# the dossier follows the click.
	scene.find_child("Occupant_char_princess", true, false).pressed.emit()
	await wait_frames(1)
	assert_eq(scene.audience(), ["char_princess"])
	assert_eq(scene.focused_id(), "char_princess")
	scene.find_child("Occupant_char_princess", true, false).pressed.emit()
	await wait_frames(1)
	assert_eq(scene.focused_id(), "", "clicking again releases them")

func test_minister_beats_skip_when_minister_is_elsewhere() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	Game.state.current_location = "malvern_study"
	scene.start([
		{"kind": "minister", "portrait_id": "char_marshal",
			"speaker": "Ser Brandt", "text": "The levies!", "suggestions": []},
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"},
	], report)
	await wait_frames(2)
	# The marshal is not at Malvern's study: his beat is skipped with a note.
	assert_eq(String(scene.current_beat()["kind"]), "summary")
	assert_string_contains(scene.dialogue_text(), "You are elsewhere")

func test_absent_addressee_gets_herald_note_not_api_reply() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [],
		"court_reaction": {"addressed": ["char_lord_malvern"], "tone": "neutral"}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	# At the Council Chamber, Malvern (in his study) cannot answer a greeting.
	assert_eq(Game.state.current_location, "council_chamber")
	_got = {}
	Game.submit_free_text("greetings, Lord Malvern", func(res): _got = res)
	await wait_frames(4)
	assert_true(_got.has("reply"))
	assert_eq(String(_got["reply"]["speaker"]), "Herald",
		"the absent cannot converse — a herald note instead")
	assert_true(bool(_got["reply"]["degraded"]), "no API call for the absent")

var _got: Dictionary = {}

## --- Talk-to-whom targeting (user request 2026-08-31) ---

func _conversation_at(location: String) -> ConversationScene:
	Game.start_campaign(42)
	var report := Game.next_tick()
	Game.state.current_location = location
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	scene.start([{"kind": "minister", "portrait_id": "char_chancellor",
		"speaker": "Aldwin Reeve", "text": "My lord.", "suggestions": []}], report)
	await wait_frames(2)
	return scene

func test_no_selection_addresses_everyone_present() -> void:
	var scene := await _conversation_at("council_chamber")
	assert_eq(scene.selected_ids().size(), 0, "nothing selected by default")
	assert_eq(scene.audience().size(), 5, "the whole council chamber is addressed")
	assert_string_contains(scene.free_text_field().placeholder_text, "everyone")

func test_selecting_one_character_narrows_the_audience_and_names_them() -> void:
	var scene := await _conversation_at("council_chamber")
	scene.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_frames(1)
	assert_eq(scene.audience(), ["char_marshal"])
	assert_string_contains(scene.free_text_field().placeholder_text,
		"Ser Brandt of Harrow", "the box names who you are addressing")

func test_selecting_several_reports_a_count() -> void:
	var scene := await _conversation_at("council_chamber")
	scene.find_child("Occupant_char_marshal", true, false).pressed.emit()
	scene.find_child("Occupant_char_steward", true, false).pressed.emit()
	await wait_frames(1)
	assert_eq(scene.audience().size(), 2)
	assert_string_contains(scene.free_text_field().placeholder_text, "2 people")

func test_clicking_a_selected_character_deselects_and_returns_to_everyone() -> void:
	var scene := await _conversation_at("council_chamber")
	var btn: Button = scene.find_child("Occupant_char_marshal", true, false)
	btn.pressed.emit()
	await wait_frames(1)
	assert_eq(scene.audience(), ["char_marshal"])
	btn.pressed.emit()
	await wait_frames(1)
	assert_eq(scene.selected_ids().size(), 0)
	assert_eq(scene.audience().size(), 5, "back to addressing the room")
	assert_string_contains(scene.free_text_field().placeholder_text, "everyone")

func test_moving_location_clears_the_selection() -> void:
	var scene := await _conversation_at("council_chamber")
	scene.find_child("Occupant_char_marshal", true, false).pressed.emit()
	await wait_frames(1)
	assert_eq(scene.selected_ids().size(), 1)
	Game.move_to("mustering_field")
	await wait_frames(2)
	assert_eq(scene.selected_ids().size(), 0,
		"a selection cannot survive walking away from the people in it")

func test_everyone_addressed_remembers_but_only_one_answers() -> void:
	# The point of the feature: you told the room, so the room remembers —
	# while cost discipline keeps it to a single reply.
	var scene := await _conversation_at("council_chamber")
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [],
		"court_reaction": {"addressed": [], "tone": "neutral"}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	scene.free_text_field().text_submitted.emit("the granaries are full")
	await wait_frames(4)
	var heard := 0
	for id in LocationSystem.occupants(Game.data, Game.state, "council_chamber"):
		var log := AgentMemory.exchanges_for(Game.state, String(id))
		if log.size() >= 1 and String(log[0]["text"]) == "the granaries are full":
			heard += 1
	assert_eq(heard, 5, "every minister present remembers being told")
	# Review finding 2026-09-01: the answer is spoken in the same room, so
	# the room remembers it too — speaker recorded by character id.
	var chancellor_log := AgentMemory.exchanges_for(Game.state, "char_chancellor")
	assert_eq(chancellor_log.size(), 2, "the answerer also remembers his own reply")
	assert_eq(String(chancellor_log[1]["speaker"]), "char_chancellor")
	var marshal_log := AgentMemory.exchanges_for(Game.state, "char_marshal")
	assert_eq(marshal_log.size(), 2, "bystanders remember the reply they overheard")
	assert_eq(String(marshal_log[1]["speaker"]), "char_chancellor")
	assert_eq(AgentMemory.exchanges_for(Game.state, "char_lord_malvern").size(), 0,
		"Malvern is in his study and hears nothing")

func test_selected_targets_alone_remember() -> void:
	var scene := await _conversation_at("council_chamber")
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [],
		"court_reaction": {"addressed": [], "tone": "neutral"}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	scene.find_child("Occupant_char_spymaster", true, false).pressed.emit()
	await wait_frames(1)
	scene.free_text_field().text_submitted.emit("a word in your ear")
	await wait_frames(4)
	var log := AgentMemory.exchanges_for(Game.state, "char_spymaster")
	assert_eq(log.size(), 2,
		"the one you singled out remembers the word AND their own reply")
	assert_eq(String(log[0]["text"]), "a word in your ear")
	assert_eq(log[0]["audience"], ["char_spymaster"], "recorded as a private word")
	assert_eq(String(log[1]["speaker"]), "char_spymaster",
		"the reply is remembered under the speaker's own id (2026-09-01)")
	assert_eq(AgentMemory.exchanges_for(Game.state, "char_chancellor").size(), 0,
		"the rest of the room does not overhear a targeted word")

func test_chat_after_event_resolution_shows_reply() -> void:
	# User bug 2026-08-30 ("why I still cannot see response?"): resolve an
	# event, then seek someone out and greet them — the old blanket
	# _resolved_event guard silently swallowed the reply callback.
	Game.start_campaign(42)
	var report := Game.next_tick()
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": []})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template",
		"choices": [{"choice_id": "accept", "label": "Accept"}]}
	Game.state.pending_event = ev.duplicate(true)
	scene.start([{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": ev},
		{"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"}], report)
	await wait_frames(3)
	scene.reply_buttons()[0].pressed.emit()  # resolve the event
	await wait_frames(2)
	# Still on the same (resolved) beat: visit the Chancellor and speak.
	scene.find_child("Occupant_char_chancellor", true, false).pressed.emit()
	await wait_frames(1)
	scene.free_text_field().text_submitted.emit("greetings")
	await wait_frames(4)
	assert_string_contains(scene.dialogue_text(), "You: greetings")
	assert_string_contains(scene.dialogue_text(), "Aldwin Reeve:",
		"the visited minister's reply is shown, not swallowed")

func test_transcript_names_are_colored_per_speaker() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	scene.start([{"kind": "minister", "portrait_id": "char_marshal",
		"speaker": "Ser Brandt of Harrow", "text": "The border holds.",
		"suggestions": []}], report)
	await wait_frames(2)
	var raw: String = scene.find_child("TextLabel", true, false).text
	assert_string_contains(raw, "[color=#", "names carry bbcode colors")
	assert_string_contains(scene.dialogue_text(), "Ser Brandt of Harrow: The border holds.")
	var c1 := ConversationScene._speaker_color("Ser Brandt of Harrow")
	assert_eq(c1, ConversationScene._speaker_color("Ser Brandt of Harrow"),
		"per-speaker color is stable")
	assert_ne(ConversationScene._speaker_color("You"), c1)
