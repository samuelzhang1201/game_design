extends GutTest
const SuiteData = preload("res://tests/suite_data.gd")

func _panel() -> Control:
	var path := "res://scenes/panels/prisoner_panel.tscn"
	assert_true(ResourceLoader.exists(path), "Custody needs an editor-authored panel")
	if not ResourceLoader.exists(path): return null
	var panel: Control = load(path).instantiate()
	add_child_autofree(panel)
	return panel

func _view() -> Dictionary:
	return {"player_realm":"home", "next_proposal_id":"ui:1", "current_count":60, "historical_captured":100,
		"batches":[{"id":"batch", "holder_code":"actual", "holder_label":"The actual captor", "holder_realm":"home", "origin_realm":"away", "count":60, "wounded_count":20, "named":[], "observed_day":8, "current_verified":true},
			{"id":"reciprocal", "holder_label":"Their host", "holder_realm":"away", "origin_realm":"home", "count":10, "wounded_count":2, "named":[]}],
		"proposals":[]}

func test_custody_history_and_actual_holder_are_separate() -> void:
	var panel := _panel()
	if panel == null: return
	panel.show_view(_view())
	assert_string_contains(panel.get_node("%Summary").text, "60")
	assert_string_contains(panel.get_node("%Summary").text, "100")
	assert_string_contains(panel.get_node("%Summary").text, "historical")
	assert_string_contains(panel.get_node("%BatchDetails").text, "The actual captor")
	watch_signals(panel)
	panel.get_node("%Count").value = 10
	panel.get_node("%Wounded").value = 2
	panel.get_node("%Money").value = 100
	panel.get_node("%Reason").text = "Agreed ransom"
	panel.get_node("%Propose").pressed.emit()
	var request: Array = get_signal_parameters(panel, "action_requested")
	assert_eq(request[0], "PRISONER_PROPOSE")
	assert_eq(request[1].money, 100)
	assert_eq(request[1].batches, [{"batch_id":"batch", "count":10, "wounded_count":2, "named_ids":[]}])
	assert_eq(request[1].parties, {"proposer":"home", "payer":"away"})

func test_exchange_selects_both_sides_and_named_link_is_identity() -> void:
	var panel := _panel()
	if panel == null: return
	var view := _view()
	view.batches[0].named = [{"id":"person-original", "name":"The captive"}]
	panel.show_view(view)
	watch_signals(panel)
	panel.get_node("%People").meta_clicked.emit("person-original")
	assert_signal_emitted_with_parameters(panel, "character_selected", ["person-original"])
	panel.get_node("%Kind").select(1)
	panel.get_node("%Kind").item_selected.emit(1)
	panel.get_node("%Reason").text = "Reciprocal exchange"
	panel.get_node("%Propose").pressed.emit()
	var request: Array = get_signal_parameters(panel, "action_requested")
	assert_eq(request[1].kind, "exchange")
	assert_eq(request[1].batches.size(), 2)
	assert_eq(request[1].batches[0].named_ids, ["person-original"])
	assert_eq(request[1].batches[1].batch_id, "reciprocal")

func test_proposal_requires_real_consent_before_fulfillment() -> void:
	var panel := _panel()
	if panel == null: return
	var view := _view()
	view.proposals = [{"id":"p", "kind":"ransom", "status":"proposed", "required_parties":["home","away"], "consents":{"away":true}, "request":{"money":100,"reason":"Terms"}, "result":{}}]
	panel.show_view(view)
	assert_true(panel.get_node("%Settle").disabled)
	watch_signals(panel)
	panel.get_node("%Accept").pressed.emit()
	assert_signal_emitted_with_parameters(panel, "action_requested", ["PRISONER_RESPOND", {"proposal_id":"p", "accepted":true}])
	view.proposals[0].status = "accepted"
	view.proposals[0].consents.home = true
	panel.show_view(view)
	assert_false(panel.get_node("%Settle").disabled)
	assert_true(panel.get_node("%Accept").disabled)
	view.proposals[0].status = "fulfilled"
	view.proposals[0].result = {"released":10,"reason":"Paid once"}
	panel.show_view(view)
	assert_true(panel.get_node("%Settle").disabled)
	assert_string_contains(panel.get_node("%ProposalDetails").text, "Paid once")
	view.proposals[0].status = "unconfirmed"
	view.proposals[0].reason = "No reply; negotiate a new agreement."
	view.proposals[0].result = {}
	panel.show_view(view)
	assert_true(panel.get_node("%Settle").disabled)
	assert_string_contains(panel.get_node("%ProposalDetails").text, "No reply")

func test_report_panel_only_renders_delivered_rows() -> void:
	var path := "res://scenes/panels/battle_report_panel.tscn"
	assert_true(ResourceLoader.exists(path))
	if not ResourceLoader.exists(path): return
	var panel: Control = load(path).instantiate()
	add_child_autofree(panel)
	panel.show_view({"detailed_reports":[]})
	assert_string_contains(panel.get_node("%Summary").text, "delivered")
	panel.show_view({"detailed_reports":[{"battle_id":7,"place":"The ford", "duration_days":3,
		"personnel":{"own":{"participants":600,"fit":430,"wounded":70,"dead":40,"captured":60,"released":0},"enemy":{"dead":{"lo":20,"hi":40}}},
		"participants":[],"reinforcements":[],"formations":{},"orders":[],"events":[],"prisoners":[],"equipment":[],"supplies":[],"family_changes":[{"reason":"Rescued the heir"}],"outcome":{"result":"victory"}}]})
	assert_string_contains(panel.get_node("%Summary").text, "600")
	assert_string_contains(panel.get_node("%Summary").text, "20–40")
	assert_string_contains(panel.get_node("%Summary").text, "Rescued the heir")

