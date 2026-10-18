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
	var screen: CourtScreen = load("res://scenes/screens/court.tscn").instantiate()
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
