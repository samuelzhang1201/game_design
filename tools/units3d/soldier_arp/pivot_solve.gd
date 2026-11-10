extends SceneTree
## Runs the merged Map3DInfantryPivot.sample_transition on pivot_mapping.py's cases.
## Godot --headless --path . -s tools/units3d/soldier_arp/pivot_solve.gd -- INPUTS.json OUT.json
## OUT is pivot.py's sample package: {"cases": [{turn_udeg, failures, frames: [{phase, pose}]}]}.

const Pivot = preload("res://scripts/map3d/map3d_infantry_pivot.gd")


func _vector(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _basis(a: Array) -> Basis:
	return Basis(Vector3(a[0][0], a[1][0], a[2][0]), Vector3(a[0][1], a[1][1], a[2][1]), Vector3(a[0][2], a[1][2], a[2][2]))


func _transform(a: Array) -> Transform3D:
	return Transform3D(_basis(a), Vector3(a[0][3], a[1][3], a[2][3]))


func _array(t: Transform3D) -> Array:
	return [[t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x], [t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y],
		[t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z], [0.0, 0.0, 0.0, 1.0]]


func _decode_pose(p: Dictionary) -> void:
	for n: String in p:
		p[n] = _transform(p[n])


func _decode(f: Dictionary) -> void:
	for bone: Dictionary in f.rest.bones:
		bone.local = _transform(bone.local)
	_decode_pose(f.pose)
	_decode_pose(f.transition.entry_pose)
	_decode_pose(f.transition.exit_pose)
	for reference: Dictionary in f.reference_poses:
		_decode_pose(reference)
	for leg: Dictionary in f.rest.legs:
		leg.pole = _vector(leg.pole)
	for hip: String in f.contacts.legs:
		var c: Dictionary = f.contacts.legs[hip]
		c.sole_bind = _transform(c.sole_bind)
		c.toe_bind = _transform(c.toe_bind)
		for interval: Dictionary in c.intervals:
			interval.point_from = _vector(interval.point_from)
			interval.point_to = _vector(interval.point_to)
			for n: String in ["sole_from", "sole_to", "toe_from", "toe_to"]:
				interval[n] = _basis(interval[n])
	for n: String in ["duration_q", "yaw0_udeg", "turn_udeg"]:
		f.op[n] = int(f.op[n])


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var input: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var report: Dictionary = {"input_sha256": FileAccess.get_sha256(args[0]),
		"helper_sha256": FileAccess.get_sha256("res://scripts/map3d/map3d_infantry_pivot.gd"), "cases": []}
	for f: Dictionary in input.cases:
		_decode(f)
		var row: Dictionary = {"turn_udeg": f.op.turn_udeg, "march_entry_phase": f.op.march_entry_phase,
			"march_exit_phase": f.op.march_exit_phase, "frames": [], "failures": []}
		for index: int in f.phases.size():
			var phase: float = f.phases[index]
			f.pose = f.reference_poses[index]
			f.op.phase = phase
			f.op.current_yaw_udeg = fposmod(float(f.op.yaw0_udeg) + float(f.op.turn_udeg) * phase, 360000000.0)
			var result: Dictionary = Pivot.sample_transition(f.rest, f.pose, f.op, f.contacts, f.transition)
			if not result.ok:
				row.failures.append({"phase": phase, "reason": result.reason})
				continue
			var poses: Dictionary = {}
			for n: String in result.pose:
				poses[n] = _array(result.pose[n])
			row.frames.append({"phase": phase, "pose": poses})
		report.cases.append(row)
		print("PIVOT_SOLVE_CASE ", f.op.turn_udeg, " frames=", row.frames.size(), " failures=", row.failures.size())
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report, "", true, true))
	quit()
