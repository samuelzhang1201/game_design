class_name Map3DRoyalPivot
extends RefCounted
## The royal piece's pivot for ANY committed turn, leaving and rejoining MARCH (LOCO-ROY-PROVIDER;
## owner rulings R-A / R-C 2026-11-10; coordinator ruling 2026-11-11: stop, start and hold only at
## the admitted MARCH phase, PLAN.march_phase). Candidate only, no ordinary caller; its interface is
## the shared Map3DPivotProvider `solve`, so the body's yaw is BodyMotion's (yaw0 - turn x phase)
## and the root is never moved. The installed PIVOT clips run STANDBY(0) -> STANDBY(0), 1.52 m from
## any MARCH pose (bake-only playback cannot join MARCH); this solves the whole operation instead:
## every hoof steps once per PLAN.step_deg of turn (at least twice), hoof i in the i-th quarter of
## each step, through the stand turned by the step's share of the turn. Before its first step a hoof
## stands where MARCH left it; its last step lands it where MARCH, turned by the whole turn, takes it
## up. The hooves in the air at PLAN.march_phase step first in the first step and last in the last,
## so none hangs in the air; the body (the rider, his sword) blends MARCH -> stand over the first
## step or PLAN.blend of the operation, whichever is longer, and back over the last. The stand is
## STANDBY(0) with each hoof seated by IK until its lowest patch vertex touches
## the seated plane (STANDBY itself stands 0-5 mm up). Legs are solved by Map3DCavalryPivot.sample
## against hoof frames planted in the ground (its START frame, turning with the body), so phase 0
## and 1 are MARCH(PLAN.march_phase) exactly. Plan: assets/3D/units/royal/royal_pivot_plan.json.
## Reads no clock or state and certifies nothing.

const _Pivot: GDScript = preload("res://scripts/map3d/map3d_cavalry_pivot.gd")
const _Math: GDScript = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")
const Provider = preload("res://scripts/map3d/map3d_pivot_provider.gd")
const SOURCE: String = "res://assets/3D/units/royal/royal_locomotion_source.tres"
const PLAN_PATH: String = "res://assets/3D/units/royal/royal_pivot_plan.json"
# The installed pivots' hoof order (left fore, left hind, right fore, right hind): diagonal steps.
const HOOVES: Array[String] = ["FrontHoof.L", "HindHoof.L", "FrontHoof.R", "HindHoof.R"]
const _CHAINS: Dictionary = {
	"FrontHoof": ["FrontScapula", "FrontUpperArm", "FrontForearm", "FrontCannon", "FrontHoof"],
	"HindHoof": ["HindThigh", "HindShin", "HindCannon", "HindHoof"]}
# Skeleton-space axis whose positive turn is the engine's positive (RIGHT, decreasing) yaw.
const TURN_AXIS: Vector3 = Vector3(0.0, -1.0, 0.0)
const _ZERO: Transform3D = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

static var _plan: Dictionary = {}
static var _bound_by_id: Dictionary = {}  # skeleton instance id -> {rest, patches, stand}


## Certifier provider (tools/units3d/certify_locomotion.py), through the shared shell.
static func pose(player: AnimationPlayer, skeleton: Skeleton3D, request: Dictionary) -> void:
	Provider.apply(solve, player, skeleton, request)


## One phase of a `turn_udeg` pivot: {ok, reason, pose: {bone: local Transform3D}}.
static func solve(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, turn_udeg: int,
		phase: float) -> Dictionary:
	if clip != ("PIVOT_RIGHT" if turn_udeg > 0 else "PIVOT_LEFT"):
		return {"ok": false, "reason": "clip %s does not turn %d" % [clip, turn_udeg], "pose": {}}
	var bound: Dictionary = bind(player, skeleton)
	if not bound.ok:
		return {"ok": false, "reason": bound.reason, "pose": {}}
	var march: Dictionary = Provider.locals(player, skeleton, "MARCH",
		float(plan().march_phase) * player.get_animation("MARCH").length, bound.rest.bones)
	var out: Dictionary = sample(bound.rest, phase, turn_udeg, march, bound.stand, bound.patches, plan())
	if not out.ok:
		return {"ok": false, "reason": str(out.diagnostics), "pose": {}}
	return {"ok": true, "reason": "", "pose": out.locals}


