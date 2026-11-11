extends GutTest
## Map3DPivotProvider: the arm-generic turn -> pose shell the certifier and consumer share.

const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
static var _calls: Array = []


func before_all() -> void:
	_model = (load("res://scenes/models/units/archers.tscn") as PackedScene).instantiate() as Node3D
	add_child(_model)
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]


func after_all() -> void:
	_model.free()


func _globals() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone: int in _skeleton.get_bone_count():
		out.append(_skeleton.get_bone_global_pose(bone))
	return out


func _same(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	for i: int in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


static func _solve_lift(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, turn: int, phase: float) -> Dictionary:
	_calls.append([clip, turn, phase])
	var root := skeleton.get_bone_name(0)
	var lifted := skeleton.get_bone_pose(0).translated(Vector3(0, 0.25, 0))
	return {"ok": true, "reason": "", "pose": {root: lifted, "not_a_bone": Transform3D.IDENTITY}}


func test_march_and_a_turnless_pivot_are_the_native_seek() -> void:
	Provider.seek(_player, _skeleton, "MARCH", 0.3 * _player.get_animation("MARCH").length)
	var native := _globals()
	_calls.clear()
	Provider.apply(_solve_lift, _player, _skeleton, {"clip": "MARCH", "phase": 0.3, "turn_udeg": 5})
	assert_true(_same(_globals(), native), "MARCH is never solved")
	Provider.seek(_player, _skeleton, "PIVOT_RIGHT", 0.4 * _player.get_animation("PIVOT_RIGHT").length)
	native = _globals()
	Provider.apply(_solve_lift, _player, _skeleton, {"clip": "PIVOT_RIGHT", "phase": 0.4, "turn_udeg": null})
	assert_true(_same(_globals(), native), "a pivot with no turn is the native seek")
	assert_eq(_calls, [])


func test_a_pivot_applies_the_arms_solve() -> void:
	_calls.clear()
	Provider.seek(_player, _skeleton, "PIVOT_LEFT", 0.5 * _player.get_animation("PIVOT_LEFT").length)
	var native_root := _skeleton.get_bone_pose(0).origin
	Provider.apply(_solve_lift, _player, _skeleton, {"clip": "PIVOT_LEFT", "phase": 0.5, "turn_udeg": -45000000})
	assert_eq(_calls, [["PIVOT_LEFT", -45000000, 0.5]])
	assert_almost_eq(_skeleton.get_bone_pose(0).origin.y - native_root.y, 0.25, 1e-5, "the solved pose is set; unknown bones ignored")


func test_locals_keep_a_missing_bones_own_local() -> void:
	var root := Transform3D(Basis(), Vector3(1, 2, 3))
	var out := Provider.locals(_player, _skeleton, "MARCH", 0.0,
		[{"name": "rig_root_not_in_skeleton", "local": root}, {"name": _skeleton.get_bone_name(0), "local": Transform3D()}])
	assert_eq(out.rig_root_not_in_skeleton, root)
	assert_true(out[_skeleton.get_bone_name(0)].is_equal_approx(_skeleton.get_bone_pose(0)))


func test_seek_is_the_certifiers_native_path() -> void:
	# certify_locomotion.py's native twin: play(name, 0.0), seek(t, true), force_update.
	var length := _player.get_animation("MARCH").length
	for t: float in [0.0, 0.37 * length]:
		_player.stop(true)
		_skeleton.reset_bone_poses()
		_player.play("MARCH", 0.0)
		_player.seek(t, true)
		_skeleton.force_update_all_bone_transforms()
		var native := _globals()
		_skeleton.reset_bone_poses()
		Provider.seek(_player, _skeleton, "MARCH", t)
		assert_true(_same(_globals(), native), "seek at %s" % t)
	Provider.seek(_player, _skeleton, "MARCH", 0.0)
	var start := _globals()
	Provider.seek(_player, _skeleton, "MARCH", 0.37 * length)
	assert_false(_same(_globals(), start), "seek moves the pose")
