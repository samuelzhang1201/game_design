extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## How a courier goes off the road network and along rivers (owner 2026-10-11:
## he goes round slopes like a march, crosses water, takes rivers at 80% of
## road pace). Fixtures in pack px on beria's measure (1 px = 1000 m); every
## height tier is forced to 1000 so the hand sums hold.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	RoadGraph.forget()
	MarchPath.forget()
	repo.road_speed = {"road": 1000, "trail": 800, "offroad": 500, "river": 800, "sea": 800,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	repo.balance["courier_graph_snap_px"] = 2.0
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == "clear" else 0
		repo.weather_odds[key] = w
	Weather.forget()


func after_each() -> void:
	RoadGraph.forget()
	MarchPath.forget()


func _grid(cols: int, rows: int, ground: int, cells: Array, value: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(cols * rows)
	bytes.fill(ground)
	for c: Vector2i in cells:
		bytes[c.y * cols + c.x] = value
	return MarchPath.build(repo, cols, rows, 1000, bytes, true)


func _gap_wall(wall: int) -> MarchPath:
	return _grid(9, 5, 20, [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)], wall)


## 8 x 3 cells of 1 km, water at (3, 1) and (4, 1): along y = 1500 the leg is
## land 500..3000, water 3000..5000, land 5000..7500. Land at offroad 500:
## 2500 m x 1000 / 500 = 5000 and 2500 m -> 5000; water at sea 800: 2000 m x
## 1000 / 800 = 2500. In all 12,500 clear-road metres.
func test_a_leg_over_water_rides_at_the_water_s_pace() -> void:
	var g := _grid(8, 3, 20, [Vector2i(3, 1), Vector2i(4, 1)], MarchPath.WATER)
	var way := RoadGraph.across(repo, g, Vector2i(500, 1500), Vector2i(7500, 1500))
	assert_eq(way, [[3000, 1500, "offroad"], [5000, 1500, "sea"], [7500, 1500, "offroad"]])
	var s := SuiteData.campaign(repo, 7)
	assert_eq(CourierSystem.need_along(repo, s, Vector2i(500, 1500), way, 10), 5000 + 2500 + 5000)


## A road along a river: the drawn road (0, 0) -> (10, 0), then the river
## (10, 0) -> (10, 10) -> (20, 10), no grid.
func test_a_courier_rides_the_river() -> void:
	repo.balance["army_march_grid_px"] = 0
	repo.routes = {"r1": {"group": "roads", "polyline": PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])}}
	repo.rivers = {"rv": {"polyline": PackedVector2Array([Vector2(10, 0), Vector2(10, 10), Vector2(20, 10)])}}
	RoadGraph.forget()
	var path := CourierSystem.path_between(repo, Vector2(0, 0), Vector2(20, 10))
	assert_eq(path, [[10000, 0, "road"], [10000, 10000, "river"], [20000, 10000, "river"], [20000, 10000, "offroad"]])


## His last leg follows the column round a scarp: the column (7500, 2500)
## across the wall from his road's end, the tail is planned afresh.
func test_his_last_leg_goes_round_a_scarp_to_the_moved_column() -> void:
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, _gap_wall(150), true)
	var s := SuiteData.campaign(repo, 7)
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	(s.regiments[code] as Dictionary)["x_m"] = 7500
	(s.regiments[code] as Dictionary)["y_m"] = 2500
	var reg := ArmySystem.regiment(repo, code, s)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, reg)), Vector2i(7500, 2500))
	var c := {"id": 1, "kind": "ordinary", "x_m": 500, "y_m": 2500,
		"path": [[1500, 2500, "road"], [3500, 2500, "offroad"]], "aim_x_m": 3500, "aim_y_m": 2500}
	CourierSystem._reaim(repo, s, c, reg)
	assert_eq(c["path"], [[1500, 2500, "road"], [4500, 4500, "offroad"], [7500, 2500, "offroad"]])
	assert_eq(Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"])), Vector2i(7500, 2500))
