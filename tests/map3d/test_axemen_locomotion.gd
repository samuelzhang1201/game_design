extends GutTest
## Map3DAxemenLocomotion: the infantry's pivot solver on the hand-axe soldier's own plan.

const SuiteData := preload("res://tests/suite_data.gd")
const Loco = preload("res://scripts/map3d/map3d_axemen_locomotion.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D


func before_all() -> void:
	_model = (load("res://scenes/models/units/axemen.tscn") as PackedScene).instantiate() as Node3D
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


func _worst_joint_m(clip: String, turn: int, phase: float) -> float:
	var native := _clip_globals(clip, phase)
	var result := Loco.solve(_player, _skeleton, clip, turn, phase)
	assert_true(result.ok, "%s %d @%s: %s" % [clip, turn, phase, result.reason])
	Provider.set_pose(_skeleton, result.pose)
	var worst := 0.0
	for bone: int in _skeleton.get_bone_count():
		worst = maxf(worst, (_skeleton.get_bone_global_pose(bone).origin - native[bone].origin).length())
	return worst


func test_ninety_degrees_reproduces_the_installed_clips() -> void:
	# The clips are this plan's +/-90 solve: re-solving them changes no joint (float noise only).
	for row: Array in [["PIVOT_RIGHT", 90000000], ["PIVOT_LEFT", -90000000]]:
		for phase: float in [0.0, 0.2, 0.55, 0.9, 1.0]:
			assert_lt(_worst_joint_m(row[0], row[1], phase), 0.001, "%s @%s" % [row[0], phase])


func test_every_grid_turn_solves_and_keeps_the_march_endpoints() -> void:
	for turn: int in [1, -1, 45000000, -2000000, 179999999, -179999999, 180000000]:
		var clip := "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
		for phase: float in [0.0, 1.0]:
			assert_lt(_worst_joint_m(clip, turn, phase), 0.001, "endpoint %d @%s" % [turn, phase])
		_worst_joint_m(clip, turn, 0.5)
