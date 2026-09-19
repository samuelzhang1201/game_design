extends GutTest
## A landmark's words (spec 2026-09-19-map3d-heights-design §4): its name,
## height, tier and biome, where it is and who holds it, and what it means
## for a garrison and a fight.

func before_each() -> void:
	Game.start_campaign(42)

func test_the_lines_of_the_highest_landmark() -> void:
	var m: Dictionary = Elevation.landmarks(Game.data)[0]
	var id := int(m["cell"])
	var lines := MapObjects.landmark_lines(Game.data, Game.state, id)
	var tier := Elevation.tier_of(Game.data, float(Game.data.cells[id]["height"]))
	assert_string_contains(lines[0], "%d m" % int(m["metres"]))
	assert_string_contains(lines[0], String(tier["tier"]).capitalize())
	var province := MapManors.province_of(Game.data, id, Game.state)
	assert_string_contains(lines[1], String(Game.data.provinces[province].get("label", province)))
	assert_string_contains(lines[2], "×%.1f" % (float(int(tier["supply_permille"])) / 1000.0))
	var edge := Elevation.local_edge_m(Game.data, id)
	var pct := (ArmySystem.height_factor(Game.data, absi(edge)) - 1000) / 10
	assert_string_contains(lines[3], "%d m" % absi(edge))
	assert_string_contains(lines[3], "%d%%" % pct)

func test_the_hover_text_starts_with_the_name() -> void:
	var m: Dictionary = Elevation.landmarks(Game.data)[0]
	var text := MapObjects.label_of(Game.data, {"kind": "landmark", "cell": int(m["cell"])})
	assert_true(text.begins_with(String(m["name"]) + "\n"))

## The where/holder line never doubles up a name it already carries, and
## never opens with a bare " — " when there is nothing to name before it.
func test_the_where_line_collapses_a_shared_name() -> void:
	assert_eq(MapObjects._landmark_where_line("Wickhampia", "Wickhampia"), "Wickhampia",
		"a house that wears the province's own name is not repeated")
	assert_eq(MapObjects._landmark_where_line("", "House Ward"), "House Ward",
		"no province to name, but a holder still reads — no leading dash")
	assert_eq(MapObjects._landmark_where_line("Harhamburgh", ""), "Harhamburgh",
		"no holder at all — just the province")
	assert_eq(MapObjects._landmark_where_line("Harhamburgh", "House Ward"),
		"Harhamburgh — House Ward", "the ordinary case is unchanged")

## Proved against the real pack too, wherever an unmoved manor's landmark
## reads as its own province's house.
func test_the_where_line_never_doubles_on_the_pack() -> void:
	var found_a_case := false
	for m: Dictionary in Elevation.landmarks(Game.data):
		var lines := MapObjects.landmark_lines(Game.data, Game.state, int(m["cell"]))
		var where_line := String(lines[1])
		var parts := where_line.split(" — ")
		if parts.size() == 2 and parts[0] == parts[1]:
			found_a_case = true
			fail_test("%s repeats itself: %s" % [String(m["name"]), where_line])
	assert_false(found_a_case)
