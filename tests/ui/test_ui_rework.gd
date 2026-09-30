extends GutTest
## The 2026-08-30 UI change batch: menu buttons (character creation went
## 2026-09-30),
## opening narration popup, centered event popup, dossier tabs, bottom tab
## bar with info tables, colored transcript names, top-bar event chip out of
## the metrics row.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_main_menu_has_start_load_quit_and_starts_with_the_founding_names() -> void:
	var r := _root()
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	var col := menu.menu_column()
	assert_not_null(col.get_node("StartGame"))
	assert_not_null(col.get_node("LoadGame"))
	assert_not_null(col.get_node("Quit"))
	# The realm and the ruler are not customised (owner 2026-09-30): Start
	# Game begins the reign at once, with no character creation.
	assert_null(menu.find_child("SetupPanel", true, false))
	Game.player_setup = {"first_name": "Edmund"}
	col.get_node("StartGame").pressed.emit()
	await wait_frames(2)
	assert_eq(Game.player_setup, {}, "no chosen identity survives")
	assert_false(r.current_screen is MainMenu, "the reign began")
	assert_eq(Game.state.characters["you"].display_name, "King Aldric Valorin")

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
	assert_string_contains(scene.said_text(), "ascended to the throne")
	# Regression (user bug 2026-08-30): the full background text made the
	# centered popup taller than the viewport, pushing the continue button off
	# screen with no way to scroll. The narration now stands in the audience
	# window (owner 2026-09-15), whose speech scrolls inside a capped box, so
	# the window must fit and the button must be on screen.
	var panel: PanelContainer = scene.find_child("AudienceWindow", true, false)
	var viewport_h := scene.get_viewport_rect().size.y
	assert_lt(panel.size.y, viewport_h, "the window fits the viewport")
	var scroll: ScrollContainer = scene.find_child("SpeechScroll", true, false)
	assert_not_null(scroll, "narration text scrolls inside the window")
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
	# The reign opens on the prologue's first council, not on whatever the
	# random roll happened to pick (chapter 0, 2026-09-21): the narration is
	# pushed in front of the tick's own event beat, and that beat is the
	# chapter opener GameState.new_campaign scheduled for tick 1.
	var beat := scene.current_beat()
	assert_eq(String(beat["kind"]), "event")
	assert_eq(String(beat["event"]["event_id"]), "c0_01")
	assert_string_contains(scene.speech_text(), "older than the kingdom",
		"the authored scene is shown verbatim")

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
	# Owner 2026-09-15: the event stands in the audience window, its title in
	# the banner where the placeholder art's caption used to be.
	var title: Label = scene.find_child("AudienceTitle", true, false)
	assert_ne(title.text, "", "the event's title heads the window")
	assert_gt(scene.reply_buttons().size(), 0, "choices live in the window")

