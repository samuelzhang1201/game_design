extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The supply lines on the war room's table (owner 2026-10-07: 实心的金色线，带流动感，
## 实时跟随军队移动): only our FLOWING lines, ending where the piece stands now.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func _land_codes() -> Array:
	var out: Array = []
	for c in state.regiments.keys():
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out


func _supply_all(st: String) -> void:
	for c: String in _land_codes():
		state.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
		state.supply_lines[c]["state"] = st


func _everywhere() -> Rect2:
	return Rect2(-100000, -100000, 200000, 200000)


func test_only_our_flowing_lines_are_drawn() -> void:
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(r: Dictionary) -> String: return String(r["regiment_code"]))
	for st: String in [SupplyLines.ORDERED, SupplyLines.RIDING, SupplyLines.CUT, SupplyLines.FRONT, SupplyLines.FLOWING]:
		_supply_all(st)
		var routes := WarSupplyFlow.routes(repo, state, _everywhere())
		var broken := WarSupplyFlow.routes(repo, state, _everywhere(), SupplyLines.FRONT)
		assert_eq(broken.size() > 0, st == SupplyLines.FRONT, "only a FRONT line is drawn broken (%s)" % st)
		if st == SupplyLines.FLOWING:
			assert_gt(routes.size(), 0, "a flowing line is drawn")
			for r: Dictionary in routes:
				assert_true(String(r["code"]) in ours, "never a foreign line")
				assert_gte((r["route"] as PackedVector2Array).size(), 2)
		else:
			assert_eq(routes.size(), 0, "a %s line is not drawn" % st)


func test_a_line_runs_from_its_town_and_ends_where_the_piece_stands_now() -> void:
	_supply_all(SupplyLines.FLOWING)
	var routes := WarSupplyFlow.routes(repo, state, _everywhere())
	var r: Dictionary = routes[0]
	var route: PackedVector2Array = r["route"]
	var town := String(SupplyLines.line(state, String(r["code"]))["town"])
	assert_almost_eq(route[0].distance_to(Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))), 0.0, 0.01,
		"it starts at its town")
	var pushed := route[route.size() - 1] + Vector2(3, 4)   # the piece pushed a step on
	var lines := WarSupplyFlow.lines([r], {String(r["code"]): pushed}, _everywhere())
	var poly: PackedVector2Array = lines[0]["poly"]
	assert_almost_eq(poly[poly.size() - 1].distance_to(pushed), 0.0, 0.01, "and ends on the piece")
	var still := WarSupplyFlow.lines([r], {String(r["code"]): route[route.size() - 1]}, _everywhere())
	assert_eq((still[0]["poly"] as PackedVector2Array).size(), route.size(), "a piece where the road ends adds no step")


func test_a_line_is_clipped_to_the_sheet() -> void:
	var r := {"code": "x", "route": PackedVector2Array([Vector2(-10, 5), Vector2(5, 5), Vector2(20, 5)])}
	var lines := WarSupplyFlow.lines([r], {}, Rect2(0, 0, 10, 10))
	assert_eq(lines.size(), 1)
	for p: Vector2 in lines[0]["poly"]:
		assert_true(p.x >= -0.001 and p.x <= 10.001, "inside the sheet: %s" % p)


func test_the_ribbon_runs_its_metres_along_the_line() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.3, 0, 0), Vector3(0.3, 0, 0.4)])
	var mesh := WarSupplyFlow.ribbon([pts])
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(verts.size(), 6, "two vertices a point")
	assert_eq(verts[2], pts[1], "laid on the line; the shader widens them")
	assert_almost_eq(uvs[4].x, 0.7, 0.0001, "UV.x the metres run from the town")
	assert_eq(uvs[0].y, 0.0)
	assert_eq(uvs[1].y, 1.0)
	assert_almost_eq(normals[0].dot(Vector3(1, 0, 0)), 0.0, 0.0001, "the side is across the line")
	assert_null(WarSupplyFlow.ribbon([]), "nothing to draw")


## A broken line (owner 2026-10-11): road (0,0) -> (100,0), its piece drawn at
## (100,0); gap 20, tick 4: the dashes run (0,0) -> (80,0), the tick (80,4) to
## (80,-4). A sheet ending at x 50 keeps the dashes to 50 and draws no tick
## (the break is off the sheet).
func test_a_broken_line_stops_short_of_its_piece_with_a_tick() -> void:
	var r := {"code": "x", "route": PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])}
	var got := WarSupplyFlow.broken_lines([r], {"x": Vector2(100, 0)}, Rect2(-10, -10, 200, 20), 20.0, 4.0)
	assert_eq(got.size(), 2)
	var poly: PackedVector2Array = got[0]["poly"]
	assert_almost_eq(poly[poly.size() - 1].distance_to(Vector2(80, 0)), 0.0, 0.01, "stopped 20 short")
	var tick: PackedVector2Array = got[1]["tick"]
	assert_true(tick[0].is_equal_approx(Vector2(80, 4)) or tick[0].is_equal_approx(Vector2(80, -4)), str(tick))
	assert_almost_eq(tick[0].distance_to(tick[1]), 8.0, 0.001)
	var clipped := WarSupplyFlow.broken_lines([r], {"x": Vector2(100, 0)}, Rect2(-10, -10, 60, 20), 20.0, 4.0)
	assert_eq(clipped.size(), 1, "the break off the sheet: no tick")
	assert_false(clipped[0].has("tick"))


func test_a_tick_runs_negative_in_the_ribbon() -> void:
	var mesh := WarSupplyFlow.ribbon([PackedVector3Array([Vector3(0, 0, 0), Vector3(0.01, 0, 0)])], [-1.0])
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_lt(uvs[uvs.size() - 1].x, 0.0, "drawn whole by the dashed look")