## The pivot at `phase`: march = MARCH locals at PLAN.march_phase, stand = the seated stand,
## patches = hoof -> patch. Returns {ok, locals, diagnostics}; never a partial pose.
static func sample(rest: Dictionary, phase: float, turn_udeg: int, march: Dictionary,
		stand: Dictionary, hooves: Dictionary, profile: Dictionary) -> Dictionary:
	if turn_udeg == 0 or phase < 0.0 or phase > 1.0:
		return {"ok": false, "locals": {}, "diagnostics": {"reason": "request"}}
	var turn: float = float(turn_udeg) / 1e6
	var steps: int = steps_for(turn, profile)
	# The horse eases MARCH <-> stand over one step (a longer ease folds the fore legs against the
	# planted hooves and tears the chest skin); the rider, whose sword swing read as a flick over
	# one step, eases over at least PLAN.blend.
	var horse_w: float = 1.0 / float(steps)
	var rider_w: float = maxf(horse_w, float(profile.blend))
	var native: Dictionary = march
	if phase > 0.0 and phase < 1.0:
		var rider: Dictionary = riders(rest, String(profile.rider_root))
		native = {}
		for name: String in march:
			var w: float = rider_w if rider.has(name) else horse_w
			var t: float = clampf(minf(phase, 1.0 - phase) / w, 0.0, 1.0)
			native[name] = stand[name] if t == 1.0 else \
				(march[name] as Transform3D).interpolate_with(stand[name], t * t * (3.0 - 2.0 * t))
	var op: Dictionary = {"start_heading": 0.0, "end_heading": fposmod(turn, 360.0), "turn_degrees": turn,
		"duration": 1.0, "phase": phase, "entry_phase": float(profile.march_phase),
		"exit_phase": float(profile.march_phase)}
	var contacts: Dictionary = contacts_for(_Math._fk(rest.bones, march), _Math._fk(rest.bones, stand), hooves, turn, profile)
	return _Pivot.sample(rest, {"locals": native, "entry": march, "exit": march}, op, contacts)


static func steps_for(turn_deg: float, profile: Dictionary) -> int:
	return maxi(2, ceili(absf(turn_deg) / float(profile.step_deg)))


## Hoof frames in the operation's START ground frame (skeleton space at phase 0). Step k spans
## [k, k + 1] / steps; hoof i of that step's order swings in its i-th quarter and lands on the stand
## turned by (k + 1) / steps of the turn — the last step on MARCH turned by the whole turn. Airborne
## hooves (lowest patch vertex above support_m at march_phase) lead the first step's order and close
## the last's; between, the installed order.
static func contacts_for(march_g: Dictionary, stand_g: Dictionary, hooves: Dictionary, turn_deg: float,
		profile: Dictionary) -> Dictionary:
	var air: Array[String] = []
	var planted: Array[String] = []
	for hoof: String in HOOVES:
		(planted if lowest(march_g, hooves[hoof]) <= float(profile.support_m) else air).append(hoof)
	var steps: int = steps_for(turn_deg, profile)
	var end_turn: Transform3D = Transform3D(Basis(TURN_AXIS, deg_to_rad(turn_deg)), Vector3.ZERO)
	var out: Dictionary = {}
	for hoof: String in HOOVES:
		var segments: Array = []
		var previous: Transform3D = march_g[hoof]
		var at: float = 0.0
		for step: int in steps:
			var order: Array = HOOVES
			if step == 0:
				order = air + planted
			elif step == steps - 1:
				order = planted + air
			var i: int = order.find(hoof)
			var start: float = (float(step) + float(i) * 0.25) / float(steps)
			var finish: float = start + 0.25 / float(steps)
			var target: Transform3D = end_turn * march_g[hoof] if step == steps - 1 else \
				Transform3D(Basis(TURN_AXIS, deg_to_rad(turn_deg * float(step + 1) / float(steps))), Vector3.ZERO) * stand_g[hoof]
			at = _step(segments, at, start, finish, previous, target, float(profile.lift_m), float(profile.lift_share))
			previous = target
		if at < 1.0:
			segments.append(_segment(at, 1.0, "stance", previous, previous))
		out[hoof] = {"offset": Transform3D.IDENTITY, "segments": segments}
	return out


