extends GutTest
## Map3DCavalryLocomotion: the cavalry pivot for any turn, leaving and rejoining MARCH
## (LOCO-CAV-PROVIDER). The shared solver's own schedule (step counts, partitions, planted
## hooves) is tested by test_royal_pivot.gd; this holds the cavalry binding.

const Loco = preload("res://scripts/map3d/map3d_cavalry_locomotion.gd")
const Horse = preload("res://scripts/map3d/map3d_royal_pivot.gd")
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
	_model = load("res://scenes/models/units/cavalry.tscn").instantiate()
	add_child(_model)
	_sk = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	var bound: Dictionary = Loco.bind(_player, _sk)
	assert_true(bound.ok, String(bound.get("reason", "")))
	_rest = bound.rest
	_patches = bound.patches
	_stand = bound.stand
	_march = Shell.locals(_player, _sk, "MARCH", Loco.plan().march_phase * _player.get_animation("MARCH").length,
		_rest.bones)


func after_all() -> void:
	_model.free()


func _pose(turn: int, phase: float) -> Dictionary:
	var out: Dictionary = Loco.solve(_player, _sk, "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT", turn, phase)
	assert_true(out.ok, "%s %s %s" % [turn, phase, out.reason])
	return out.pose


func test_plan_admits_one_march_phase_matching_the_check_config() -> void:
	var plan: Dictionary = Loco.plan()
	assert_eq(plan.march_phase, 0.4375, "MARCH key 7/16")
	assert_eq(plan.rider_root, "Saddle")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://docs/reviews/cluster-formations/evidence/locomotion/cavalry/provider-check.config.json"))
	assert_eq(plan.patch_band_m, float(config.patch_band_m), "the certifier config's patch_band_m")
	assert_eq(float(config.entry_phase), plan.march_phase, "the certifier enters MARCH where the pivot leaves it")
	assert_eq(config.march_stop_phases, [plan.march_phase])


func test_landmarks_connect_every_leg_chain_exactly() -> void:
	# Map3DCavalryPivot requires each chain bone's head (in its parent's frame) on its parent's tail.
	for hoof: String in Horse.HOOVES:
		var chain: Array = _rest.chains[hoof].bones
		for i: int in range(1, chain.size()):
			var child: Dictionary = Math._bone(_rest.bones, chain[i])
			var parent: Dictionary = Math._bone(_rest.bones, chain[i - 1])
			assert_almost_eq((child.bind * child.head).distance_to(parent.tail), 0.0, 1e-5, chain[i])
	for bone: Dictionary in _rest.bones:
		assert_ne(bone.head, bone.tail, bone.name)


## At 7/16 the left fore and right hind stand; the right fore (4.5 mm) and left hind (10.8 mm) are
## barely up, so their first and last steps are short and flat (at 8/16 the left hind is 151 mm up
## and flexed, and its swing to the stand dragged the toe through the planting band: pivot slide 168 mm sampled,
## 196 mm with the certifier's margin).
func test_two_hooves_stand_and_two_are_barely_up_at_the_admitted_phase() -> void:
	var march_g: Dictionary = Math._fk(_rest.bones, _march)
	var down: Array = []
	for hoof: String in Horse.HOOVES:
		if Horse.lowest(march_g, _patches[hoof]) <= Loco.plan().support_m:
			down.append(hoof)
	assert_eq(down, ["FrontHoof.L", "HindHoof.R"])
	for hoof: String in ["FrontHoof.R", "HindHoof.L"]:
		assert_lt(Horse.lowest(march_g, _patches[hoof]), 0.02, hoof)


func test_leaves_and_rejoins_march_exactly_and_never_moves_the_root() -> void:
	for turn: int in [1, -1, 90000000, 180000000, -179999999]:
		for phase: float in [0.0, 1.0]:
			var pose: Dictionary = _pose(turn, phase)
			for name: String in _march:
				assert_eq(pose[name], _march[name], "%s %s %s" % [turn, phase, name])
	# Cavalry MARCH keys the root bone (an 8.5 cm bob and a slight pitch about X); STANDBY does not,
	# so the eased pose blends the two. The root bone never yaws or moves sideways, and its height and
	# fore-aft stay within MARCH's own bob: the body's yaw and ground position stay BodyMotion's.
	for phase: float in [0.05, 0.2, 0.5, 0.95]:
		var root: Transform3D = _pose(90000000, phase)["root"]
		assert_almost_eq(root.basis.x, Vector3.RIGHT, Vector3.ONE * 1e-5, str(phase))
		assert_almost_eq(root.origin.x, 0.0, 1e-6, str(phase))
		for axis: int in [1, 2]:  # height and the bob's few mm fore-aft stay between MARCH's and the stand's
			var lo: float = minf(_march["root"].origin[axis], _stand["root"].origin[axis])
			var hi: float = maxf(_march["root"].origin[axis], _stand["root"].origin[axis])
			assert_between(root.origin[axis], lo - 1e-6, hi + 1e-6, "%s axis %d" % [phase, axis])


func test_the_stand_is_seated_on_the_plane() -> void:
	var seated: Dictionary = Math._fk(_rest.bones, _stand)
	for hoof: String in Horse.HOOVES:
		assert_gt(_patches[hoof].size(), 0, hoof)
		assert_almost_eq(Horse.lowest(seated, _patches[hoof]), 0.0, 1e-4, hoof)


func test_every_certifier_grid_turn_solves_through_the_turn() -> void:
	# tools/units3d/certify_locomotion.py turn_grid(): a failure would fall back to the seeked clip.
	var turns: Array[int] = [1, -1, 2000000, -2000000, 45000000, -45000000, 90000000, -90000000,
		135000000, -135000000, 179999999, -179999999, 180000000]
	for turn: int in turns:
		var clip: String = "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
		for i: int in 25:
			var out: Dictionary = Loco.solve(_player, _sk, clip, turn, float(i) / 24.0)
			assert_true(out.ok, "%d at %d/24: %s" % [turn, i, out.reason])


func test_a_clip_that_does_not_match_the_turn_is_refused() -> void:
	var out: Dictionary = Loco.solve(_player, _sk, "PIVOT_LEFT", 90000000, 0.5)
	assert_false(out.ok)
	assert_eq(out.pose, {})
