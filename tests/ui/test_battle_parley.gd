extends GutTest

func test_encounter_displays_frozen_clauses_without_renegotiation() -> void:
	var panel: BattleEncounterPanel = load("res://scenes/panels/battle_encounter_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.show_decision({"token": "1:encounter:5"}, "the field", {"agreements": "Herald safety — agreed: protect (received A v2 / D v3)"})
	assert_true(String(panel.get_node("%Summary").text).contains("received A v2 / D v3"))
	assert_false(String(panel.get_node("%Summary").text).contains("renegotiate"))
	var scroll: ScrollContainer = panel.get_node("Center/Window/Body/ClauseScroll")
	assert_true(scroll.is_ancestor_of(panel.get_node("%Summary")))

func test_formation_diagram_draws_the_strength_tier_never_a_battle_formation() -> void:
	var dots := WarFormationDots.new()
	add_child_autofree(dots)
	dots.set_meta("figures", 9)
	dots.set_meta("formation", "wedge")
	var tier: Array = []
	for row: Dictionary in Game.data.army_formations:
		if int(row["figures"]) == 9:
			tier = row["slots"]
	assert_eq(dots.deployment_slots(), tier)

func test_the_encounter_panel_has_no_formation_controls() -> void:
	var panel: BattleEncounterPanel = load("res://scenes/panels/battle_encounter_panel.tscn").instantiate()
	add_child_autofree(panel)
	for name: String in ["%FormationChoice", "%FormationSend", "%FormationStatus"]:
		assert_null(panel.get_node_or_null(name), name)
