extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The way round ground a column cannot climb (spec 2026-10-10-march-slope-
## detour; owner: 山坡斜度超过一定限制，军队必须走最近的绕道). Hand-built grids:
## a cell holds its steepest rise per run in hundredths, 255 water; a cell
## steeper than army_max_slope (per mille) is closed.

var repo: DataRepository


func before_all() -> void:
	# the march's own pace held flat and dry, so a day count is the road's length
	repo = SuiteData.flat_ground(SuiteData.repo())
	repo.balance["army_march_grid_px"] = 4   # flat_ground walks straight; this file is the detour
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


func after_each() -> void:
	MarchPath.forget()


## `cols` x `rows` cells of 1 km, every cell `ground` but those in `walls`.
func _grid(cols: int, rows: int, ground: int, walls: Array, wall: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(cols * rows)
	bytes.fill(ground)
	for c: Vector2i in walls:
		bytes[c.y * cols + c.x] = wall
	return MarchPath.build(repo, cols, rows, 1000, bytes)


## A wall down column 4 of a 9 x 5 grid, open only in the bottom row.
func _gap_wall(wall: int) -> MarchPath:
	return _grid(9, 5, 20, [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)], wall)


## From cell (1, 2)'s centre to cell (7, 2)'s across the wall: the straight
## line meets (4, 2). The only way is the gap (4, 4). From (1500, 2500) the
## line to the gap's centre (4500, 4500) enters column 4 at y = 2500 + 2500 x
## 2000 / 3000 = 4167, in the gap's row; to any cell past it, column 4 is
## crossed above y 4000 — a closed cell. So the road is pulled taut to the
## gap's centre, and from there the end is in sight (it leaves column 4 at
## y = 4500 - 500 x 2000 / 3000 = 4167, the gap's row again).
func test_a_march_across_a_scarp_goes_round_by_its_gap() -> void:
	var g := _gap_wall(150)   # 1.5 rise per run: steeper than army_max_slope (1000 per mille)
	assert_false(g.clear(Vector2i(1500, 2500), Vector2i(7500, 2500)), "the straight line meets the scarp")
	assert_eq(g.road(Vector2i(1500, 2500), Vector2i(7500, 2500)), [Vector2i(4500, 4500), Vector2i(7500, 2500)])


func test_a_gentle_slope_is_walked_straight() -> void:
	var g := _gap_wall(90)    # 0.9 rise per run: under the limit
	assert_true(g.clear(Vector2i(1500, 2500), Vector2i(7500, 2500)))
	assert_eq(g.road(Vector2i(1500, 2500), Vector2i(7500, 2500)), [Vector2i(7500, 2500)], "no detour")


## army_max_slope 1000 per mille is 100 hundredths: 100 itself is walked, 101 is not.
func test_the_limit_itself_is_climbed_and_one_past_it_is_not() -> void:
	assert_false(_gap_wall(100).is_closed(Vector2i(4, 2)))
	assert_true(_gap_wall(101).is_closed(Vector2i(4, 2)))
	assert_true(_gap_wall(MarchPath.WATER).is_closed(Vector2i(4, 2)), "water")


## With no way round (the gap closed too) the column walks the straight line.
func test_no_way_round_walks_the_straight_line() -> void:
	var g := _grid(9, 5, 20, [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4)], 255)
	assert_eq(g.road(Vector2i(1500, 2500), Vector2i(7500, 2500)), [Vector2i(7500, 2500)])


## A column standing ON a closed cell (a town on a scarp) may leave it, and
## one sent onto one may reach it: the ends' own cells never block.
func test_the_ends_own_cells_never_block() -> void:
	var g := _grid(9, 5, 20, [Vector2i(1, 2), Vector2i(7, 2)], 200)
	assert_eq(g.road(Vector2i(1500, 2500), Vector2i(7500, 2500)), [Vector2i(7500, 2500)])