## The widest the audience window can get: a chapter beat with four choices
## AND an illustration band over it. The whole thing — the window and the
## last option in it — has to stay inside the viewport, or the player is
## given a choice they cannot click (the bug the opening narration had in
## 2026-08-30, one layer up).
func test_the_window_fits_with_an_illustration_and_four_choices() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	var scene: ConversationScene = r.current_screen
	var ev := EventSystem.new(Game.data)._fire("c0_02", Game.state)
	assert_eq((ev["choices"] as Array).size(), 4,
		"C0-02 is the chapter's widest beat: three roads and the captain's offer")
	scene.start([{"kind": "event", "portrait_id": "round_table",
		"speaker": "The Council", "event": ev}], TickReport.new())
	await wait_frames(3)
	# Stand in for the installed render at the size install_map_art.py writes.
	var band: TextureRect = scene.find_child("EventArt", true, false)
	var stand_in := PlaceholderTexture2D.new()
	stand_in.size = Vector2(1280, 533)
	band.texture = stand_in
	band.visible = true
	for btn in scene.reply_buttons():
		btn.visible = true
	await wait_frames(3)
	var panel: PanelContainer = scene.find_child("AudienceWindow", true, false)
	var viewport_h := scene.get_viewport_rect().size.y
	assert_lt(panel.size.y, viewport_h, "the window fits the viewport")
	var last: Button = scene.reply_buttons()[scene.reply_buttons().size() - 1]
	var bottom: float = last.get_global_rect().position.y + last.get_global_rect().size.y
	assert_lt(bottom, viewport_h, "the last option is on screen")

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
	# Owner ruling 2026-09-10: the dossier stands over the talk in the right
	# column, so its pages rest closed and a tab opens one at a time.
	assert_false(scene.tab_page(0).visible, "the pages rest closed")
	assert_false(scene.tab_page(1).visible)
	scene.select_tab(0)
	assert_true(scene.tab_page(0).visible, "BIO opens on its tab")
	scene.select_tab(2)
	assert_false(scene.tab_page(0).visible)
	assert_true(scene.tab_page(2).visible, "TIES tab selected")
	scene.select_tab(2)
	assert_false(scene.tab_page(2).visible, "the same tab again closes it")

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
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(1)
	assert_false(r.info_screen().visible, "info yields to the ledger")
	assert_true(r.ledger_screen().visible)
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(1)
	assert_false(r.ledger_screen().visible, "the tab toggles the ledger off again")

## FAMILIES (user request 2026-09-09): the noble houses of the player's own
## realm, with the seats they hold and how they regard the king. Four columns,
## so the table widens for it — the name/value tabs are unaffected.
func test_families_tab_lists_the_houses_of_the_realm() -> void:
	Game.start_campaign(42)
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	r.bottom_bar().button("FAMILIES").pressed.emit()
	await wait_frames(2)
	assert_true(r.info_screen().visible)
	assert_eq(r.info_screen().current_tab(), "FAMILIES")
	var table := r.info_screen().table()
	assert_eq(table.columns, 4, "House / Members / Seats / Standing")
	var cells: Array[String] = []
	for child in table.get_children():
		cells.append(child.text)
	for header in ["House", "Members", "Seats", "Standing"]:
		assert_has(cells, header, "the table is headed")
	# The king's own house is in the realm, so it must be listed.
	var king: Character = Game.state.characters["you"]
	assert_has(cells, king.family_name, "the royal house is listed")
	assert_has(cells, "Crown", "and the king holds the crown")
	# A foreign house must not be: this is the realm's own nobility.
	var petra: Character = Game.state.characters.get("char_envoy_petra")
	if petra != null and petra.family_name != "":
		assert_does_not_have(cells, petra.family_name,
			"a foreign envoy's house is not one of the realm's")