func test_read_only_dossier_keeps_character_identity_and_game_state() -> void:
	var old_state: GameState = Game.state
	var old_data: DataRepository = Game.data
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 91)
	var id: String = Game.state.characters.keys()[0]
	var original: Character = Game.state.characters[id]
	var before := JSON.stringify(Game.state.to_dict())
	var panel: Control = load("res://scenes/panels/character_dossier.tscn").instantiate()
	add_child_autofree(panel)
	panel.show_character(id)
	assert_eq(panel.inspected_id, id)
	assert_eq(panel.get_node("%MinisterName").text, original.display_name)
	assert_same(Game.state.characters[id], original)
	assert_eq(JSON.stringify(Game.state.to_dict()), before, "Reading a captive's dossier cannot travel, speak or mutate the campaign")
	assert_false(panel.get_node("%TalkRow").visible)
	Game.state = old_state
	Game.data = old_data

func test_host_exposes_both_editor_authored_entry_buttons() -> void:
	var panel := MilitaryPanel.create()
	add_child_autofree(panel)
	watch_signals(panel)
	panel.get_node("%Prisoners").pressed.emit()
	panel.get_node("%BattleReports").pressed.emit()
	assert_signal_emitted(panel, "prisoners_requested")
	assert_signal_emitted(panel, "battle_reports_requested")

func test_foreign_custody_is_discoverable_but_cannot_propose_for_its_holder() -> void:
	var panel := _panel()
	if panel == null: return
	panel.show_view(_view())
	assert_eq(panel.get_node("%Batch").item_count, 2)
	panel.get_node("%Batch").select(1)
	panel.get_node("%Batch").item_selected.emit(1)
	assert_string_contains(panel.get_node("%BatchDetails").text, "Their host")
	assert_string_contains(panel.get_node("%BatchDetails").text, "Only the holding realm")
	assert_true(panel.get_node("%Propose").disabled)
	watch_signals(panel)
	panel.get_node("%Propose").pressed.emit()
	assert_signal_not_emitted(panel, "action_requested")

func test_live_refresh_preserves_explicit_partial_selection() -> void:
	var panel := _panel()
	if panel == null: return
	panel.show_view(_view())
	panel.get_node("%Count").value = 10
	panel.get_node("%Wounded").value = 2
	panel.show_view(_view())
	assert_eq(int(panel.get_node("%Count").value), 10)
	assert_eq(int(panel.get_node("%Wounded").value), 2)

func test_battle_panel_labels_missing_reading_unknown() -> void:
	var panel: Control = load("res://scenes/panels/battle_panel.tscn").instantiate()
	add_child_autofree(panel)
	var text: String = panel._summary({"units": [{"label": "Remote host", "commander": "Captain", "known": false,
		"fit": 0, "wounded": 0, "morale": 0, "supplies": 0}]})
	assert_string_contains(text.to_lower(), "unknown")
	assert_false(text.contains("0 fit"))
	assert_false(text.contains("day 0"))

func test_host_bars_and_summary_use_only_received_remote_readings() -> void:
	var old_data: DataRepository = Game.data
	var old_state: GameState = Game.state
	Game.data = SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	Game.state = preload("res://tests/fixtures/battle_scenario.gd").contact(Game.data, 10)
	BattleSystem.detect_contacts(Game.data, Game.state)
	Game.state.king_state = {"x_m": 10000000, "y_m": 10000000}
	var code := String(Game.state.battles[0].def[0])
	var strength_path := "military.kingdoms.%s.strength" % Game.data.resolve_realm("player_realm")
	Game.data.world_schema.append({"path":strength_path, "type":"int"})
	Game.data.schema_cache.clear()
	Game.state.world[strength_path] = 777
	var panel := MilitaryPanel.create()
	add_child_autofree(panel)
	panel.refresh()
	assert_string_contains(panel.get_node("Summary").text.to_lower(), "unknown")
	var unknown: Array = panel.regiments_chart().rows.filter(func(row: Dictionary) -> bool: return row.text.to_lower().contains("unknown"))
	assert_eq(unknown.size(), 1)
	Game.state.king_state.battle_reports = [{"unit_readings": {code: {"fit": 321, "wounded": 12, "morale": 70, "supplies": 89, "day": 8}}}]
	panel.refresh()
	var arms: Array = panel.arms_chart().rows.duplicate(true)
	var regs: Array = panel.regiments_chart().rows.duplicate(true)
	var summary: String = panel.get_node("Summary").text
	for cohort_id: String in Game.state.military_rosters[code].cohort_ids:
		Game.state.military_cohorts[cohort_id].fit = 1
		Game.state.military_cohorts[cohort_id].wounded = 0
	Game.state.regiments[code].supplies = 1
	panel.refresh()
	assert_eq(panel.arms_chart().rows, arms)
	assert_eq(panel.regiments_chart().rows, regs)
	assert_eq(panel.get_node("Summary").text, summary)
	assert_string_contains(summary, "strength awaiting a report")
	Game.state.battles.clear()
	panel.refresh()
	assert_string_contains(panel.get_node("Summary").text, "; strength ")
	assert_false(panel.get_node("Summary").text.contains("awaiting a report"))
	Game.data = old_data
	Game.state = old_state
