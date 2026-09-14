extends GutTest
## The country card (owner 2026-09-14): the realm's temper — unrest,
## legitimacy, the army's drill and the church — left the top bar for the
## player's own country's card; a foreign card does not show it.

func test_the_players_own_card_carries_the_realms_temper() -> void:
	Game.start_campaign(42)
	var panel := CountryPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	panel.show_country(mine)
	for key in CountryPanel.REALM_METRICS:
		assert_eq(panel.realm_metric_text(key), str(int(Game.state.metrics[key])), key)
	Game.state.metrics["unrest"] = 37.0
	Game.state_changed.emit()
	assert_eq(panel.realm_metric_text("unrest"), "37", "it follows the live metric")
	var foreign := ""
	for code: String in Game.data.kingdoms:
		if code != mine:
			foreign = code
			break
	panel.show_country(foreign)
	assert_eq(panel.realm_metric_text("unrest"), "", "a foreign court's temper is not shown")
