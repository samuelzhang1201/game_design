extends GutTest

func _panel() -> Control:
	Game.start_campaign(44)
	Game.state.day_resolution.clear()
	Game.state.metrics["treasury"] = 10000000
	var panel: Control = load("res://scenes/panels/army_recruitment_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.open()
	return panel

func test_preview_is_read_only_and_commander_is_included() -> void:
	var panel := _panel()
	var before := Game.state.to_dict()
	panel.refresh_quote()
	assert_eq(Game.state.to_dict(), before)
	var quote: Dictionary = panel.offer()
	assert_false(quote.has("error"), str(quote))
	if quote.has("error"):
		return
	var c: Dictionary = quote["composition"]
	assert_eq(int(c["commoners"]) + int(c["noble_troops"]) + int(c["commander"]), int(panel.request()["total"]))
	assert_eq(int(c["commander"]), 1)
	assert_string_contains((panel.get_node("%Share") as Label).text, "actual final share: 0.17%")
	assert_false(panel.quote_text().contains("Final unit:"), "new-unit composition is already the final composition")
	assert_eq(int(panel.get_node("%Nobles").max_value), 100)

func test_insufficient_funds_disable_confirm() -> void:
	var panel := _panel()
	Game.state.metrics["treasury"] = 0
	panel.refresh_quote()
	assert_true((panel.get_node("%Confirm") as Button).disabled)
	assert_string_contains(panel.quote_text(), "treasury")
	assert_string_contains(panel.quote_text(), "paid once, in full")
	assert_true(panel.offer().has("composition"), "a funding refusal retains its reviewable quote")

func test_confirmation_pays_once_and_reserves_assembling_people() -> void:
	var panel := _panel()
	var quote: Dictionary = panel.offer()
	assert_false(quote.has("error"), str(quote))
	if quote.has("error"):
		return
	var before := int(Game.state.metrics["treasury"])
	panel.confirm()
	assert_eq(int(Game.state.metrics["treasury"]), before - int(quote["gold"]))
	assert_false(panel.visible)
	panel.confirm()
	assert_eq(int(Game.state.metrics["treasury"]), before - int(quote["gold"]))
	assert_gt(Game.state.recruitment_projects.size(), 0)
	var project: Dictionary = Game.state.recruitment_projects.values().back()
	assert_eq(project["status"], "assembling")

func test_close_releases_only_its_own_hold() -> void:
	var panel := _panel()
	Game.hold_clock(true, "other_test")
	assert_true(Game.holds_clock("recruitment"))
	panel.close()
	assert_false(Game.holds_clock("recruitment"))
	assert_true(Game.holds_clock("other_test"))
	Game.hold_clock(false, "other_test")

func test_project_pause_reason_is_visible() -> void:
	var panel := _panel()
	Game.state.recruitment_projects["test"] = {"unit_code": "test", "status": "paused", "worked_days": 2, "build_days": 10, "pause_reason": "The town is lost."}
	panel.refresh_quote()
	assert_string_contains((panel.get_node("%Projects") as Label).text, "The town is lost.")

func test_static_form_is_authored_in_scene() -> void:
	var panel := _panel()
	assert_not_null(panel.get_node("%Town"))
	assert_not_null(panel.get_node("%Commander"))
	assert_eq((panel.get_node("%Title") as Label).theme_type_variation, &"CardTitle")
	assert_eq((panel.get_node("%Confirm") as Button).theme_type_variation, &"CardCommand")

func test_host_counts_living_people_including_wounded_and_paid_units() -> void:
	var panel := _panel()
	var repo := Game.data
	var request: Dictionary = panel.request()
	var quote: Dictionary = panel.offer()
	assert_false(quote.has("error"), str(quote))
	if quote.has("error"):
		return
	panel.confirm()
	for i: int in int(quote["build_days"]):
		RecruitmentSystem.step_day(repo, Game.state)
		Game.state.day += 1
	var code := String(quote["unit_code"])
	assert_true(Game.state.regiments.has(code), "paid assembly completed into a real unit")
	var roster: Dictionary = Game.state.military_rosters[code]
	var cohort_id := String(roster["cohort_ids"][0])
	assert_false(MilitaryRoster.transition(repo, Game.state, "ui-host:wound", [
		{"cohort_id": cohort_id, "from": "fit", "to": "wounded", "count": 1}], "a recruitment test injury").has("error"))
	var host := MilitaryPanel.create()
	add_child_autofree(host)
	host.refresh()
	var found := false
	for row: Dictionary in host.regiments_chart().rows:
		if row["label"] == MilitaryPanel._short(String(Game.state.army_roster[code]["label"])):
			found = true
			assert_eq(int(row["value"]), int(request["total"]), "paid personnel include their wounded member")
	assert_true(found)

func test_host_names_ships_separately_from_real_living_crews() -> void:
	var panel := _panel()
	var host := MilitaryPanel.create()
	add_child_autofree(host)
	host.refresh()
	var found := false
	for unit: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if MapObjects.regiment_arm(Game.data, unit) != "fleet":
			continue
		for row: Dictionary in host.regiments_chart().rows:
			if row["label"] == MilitaryPanel._short(String(unit["label"])):
				found = true
				var people := ArmySystem.living_count(Game.data, Game.state, String(unit["regiment_code"]))
				assert_eq(int(row["value"]), people)
				assert_gt(people, int(unit["fleet"]), "ships are equipment with living crews")
				assert_string_contains(String(row["text"]), "%s ships" % UiPalette.format_int(int(unit["fleet"])))
	assert_true(found, "the starting realm has a real fleet")
	panel.close()

func test_root_connects_both_hosts_and_keeps_the_modal_lazy() -> void:
	Game.start_campaign(44)
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	assert_null(root.recruitment_panel())
	for screen: GameRoot.State in [GameRoot.State.COURT, GameRoot.State.CONVERSATION]:
		root._switch_to(screen)
		root.current_screen.military_panel().recruitment_requested.emit()
		assert_true(root.recruitment_panel().visible)
		assert_true(Game.holds_clock("recruitment"))
		root.recruitment_panel().close()
		assert_false(Game.holds_clock("recruitment"))

func test_escape_closes_recruitment_before_pause_menu_and_scene_keeps_look() -> void:
	Game.start_campaign(44)
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	root._switch_to(GameRoot.State.COURT)
	root.open_recruitment()
	var panel := root.recruitment_panel()
	var frame := panel.get_node("Frame") as PanelContainer
	var bounds := [frame.anchor_left, frame.anchor_right, frame.anchor_top, frame.anchor_bottom]
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.get_viewport().push_input(key)
	await wait_process_frames(1)
	assert_false(panel.visible)
	assert_false(root.pause_menu().visible)
	panel.open()
	assert_eq([frame.anchor_left, frame.anchor_right, frame.anchor_top, frame.anchor_bottom], bounds)
	assert_eq((panel.get_node("%Confirm") as Button).theme_type_variation, &"CardCommand")

func test_refusal_has_warning_theme_and_only_shows_when_refused() -> void:
	var panel := _panel()
	var warning := panel.get_node_or_null("%Refusal") as Label
	assert_not_null(warning, "refusal has its own editor-authored label")
	if warning == null:
		return
	assert_eq(warning.theme_type_variation, &"CardWarn")
	assert_eq(warning.get_theme_font_size("font_size"), (panel.get_node("%Quote") as Label).get_theme_font_size("font_size"))
	assert_false(warning.visible)
	Game.state.metrics["treasury"] = 0
	panel.refresh_quote()
	assert_true(warning.visible)
	assert_string_contains(warning.text, "treasury")
	assert_string_contains(panel.quote_text(), warning.text)
	Game.state.metrics["treasury"] = 10000000
	panel.refresh_quote()
	assert_false(warning.visible)
	assert_string_contains(panel.quote_text(), "2 / day")
	assert_false(panel.quote_text().contains("2–2 / day"))

func test_quote_shows_engine_monthly_wages_in_affordable_and_refused_states() -> void:
	var panel := _panel()
	for gold: int in [10000000, 0]:
		Game.state.metrics["treasury"] = gold
		panel.refresh_quote()
		var quote: Dictionary = panel.offer()
		assert_true(quote.has("quality"))
		var monthly := int(quote["quality"]["monthly_wages"])
		assert_string_contains(panel.quote_text(), "Military wages: %s gold / month" % UiPalette.format_int(monthly))

func test_completed_assembly_displays_actual_survivors_instead_of_quoted_share() -> void:
	var panel := _panel()
	Game.state.recruitment_projects["after-losses"] = {"unit_code": "after-losses", "status": "complete",
		"worked_days": 2, "build_days": 2, "pause_reason": "",
		"completion_composition": {"after-losses": {"commoners": 270, "noble_troops": 59, "commander": 1}}}
	panel.refresh_quote()
	var text := (panel.get_node("%Projects") as Label).text
	assert_string_contains(text, "Actual survivors: 330 people")
	assert_string_contains(text, "60 nobles (18.18%, commander included)")
