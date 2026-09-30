extends GutTest
## The LEDGER's ontology is data (spec 2026-09-30-ledger-ontology-design §7.1).

var data: DataRepository

func before_all() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)

func test_the_tables_load_in_file_order() -> void:
	assert_eq(String(data.ledger_lenses[0]["lens"]), "economy")
	assert_gt(data.ledger_types.size(), 20)
	assert_gt(data.ledger_links.size(), 30)
	assert_gt(data.ledger_actions.size(), 5)
	assert_gt(data.ledger_loops.size(), 0)

func test_a_type_row_carries_its_place_and_layer() -> void:
	var row: Dictionary = {}
	for r: Dictionary in data.ledger_types:
		if String(r["type_id"]) == "regiment":
			row = r
	assert_eq(String(row["layer"]), "things")
	assert_eq(float(row["x"]), 9.0)
	assert_eq(String(row["instances"]), "regiments")

func test_every_court_relation_type_has_a_link_row() -> void:
	var links := {}
	for r: Dictionary in data.ledger_links:
		links[String(r["link_id"])] = r
	for e: Dictionary in data.relationships:
		var t := String(e["rel_type"])
		assert_true(links.has(t), "relationships.csv type %s has a ledger link row" % t)
		assert_eq(String(links[t]["resolver"]), "court_relations")

func test_the_palette_is_colours() -> void:
	assert_true(data.ledger_palette["thread_live"] is Color)
	assert_true(data.ledger_palette.has("background"))

func test_the_look_numbers_are_balance() -> void:
	for key in ["ledger_layer_gap_m", "ledger_instance_cap", "ledger_camera_distance",
			"ledger_layout_iterations", "ledger_thread_width_max"]:
		assert_true(data.balance.has(key), key)

## Final fix I3: an order that needs the map promises only what it does —
## it shows the place on the map; the order itself is given there.
func test_an_order_that_needs_the_map_says_it_shows_the_map() -> void:
	for a: Dictionary in data.ledger_actions:
		if String(a["needs_map"]) == "1":
			assert_true(String(a["label"]).begins_with("Show on the map to "), String(a["label"]))