## Append a stance up to `start`, then a two-part swing over [start, finish] through a point raised
## by at most lift (never more than `share` of the distance travelled). Returns the new end.
static func _step(segments: Array, at: float, start: float, finish: float, from: Transform3D, to: Transform3D,
		lift: float, share: float) -> float:
	if start > at:
		segments.append(_segment(at, start, "stance", from, from))
	var high: Transform3D = from.interpolate_with(to, 0.5)
	high.origin.y += minf(lift, share * from.origin.distance_to(to.origin))
	var mid: float = (start + finish) * 0.5
	segments.append(_segment(start, mid, "swing", from, high))
	segments.append(_segment(mid, finish, "swing", high, to))
	return finish


static func _segment(start: float, end: float, mode: String, from: Transform3D, to: Transform3D) -> Dictionary:
	return {"start": start, "end": end, "mode": mode, "from": from, "to": to, "from_derivative": _ZERO, "to_derivative": _ZERO}


## Kernel rest from the installed skin (inverse binds) and R1's anatomical landmarks.
static func rest_of(skeleton: Skeleton3D, skin: Skin, landmarks: Dictionary) -> Dictionary:
	var binds: Dictionary = {}
	for i: int in skin.get_bind_count():
		binds[skin.get_bind_name(i)] = skin.get_bind_pose(i).affine_inverse()
	var bones: Array = []
	for i: int in skeleton.get_bone_count():
		var name: String = skeleton.get_bone_name(i)
		var parent: int = skeleton.get_bone_parent(i)
		var parent_name: String = "" if parent < 0 else skeleton.get_bone_name(parent)
		var mark: Dictionary = landmarks[name]
		var bind: Transform3D = binds[name] if parent < 0 else binds[parent_name].affine_inverse() * binds[name]
		bones.append({"name": name, "parent": parent_name, "bind": bind, "bind_global": binds[name],
			"head": mark.head, "tail": mark.tail})
	var bind_locals: Dictionary = {}
	for bone: Dictionary in bones:
		bind_locals[bone.name] = bone.bind
	var globals: Dictionary = _Math._fk(bones, bind_locals)
	var chains: Dictionary = {}
	for hoof: String in HOOVES:
		var names: Array = []
		for part: String in _CHAINS[hoof.get_slice(".", 0)]:
			names.append(part + "." + hoof.get_slice(".", 1))
		var parent: String = _Math._bone(bones, names[0]).parent
		var normals: Array = []
		var bends: Array = []
		var limits: Array = []
		for name: String in names:
			limits.append(PI)  # no anatomical limit is claimed; the sampled certificate judges the result
		for i: int in range(1, names.size() - 1):
			bends.append(Vector2(-PI, PI))
			var a: Vector3 = globals[names[i]].origin - globals[names[i - 1]].origin
			var b: Vector3 = globals[names[i + 1]].origin - globals[names[i]].origin
			normals.append((globals[parent].basis.inverse() * a.cross(b)).normalized())
		chains[hoof] = {"bones": names, "rotation_limits": limits, "bend_limits": bends, "bend_normals": normals}
	return {"version": 1, "turn_axis": TURN_AXIS, "bones": bones, "chains": chains}