## Every row must have one cell per column, or the grid shears.
func test_families_rows_are_complete() -> void:
	Game.start_campaign(42)
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	r.bottom_bar().button("FAMILIES").pressed.emit()
	await wait_frames(2)
	var table := r.info_screen().table()
	assert_eq(table.get_child_count() % 4, 0,
		"%d cells is not a whole number of 4-column rows" % table.get_child_count())
	assert_gt(table.get_child_count() / 4.0, 1.0, "at least one house beyond the header")

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
	fake.canned_text = JSON.stringify({"narrative": "Full they are, my lord.", "impacts": {
		"actions": [], "world": [], "court_reaction": {"addressed": [], "tone": "neutral"}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	scene.free_text_field().text_submitted.emit("the granaries are full")
	await wait_frames(4)
	var heard := 0
	for id in LocationSystem.occupants(Game.data, Game.state, "council_chamber"):
		var entries := AgentMemory.exchanges_for(Game.state, String(id))
		if entries.size() >= 1 and String(entries[0]["text"]) == "the granaries are full":
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
	fake.canned_text = JSON.stringify({"narrative": "I am listening, my lord.", "impacts": {
		"actions": [], "world": [], "court_reaction": {"addressed": [], "tone": "neutral"}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	scene.find_child("Occupant_char_spymaster", true, false).pressed.emit()
	await wait_frames(1)
	scene.free_text_field().text_submitted.emit("a word in your ear")
	await wait_frames(4)
	var entries := AgentMemory.exchanges_for(Game.state, "char_spymaster")
	assert_eq(entries.size(), 2,
		"the one you singled out remembers the word AND their own reply")
	assert_eq(String(entries[0]["text"]), "a word in your ear")
	assert_eq(entries[0]["audience"], ["char_spymaster"], "recorded as a private word")
	assert_eq(String(entries[1]["speaker"]), "char_spymaster",
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
	fake.canned_text = JSON.stringify({"narrative": "Greetings, my lord.",
		"impacts": {"actions": []}})
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
	assert_string_contains(scene.said_text(), "You: greetings")
	# The window names him on its plate, so his reply stands there without
	# his name before it (2026-09-28): it is the words after the player's.
	assert_ne(scene.speech_text().get_slice("greetings", 1).strip_edges(), "",
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
	# The record holds what has passed: the beat joins it once the audience
	# window no longer shows it (owner 2026-09-28).
	assert_false("The border holds." in scene.dialogue_text(), "not twice while the window shows it")
	(scene.find_child("AudienceLayer", true, false) as Control).visible = false
	await wait_frames(1)
	var raw: String = scene.find_child("TextLabel", true, false).text
	assert_string_contains(raw, "[color=#", "names carry bbcode colors")
	assert_string_contains(scene.dialogue_text(), "Ser Brandt of Harrow: The border holds.")
	var c1 := ConversationScene._speaker_color("Ser Brandt of Harrow")
	assert_eq(c1, ConversationScene._speaker_color("Ser Brandt of Harrow"),
		"per-speaker color is stable")
	assert_ne(ConversationScene._speaker_color("You"), c1)

## The bottom tab strip must be tall enough for its own buttons. BAR_HEIGHT
## is a constant because NewsTicker and ScreenLayout both place
## themselves off it — so the relation gets a test instead of a computation.
## It broke once in exactly this way: the design viewport went 640x360 ->
## 1280x720, every font size doubled with it, and the tabs fell off the
## bottom of the screen with nothing to catch it.
func test_the_bottom_tab_strip_is_tall_enough_for_its_buttons() -> void:
	var bar := BottomBar.new()
	bar.theme = UiPalette.build_theme()
	add_child_autofree(bar)
	await wait_frames(2)
	var need := bar.content_height()
	assert_gt(need, 0.0, "the strip measured itself")
	assert_lte(need, BottomBar.BAR_HEIGHT,
		"BAR_HEIGHT (%.0f) must cover the buttons (%.0f)" % [BottomBar.BAR_HEIGHT, need])

func test_the_bottom_tabs_fit_across_the_design_viewport() -> void:
	var bar := BottomBar.new()
	bar.theme = UiPalette.build_theme()
	add_child_autofree(bar)
	await wait_frames(2)
	var row: Control = bar.get_node("Bar/Row")
	assert_lte(row.get_combined_minimum_size().x, 1280.0,
		"%d tabs still fit the 1280 px design viewport" % BottomBar.TABS.size())

## The MANORS tab (MANOR_SYSTEM.md §6) lights the manors view on the map —
## house colours and, since ECONOMY was folded into it (owner 2026-09-19),
## the output badges — and is exclusive with HEIGHTS.
func test_the_manors_tab_is_a_theme_exclusive_with_the_others() -> void:
	Game.start_campaign(42)
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	r.bottom_bar().button("MANORS").pressed.emit()
	await wait_frames(1)
	assert_true(r.manor_view(), "the tab drives it")
	assert_eq(r.current_screen.map3d_view().manor_theme(), "manors", "the map colours by house")
	assert_true(r.bottom_bar().button("MANORS").button_pressed)
	r.bottom_bar().button("HEIGHTS").pressed.emit()
	await wait_frames(1)
	assert_true(r.height_view())
	assert_false(r.manor_view(), "HEIGHTS put MANORS out")
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights", "one theme at a time")
