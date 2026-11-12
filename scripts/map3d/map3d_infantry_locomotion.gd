class_name Map3DInfantryLocomotion
extends RefCounted
## The infantry's pivot for ANY committed turn (certifier provider; candidate only, no caller).
## The installed PIVOT_LEFT/RIGHT clips are the coupled author mapping solved at -/+90 degrees.
## For another turn the same plan is expanded with that turn (held targets rotated by
## -turn x the swing's end, pivot_mapping.py `expand`) and Map3DInfantryPivot.sample_transition
## re-solves the legs, with the clip's own pose at the phase as the authored reference.
## Entry and exit stay the clip's endpoints (MARCH at PLAN.march_phase). The plan is generated
## by tools/units3d/soldier_arp/pivot_mapping.py `plan`.

const Pivot = preload("res://scripts/map3d/map3d_infantry_pivot.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const PLAN_PATH := "res://assets/3D/units/infantry/infantry_pivot_plan.json"
const SWING_STEPS := 16
const LIFT_M := 0.05

static var _plan: Dictionary = {}


## Certifier provider (tools/units3d/certify_locomotion.py), through the shared shell.
static func pose(player: AnimationPlayer, skeleton: Skeleton3D, request: Dictionary) -> void:
	Provider.apply(solve, player, skeleton, request)


## Solves one phase of a `turn_udeg` pivot on `clip` (the clip whose sign matches the turn).
static func solve(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, turn_udeg: int,
		phase: float) -> Dictionary:
	var plan := _load()
	var length := player.get_animation(clip).length
	var rest: Dictionary = plan.rest
	var entry := Provider.locals(player, skeleton, clip, 0.0, rest.bones)
	var exit := Provider.locals(player, skeleton, clip, length, rest.bones)
	var current := Provider.locals(player, skeleton, clip, phase * length, rest.bones)
	# The clip's body above the legs carries MARCH's arm swing, right for a 90-degree turn and an
	# unmotivated flourish for a small one: scale it toward the held entry pose by the turn's share
	# of 90 degrees (at +/-90 the clip is unchanged; entry == exit, so both ends stay native).
	var share := minf(1.0, absf(float(turn_udeg)) / 90000000.0)
	if share < 1.0:
		var legs := {}
		for leg: Dictionary in rest.legs:
			for name: String in [leg.hip, leg.knee, leg.ankle, leg.toe]:
				legs[name] = true
			for name: String in leg.followers:
				legs[name] = true
		for bone: Dictionary in rest.bones:
			if bone.parent != "" and not legs.has(bone.name):
				current[bone.name] = (entry[bone.name] as Transform3D).interpolate_with(current[bone.name], share)
	var march: float = plan.march_phase
	var op := {"duration_q": 100000, "phase": phase, "yaw0_udeg": 0, "turn_udeg": turn_udeg,
		"current_yaw_udeg": fposmod(float(turn_udeg) * phase, 360000000.0),
		"march_entry_phase": march, "march_exit_phase": march}
	var contacts := {"march_entry_phase": march, "march_exit_phase": march, "legs": expand(plan, turn_udeg)}
	return Pivot.sample_transition(rest, current, op, contacts, {"entry_pose": entry, "exit_pose": exit})


## pivot_mapping.py `expand`: the turn's contact intervals from the turn-free plan.
static func expand(plan: Dictionary, turn_udeg: int) -> Dictionary:
	var turn := float(turn_udeg) / 1000000.0
	var lift := LIFT_M * minf(1.0, absf(turn) / 90.0)
	var out := {}
	for leg: Dictionary in plan.legs:
		var point: Vector3 = leg.point
		var sole: Basis = leg.sole
		var toe: Basis = leg.toe
		var cursor := 0.0
		var intervals: Array = []
		for swing: Dictionary in leg.swings:
			var a: float = swing.t0
			var z: float = swing.t1
			if cursor < a:
				intervals.append(_interval(cursor, a, "stance", point, point, sole, sole, toe, toe))
			var r := Basis(Vector3.UP, deg_to_rad(-turn * float(swing.future)))
			var target: Vector3 = r * (swing.place as Vector3)
			var sole_to: Basis = r * (swing.sole as Basis)
			var toe_to: Basis = r * (swing.toe as Basis)
			var p_prev := point
			var s_prev := sole
			var t_prev := toe
			for k: int in range(1, SWING_STEPS + 1):
				var s := float(k) / SWING_STEPS
				var e := s * s * (3.0 - 2.0 * s)
				var p := point.lerp(target, e)
				p.y += lift * pow(sin(PI * s), 2.0)
				var ss := sole.slerp(sole_to, e)
				var tt := toe.slerp(toe_to, e)
				var t1 := z if k == SWING_STEPS else a + (z - a) * float(k) / SWING_STEPS
				intervals.append(_interval(a + (z - a) * float(k - 1) / SWING_STEPS, t1, "swing",
					p_prev, p, s_prev, ss, t_prev, tt))
				p_prev = p
				s_prev = ss
				t_prev = tt
			point = target
			sole = sole_to
			toe = toe_to
			cursor = z
		if cursor < 1.0:
			intervals.append(_interval(cursor, 1.0, "stance", point, point, sole, sole, toe, toe))
		out[leg.hip] = {"sole_bind": leg.sole_bind, "toe_bind": leg.toe_bind, "intervals": intervals}
	return out


static func _interval(a: float, z: float, kind: String, p0: Vector3, p1: Vector3, s0: Basis, s1: Basis,
		t0: Basis, t1: Basis) -> Dictionary:
	return {"t0": a, "t1": z, "kind": kind, "point_from": p0, "point_to": p1, "sole_from": s0, "sole_to": s1,
		"toe_from": t0, "toe_to": t1}


static func _load() -> Dictionary:
	if not _plan.is_empty():
		return _plan
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	for bone: Dictionary in raw.rest.bones:
		bone.local = _transform(bone.local)
	for leg: Dictionary in raw.rest.legs:
		leg.pole = _vector(leg.pole)
	for leg: Dictionary in raw.legs:
		leg.sole_bind = _transform(leg.sole_bind)
		leg.toe_bind = _transform(leg.toe_bind)
		leg.point = _vector(leg.point)
		leg.sole = _basis(leg.sole)
		leg.toe = _basis(leg.toe)
		for swing: Dictionary in leg.swings:
			swing.place = _vector(swing.place)
			swing.sole = _basis(swing.sole)
			swing.toe = _basis(swing.toe)
	_plan = raw
	return _plan


static func _vector(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _basis(a: Array) -> Basis:
	return Basis(Vector3(a[0][0], a[1][0], a[2][0]), Vector3(a[0][1], a[1][1], a[2][1]), Vector3(a[0][2], a[1][2], a[2][2]))


static func _transform(a: Array) -> Transform3D:
	return Transform3D(_basis(a), Vector3(a[0][3], a[1][3], a[2][3]))
