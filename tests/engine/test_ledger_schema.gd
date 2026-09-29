# tests/engine/test_ledger_schema.gd
extends GutTest
## The ontology is checked as data (spec 2026-09-30 §7.2, §9).

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)

func _has(errors: Array[String], fragment: String) -> bool:
	for e in errors:
		if e.contains(fragment):
			return true
	return false

func test_the_shipped_ontology_is_clean() -> void:
	assert_eq(Ledger.validate(data), [] as Array[String])

func test_a_live_link_needs_a_reader() -> void:
	data.ledger_links.append({"link_id": "x", "from_type": "manor", "to_type": "gold", "verb": "v",
		"lenses": "all", "status": "live", "resolver": "nope", "governor_seat": "", "governor_kind": "",
		"milestone": "", "planned_note": ""})
	assert_true(_has(Ledger.validate(data), "x: live without a reader"))

func test_a_planned_link_names_its_milestone() -> void:
	data.ledger_links.append({"link_id": "y", "from_type": "manor", "to_type": "gold", "verb": "v",
		"lenses": "all", "status": "planned", "resolver": "", "governor_seat": "", "governor_kind": "",
		"milestone": "", "planned_note": ""})
	assert_true(_has(Ledger.validate(data), "y: planned without a milestone"))

func test_a_live_link_cannot_touch_a_planned_type() -> void:
	data.ledger_links.append({"link_id": "z", "from_type": "regiment", "to_type": "stronghold", "verb": "v",
		"lenses": "all", "status": "live", "resolver": "based_in", "governor_seat": "", "governor_kind": "",
		"milestone": "", "planned_note": ""})
	assert_true(_has(Ledger.validate(data), "z: live on a planned type"))

func test_an_action_must_exist_and_carry_a_cost() -> void:
	data.ledger_actions.append({"target": "manor", "action_code": "LEDGER_NOPE", "label": "", "params": "",
		"needs_map": "0"})
	assert_true(_has(Ledger.validate(data), "LEDGER_NOPE: unknown action"))

func test_unknown_lenses_layers_and_seats_are_caught() -> void:
	data.ledger_types.append({"type_id": "q", "layer": "sky", "lenses": "nowhere", "label": "Q", "icon": "",
		"x": "0", "z": "0", "instances": "", "status": "live", "milestone": ""})
	data.ledger_links.append({"link_id": "w", "from_type": "manor", "to_type": "gold", "verb": "v",
		"lenses": "all", "status": "planned", "resolver": "", "governor_seat": "jester", "governor_kind": "seat",
		"milestone": "M9", "planned_note": ""})
	var errors := Ledger.validate(data)
	assert_true(_has(errors, "q: unknown layer sky"))
	assert_true(_has(errors, "q: unknown lens nowhere"))
	assert_true(_has(errors, "w: unknown seat jester"))

func test_type_of_reads_every_id_shape() -> void:
	assert_eq(Ledger.type_of("type:regiment"), "regiment")
	assert_eq(Ledger.type_of("regiment:abc"), "regiment")
	assert_eq(Ledger.type_of("building:12:chapel"), "building")
	assert_eq(Ledger.type_of("works|peasants:a|manor:3"), "")
