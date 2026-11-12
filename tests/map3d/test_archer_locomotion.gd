extends GutTest
## Map3DArcherLocomotion: the archers' pivot for any turn, on the installed archers.tscn.

const Locomotion = preload("res://scripts/map3d/map3d_archer_locomotion.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D


func before_all() -> void:
	_model = (load("res://scenes/models/units/archers.tscn") as PackedScene).instantiate() as Node3D
	add_child(_model)
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]


func after_all() -> void:
	_model.free()


## Global bone poses after the provider poses the skeleton for `request`.
func _posed(clip: String, turn: Variant, phase: float) -> Array[Transform3D]:
	var length := _player.get_animation(clip).length
	Locomotion.pose(_player, _skeleton, {"clip": clip, "time_s": phase * length, "phase": phase, "turn_udeg": turn})
	var out: Array[Transform3D] = []
	for bone: int in _skeleton.get_bone_count():
		out.append(_skeleton.get_bone_global_pose(bone))
	return out


func _max_gap(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst := 0.0
	for i: int in a.size():
		worst = maxf(worst, a[i].origin.distance_to(b[i].origin))
		for axis: int in 3:
			worst = maxf(worst, a[i].basis[axis].distance_to(b[i].basis[axis]))
	return worst


func _world(clip: String, turn: int, phase: float, bone: String) -> Vector3:
	# BodyMotion: world yaw = yaw0 - turn x phase; the skeleton sits in the figure at the origin.
	var g := _posed(clip, turn, phase)
	var to_model := _model.global_transform.affine_inverse() * _skeleton.global_transform
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(turn / 1000000.0) * phase), Vector3.ZERO) \
		* to_model * g[_skeleton.find_bone(bone)].origin


func test_half_turn_is_the_native_clip() -> void:
	for clip: String in ["PIVOT_RIGHT", "PIVOT_LEFT"]:
		var turn := 180000000 if clip == "PIVOT_RIGHT" else -180000000
		for phase: float in [0.1, 0.37, 0.5, 0.83]:
			assert_lt(_max_gap(_posed(clip, turn, phase), _posed(clip, null, phase)), 0.00001, "%s %s" % [clip, phase])


func test_every_turn_keeps_the_native_endpoints() -> void:
	for turn: int in [1, 2000000, 90000000, 179999999, -1, -45000000, -179999999]:
		var clip := "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
		for phase: float in [0.0, 1.0]:
			assert_lt(_max_gap(_posed(clip, turn, phase), _posed(clip, null, phase)), 0.00001, "%d at %s" % [turn, phase])


func test_a_planted_foot_holds_the_world_for_small_and_quarter_turns() -> void:
	# The native right foot stands from phase 0 to about 0.12 and again from 0.25 to 0.37.
	for turn: int in [1, 2000000, 90000000]:
		for window: Array in [[0.01, 0.11], [0.26, 0.36]]:
			var start := _world("PIVOT_RIGHT", turn, window[0], "foot.r")
			var end := _world("PIVOT_RIGHT", turn, window[1], "foot.r")
			assert_lt(Vector2(end.x - start.x, end.z - start.z).length(), 0.003, "turn %d window %s" % [turn, window])


func test_leg_spans_and_pelvis_are_kept() -> void:
	var native := _posed("PIVOT_RIGHT", null, 0.4)
	var turned := _posed("PIVOT_RIGHT", 2000000, 0.4)
	var root := _skeleton.find_bone("root.x")
	assert_lt(native[root].origin.distance_to(turned[root].origin), 0.000001, "pelvis stays native")
	for side: String in ["l", "r"]:
		var hip := _skeleton.find_bone("thigh_twist." + side)
		var knee := _skeleton.find_bone("leg_stretch." + side)
		var ankle := _skeleton.find_bone("foot." + side)
		assert_almost_eq(turned[hip].origin.distance_to(turned[knee].origin), native[hip].origin.distance_to(native[knee].origin), 0.00001)
		assert_almost_eq(turned[knee].origin.distance_to(turned[ankle].origin), native[knee].origin.distance_to(native[ankle].origin), 0.00001)


func test_a_turn_on_the_other_clip_is_refused() -> void:
	var result: Dictionary = Locomotion.solve(_player, _skeleton, "PIVOT_LEFT", 90000000, 0.5)
	assert_false(result.ok)
	assert_string_contains(String(result.reason), "does not belong")
