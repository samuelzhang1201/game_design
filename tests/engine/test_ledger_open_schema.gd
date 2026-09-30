# tests/engine/test_ledger_open_schema.gd
extends GutTest
## The owner adds, changes or removes nodes and edges at any time, in data
## (spec 2026-09-30-ledger-galaxy-design §3b): a new type, a new link type,
## single nodes and edges written down — with no code.

var data: DataRepository
var s: GameState


func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()


func after_each() -> void:
	RealmEconomy.forget()


func _add_shrines() -> void:
	data.ledger_types.append({"type_id": "shrine", "layer": "things", "lenses": "economy|all", "label": "Shrines",
		"icon": "", "x": "0", "z": "0", "instances": "static", "status": "live", "milestone": "",
		"cluster": "court", "fold_to": "", "star": "instance"})
	data.ledger_links.append({"link_id": "venerates", "from_type": "character", "to_type": "shrine",
		"verb": "venerates", "lenses": "court|all", "status": "live", "resolver": "static", "governor_seat": "",
		"governor_kind": "", "milestone": "", "planned_note": "", "look": "tie"})
	data.ledger_static_nodes.append({"node_id": "shrine:saint_odo", "type_id": "shrine", "label": "Shrine of St Odo",
		"note": "Pilgrims leave coin here."})
	data.ledger_static_nodes.append({"node_id": "shrine:old_oak", "type_id": "shrine", "label": "The Old Oak",
		"note": "Older than the realm."})
	data.ledger_static_links.append({"link_id": "venerates", "from": "character:you", "to": "shrine:saint_odo",
		"flow": 40, "note": ""})


func _has(g: Dictionary, key: String, id: String) -> bool:
	for x: Dictionary in g[key]:
		if String(x["id"]) == id:
			return true
	return false


func test_a_type_and_its_nodes_written_down_appear_with_no_code() -> void:
	_add_shrines()
	assert_eq(Ledger.validate(data), [] as Array[String], "the added rows validate")
	var g := Ledger.galaxy(data, s, {})
	assert_true(_has(g, "nodes", "shrine:saint_odo") and _has(g, "nodes", "shrine:old_oak"))
	assert_true(_has(g, "links", "venerates|character:you|shrine:saint_odo"))
	for n: Dictionary in g["nodes"]:
		if String(n["id"]) == "shrine:saint_odo":
			assert_eq(String(n["cluster"]), "court")
			assert_eq(String(n["label"]), "Shrine of St Odo")


func test_changing_a_row_changes_the_node_and_the_edge() -> void:
	_add_shrines()
	data.ledger_static_nodes[-2]["label"] = "Shrine of St Odo the Younger"
	data.ledger_static_links[-1]["flow"] = 55
	var g := Ledger.galaxy(data, s, {})
	for n: Dictionary in g["nodes"]:
		if String(n["id"]) == "shrine:saint_odo":
			assert_eq(String(n["label"]), "Shrine of St Odo the Younger")
	for l: Dictionary in g["links"]:
		if String(l["id"]) == "venerates|character:you|shrine:saint_odo":
			assert_eq(int(l["flow"]), 55)


func test_removing_the_rows_removes_them() -> void:
	_add_shrines()
	data.ledger_static_links.pop_back()
	data.ledger_static_nodes.pop_back()
	var g := Ledger.galaxy(data, s, {})
	assert_false(_has(g, "links", "venerates|character:you|shrine:saint_odo"), "the edge's row is gone")
	assert_false(_has(g, "nodes", "shrine:old_oak"), "the node's row is gone")
	assert_true(_has(g, "nodes", "shrine:saint_odo"), "the other stays")


func test_an_edge_to_someone_who_no_longer_exists_is_not_drawn() -> void:
	_add_shrines()
	data.ledger_static_links.append({"link_id": "venerates", "from": "character:nobody", "to": "shrine:old_oak",
		"flow": 5, "note": ""})
	var g := Ledger.galaxy(data, s, {})
	assert_false(_has(g, "nodes", "character:nobody"))
	assert_false(_has(g, "links", "venerates|character:nobody|shrine:old_oak"))


func test_validate_names_a_row_pointing_at_nothing() -> void:
	data.ledger_static_nodes.append({"node_id": "idol:gold", "type_id": "idol", "label": "Idol", "note": ""})
	data.ledger_static_links.append({"link_id": "worships", "from": "character:you", "to": "idol:gold",
		"flow": -1, "note": ""})
	var errors := Ledger.validate(data)
	assert_has(errors, "static node idol:gold: unknown type idol")
	assert_has(errors, "static link worships: unknown link type")


func test_a_static_node_has_a_card() -> void:
	_add_shrines()
	var g := Ledger.galaxy(data, s, {})
	var card := LedgerCards.entry(data, s, "shrine:saint_odo", g)
	assert_eq(String(card["title"]), "Shrine of St Odo")
	assert_has(card["lines"], "Pilgrims leave coin here.")
