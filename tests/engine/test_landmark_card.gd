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
