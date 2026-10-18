extends GutTest

func test_encounter_displays_frozen_clauses_without_renegotiation() -> void:
	var panel: BattleEncounterPanel = load("res://scenes/panels/battle_encounter_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.show_decision({"token": "1:encounter:5"}, "the field", {"agreements": "Herald safety — agreed: protect (received A v2 / D v3)"})
	assert_true(String(panel.get_node("%Summary").text).contains("received A v2 / D v3"))
	assert_false(String(panel.get_node("%Summary").text).contains("renegotiate"))
	var scroll: ScrollContainer = panel.get_node("Center/Window/Body/ClauseScroll")
	assert_true(scroll.is_ancestor_of(panel.get_node("%Summary")))

func test_formation_diagram_reads_the_battle_formation() -> void:
	var dots := WarFormationDots.new()
	add_child_autofree(dots)
	dots.set_meta("figures", 9)
	dots.set_meta("formation", "wedge")
	assert_eq(dots.deployment_slots(), BattleFormation.slots("wedge", 9))

func test_diamond_option_explains_absent_centre() -> void:
	var panel: BattleEncounterPanel = load("res://scenes/panels/battle_encounter_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.show_decision({"token": "1:encounter:6"}, "the field", {"gold": 1, "courier_gold": 2,
		"options": [{"id": "diamond", "label": "Diamond guard", "reason": "", "note": "Insufficient benefit: no real centre."}]})
	assert_true(String(panel.get_node("%FormationStatus").text).contains("no real centre"))
