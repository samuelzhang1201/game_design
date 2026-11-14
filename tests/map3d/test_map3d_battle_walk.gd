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
	var stood: Vector3 = (block["figs"][0] as Node3D).global_position
	assert_false(BattleSystem.discover_contacts(repo, state).is_empty(), "real contact starts the encounter")
	var frozen := SaveLoad.state_hash(state)
	layer.refresh()
	var piece: Dictionary = layer.built_piece(foe)
	assert_eq(piece.get("layout", ""), "physical_groups")
	var node: Node3D = piece["groups"][0]["piece"]["node"]
	assert_almost_eq(Vector2(node.global_position.x, node.global_position.z), Vector2(stood.x, stood.z),
		Vector2(0.01, 0.01), "the first group starts where the block's first figure stood")
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
