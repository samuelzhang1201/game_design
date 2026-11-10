extends GutTest
## Map3DInfantryLocomotion: the infantry pivot for any turn (LOCO-CERT-INF provider).

const Loco = preload("res://scripts/map3d/map3d_infantry_locomotion.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D


func before_all() -> void:
	_model = (load("res://scenes/models/units/infantry.tscn") as PackedScene).instantiate() as Node3D
	add_child(_model)
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]


func after_all() -> void:
	_model.free()


func _clip_globals(clip: String, phase: float) -> Array[Transform3D]:
	Provider.seek(_player, _skeleton, clip, phase * _player.get_animation(clip).length)
	var out: Array[Transform3D] = []
	for bone: int in _skeleton.get_bone_count():
		out.append(_skeleton.get_bone_global_pose(bone))
	return out


func _solved_globals(clip: String, turn: int, phase: float) -> Array[Transform3D]:
	var result := Loco.solve(_player, _skeleton, clip, turn, phase)
	assert_true(result.ok, "%s %d @%s: %s" % [clip, turn, phase, result.reason])
	Provider.set_pose(_skeleton, result.pose)
	var out: Array[Transform3D] = []
	for bone: int in _skeleton.get_bone_count():
		out.append(_skeleton.get_bone_global_pose(bone))
	return out


func _max_joint_m(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst := 0.0
	for i: int in a.size():
		worst = maxf(worst, (a[i].origin - b[i].origin).length())
	return worst


func test_contact_plan_partitions_the_pivot() -> void:
	var legs := Loco.expand(Loco._load(), 45000000)
	assert_eq(legs.size(), 2)
	for hip: String in legs:
		var intervals: Array = legs[hip].intervals
		assert_eq(intervals[0].t0, 0.0, hip)
		assert_eq(intervals[-1].t1, 1.0, hip)
		for i: int in range(1, intervals.size()):
			assert_eq(intervals[i].t0, intervals[i - 1].t1, "%s gap at %d" % [hip, i])


func test_ninety_degrees_reproduces_the_installed_clips() -> void:
	# The clips are this plan's +/-90 solve: re-solving them changes no joint (float noise only).
	for row: Array in [["PIVOT_RIGHT", 90000000], ["PIVOT_LEFT", -90000000]]:
		for phase: float in [0.0, 0.2, 0.55, 0.9, 1.0]:
			var clip := _clip_globals(row[0], phase)
			assert_lt(_max_joint_m(_solved_globals(row[0], row[1], phase), clip), 0.001, "%s @%s" % [row[0], phase])


func test_every_grid_turn_solves_and_keeps_the_march_endpoints() -> void:
	for turn: int in [1, -1, 45000000, -2000000, 179999999, -179999999, 180000000]:
		var clip := "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
		for phase: float in [0.0, 1.0]:
			var native := _clip_globals(clip, phase)
			assert_lt(_max_joint_m(_solved_globals(clip, turn, phase), native), 0.001, "endpoint %d @%s" % [turn, phase])
		_solved_globals(clip, turn, 0.5)


func test_a_march_request_is_the_native_seek() -> void:
	Loco.pose(_player, _skeleton, {"clip": "MARCH", "phase": 0.3, "turn_udeg": null})
	_skeleton.force_update_all_bone_transforms()
	var posed: Array[Transform3D] = []
	for bone: int in _skeleton.get_bone_count():
		posed.append(_skeleton.get_bone_global_pose(bone))
	assert_lt(_max_joint_m(posed, _clip_globals("MARCH", 0.3)), 1e-6)
