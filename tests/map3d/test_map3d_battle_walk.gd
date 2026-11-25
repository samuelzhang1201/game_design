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
	var walk_s := float(piece["groups"][0]["piece"]["walk"]["s"])
	assert_gte(walk_s, repo.bal("map3d_battle_walk_s"), "a walk-in lasts its paced length, never under the gentle floor")
	for group: Dictionary in piece["groups"]:
		assert_eq(float(group["piece"]["walk"]["s"]), walk_s, "every figure of the block arrives together")
	layer.step(walk_s)
	var row: Dictionary = piece["groups"][0]
	assert_almost_eq(Vector2(node.global_position.x, node.global_position.z), Groups.stand_xz(ctx, piece, row), Vector2(0.01, 0.01),
		"and ends where it stands for its saved point, at the block's spacing")
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


## A duel's step in or out (Map3DDuelDriver's `step_facing`) keeps facing the foe: never turned to its way.
func test_a_duel_step_keeps_its_facing() -> void:
	var from := Vector2(0, 0)
	var to := Vector2(0, -3)
	var half: Dictionary = Groups.eased(from, 1.0, to, 1.2, 0.5, 0.0, true)
	assert_eq(half["xz"], Vector2(0, -1.5))
	assert_almost_eq(float(half["yaw"]), lerp_angle(1.0, 1.2, 0.5), 0.0001, "it turns straight from its facing to the next")


## A block's walk-in lasts what its farthest walker needs at the stride's own pace
## (k 10: 1.4838 model m a 1.1 s loop = 13.489091 world m/s), a late lane over
## the share it has left; never shorter than `map3d_battle_walk_s` (1.6 here).
func test_a_walk_in_lasts_its_farthest_walkers_pace() -> void:
	assert_almost_eq(Groups.walk_in_s([40.0, 20.0], [0.0, 0.4], 10.0, 1.1, 1.4838, 1.6), 2.965373, 0.0001,
		"40 m at 13.489091 m/s; the late 20 m needs only 2.471144")
	assert_almost_eq(Groups.walk_in_s([40.0, 30.0], [0.0, 0.4], 10.0, 1.1, 1.4838, 1.6), 3.706716, 0.0001,
		"the late lane's 30 m over 0.6 of the walk wins")
	assert_almost_eq(Groups.walk_in_s([10.0], [0.0], 10.0, 1.1, 1.4838, 1.6), 1.6, 0.0001, "a short walk keeps the gentle floor")
	assert_almost_eq(Groups.walk_in_s([40.0], [0.0], 10.0, 1.1, 0.0, 1.6), 1.6, 0.0001, "no stride: the floor")


func _walker() -> Array:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for spec: Array in [["GARRISON", 1.0], ["MARCH", 1.1]]:
		var clip := Animation.new()
		clip.length = spec[1]
		clip.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(spec[0], clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	anim.play("MARCH")
	var child := {"anims": [anim], "walking": true, "clip_s": 1.1, "stride_m": 1.4838, "at": {"xz": Vector2(0, 50), "yaw": 0.0}}
	return [{"action": "MARCH", "clock": 0.0}, child, anim]


## Each frame a walking figure's MARCH plays at its ground over its stride
## (2 world m in 0.1 s facing its way at k 10: 2 / 0.1 / 10 × 1.1 / 1.4838 = 1.482679).
func test_a_walking_figure_marches_at_its_ground_pace() -> void:
	var w := _walker()
	var piece: Dictionary = w[0]
	var child: Dictionary = w[1]
	var anim: AnimationPlayer = w[2]
	for i in 3:
		piece["clock"] = 0.1 * i
		child["at"] = {"xz": Vector2(0, 50 - 2.0 * i), "yaw": 0.0}
		Groups.pace_walk(piece, child, 10.0)
	assert_eq(anim.current_animation, "MARCH")
	assert_almost_eq(anim.speed_scale, 1.482679, 0.0001, "its feet keep the ground")
	for i in 2:  # its lane held back: it stands where it is
		piece["clock"] = 0.3 + 0.1 * i
		Groups.pace_walk(piece, child, 10.0)
	assert_eq(anim.current_animation, "GARRISON", "held back, it stands its guard, never marches on the spot")
	piece["clock"] = 0.5
	child["at"] = {"xz": Vector2(0, 42), "yaw": 0.0}
	Groups.pace_walk(piece, child, 10.0)
	assert_eq(anim.current_animation, "MARCH", "and steps off again")
	child["walking"] = false
	Groups.pace_walk(piece, child, 10.0)
	assert_eq(anim.speed_scale, 1.0, "arrived, its clips play at their own speed")


func test_a_duellist_is_left_to_its_driver() -> void:
	var w := _walker()
	var anim: AnimationPlayer = w[2]
	anim.set_meta("duel", true)
	anim.speed_scale = 0.7
	for i in 2:
		w[0]["clock"] = 0.1 * i
		w[1]["at"] = {"xz": Vector2(0, 50 - 2.0 * i), "yaw": 0.0}
		Groups.pace_walk(w[0], w[1], 10.0)
	assert_almost_eq(anim.speed_scale, 0.7, 0.0001, "the duel driver paces its own steps")
