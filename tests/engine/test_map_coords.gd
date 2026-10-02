extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The pack's own graticule (spec 2026-10-02-war-room-v2 §2.1): pack px to
## longitude and latitude from map_info's mapCoordinates rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	repo.map_info["width"] = "2000"
	repo.map_info["height"] = "1000"
	repo.map_info["lat_n"] = "60"
	repo.map_info["lat_s"] = "-40"
	repo.map_info["lon_w"] = "-100"
	repo.map_info["lon_e"] = "100"


func test_the_corners_and_the_middle() -> void:
	assert_eq(MapCoords.px_per_deg(repo), Vector2(10.0, 10.0))
	assert_eq(MapCoords.lon_lat(repo, Vector2.ZERO), Vector2(-100.0, 60.0), "north-west corner")
	assert_eq(MapCoords.lon_lat(repo, Vector2(2000, 1000)), Vector2(100.0, -40.0), "south-east corner")
	assert_eq(MapCoords.px_of(repo, 0.0, 0.0), Vector2(1000.0, 600.0))


func test_cells_count_from_the_north_west_corner() -> void:
	assert_eq(MapCoords.cell_of(repo, Vector2(250, 150), 20.0), Vector2i(1, 0))
	assert_eq(MapCoords.cell_rect(repo, Vector2i(1, 0), 20.0), Rect2(200, 0, 200, 200))
	assert_eq(MapCoords.grid_size(repo, 20.0), Vector2i(10, 5))
	assert_eq(MapCoords.grid_size(repo, 30.0), Vector2i(7, 4), "a part cell at the edge still counts")


func test_format_rounds_to_whole_degrees() -> void:
	assert_eq(MapCoords.format(Vector2(51.4, 23.6)), "24°N 51°E")
	assert_eq(MapCoords.format(Vector2(-12.5, -3.2)), "3°S 13°W")
	assert_eq(MapCoords.format(Vector2(0.2, -0.2)), "0°N 0°E")


func test_a_pack_without_coordinates_spans_the_globe() -> void:
	for k in ["lat_n", "lat_s", "lon_w", "lon_e"]:
		repo.map_info.erase(k)
	var b := MapCoords.bounds(repo)
	assert_eq([b["lat_n"], b["lat_s"], b["lon_w"], b["lon_e"]], [90.0, -90.0, -180.0, 180.0])


func test_the_pack_carries_its_coordinates() -> void:
	var real := SuiteData.repo()
	for k in ["lat_n", "lat_s", "lon_w", "lon_e"]:
		assert_true(real.map_info.has(k), k)
