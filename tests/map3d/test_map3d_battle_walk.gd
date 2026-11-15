extends GutTest

const SuiteData = preload("res://tests/suite_data.gd")
const Groups := preload("res://scripts/map3d/map3d_battle_groups.gd")
## A unit entering a battle WALKS its figures from where its block stood to
## their saved battle points (owner 2026-11-14: 进入对峙的动画非常突兀); the
## saved points themselves are never touched.


func test_a_walk_starts_where_it_stood_and_ends_on_the_saved_point() -> void:
	var from := Vector2(10, 20)
	var to := Vector2(110, 20)
	var first: Dictionary = Groups.eased(from, 1.0, to, 2.0, 0.0)
	assert_eq(first["xz"], from)
	assert_almost_eq(float(first["yaw"]), 1.0, 0.0001)
	var half: Dictionary = Groups.eased(from, 1.0, to, 2.0, 0.5)
	assert_eq(half["xz"], Vector2(60, 20), "halfway there at half the time")
	assert_almost_eq(float(half["yaw"]), Map3DUnits.facing_yaw(to - from), 0.0001, "it faces the way it walks")
	var last: Dictionary = Groups.eased(from, 1.0, to, 2.0, 1.0)
	assert_eq(last["xz"], to)
	assert_almost_eq(float(last["yaw"]), 2.0, 0.0001, "it ends on its saved facing")
	assert_eq(Groups.eased(to, 1.0, to, 2.0, 0.5)["xz"], to, "a group already on its point only turns")


func test_lanes_pair_starts_and_targets_along_the_front_without_crossing() -> void:
	var across := Vector2(1, 0)
	var starts := [{"xz": Vector2(5, 0)}, {"xz": Vector2(-5, 0)}]
	var targets := [{"xz": Vector2(-40, 30)}, {"xz": Vector2(40, 30)}, {"xz": Vector2(0, 30)}]
	var paired := Groups.lanes(starts, targets, across)
	# along the front the targets run -40, 0, 40 and the starts -5, 5: shares 0, 0, 1 (k * 2 / 3)
	assert_eq(paired[0]["xz"], Vector2(-5, 0), "the leftmost target walks from the leftmost start")
	assert_eq(paired[2]["xz"], Vector2(-5, 0))
	assert_eq(paired[1]["xz"], Vector2(5, 0), "the rightmost from the rightmost")
	# the way is (0, 90) summed, so a lane leads by its start's y, then its target's: the start
	# at y 0 is shared, so the tie falls to the targets (all y 30), then the sort's order —
	# every lane gets one of 0, .2, .4 (FILE_OUT .4 over three lanes), each once
	var delays: Array = paired.map(func(p: Dictionary) -> float: return snappedf(float(p["delay"]), 0.0001))
	delays.sort()
	assert_eq(delays, [0.0, 0.2, 0.4], "the lanes file out, the last 0.4 of the walk after the first")


func test_the_rider_furthest_along_the_way_files_out_first() -> void:
	var starts := [{"xz": Vector2(0, 0)}, {"xz": Vector2(0, 10)}]   # the unit walks toward +y
	var targets := [{"xz": Vector2(-1, 100)}, {"xz": Vector2(1, 100)}]
	var paired := Groups.lanes(starts, targets, Vector2(1, 0))
	var by_start := {}
	for p: Dictionary in paired: by_start[p["xz"]] = float(p["delay"])
	assert_almost_eq(float(by_start[Vector2(0, 10)]), 0.0, 0.0001, "the one ahead goes first")
	assert_almost_eq(float(by_start[Vector2(0, 0)]), 0.4, 0.0001, "the one behind waits its turn")


func test_entering_a_battle_walks_the_figures_in() -> void:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := preload("res://tests/fixtures/battle_scenario.gd").contact(repo, 10)
	var foe := String(state.foes.keys()[0])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	var here := ctx.to_world(ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, foe, state)))
	ctx.camera.position = Vector3(here.x, 500, here.y + 500)
	ctx.camera.look_at(Vector3(here.x, 0, here.y))
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	layer.shown = true
	layer.refresh()
	var block: Dictionary = layer.built_piece(foe)
	assert_ne(block.get("layout", ""), "physical_groups")
	var stood: Array = (block["figs"] as Array).map(func(fig: Node3D) -> Vector2: return Vector2(fig.global_position.x, fig.global_position.z))
	assert_false(BattleSystem.discover_contacts(repo, state).is_empty(), "real contact starts the encounter")
	var frozen := SaveLoad.state_hash(state)
	layer.refresh()
	var piece: Dictionary = layer.built_piece(foe)
	assert_eq(piece.get("layout", ""), "physical_groups")
	var node: Node3D = piece["groups"][0]["piece"]["node"]
	var at := Vector2(node.global_position.x, node.global_position.z)
	assert_true(stood.any(func(xz: Vector2) -> bool: return xz.distance_to(at) < 0.01),
		"the first group starts where a figure of the block stood")
	assert_true(bool(piece.get("easing", false)))
	layer.step(0.1)
	assert_eq(String(piece.get("action", "")), "MARCH", "it walks in, on a stopped clock too")
	layer.step(repo.bal("map3d_battle_walk_s"))
	var row: Dictionary = piece["groups"][0]
	var saved := ctx.to_world(ArmySystem.metres_to_pack(repo, Vector2i(int(row["x_m"]), int(row["y_m"]))))
	assert_almost_eq(Vector2(node.global_position.x, node.global_position.z), saved, Vector2(0.01, 0.01),
		"and ends on its saved point")
	assert_false(bool(piece.get("easing", false)))
	layer.step(0.1)
	assert_ne(String(piece.get("action", "")), "MARCH", "arrived, it stands")
	assert_eq(SaveLoad.state_hash(state), frozen, "drawing never changes the saved battle")


func test_a_loaded_save_places_its_battle_without_a_walk() -> void:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := preload("res://tests/fixtures/battle_scenario.gd").contact(repo, 10)
	var foe := String(state.foes.keys()[0])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	var here := ctx.to_world(ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, foe, state)))
	ctx.camera.position = Vector3(here.x, 500, here.y + 500)
	ctx.camera.look_at(Vector3(here.x, 0, here.y))
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	layer.shown = true
	layer.refresh()
	assert_true(layer.built_piece(foe).has("seat_key"), "the block stood seated before the load")
	var loaded := GameState.from_dict(state.to_dict())   # another state object: a save loaded
	assert_false(BattleSystem.discover_contacts(repo, loaded).is_empty())
	ctx.state_fn = func() -> GameState: return loaded
	layer.refresh()
	var piece: Dictionary = layer.built_piece(foe)
	assert_eq(piece.get("layout", ""), "physical_groups")
	assert_false(bool(piece.get("easing", false)), "nobody walks in from the previous campaign's ground")
