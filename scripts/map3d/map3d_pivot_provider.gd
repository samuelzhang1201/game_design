class_name Map3DPivotProvider
extends RefCounted
## The shared turn -> pose provider shell (every arm; candidate only, no ordinary caller).
## An arm script supplies
##   static func solve(player: AnimationPlayer, skeleton: Skeleton3D, clip: String,
##       turn_udeg: int, phase: float) -> Dictionary   # {ok, reason, pose: {bone name: local Transform3D}}
## and its certifier entry is one line, through a PRELOAD (the certifier copies only res:// paths
## it finds in the provider's files, never a bare class_name):
##   const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
##   static func pose(player, skeleton, request) -> void: Provider.apply(solve, player, skeleton, request)
## `request` is tools/units3d/certify_locomotion.py's {clip, time_s, phase, turn_udeg}; a positive turn
## plays PIVOT_RIGHT and the world yaw is yaw0 - turn x phase (BodyMotion). MARCH, or a pivot with no
## turn, is the native seek. The consumer applies the same solve to a figure in place of seeking the
## pivot clip. `solve` may sample the arm's own clips through `seek` / `locals`; pose bones the
## skeleton lacks (the rig root) are ignored.


static func apply(solve: Callable, player: AnimationPlayer, skeleton: Skeleton3D, request: Dictionary) -> void:
	var clip: String = request.clip
	seek(player, skeleton, clip, float(request.phase) * player.get_animation(clip).length)
	if not clip.begins_with("PIVOT_") or request.turn_udeg == null:
		return
	var result: Dictionary = solve.call(player, skeleton, clip, int(request.turn_udeg), float(request.phase))
	if not result.ok:
		push_error("pivot provider %s %s: %s" % [clip, request.turn_udeg, result.reason])
		return
	set_pose(skeleton, result.pose)


## Plays `clip` at `time_s` and leaves the skeleton there (the player stopped, its state kept).
static func seek(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, time_s: float) -> void:
	player.play(clip, 0.0)
	player.seek(time_s, true)
	player.advance(0.0)
	player.stop(true)
	skeleton.force_update_all_bone_transforms()


## Parent-relative locals of `clip` at `time_s` for `bones` ([{name, local}]); a bone the skeleton
## lacks keeps its own `local` (the rig root of a solver's hierarchy).
static func locals(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, time_s: float,
		bones: Array) -> Dictionary:
	seek(player, skeleton, clip, time_s)
	var out := {}
	for bone: Dictionary in bones:
		var index := skeleton.find_bone(bone.name)
		out[bone.name] = bone.local if index < 0 else skeleton.get_bone_pose(index)
	return out


static func set_pose(skeleton: Skeleton3D, pose: Dictionary) -> void:
	for name: String in pose:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			skeleton.set_bone_pose(bone, pose[name])
	skeleton.force_update_all_bone_transforms()