func test_the_same_ends_give_the_same_road_on_a_new_grid() -> void:
	var a := _gap_wall(150).road(Vector2i(1200, 300), Vector2i(8100, 700))
	var b := _gap_wall(150).road(Vector2i(1200, 300), Vector2i(8100, 700))
	assert_eq(a, b)
	assert_gt(a.size(), 1, "it goes round")


## Every leg of a road is in sight of the next: no leg crosses a closed cell
## but the ends'; and its length is the way through the gap.
func test_every_leg_of_the_road_is_clear() -> void:
	var g := _gap_wall(150)
	var from := Vector2i(500, 500)
	var to := Vector2i(8500, 500)
	var road := g.road(from, to)
	var prev := from
	for p: Vector2i in road:
		assert_true(g.clear(prev, p, [g.cell_of(from), g.cell_of(to)]), "%s -> %s" % [prev, p])
		prev = p
	assert_eq(road.back(), to)
	# no shorter than the taut string round the gap's corners (4000, 4000) and
	# (5000, 4000): 2 x 4950 + 1000 = 10900 m; no longer than by the gap's
	# centre and back with a cell to spare: 2 x 5657 + 1000
	assert_between(MarchRoute.length_from(from, road), 10900.0, 12314.0)


## --- the march (ArmySystem) on a hand-built grid over the pack ---------------

func _marcher() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


func _here_m(s: GameState, code: String) -> Vector2i:
	return Vector2i(int(s.regiments[code]["x_m"]), int(s.regiments[code]["y_m"]))


## A pack-wide grid of the bake's own cells, all gentle, with a scarp of 11
## cells three cells east of the column (and the pack's measure).
func _pack_grid(s: GameState, code: String) -> MarchPath:
	var px := int(repo.bal("army_march_grid_px"))
	var cols := int(ceil(float(repo.map_info["width"]) / float(px)))
	var rows := int(ceil(float(repo.map_info["height"]) / float(px)))
	var cell_m := px * ArmySystem.metres_per_pack_px(repo)
	var bytes := PackedByteArray()
	bytes.resize(cols * rows)
	bytes.fill(30)
	var c: Vector2i = _here_m(s, code) / cell_m
	for y in range(c.y - 5, c.y + 6):
		bytes[y * cols + c.x + 3] = 180
	var g := MarchPath.build(repo, cols, rows, cell_m, bytes)
	MarchPath.use(repo, g)
	return g


func test_a_straight_order_across_a_scarp_keeps_the_road_round_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var g := _pack_grid(s, code)
	var h := _here_m(s, code)
	var dest := h + Vector2i(6 * g.cell_m, 0)
	ArmySystem.set_march(repo, s, code, ArmySystem.metres_to_pack(repo, dest))
	var route := MarchRoute.from_pairs(s.regiments[code]["route_m"])
	assert_eq(route, g.road(h, dest), "the road MarchPath gives")
	assert_false(s.regiments[code].has("waypoints_m"), "no waypoints of its own")
	var far := 0
	for p: Vector2i in route:
		far = maxi(far, absi(p.y - h.y))
	assert_gt(far, 4 * g.cell_m, "it goes round the scarp's end")
	assert_eq(ArmySystem.route_px(repo, s, code).size(), route.size(), "the maps draw the road it walks")
	assert_eq(ArmySystem.curve_px(repo, ArmySystem.metres_to_pack(repo, h), [], ArmySystem.metres_to_pack(repo, dest)).size(),
		route.size() + 1, "the plan draws it before it is sent")


