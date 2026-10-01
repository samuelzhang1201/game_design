# tests/engine/test_ledger_schema.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The ontology is checked as data (spec 2026-09-30 §7.2, §9).

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()
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
	data.ledger_links.append({"link_id": "z", "from_type": "regiment", "to_type": "enemy_host", "verb": "v",
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


func test_every_type_has_a_known_cluster() -> void:
	var clusters := {}
	for c: Dictionary in data.ledger_clusters:
		clusters[String(c["cluster"])] = c
	for want in ["economy", "war", "court", "intelligence"]:
		assert_true(clusters.has(want), want)
	for r: Dictionary in data.ledger_types:
		assert_true(clusters.has(String(r["cluster"])), "%s: cluster %s" % [r["type_id"], r["cluster"]])


func test_the_economy_folds_manors_buildings_and_towns_into_provinces() -> void:
	for r: Dictionary in data.ledger_types:
		var id := String(r["type_id"])
		var want := "province" if id in ["manor", "building", "town"] else ""
		assert_eq(String(r["fold_to"]), want, id)
	assert_eq(String(Ledger.type_row(data, "province")["cluster"]), "economy", "owner: economy by province")


func test_every_type_says_how_its_star_is_sized_and_every_link_how_it_is_drawn() -> void:
	for r: Dictionary in data.ledger_types:
		assert_true(String(r["star"]) in ["pool", "instance"], "%s: star %s" % [r["type_id"], r["star"]])
	for r: Dictionary in data.ledger_links:
		assert_true(String(r["look"]) in ["flow", "tie", "kin", "structure"], "%s: look %s" % [r["link_id"], r["look"]])
	assert_eq(String(Ledger.link_row(data, "kin")["look"]), "kin")
	assert_eq(String(Ledger.link_row(data, "rival")["look"]), "tie")
	assert_eq(String(Ledger.link_row(data, "yields_civil")["look"]), "flow")


func test_a_cluster_anchor_is_read_as_vectors() -> void:
	var c: Dictionary = data.ledger_clusters[0]
	assert_true(c["at"] is Vector3)
	assert_false(c.has("at2"), "no 2D anchor: the flat view was removed (owner 2026-10-01)")
	assert_true(data.ledger_palette.has(String(c["colour"])), "its colour is a palette key")


func test_validate_names_an_unknown_cluster() -> void:
	var r: Dictionary = data.ledger_types[0]
	var was := String(r["cluster"])
	r["cluster"] = "astrology"
	assert_has(Ledger.validate(data), "%s: unknown cluster astrology" % r["type_id"])
	r["cluster"] = was
