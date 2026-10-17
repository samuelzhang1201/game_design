extends GutTest

func test_event_choices_keep_costs_and_refusal_visible() -> void:
	var path := "res://scenes/panels/battle_panel.tscn"
	assert_true(ResourceLoader.exists(path), "Battle decisions need an editor-authored panel")
	if not ResourceLoader.exists(path): return
	var panel: Control = load(path).instantiate()
	add_child_autofree(panel)
	panel.show_view({"battles": [], "enemies": [], "reports": [], "decision": {
		"token": "10:battle_event:1:ev_51", "kind": "battle_event", "battle_id": 1,
		"title": "The wavering flank", "scene": "The right wing gives ground.", "art_key": "flank",
		"options": [{"id": "encourage", "label": "Promise a reward", "gold": 7, "effects_text": "+8 morale", "reason": "Insufficient available gold", "legal": false},
			{"id": "hold", "label": "Keep the current order", "gold": 0, "effects_text": "Preserve the treasury", "reason": "", "legal": true}]}}, 1)
	assert_true(panel.visible)
	assert_true(panel.get_node("%Choice1").disabled)
	assert_string_contains(panel.get_node("%Choice1").text, "7 gold")
	assert_string_contains(panel.get_node("%ChoiceDetails1").text, "Insufficient")
	assert_false(panel.get_node("%Choice2").disabled)
	assert_false(panel.get_node("%Close").visible, "An unresolved decision cannot be hidden")

func test_commands_show_delivery_and_costs_and_emit_only_identifiers() -> void:
	var path := "res://scenes/panels/battle_panel.tscn"
	assert_true(ResourceLoader.exists(path))
	if not ResourceLoader.exists(path): return
	var panel: Control = load(path).instantiate()
	add_child_autofree(panel)
	panel.show_view({"decision": {}, "enemies": [], "reports": [], "battles": [{"id": 1, "place": "the ford", "units": [], "action": "hold", "formation": "double_rank", "agreements": "Heralds protected", "warrants": [{"kind": "inspire", "status": "pending", "reserved_gold": 7, "reason": "The courier is riding"}], "orders": [{"id": "inspire", "label": "Reward and inspire", "regiment": "own", "reason": "", "courier_gold": 2, "filing_gold": 0, "reserved_gold": 7, "cooldown_days": 0, "effects_text": "+8 morale", "local": false}]}]}, 1)
	assert_string_contains(panel.get_node("%OrderDetails").text, "2 gold")
	assert_string_contains(panel.get_node("%OrderDetails").text, "7 gold")
	assert_string_contains(panel.get_node("%Summary").text, "pending")
	watch_signals(panel)
	panel.get_node("%Send").pressed.emit()
	assert_signal_emitted_with_parameters(panel, "order_requested", ["own", 1, "inspire"])

func test_fourth_authored_choice_is_reachable() -> void:
	var panel: Control = load("res://scenes/panels/battle_panel.tscn").instantiate()
	add_child_autofree(panel)
	var options: Array = []
	for i: int in 4:
		options.append({"id":str(i), "label":"Choice " + str(i), "legal":i == 3, "reason":"Unavailable" if i < 3 else ""})
	panel.show_view({"decision":{"kind":"battle_event", "token":"terminal", "options":options}})
	var buttons := panel.get_node("%Choices").get_children()
	assert_gte(buttons.size(), 4, "All authored choices must have an editor-authored slot")
	if buttons.size() < 4: return
	var fourth: Button = panel.get_node("%Choice4")
	assert_true(fourth.is_visible_in_tree())
	assert_false(fourth.disabled)
	watch_signals(panel)
	fourth.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "decision_selected", ["terminal", "3"])