func test_the_days_promised_are_the_days_walked_round_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var g := _pack_grid(s, code)
	var h := _here_m(s, code)
	var dest := h + Vector2i(6 * g.cell_m, 0)
	var promised := ArmySystem.march_days_between(repo, s, code, ArmySystem.metres_to_pack(repo, h),
		ArmySystem.metres_to_pack(repo, dest))
	MarchPath.use(repo, null)   # open country: the straight line
	var straight := ArmySystem.march_days_between(repo, s, code, ArmySystem.metres_to_pack(repo, h),
		ArmySystem.metres_to_pack(repo, dest))
	MarchPath.use(repo, g)
	assert_gt(promised, straight, "the way round is longer")
	ArmySystem.set_march(repo, s, code, ArmySystem.metres_to_pack(repo, dest))
	var days := 0
	while days < 60:
		days += 1
		if ArmySystem.march_day(repo, s).has(code):
			break
	assert_eq(days, promised, "it arrives on the day it was promised")


func test_the_road_round_survives_the_save() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var g := _pack_grid(s, code)
	ArmySystem.set_march(repo, s, code, ArmySystem.metres_to_pack(repo, _here_m(s, code) + Vector2i(6 * g.cell_m, 0)))
	ArmySystem.march_day(repo, s)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(MarchRoute.from_pairs(loaded.regiments[code]["route_m"]), MarchRoute.from_pairs(s.regiments[code]["route_m"]))
	ArmySystem.march_day(repo, s)
	ArmySystem.march_day(repo, loaded)
	assert_eq(_here_m(loaded, code), _here_m(s, code), "the same next day")


## A waypoint leg across the scarp goes round it; the waypoint stays on the road.
func test_a_waypoint_leg_across_a_scarp_goes_round_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var g := _pack_grid(s, code)
	var h := _here_m(s, code)
	var wp := h + Vector2i(6 * g.cell_m, 0)
	var dest := wp + Vector2i(0, 3 * g.cell_m)
	ArmySystem.set_march(repo, s, code, ArmySystem.metres_to_pack(repo, dest), [ArmySystem.metres_to_pack(repo, wp)])
	var route := MarchRoute.from_pairs(s.regiments[code]["route_m"])
	var at := route.find(wp)
	assert_gt(at, 0, "the waypoint is on the road")
	assert_eq(route.slice(0, at + 1), g.road(h, wp), "its first leg goes round")
	assert_eq(route.back(), dest)


## A foe re-aimed every day at the same end keeps the road it walks.
func test_aim_entry_keeps_the_road_to_the_same_end() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var g := _pack_grid(s, code)
	var e: Dictionary = (s.regiments[code] as Dictionary).duplicate(true)
	var to := _here_m(s, code) + Vector2i(6 * g.cell_m, 0)
	ArmySystem.aim_entry(repo, e, to)
	var first: Array = e["route_m"]
	assert_eq(MarchRoute.from_pairs(first), g.road(_here_m(s, code), to))
	ArmySystem.aim_entry(repo, e, to)
	assert_true(is_same(e["route_m"], first), "not searched again")
	ArmySystem.aim_entry(repo, e, _here_m(s, code) + Vector2i(0, g.cell_m))
	assert_false(e.has("route_m"), "a new end in plain sight walks straight")


## The 3D piece walks its day along the route's corners, by length.
func test_along_walks_a_polyline_by_length() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)])
	assert_eq(MarchRoute.along(pts, 0.0), Vector2(0, 0))
	assert_eq(MarchRoute.along(pts, 0.5), Vector2(3, 0.5), "3.5 of 7: round the corner")
	assert_eq(MarchRoute.along(pts, 1.0), Vector2(3, 4))


## The pack's own grid: baked (bake_march_grid.py) to the pack's size, some
## cells closed, most of the land open.
func test_the_pack_has_its_march_grid() -> void:
	var g := MarchPath.of_pack(repo)
	assert_not_null(g, "data/maps/<pack>/geography/march_grid.png, built by build_pack.sh")
	if g == null:
		return
	var px := int(repo.bal("army_march_grid_px"))
	assert_eq(g.cols, int(ceil(float(repo.map_info["width"]) / float(px))))
	assert_eq(g.rows, int(ceil(float(repo.map_info["height"]) / float(px))))
	var shut := 0
	for c in g.closed:
		shut += c
	assert_between(shut, 1, g.closed.size() - 1)
