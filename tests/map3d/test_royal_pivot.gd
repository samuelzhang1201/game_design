extends GutTest
## Map3DRoyalPivot: the royal pivot for any turn, leaving and rejoining MARCH (LOCO-ROY-PROVIDER).

const Provider = preload("res://scripts/map3d/map3d_royal_pivot.gd")
const Math = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")
const Shell = preload("res://scripts/map3d/map3d_pivot_provider.gd")

var _model: Node3D
var _sk: Skeleton3D
var _player: AnimationPlayer
var _rest: Dictionary
var _patches: Dictionary
var _stand: Dictionary
var _march: Dictionary


func before_all() -> void:
	_model = load("res://scenes/models/units/royal.tscn").instantiate()
	add_child(_model)
	_sk = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	var bound: Dictionary = Provider.bind(_player, _sk)
	_rest = bound.rest
	_patches = bound.patches
	_stand = bound.stand
	_march = _native("MARCH", Provider.plan().march_phase)


func after_all() -> void:
	_model.free()


func _native(clip: String, phase: float) -> Dictionary:
	return Shell.locals(_player, _sk, clip, phase * _player.get_animation(clip).length, _rest.bones)


func _pose(turn: int, phase: float) -> Dictionary:
	var out: Dictionary = Provider.solve(_player, _sk, "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT", turn, phase)
	assert_true(out.ok, "%s %s %s" % [turn, phase, out.reason])
	return out.pose


## A hoof frame in the world the engine draws: the body yawed by turn x phase (positive = RIGHT).
func _world(turn: int, phase: float, hoof: String) -> Transform3D:
	var yaw: Transform3D = Transform3D(Basis(Provider.TURN_AXIS, deg_to_rad(float(turn) / 1e6) * phase), Vector3.ZERO)
	return yaw * Math._fk(_rest.bones, _pose(turn, phase))[hoof]


func test_plan_admits_one_march_phase() -> void:
	var plan: Dictionary = Provider.plan()
	assert_eq(plan.march_phase, 0.4375, "MARCH key 7/16")
	assert_eq(plan.step_deg, 15.0)
	assert_eq(plan.support_m, 0.003)
	assert_eq(plan.patch_band_m, 0.005, "the royal certifier config's patch_band_m")
	assert_eq(plan.blend, 0.25)


func test_leaves_and_rejoins_march_exactly() -> void:
	# The certifier's seams MARCH(7/16) -> pivot(0) and pivot(1) -> MARCH(7/16) are exact,
	# and the root is never moved (the body's yaw stays BodyMotion's).
	for turn: int in [1, -1, 90000000, 180000000, -179999999]:
		for phase: float in [0.0, 1.0]:
			var pose: Dictionary = _pose(turn, phase)
			for name: String in _march:
				assert_eq(pose[name], _march[name], "%s %s %s" % [turn, phase, name])
	# The solver never rotates the root: mid-turn it is the stand's (MARCH and STANDBY share it).
	assert_eq(_pose(90000000, 0.5)["root"], _stand["root"])


func test_step_count_follows_the_turn() -> void:
	# ceil(|turn| / 15 degrees), at least two (a first and a last step).
	for pair: Array in [[1e-6, 2], [15.0, 2], [30.0, 2], [30.000001, 3], [90.0, 6], [-180.0, 12]]:
		assert_eq(Provider.steps_for(pair[0], Provider.plan()), pair[1], str(pair))
		var contacts: Dictionary = Provider.contacts_for(Math._fk(_rest.bones, _march),
			Math._fk(_rest.bones, _stand), _patches, pair[0], Provider.plan())
		var swings: int = 0
		for segment: Dictionary in contacts["FrontHoof.L"].segments:
			swings += 1 if segment.mode == "swing" else 0
		assert_eq(swings, 2 * int(pair[1]), str(pair))


func test_three_hooves_are_down_at_the_admitted_phase() -> void:
	var march_g: Dictionary = Math._fk(_rest.bones, _march)
	var down: Array = []
	for hoof: String in Provider.HOOVES:
		if Provider.lowest(march_g, _patches[hoof]) <= Provider.plan().support_m:
			down.append(hoof)
	assert_eq(down, ["FrontHoof.L", "FrontHoof.R", "HindHoof.R"])