## A hoof's patch: its body vertices (weight share over PLAN.patch_share on the hoof bone) within
## PLAN.patch_band_m of their lowest at rest — the certifier's material patch, which its config's
## patch_band_m must match — with their packed skin, bound to bone names.
static func patches(mesh: MeshInstance3D, profile: Dictionary) -> Dictionary:
	var names: Array[String] = []
	var binds: Array[Transform3D] = []
	for i: int in mesh.skin.get_bind_count():
		names.append(mesh.skin.get_bind_name(i))
		binds.append(mesh.skin.get_bind_pose(i))
	var out: Dictionary = {}
	for hoof: String in HOOVES:
		var rows: Array = []
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width: int = bones.size() / vertices.size()
			for v: int in vertices.size():
				var share: float = 0.0
				var row: Dictionary = {"v": vertices[v], "bones": [], "weights": [], "binds": []}
				for k: int in width:
					var w: float = weights[v * width + k]
					if w == 0.0:
						continue
					var bind: int = bones[v * width + k]
					share += w if names[bind] == hoof else 0.0
					row.bones.append(names[bind])
					row.weights.append(w)
					row.binds.append(binds[bind])
				if share > float(profile.patch_share):
					rows.append(row)
		var low: float = INF
		for row: Dictionary in rows:
			low = minf(low, row.v.y)
		var band: float = float(profile.patch_band_m)
		out[hoof] = rows.filter(func(row: Dictionary) -> bool: return row.v.y <= low + band)
	return out


## The lowest skinned patch vertex (skeleton space, y up) under bone globals.
static func lowest(globals: Dictionary, patch: Array) -> float:
	var low: float = INF
	for row: Dictionary in patch:
		var at: Vector3 = Vector3.ZERO
		for k: int in row.bones.size():
			at += (globals[row.bones[k]] * row.binds[k] * row.v) * float(row.weights[k])
		low = minf(low, at.y)
	return low


## The stand with every hoof lowered (or raised) by IK until its patch touches the seated plane;
## {} when a hoof has no patch or the IK fails.
static func seat(rest: Dictionary, stand: Dictionary, patches: Dictionary) -> Dictionary:
	var locals: Dictionary = stand.duplicate()
	for hoof: String in HOOVES:
		var chain: Dictionary = rest.chains[hoof]
		var parent: String = _Math._bone(rest.bones, chain.bones[0]).parent
		if patches[hoof].is_empty():
			return {}
		for i: int in 3:  # the hoof moves rigidly; the cannon-weighted rim needs a second look
			var globals: Dictionary = _Math._fk(rest.bones, locals)
			var drop: float = lowest(globals, patches[hoof])
			if absf(drop) < 1e-6:
				break
			var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, -drop, 0.0)) * globals[hoof]
			var solved: Dictionary = _Math._solve(rest, chain, locals, target, globals[parent], Transform3D.IDENTITY, Transform3D.IDENTITY)
			if not solved.ok:
				return {}
			for name: String in chain.bones:
				locals[name] = solved.locals[name]
	return locals


## The rider: every bone below `root` (the saddle, which is the horse's), as a set.
static func riders(rest: Dictionary, root: String) -> Dictionary:
	var out: Dictionary = {}
	for bone: Dictionary in rest.bones:  # parents come before children
		if bone.parent == root or out.has(bone.parent):
			out[bone.name] = true
	return out


static func plan() -> Dictionary:
	if _plan.is_empty():
		_plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	return _plan


## {ok, reason, rest, patches, stand}: the kernel rest, hoof patches and seated stand of this
## figure, built once per skeleton. The cache is never evicted and each figure scans its mesh:
## fine for the certifier; the consumer (CF04c) must key it on the shared skin and mesh instead.
static func bind(player: AnimationPlayer, skeleton: Skeleton3D) -> Dictionary:
	var id: int = skeleton.get_instance_id()
	if not _bound_by_id.has(id):
		var meshes: Array[Node] = skeleton.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1:
			return {"ok": false, "reason": "royal figure must have one skinned mesh"}
		var mesh: MeshInstance3D = meshes[0]
		var rest: Dictionary = rest_of(skeleton, mesh.skin, load(SOURCE).landmarks)
		var hooves: Dictionary = patches(mesh, plan())
		var stand: Dictionary = seat(rest, Provider.locals(player, skeleton, "STANDBY", 0.0, rest.bones), hooves)
		if stand.is_empty():
			return {"ok": false, "reason": "royal stand could not be seated"}
		_bound_by_id[id] = {"ok": true, "reason": "", "rest": rest, "patches": hooves, "stand": stand}
	return _bound_by_id[id]
