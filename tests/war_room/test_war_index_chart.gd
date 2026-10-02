extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The sheet index on the war room's wall: the chart's image and its pick (spec §2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()
	WarSheets.forget()


func test_the_chart_keeps_the_maps_ratio() -> void:
	var img := WarIndexChart.image(repo, 512)
	assert_eq(img.get_width(), 512)
	assert_eq(img.get_height(), int(round(512.0 * 929.0 / 2560.0)))


func test_a_uv_in_a_land_cell_picks_its_sheet_and_a_sea_cell_nothing() -> void:
	var w := float(repo.map_info["width"])
	var h := float(repo.map_info["height"])
	for s: Dictionary in WarSheets.series(repo):
		var c := (s["cell"] as Rect2).get_center() / Vector2(w, h)
		assert_eq(WarIndexChart.sheet_at_uv(repo, c), int(s["index"]), String(s["id"]))
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var taken: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		taken[Vector2i(int(s["col"]), int(s["row"]))] = true
	var sea_seen := false
	for row in g.y:
		for col in g.x:
			if sea_seen or taken.has(Vector2i(col, row)):
				continue
			var c := MapCoords.cell_rect(repo, Vector2i(col, row), deg).get_center() / Vector2(w, h)
			if c.x < 1.0 and c.y < 1.0:
				assert_eq(WarIndexChart.sheet_at_uv(repo, c), -1, "sea cell %d,%d" % [col, row])
				sea_seen = true
	assert_true(sea_seen, "the pack has a sea cell")
	assert_eq(WarIndexChart.sheet_at_uv(repo, Vector2(-0.1, 0.5)), -1)


func test_uv_of_cell_is_the_cell_over_the_map() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r := WarIndexChart.uv_of_cell(repo, s)
	var c: Rect2 = s["cell"]
	var size := Vector2(float(repo.map_info["width"]), float(repo.map_info["height"]))
	assert_eq(r, Rect2(c.position / size, c.size / size))
