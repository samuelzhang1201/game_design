class_name Map3DArcherLocomotion
extends RefCounted
## The archers' pivot for ANY committed turn (certifier provider; candidate only, no caller).
## The installed PIVOT_LEFT/RIGHT clips turn the body a half turn (world yaw yaw0 -/+ pi x phase)
## while each foot steps round on the ground. For a turn T the clip still plays at the phase,
## and each foot's WORLD track is turned about the pivot by (|T|/180 - 1) x that foot's own
## accumulated world heading in the native clip: a planted foot's heading is constant, so it
## stays planted; at phase 0 and 1 the correction is the identity, so both ends are the native
## MARCH-0 endpoints and T = 180 reproduces the clip. The legs reach the new foot with a
## two-bone IK in the leg's own plane (thigh and shin rotate about hip and knee, bone spans
## kept); the body above the legs eases toward the entry pose by |T|/180, as the infantry's
## provider does, so a small turn does not carry a half turn's arm swing. root.x (the pelvis)
## stays native.

const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const SIDES: Array[String] = ["l", "r"]
const LEG: Array[String] = ["thigh_twist", "thigh_stretch", "leg_stretch", "leg_twist", "foot", "toes_01"]
const HEADING_SAMPLES := 256

static var _headings: Dictionary = {}


## Certifier provider (tools/units3d/certify_locomotion.py), through the shared shell.
static func pose(player: AnimationPlayer, skeleton: Skeleton3D, request: Dictionary) -> void:
	Provider.apply(solve, player, skeleton, request)


## Solves one phase of a `turn_udeg` pivot on `clip` (the clip whose sign matches the turn).
static func solve(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, turn_udeg: int,
		phase: float) -> Dictionary:
	var sign := -1.0 if clip == "PIVOT_RIGHT" else 1.0  # native world yaw = sign x pi x phase
	if (turn_udeg > 0) != (clip == "PIVOT_RIGHT") or absi(turn_udeg) > 180000000:
		return {"ok": false, "reason": "turn %d does not belong to %s" % [turn_udeg, clip], "pose": {}}
	var length := player.get_animation(clip).length
	var to_model := _to_model(player, skeleton)
	var table := _heading_table(player, skeleton, clip, to_model)
	var share := absf(float(turn_udeg)) / 180000000.0
	var turn := deg_to_rad(float(turn_udeg) / 1000000.0)
	var entry := _globals(player, skeleton, clip, 0.0)
	var native := _globals(player, skeleton, clip, phase * length)
	var out := native.duplicate()
	# The body above the legs eases toward the entry pose by the turn's share of a half turn.
	if share < 1.0:
		var locals := {}
		for bone: int in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			if name == "root.x" or _is_leg(name):
				continue
			var parent := skeleton.get_bone_parent(bone)
			var a: Transform3D = entry[bone] if parent < 0 else (entry[parent] as Transform3D).affine_inverse() * entry[bone]
			var b: Transform3D = native[bone] if parent < 0 else (native[parent] as Transform3D).affine_inverse() * native[bone]
			locals[bone] = a.interpolate_with(b, share)
		for bone: int in skeleton.get_bone_count():  # parents precede children in a Skeleton3D
			if locals.has(bone):
				var parent := skeleton.get_bone_parent(bone)
				out[bone] = locals[bone] if parent < 0 else (out[parent] as Transform3D) * locals[bone]
	for side: String in SIDES:
		var foot := skeleton.find_bone("foot." + side)
		var heading: float = _sample(table[side], phase)
		var native_world := _yaw(sign * PI * phase) * to_model * (native[foot] as Transform3D)
		var world := _yaw((share - 1.0) * heading) * native_world
		var target := to_model.affine_inverse() * _yaw(turn * phase) * world  # back to skeleton space
		var failure := _reach(skeleton, out, side, target)
		if not failure.is_empty():
			return {"ok": false, "reason": failure, "pose": {}}
	var result := {}
	for bone: int in skeleton.get_bone_count():
		if (out[bone] as Transform3D).is_equal_approx(native[bone]):
			continue
		var parent := skeleton.get_bone_parent(bone)
		result[skeleton.get_bone_name(bone)] = out[bone] if parent < 0 \
			else (out[parent] as Transform3D).affine_inverse() * (out[bone] as Transform3D)
	return {"ok": true, "reason": "", "pose": result}