func test_planted_hoof_holds_the_ground_while_the_body_turns() -> void:
	# A right half turn: 12 steps of 1/12. In the first step the airborne left hind leads,
	# so the right hind (planted at 7/16) is fourth: it stands on its MARCH frame to 3/48.
	var turn: int = 180000000
	var hoof: String = "HindHoof.R"
	var anchor: Vector3 = Math._fk(_rest.bones, _march)[hoof].origin
	for phase: float in [0.0, 0.02, 0.04, 0.06]:
		assert_lt(_world(turn, phase, hoof).origin.distance_to(anchor), 1e-4, str(phase))
	# It lands at 4/48 on the stand turned by 15 degrees and stands there until 7/48.
	var stand_g: Dictionary = Math._fk(_rest.bones, _stand)
	var landed: Vector3 = (Transform3D(Basis(Provider.TURN_AXIS, deg_to_rad(15.0)), Vector3.ZERO) * stand_g[hoof]).origin
	for phase: float in [4.0 / 48.0, 5.0 / 48.0, 6.5 / 48.0]:
		assert_lt(_world(turn, phase, hoof).origin.distance_to(landed), 1e-4, str(phase))


func test_airborne_hoof_never_hangs() -> void:
	# The left hind is up at 7/16: it swings from phase 0 and its last swing ends at phase 1.
	var contacts: Dictionary = Provider.contacts_for(Math._fk(_rest.bones, _march),
		Math._fk(_rest.bones, _stand), _patches, 90.0, Provider.plan())
	var segments: Array = contacts["HindHoof.L"].segments
	assert_eq(segments[0].mode, "swing")
	assert_eq(segments[0].start, 0.0)
	assert_eq(segments[-1].mode, "swing")
	assert_eq(segments[-1].end, 1.0)


func test_the_stand_is_seated_on_the_plane() -> void:
	# STANDBY(0) stands 0-5 mm up; every seated hoof's lowest patch vertex is on y = 0.
	var raw: Dictionary = Math._fk(_rest.bones, _native("STANDBY", 0.0))
	var seated: Dictionary = Math._fk(_rest.bones, _stand)
	var lifted: float = 0.0
	for hoof: String in Provider.HOOVES:
		assert_gt(_patches[hoof].size(), 0, hoof)
		lifted = maxf(lifted, Provider.lowest(raw, _patches[hoof]))
		assert_almost_eq(Provider.lowest(seated, _patches[hoof]), 0.0, 1e-4, hoof)
	assert_gt(lifted, 0.002, "the native stand is above the plane")


func test_bad_requests_return_no_pose() -> void:
	for args: Array in [[0.5, 0], [1.5, 1], [-0.1, 1]]:
		var out: Dictionary = Provider.sample(_rest, args[0], args[1], _march, _stand, _patches, Provider.plan())
		assert_false(out.ok)
		assert_eq(out.locals, {})


func test_every_certifier_grid_turn_solves_through_the_turn() -> void:
	# tools/units3d/certify_locomotion.py turn_grid(): a failure would fall back to the seeked clip.
	var turns: Array[int] = [1, -1, 2000000, -2000000, 45000000, -45000000, 90000000, -90000000,
		135000000, -135000000, 179999999, -179999999, 180000000]
	for turn: int in turns:
		var clip: String = "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
		for i: int in 25:
			var out: Dictionary = Provider.solve(_player, _sk, clip, turn, float(i) / 24.0)
			assert_true(out.ok, "%d at %d/24: %s" % [turn, i, out.reason])


func test_contact_schedules_partition_the_operation() -> void:
	# Every step count: segments start at 0, end at exactly 1 and abut with no gap or overlap.
	var march_g: Dictionary = Math._fk(_rest.bones, _march)
	var stand_g: Dictionary = Math._fk(_rest.bones, _stand)
	for steps: int in range(2, 13):
		var contacts: Dictionary = Provider.contacts_for(march_g, stand_g, _patches, 15.0 * steps, Provider.plan())
		for hoof: String in Provider.HOOVES:
			var segments: Array = contacts[hoof].segments
			assert_eq(segments[0].start, 0.0)
			assert_eq(segments[-1].end, 1.0, "%d %s" % [steps, hoof])
			for k: int in range(1, segments.size()):
				assert_eq(segments[k].start, segments[k - 1].end, "%d %s %d" % [steps, hoof, k])
				assert_eq(segments[k].from, segments[k - 1].to)


func test_a_clip_that_does_not_match_the_turn_is_refused() -> void:
	var out: Dictionary = Provider.solve(_player, _sk, "PIVOT_LEFT", 90000000, 0.5)
	assert_false(out.ok)
	assert_eq(out.pose, {})