## Moves one leg so its foot lands on `target` (skeleton space): thigh about the hip, shin about
## the knee, foot and toes rigidly; bone spans kept. Writes the new globals into `globals`.
static func _reach(skeleton: Skeleton3D, globals: Array, side: String, target: Transform3D) -> String:
	var index := {}
	for part: String in LEG:
		index[part] = skeleton.find_bone(part + "." + side)
		if index[part] < 0:
			return "missing bone %s.%s" % [part, side]
	var hip: Vector3 = (globals[index.thigh_twist] as Transform3D).origin
	var knee: Vector3 = (globals[index.leg_stretch] as Transform3D).origin
	var ankle: Vector3 = (globals[index.foot] as Transform3D).origin
	var goal := target.origin
	var upper := knee.distance_to(hip)
	var lower := ankle.distance_to(knee)
	var span := goal.distance_to(hip)
	if span > upper + lower + 0.0001:
		return "%s foot out of reach by %.4f m" % [side, span - upper - lower]
	if span < absf(upper - lower) + 0.0001:
		return "%s foot too close to the hip (%.4f m)" % [side, span]
	var along := (goal - hip) / span
	# The knee bends the way it bends natively: the thigh's direction off the new hip-foot line.
	var up := (knee - hip) - along * along.dot(knee - hip)
	if up.length_squared() < 1e-12:
		return "%s leg straight along the foot line" % side
	up = up.normalized()
	var x := (upper * upper - lower * lower + span * span) / (2.0 * span)
	var new_knee := hip + along * x + up * sqrt(maxf(0.0, upper * upper - x * x))
	var thigh := Transform3D(Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized())), Vector3.ZERO)
	var shin := Transform3D(Basis(Quaternion((ankle - knee).normalized(), (goal - new_knee).normalized())), Vector3.ZERO)
	for part: String in ["thigh_twist", "thigh_stretch"]:
		globals[index[part]] = Transform3D(Basis.IDENTITY, hip) * thigh * Transform3D(Basis.IDENTITY, -hip) * (globals[index[part]] as Transform3D)
	for part: String in ["leg_stretch", "leg_twist"]:
		globals[index[part]] = Transform3D(Basis.IDENTITY, new_knee) * shin * Transform3D(Basis.IDENTITY, -knee) * (globals[index[part]] as Transform3D)
	var toe_in_foot := (globals[index.foot] as Transform3D).affine_inverse() * (globals[index.toes_01] as Transform3D)
	globals[index.foot] = target
	globals[index.toes_01] = target * toe_in_foot
	return ""


## Each foot's accumulated world heading (ankle -> toe, about world up) over the native clip,
## unwrapped from 0 at phase 0; cached per clip resource (the archer rig is one scene).
static func _heading_table(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, to_model: Transform3D) -> Dictionary:
	var key := player.get_animation(clip).get_instance_id()  # one table per clip resource
	if _headings.has(key):
		return _headings[key]
	var sign := -1.0 if clip == "PIVOT_RIGHT" else 1.0
	var length := player.get_animation(clip).length
	var table := {"l": PackedFloat64Array(), "r": PackedFloat64Array()}
	var previous := {}
	for i: int in HEADING_SAMPLES + 1:
		var phase := float(i) / HEADING_SAMPLES
		var g := _globals(player, skeleton, clip, phase * length)
		for side: String in SIDES:
			var world := _yaw(sign * PI * phase) * to_model
			var ankle: Vector3 = world * (g[skeleton.find_bone("foot." + side)] as Transform3D).origin
			var toe: Vector3 = world * (g[skeleton.find_bone("toes_01." + side)] as Transform3D).origin
			var angle := atan2(toe.x - ankle.x, toe.z - ankle.z)
			if i == 0:
				previous[side] = [angle, 0.0]
			var total: float = previous[side][1] + wrapf(angle - previous[side][0], -PI, PI)
			previous[side] = [angle, total]
			table[side].append(total)
	_headings[key] = table
	return table


static func _sample(table: PackedFloat64Array, phase: float) -> float:
	var x := clampf(phase, 0.0, 1.0) * HEADING_SAMPLES
	var i := mini(int(x), HEADING_SAMPLES - 1)
	return lerpf(table[i], table[i + 1], x - i)


static func _globals(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, time_s: float) -> Array:
	Provider.seek(player, skeleton, clip, time_s)
	var out := []
	for bone: int in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_pose(bone))
	return out


## Skeleton space -> the figure's own model space (the AnimationPlayer's root node).
static func _to_model(player: AnimationPlayer, skeleton: Skeleton3D) -> Transform3D:
	var model := player.get_node(player.root_node) as Node3D
	return model.global_transform.affine_inverse() * skeleton.global_transform


static func _yaw(angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)


static func _is_leg(name: String) -> bool:
	for part: String in LEG:
		if name == part + ".l" or name == part + ".r":
			return true
	return false
