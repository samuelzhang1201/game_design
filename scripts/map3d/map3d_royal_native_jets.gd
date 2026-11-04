class_name Map3DRoyalNativeJets
extends RefCounted
## Copied R1 input, never a clock, carrier, solver or contact certificate.
## The smooth branch extension keeps native delta/dot/omega/sinom constants
## (the sinom constant is enclosed by the accepted scalar receipt);
## from, coefficient, sine and affine operations are differentiated over reals.
## Each scalar stores real value/derivative intervals and a separate absolute
## native-value error. IEEE rounding is propagated, not differentiated.
## Affines are row-major 3x4; derivative affines have homogeneous bottom row ZERO.

const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const EPS: float = 0.00001 # Native Animation::_find / Math::is_zero_approx.
const U32: float = 0.00000011920928955078125
const TINY32: float = 1.1754943508222875e-38
const U64: float = 2.220446049250313e-16
const TINY64: float = 2.2250738585072014e-308
# Interval endpoint inputs are bounded by 2^100; even input FTZ in a product
# loses <2^101*2^-1022. 2^-900 encloses that loss and output FTZ as well.
const INTERVAL_FTZ: float = 1.1830521861667747e-271
const SIN_ERROR: float = 3.552713678800501e-15
const SINF_ERROR: float = 0.0000002384185791015625
# Accepted #244 exact instruction profiles AND recomputable theorem, not guessed ULPs.
const VERIFIER: String = "37f34e84334c12ed9194539d4e16505e461927ad17fd84553931f2e60ff9dc4f"
const COLLECTOR: String = "efe3205cd8d745c4a417c8db0b19ac7865f7e3132fe4754e4409b83368405b28"
const CAPTURE_SCRIPT: String = "32a552af84726cb5fe921397ab48e2c3d1460e84f0e76cae28a9a4bfac0f502e"
# Both official builds have identical Animation::_find/_interpolate, slerp,
# quaternion constructor/get_angle and Basis::set_quaternion implementations.
const BUILDS: Dictionary = {
	"ed1daf0bf001b61586d9930840f2f1394092c079": "c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf",
	"5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88": "f85bbc6b15e22416c7d797cd60b63286dd67b9cb13498847056c18520ae55a75"}
const PROFILES: Dictionary = {
	"macos-arm64": ["a3fb340f3ed530f48b649d5860f64d35", "7392ed11d47e03ef48984fe3bdd8b557336c6aa458b8bfdc377b4b7423bad65f", "09a05d8d7e98cd2c303e0a60f22a468371d13f91ef4796692796cc1c7684dea4", "/usr/lib/system/libsystem_m.dylib"],
	"linux-x86_64": ["cfae91b4a956116b64e2a41607671c1eeb3cc292", "a9e22f227c9a3a114f4fe0cd53a6777397d402a4caa8575c407186687fe9e90a", "fd4d9b804425c7009093b235d9da17eb7fcd1064a9afb7eff900e0a85e44aea8", "/usr/lib/x86_64-linux-gnu/libm.so.6"]}

var _source: Dictionary
var _tracks: Array[Dictionary] = []
var _cells: Array[Dictionary] = []
var _cuts: Array[float] = []
var _domain: Dictionary
var _issue: String = ""
var _geometry: Array[float] = [0.0, 0.0, 0.0, 0.0]


## arithmetic={receipt:Dictionary, capture_canonical:String}. The latter is the
## accepted producer's canonical capture bytes, not a reserialized float JSON.
static func prepare(source: Variant, identity: Variant, arithmetic: Variant) -> Dictionary:
	var reason: String = _schema_error(source)
	if not reason.is_empty():
		return _reject(reason)
	var valid: Dictionary = Source.validate(source, identity)
	if not valid.ok:
		return _reject("source:" + str(valid.diagnostics.reason))
	reason = _proof_error(arithmetic, identity)
	if not reason.is_empty():
		return _reject(reason)
	var authority: Map3DRoyalNativeJets = Map3DRoyalNativeJets.new()
	authority._source = source.duplicate(true)
	authority._source.animation = source.animation.duplicate(true)
	var result: Dictionary = authority._prepare(arithmetic.receipt.sha256)
	if not result.ok:
		return result
	return {"ok": true, "authority": authority, "domain": authority._domain.duplicate(true), "activation_pass": false}


func domain() -> Dictionary:
	return _domain.duplicate(true)


## Phase 1 is admitted only as 1-. At any native cut, left and right select
## separate branch limits; at authored keys the native approximate search still
## decides. No finite derivative is assigned to a crossing discontinuity.
func sample(phase: Variant, side: Variant = "right") -> Dictionary:
	if not phase is float or not is_finite(phase) or _negative(phase) or phase > 1.0 or not side is String or side not in ["left", "right"] or (phase == 1.0 and side != "left"):
		return _reject("phase_or_side")
	var length: float = _source.animation.length
	var time: float = phase * length
	if phase == 0.0 and side == "left":
		time = length
	var cell: int = _cell_at(time, side)
	var selected: Dictionary = _cells[cell]
	var lookup: float = time
	if side == "left" and _native_cut(time):
		lookup = -_next(-time)
	var input_error: float = _ua(_up(absf(time - lookup)), _ua(_um(absf(time), U64), TINY64))
	_issue = ""
	var box: Dictionary = _pose_box(selected.branches, time, time, input_error)
	if not _issue.is_empty():
		return _reject(_issue)
	var native: Dictionary = _native(lookup)
	if not native.ok:
		return native
	var locals_out: Array[Dictionary] = []
	var globals_out: Array[Dictionary] = []
	var skin_out: Array[Dictionary] = []
	for matrix: Array in box.locals:
		locals_out.append(_packet(matrix, length))
	for matrix: Array in box.globals:
		globals_out.append(_packet(matrix, length))
	for matrix: Array in box.skin:
		skin_out.append(_packet(matrix, length))
	var soles: Dictionary = {}
	for hoof: String in _source.calibration.sole_patches:
		var patch: Dictionary = _source.calibration.sole_patches[hoof]
		var bone: int = _bone_index(hoof)
		var matrix: Array = _matmul(_matmul(_constant_matrix(_source.model_from_skeleton), box.globals[bone]), _constant_matrix(patch.bone_from_sole))
		soles[hoof] = _packet(matrix, length)
		soles[hoof]["native_value"] = _source.model_from_skeleton * native.globals[bone] * patch.bone_from_sole
	var materials: Array[Dictionary] = _materials(box.skin, box.material_error, length)
	if not _issue.is_empty():
		return _reject(_issue)
	return {"ok": true, "phase": phase, "side": side, "native_time": time,
		"lookup_time": lookup, "derivative_kind": "one_sided_branch_extension", "crossing_derivative": null, "cell": cell, "branches": selected.branches.duplicate(true),
		"locals": native.locals, "globals": native.globals, "positions": native.positions,
		"local_jets": locals_out, "global_jets": globals_out, "skin_jets": skin_out,
		"sole_jets": soles, "material_jets": materials, "source_sha256": _source.sha256,
		"arithmetic_sha256": _domain.arithmetic_sha256, "domain_sha256": _domain.sha256, "activation_pass": false}


func _prepare(receipt_sha: String) -> Dictionary:
	var animation: Animation = _source.animation
	_cuts = [0.0, animation.length]
	for surface: Dictionary in _source.surfaces:
		var arrays: Array = surface.arrays
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			for axis: int in 3:
				_geometry[axis] = maxf(_geometry[axis], absf(v[axis]))
		for w: float in arrays[Mesh.ARRAY_WEIGHTS]:
			_geometry[3] = maxf(_geometry[3], w)
	var vertex_count: int = 0
	for surface: Dictionary in _source.surfaces:
		vertex_count += surface.arrays[Mesh.ARRAY_VERTEX].size()
	for i: int in animation.get_track_count():
		var times: Array[float] = []
		var values: Array = []
		for k: int in animation.track_get_key_count(i):
			var t: float = animation.track_get_key_time(i, k)
			times.append(t)
			values.append(animation.track_get_key_value(i, k))
			if not _cuts.has(t):
				_cuts.append(t)
			var cut: float = _early_cut(t)
			if cut > 0.0 and cut < animation.length and not _cuts.has(cut):
				_cuts.append(cut)
		_tracks.append({"times": times, "values": values, "bone": _source.tracks[i].bone,
			"type": animation.track_get_type(i), "enabled": animation.track_is_enabled(i),
			"step": animation.track_get_interpolation_type(i) == Animation.INTERPOLATION_NEAREST,
			"wrap": animation.track_get_interpolation_loop_wrap(i) and animation.loop_mode == Animation.LOOP_LINEAR,
			"transitions": []})
		for k: int in times.size():
			_tracks[-1].transitions.append(animation.track_get_key_transition(i, k))
	_cuts.sort()
	for i: int in _cuts.size() - 1:
		var result: Dictionary = _certify(_cuts[i], _cuts[i + 1], 0)
		if not result.ok:
			return result
	var records: Array[Dictionary] = []
	for cell: Dictionary in _cells:
		records.append({"native_time": [cell.start, cell.end], "branches": cell.branches.duplicate(true),
			"material_native_error": cell.material_error, "global_native_error": cell.global_error})
	_domain = {"schema": "royal-native-jets/1", "source_sha256": _source.sha256,
		"arithmetic_sha256": receipt_sha, "length": animation.length, "phase": [0.0, 1.0],
		"complete_phase_domain": true, "cells": records, "bone_count": _source.bones.size(),
		"vertex_count": vertex_count, "track_count": _tracks.size(),
		"extension": "native branch constants; real time-dependent operations; one-sided at cuts",
		"units": "native seconds; phase derivative = native-time derivative * actual L",
		"scope": "native values, extension derivatives and arithmetic only", "activation_pass": false}
	_domain["sha256"] = Source._digest(_domain)
	return {"ok": true}


func _certify(start: float, end: float, depth: int) -> Dictionary:
	var middle: float = start + (end - start) * 0.5
	var branches: Array[Dictionary] = []
	for track: Dictionary in _tracks:
		branches.append(_branch(track, middle))
		if not _issue.is_empty():
			return _reject(_issue)
	_issue = ""
	var box: Dictionary = _pose_box(branches, start, end, _ua(_um(end, U64), TINY64))
	if not _issue.is_empty():
		var failed: String = _issue
		_issue = ""
		if depth >= 32 or middle <= start or middle >= end:
			return _reject("uncovered_cell:" + failed + ":" + str([start, end]))
		var left: Dictionary = _certify(start, middle, depth + 1)
		if not left.ok:
			return left
		return _certify(middle, end, depth + 1)
	var global_error: Array[PackedFloat64Array] = []
	for matrix: Array in box.globals:
		var errors: PackedFloat64Array = PackedFloat64Array()
		for scalar: PackedFloat64Array in matrix:
			errors.append(scalar[4])
		global_error.append(errors)
	_cells.append({"start": start, "end": end, "branches": branches,
		"material_error": box.material_error, "global_error": global_error})
	return {"ok": true}


func _branch(track: Dictionary, time: float) -> Dictionary:
	var index: int = _find(track.times, time)
	var last: int = track.times.size() - 1
	var start_edge: bool = index == -1
	var end_edge: bool = index >= last
	if start_edge:
		index = last if track.wrap else 0
	var next: int = (index + 1) % track.times.size() if track.wrap else mini(index + 1, last)
	var delta: float = _f32(track.times[next] - track.times[index])
	if not track.wrap and (start_edge or end_edge):
		delta = 0.0
	var offset: float = -track.times[index]
	if track.wrap and start_edge:
		var endtime: float = maxf(0.0, _f32(_source.animation.length - track.times[index]))
		delta = _f32(endtime + track.times[next])
		offset = endtime
	elif track.wrap and end_edge:
		delta = _f32((_source.animation.length - track.times[index]) + track.times[next])
	var direct: bool = track.times.size() == 1 or track.step or track.transitions[index] == 0.0
	var zero_delta: bool = absf(delta) < _f32(EPS)
	var constant: bool = direct or zero_delta
	var result: Dictionary = {"bone": track.bone, "type": track.type, "enabled": track.enabled,
		"index": index, "next": next, "a": track.values[index], "b": track.values[next],
		"offset": offset, "delta": delta, "constant": constant, "direct": direct, "zero_delta": zero_delta, "step": track.step,
		"spherical": false, "negative_dot": false}
	if track.enabled and not direct and track.type == Animation.TYPE_ROTATION_3D:
		var a: Quaternion = result.a
		var b: Quaternion = result.b
		var dot: float = a.dot(b)
		result.negative_dot = dot < 0.0
		result.cosom = absf(dot)
		result.spherical = _f32(1.0 - absf(dot)) > _f32(EPS)
		if result.negative_dot:
			result.b = -b
		if result.spherical:
			if result.cosom < 0.9 or result.cosom > 1.0:
				_issue = "acosf_domain"
				return result
			# get_angle exposes real_t acos(w); the factor two is exact here.
			# Enclose native sinf(omega) with #244, including its output rounding.
			result.omega = Quaternion(0.0, 0.0, 0.0, result.cosom).get_angle() * 0.5
			var sine: Array[float] = _trig_point(result.omega, false)
			result.sinom = PackedFloat64Array([_down(sine[0] - SINF_ERROR), _up(sine[1] + SINF_ERROR), 0.0, 0.0, 0.0])
			if result.omega < 0.0 or result.omega >= 0.48 or result.sinom[0] <= 0.0:
				_issue = "native_slerp_constants"
	return result


func _pose_box(branches: Array[Dictionary], start: float, end: float, time_error: float) -> Dictionary:
	var components: Array[Dictionary] = []
	for bone: Dictionary in _source.bones:
		components.append({"p": _vector(bone.position), "q": _vector(bone.rotation), "s": _vector(bone.scale)})
	var time: PackedFloat64Array = PackedFloat64Array([start, end, 1.0, 1.0, time_error])
	for branch: Dictionary in branches:
		if not branch.enabled:
			continue
		var a: Array = _vector(branch.a)
		var b: Array = _vector(branch.b)
		var out: Array = []
		if branch.direct:
			out = a
		else:
			var coefficient: PackedFloat64Array = _c(0.0)
			if not branch.zero_delta:
				coefficient = _div(_cast(_add(time, _c(branch.offset), 64), 32), _c(branch.delta), 32)
			if coefficient[0] - coefficient[4] < -1.0 / 512.0 or coefficient[1] + coefficient[4] > 513.0 / 512.0:
				_issue = "native_coefficient_domain"
				return {}
			if branch.type != Animation.TYPE_ROTATION_3D:
				for axis: int in 3:
					out.append(_add(a[axis], _mul(_sub(b[axis], a[axis]), coefficient)))
			else:
				var scale0: PackedFloat64Array = _sub(_c(1.0), coefficient)
				var scale1: PackedFloat64Array = coefficient
				if branch.spherical:
					scale0 = _cast(_div(_sin(_mul(_sub(_c(1.0), coefficient, 64), _c(branch.omega), 64), 64), branch.sinom, 64), 32)
					scale1 = _div(_sin(_mul(coefficient, _c(branch.omega)), 32), branch.sinom)
				for axis: int in 4:
					out.append(_add(_mul(scale0, a[axis]), _mul(scale1, b[axis])))
		var key: String = "q" if branch.type == Animation.TYPE_ROTATION_3D else "p" if branch.type == Animation.TYPE_POSITION_3D else "s"
		components[branch.bone][key] = out
	var locals_out: Array[Array] = []
	var globals_out: Array[Array] = []
	for i: int in components.size():
		for scale: PackedFloat64Array in components[i].s:
			if scale[0] - scale[4] <= 0.0 and scale[1] + scale[4] >= 0.0:
				_issue = "scale_not_separated"
		var local: Array = _local(components[i])
		locals_out.append(local)
		var parent: int = _source.bones[i].parent
		globals_out.append(local if parent == -1 else _matmul(globals_out[parent], local))
		if not _matrix_finite(globals_out[-1]):
			_issue = "nonfinite_global_jet"
		if not _issue.is_empty():
			return {}
	var skin: Array[Array] = []
	for bind: Dictionary in _source.binds:
		skin.append(_matmul(globals_out[bind.bone], _constant_matrix(bind.inverse_bind)))
	for matrix: Array in skin:
		if not _matrix_finite(matrix):
			_issue = "nonfinite_skin_jet"
			return {}
	var material_error: PackedFloat64Array = _uniform_material_error(skin)
	return {"locals": locals_out, "globals": globals_out, "skin": skin, "material_error": material_error}


func _local(components: Dictionary) -> Array:
	var q: Array = components.q
	var d: PackedFloat64Array = _c(0.0)
	for component: PackedFloat64Array in q:
		d = _add(d, _square(component))
	var s: PackedFloat64Array = _div(_c(2.0), d)
	var xs: PackedFloat64Array = _mul(q[0], s)
	var ys: PackedFloat64Array = _mul(q[1], s)
	var zs: PackedFloat64Array = _mul(q[2], s)
	var wx: PackedFloat64Array = _mul(q[3], xs)
	var wy: PackedFloat64Array = _mul(q[3], ys)
	var wz: PackedFloat64Array = _mul(q[3], zs)
	var xx: PackedFloat64Array = _mul(q[0], xs)
	var xy: PackedFloat64Array = _mul(q[0], ys)
	var xz: PackedFloat64Array = _mul(q[0], zs)
	var yy: PackedFloat64Array = _mul(q[1], ys)
	var yz: PackedFloat64Array = _mul(q[1], zs)
	var zz: PackedFloat64Array = _mul(q[2], zs)
	var entries: Array = [_sub(_c(1.0), _add(yy, zz)), _sub(xy, wz), _add(xz, wy),
		_add(xy, wz), _sub(_c(1.0), _add(xx, zz)), _sub(yz, wx),
		_sub(xz, wy), _add(yz, wx), _sub(_c(1.0), _add(xx, yy))]
	var matrix: Array = []
	# R1 composes Basis(q)*Basis.from_scale, including its native multiply/adds.
	for row: int in 3:
		for col: int in 3:
			var value: PackedFloat64Array = _c(0.0)
			for k: int in 3:
				value = _add(value, _mul(entries[row * 3 + k], components.s[k] if k == col else _c(0.0)))
			matrix.append(value)
		matrix.append(components.p[row])
	return matrix


func _native(time: float) -> Dictionary:
	# Exactly R1's native interpolation, TRS/FK, bind order and raw LBS path.
	var animation: Animation = _source.animation
	var components: Array = _source.bones.duplicate(true)
	for i: int in _source.tracks.size():
		var track: Dictionary = _source.tracks[i]
		if not track.enabled:
			continue
		match track.type:
			Animation.TYPE_POSITION_3D:
				components[track.bone].position = animation.position_track_interpolate(i, time)
			Animation.TYPE_ROTATION_3D:
				components[track.bone].rotation = animation.rotation_track_interpolate(i, time)
			Animation.TYPE_SCALE_3D:
				components[track.bone].scale = animation.scale_track_interpolate(i, time)
	var locals_out: Dictionary = {}
	var globals_out: Array[Transform3D] = []
	for bone: Dictionary in components:
		var local: Transform3D = Transform3D(Basis(bone.rotation) * Basis.from_scale(bone.scale), bone.position)
		if not Source._affine(local):
			return _reject("singular_native_pose")
		locals_out[bone.name] = local
		globals_out.append(local if bone.parent == -1 else globals_out[bone.parent] * local)
	var skin: Array[Transform3D] = []
	for bind: Dictionary in _source.binds:
		skin.append(globals_out[bind.bone] * bind.inverse_bind)
	var positions: Array[PackedVector3Array] = []
	for surface: Dictionary in _source.surfaces:
		var vertices: PackedVector3Array = Source._skin_vertices(surface.arrays, skin)
		for i: int in vertices.size():
			vertices[i] = _source.model_from_skeleton * vertices[i]
		positions.append(vertices)
	return {"ok": true, "locals": locals_out, "globals": globals_out, "positions": positions}


func _uniform_material_error(skin: Array[Array]) -> PackedFloat64Array:
	var input: Array = []
	for axis: int in 3:
		input.append(PackedFloat64Array([-_geometry[axis], _geometry[axis], 0.0, 0.0, 0.0]))
	var hull: Array = []
	for axis: int in 3:
		var scalar: PackedFloat64Array = PackedFloat64Array([INF, -INF, 0.0, 0.0, 0.0])
		for matrix: Array in skin:
			var p: PackedFloat64Array = _c(0.0)
			for col: int in 3:
				p = _add(p, _mul(matrix[axis * 4 + col], input[col]))
			p = _add(p, matrix[axis * 4 + 3])
			scalar[0] = minf(scalar[0], p[0])
			scalar[1] = maxf(scalar[1], p[1])
			scalar[4] = maxf(scalar[4], p[4])
		hull.append(scalar)
	var sum: Array = [_c(0.0), _c(0.0), _c(0.0)]
	var weight: PackedFloat64Array = PackedFloat64Array([0.0, _geometry[3], 0.0, 0.0, 0.0])
	for k: int in 4:
		for axis: int in 3:
			sum[axis] = _add(sum[axis], _mul(hull[axis], weight))
	var world: Array = _point(_constant_matrix(_source.model_from_skeleton), sum)
	return PackedFloat64Array([world[0][4], world[1][4], world[2][4]])


func _materials(skin: Array[Array], error: PackedFloat64Array, length: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var frame: Transform3D = _source.model_from_skeleton
	for surface: Dictionary in _source.surfaces:
		var arrays: Array = surface.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var lower: PackedFloat64Array = PackedFloat64Array()
		var upper: PackedFloat64Array = PackedFloat64Array()
		var dl: PackedFloat64Array = PackedFloat64Array()
		var du: PackedFloat64Array = PackedFloat64Array()
		var derivative: PackedFloat64Array = PackedFloat64Array()
		var phase_derivative: PackedFloat64Array = PackedFloat64Array()
		var phase_dl: PackedFloat64Array = PackedFloat64Array()
		var phase_du: PackedFloat64Array = PackedFloat64Array()
		for v: int in vertices.size():
			var bounds: Array[Array] = [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
			for k: int in 4:
				var index: int = v * 4 + k
				var matrix: Array = skin[arrays[Mesh.ARRAY_BONES][index]]
				var w: float = arrays[Mesh.ARRAY_WEIGHTS][index]
				for axis: int in 3:
					for col: int in 4:
						var factor: float = w * (vertices[v][col] if col < 3 else 1.0)
						# Both factors are binary32: their product is EXACT binary64.
						var scalar: PackedFloat64Array = matrix[axis * 4 + col]
						for kind: int in [0, 2]:
							bounds[axis][kind] = _down(bounds[axis][kind] + _down(minf(scalar[kind] * factor, scalar[kind + 1] * factor)))
							bounds[axis][kind + 1] = _up(bounds[axis][kind + 1] + _up(maxf(scalar[kind] * factor, scalar[kind + 1] * factor)))
			for axis: int in 3:
				var result: Array[float] = [float(frame.origin[axis]), float(frame.origin[axis]), 0.0, 0.0]
				for col: int in 3:
					var factor: float = frame.basis[col][axis]
					for kind: int in [0, 2]:
						result[kind] = _down(result[kind] + _down(minf(bounds[col][kind] * factor, bounds[col][kind + 1] * factor)))
						result[kind + 1] = _up(result[kind + 1] + _up(maxf(bounds[col][kind] * factor, bounds[col][kind + 1] * factor)))
				lower.append(result[0]); upper.append(result[1])
				dl.append(result[2]); du.append(result[3])
				derivative.append(result[2] + (result[3] - result[2]) * 0.5)
				phase_derivative.append(derivative[-1] * length)
				phase_dl.append(_down(result[2] * length)); phase_du.append(_up(result[3] * length))
		out.append({"extension_lower": lower, "extension_upper": upper,
			"time_derivative": derivative, "time_derivative_lower": dl, "time_derivative_upper": du,
			"phase_derivative": phase_derivative, "phase_derivative_lower": phase_dl, "phase_derivative_upper": phase_du,
			"native_error_uniform": error.duplicate()})
	return out


func _matmul(a: Array, b: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		for col: int in 4:
			var scalar: PackedFloat64Array = _c(0.0)
			for k: int in 3:
				scalar = _add(scalar, _mul(a[row * 4 + k], b[k * 4 + col]))
			if col == 3:
				scalar = _add(scalar, a[row * 4 + 3])
			out.append(scalar)
	return out


func _point(matrix: Array, point: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		var scalar: PackedFloat64Array = _c(0.0)
		for col: int in 3:
			scalar = _add(scalar, _mul(matrix[row * 4 + col], point[col]))
		out.append(_add(scalar, matrix[row * 4 + 3]))
	return out


static func _matrix_finite(matrix: Array) -> bool:
	for scalar: PackedFloat64Array in matrix:
		for value: float in scalar:
			if not is_finite(value) or absf(value) >= 1.2676506002282294e30:
				return false
	return true


static func _constant_matrix(t: Transform3D) -> Array:
	var matrix: Array = []
	for row: int in 3:
		for col: int in 3:
			matrix.append(_c(t.basis[col][row]))
		matrix.append(_c(t.origin[row]))
	return matrix


static func _vector(value: Variant) -> Array:
	var out: Array = []
	for i: int in (4 if value is Quaternion else 3):
		out.append(_c(value[i]))
	return out


static func _packet(matrix: Array, length: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["extension_lower", "extension_upper", "time_derivative_lower", "time_derivative_upper", "native_error"]:
		result[key] = PackedFloat64Array()
	for scalar: PackedFloat64Array in matrix:
		result.extension_lower.append(scalar[0]); result.extension_upper.append(scalar[1])
		result.time_derivative_lower.append(scalar[2]); result.time_derivative_upper.append(scalar[3])
		result.native_error.append(scalar[4])
	result.time_derivative = PackedFloat64Array()
	result.phase_derivative = PackedFloat64Array()
	result.phase_derivative_lower = PackedFloat64Array()
	result.phase_derivative_upper = PackedFloat64Array()
	for i: int in matrix.size():
		var value: float = matrix[i][2] + (matrix[i][3] - matrix[i][2]) * 0.5
		result.time_derivative.append(value); result.phase_derivative.append(value * length)
		result.phase_derivative_lower.append(_down(matrix[i][2] * length))
		result.phase_derivative_upper.append(_up(matrix[i][3] * length))
	return result


static func _c(value: float) -> PackedFloat64Array:
	return PackedFloat64Array([value, value, 0.0, 0.0, 0.0])


func _cast(a: PackedFloat64Array, bits: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = a.duplicate()
	out[4] = _ua(a[4], _round_error(_ua(_magnitude(a), a[4]), bits))
	return out


func _add(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var lo: float = _down(a[0] + b[0])
	var hi: float = _up(a[1] + b[1])
	var error: float = _ua(_ua(a[4], b[4]), 2.0 * _tiny(bits))
	error = _ua(error, _round_error(_ua(maxf(absf(lo), absf(hi)), error), bits))
	return PackedFloat64Array([lo, hi, _down(a[2] + b[2]), _up(a[3] + b[3]), error])


func _sub(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	return _add(a, PackedFloat64Array([-b[1], -b[0], -b[3], -b[2], b[4]]), bits)


func _mul(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var real: Array[float] = _product(a[0], a[1], b[0], b[1])
	var left: Array[float] = _product(a[2], a[3], b[0], b[1])
	var right: Array[float] = _product(a[0], a[1], b[2], b[3])
	var ae: float = _ua(a[4], _tiny(bits))
	var be: float = _ua(b[4], _tiny(bits))
	var error: float = _ua(_ua(_um(_magnitude(a), be), _um(_magnitude(b), ae)), _um(ae, be))
	error = _ua(error, _round_error(_ua(maxf(absf(real[0]), absf(real[1])), error), bits))
	return PackedFloat64Array([real[0], real[1], _down(left[0] + right[0]), _up(left[1] + right[1]), error])


func _square(a: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = _mul(a, a)
	out[0] = 0.0 if a[0] <= 0.0 and a[1] >= 0.0 else _down(minf(a[0] * a[0], a[1] * a[1]))
	return out


func _div(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var minimum: float = minf(absf(b[0]), absf(b[1]))
	if (b[0] <= 0.0 and b[1] >= 0.0) or minimum <= _ua(b[4], _tiny(bits)) or minimum < 7.888609052210118e-31:
		_issue = "denominator_not_separated"
		return _c(0.0)
	var inverse: Array[float] = [_down(1.0 / b[1]), _up(1.0 / b[0])]
	var value: Array[float] = _product(a[0], a[1], inverse[0], inverse[1])
	var ab: Array[float] = _product(a[0], a[1], b[2], b[3])
	var da: Array[float] = _product(a[2], a[3], b[0], b[1])
	var den: Array[float] = [_down(minimum * minimum), _up(maxf(b[0] * b[0], b[1] * b[1]))]
	var deriv: Array[float] = _product(_down(da[0] - ab[1]), _up(da[1] - ab[0]), _down(1.0 / den[1]), _up(1.0 / den[0]))
	var magnitude: float = maxf(absf(value[0]), absf(value[1]))
	var error: float = _up(_ua(_ua(a[4], _tiny(bits)), _um(magnitude, _ua(b[4], _tiny(bits)))) / _down(_down(minimum - b[4]) - _tiny(bits)))
	error = _ua(error, _round_error(_ua(magnitude, error), bits))
	return PackedFloat64Array([value[0], value[1], deriv[0], deriv[1], error])


func _sin(a: PackedFloat64Array, bits: int) -> PackedFloat64Array:
	if a[0] - a[4] < -0.5 or a[1] + a[4] > 0.5:
		_issue = "sine_domain"
		return _c(0.0)
	var lo: Array[float] = _trig_point(a[0], false)
	var hi: Array[float] = _trig_point(a[1], false)
	var cl: Array[float] = _trig_point(a[0], true)
	var cr: Array[float] = _trig_point(a[1], true)
	var cosine: Array[float] = [minf(cl[0], cr[0]), 1.0 if a[0] <= 0.0 and a[1] >= 0.0 else maxf(cl[1], cr[1])]
	var derivative: Array[float] = _product(cosine[0], cosine[1], a[2], a[3])
	return PackedFloat64Array([lo[0], hi[1], derivative[0], derivative[1], _ua(a[4], (SIN_ERROR if bits == 64 else SINF_ERROR))])


## Alternating series through sin degree21 / cos degree20, |x|<=1/2.
## Recurrence intervals include coefficient division and every binary64 operation.
static func _trig_point(x: float, cosine: bool) -> Array[float]:
	var initial: float = 1.0 if cosine else x
	var term: Array[float] = [initial, initial]
	var sum: Array[float] = term.duplicate()
	var square: Array[float] = [_down(x * x), _up(x * x)]
	for k: int in range(1, 11):
		var denominator: float = float((2 * k - 1) * (2 * k) if cosine else (2 * k) * (2 * k + 1))
		term = _product(term[0], term[1], -square[1], -square[0])
		term = [_down(term[0] / denominator), _up(term[1] / denominator)]
		sum = [_down(sum[0] + term[0]), _up(sum[1] + term[1])]
	# The next term bounds the entire alternating tail, with outward arithmetic.
	var denominator: float = 22.0 * 21.0 if cosine else 22.0 * 23.0
	var tail: float = _up(_um(maxf(absf(term[0]), absf(term[1])), square[1]) / denominator)
	return [_down(sum[0] - tail), _up(sum[1] + tail)]


func _round_error(magnitude: float, bits: int) -> float:
	if not is_finite(magnitude) or magnitude >= 1.2676506002282294e30:
		_issue = "arithmetic_range"
		return INF
	return _ua(_um(magnitude, (U32 if bits == 32 else U64)), _tiny(bits))


static func _ua(a: float, b: float) -> float:
	return _up(a + b)


static func _um(a: float, b: float) -> float:
	return _up(a * b)


static func _tiny(bits: int) -> float:
	return TINY32 if bits == 32 else TINY64


static func _magnitude(a: PackedFloat64Array) -> float:
	return maxf(absf(a[0]), absf(a[1]))


static func _product(al: float, au: float, bl: float, bu: float) -> Array[float]:
	if maxf(maxf(absf(al), absf(au)), maxf(absf(bl), absf(bu))) >= 1.2676506002282294e30:
		return [-INF, INF]
	return [_down(minf(minf(al * bl, al * bu), minf(au * bl, au * bu))),
		_up(maxf(maxf(al * bl, al * bu), maxf(au * bl, au * bu)))]


static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func _up(value: float) -> float:
	return _next(value + INTERVAL_FTZ)


static func _next(value: float) -> float:
	if not is_finite(value):
		return value
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var bits: int = bytes.decode_s64(0)
	if (bits & 0x7fffffffffffffff) == 0:
		bytes.encode_s64(0, 1)
	else:
		bytes.encode_s64(0, bits + (1 if bits >= 0 else -1))
	return bytes.decode_double(0)


static func _negative(value: float) -> bool:
	# Floating comparisons may treat a negative subnormal as -0 under FTZ.
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var bits: int = bytes.decode_s64(0)
	return bits < 0 and (bits & 0x7fffffffffffffff) != 0


static func _down(value: float) -> float:
	return -_up(-value)


static func _find(times: Array[float], time: float) -> int:
	var low: int = 0
	var high: int = times.size() - 1
	var middle: int = 0
	while low <= high:
		middle = (low + high) / 2
		if absf(time - times[middle]) < EPS or time == times[middle]:
			return middle
		if time < times[middle]: high = middle - 1
		else: low = middle + 1
	return middle - 1 if times[middle] > time else middle


## First binary64 argument accepted by the native approximate-equality test.
## Disjoint key bands (checked below) make this independent of binary-search order.
static func _early_cut(time: float) -> float:
	if time == 0.0 or absf(time) < EPS:
		return 0.0
	var low: float = maxf(0.0, time - 2.0 * EPS)
	var high: float = time
	for iteration: int in 64:
		if _next(low) >= high:
			break
		var middle: float = low + (high - low) * 0.5
		if absf(middle - time) < EPS: high = middle
		else: low = middle
	return high


func _native_cut(time: float) -> bool:
	if time == _source.animation.length:
		return true
	for track: Dictionary in _tracks:
		if track.enabled and _find(track.times, time) != _find(track.times, -_next(-time)):
			return true
	return false


func _cell_at(time: float, side: String) -> int:
	var low: int = 0
	var high: int = _cells.size() - 1
	while low < high:
		var middle: int = (low + high) / 2
		if time < _cells[middle].end or (side == "left" and time == _cells[middle].end): high = middle
		else: low = middle + 1
	return low


func _bone_index(name: String) -> int:
	for i: int in _source.bones.size():
		if _source.bones[i].name == name:
			return i
	return -1


static func _schema_error(source: Variant) -> String:
	if not source is Dictionary or not source.get("animation") is Animation or source.animation.get_script() != null:
		return "source_schema"
	for name: String in ["bones", "binds", "surfaces", "tracks"]:
		if not source.get(name) is Array or source[name].is_empty():
			return "source_array:" + name
	if not source.get("calibration") is Dictionary or not source.calibration.get("sole_patches") is Dictionary or not Source._affine(source.get("model_from_skeleton")):
		return "source_frames"
	var animation: Animation = source.animation
	if not is_finite(animation.length) or animation.length <= 0.0 or animation.length > 1.0 or animation.loop_mode not in [Animation.LOOP_LINEAR, Animation.LOOP_NONE] or animation.get_track_count() != source.tracks.size():
		return "unsupported_animation"
	var names: Array[String] = []
	for i: int in source.bones.size():
		var bone: Variant = source.bones[i]
		if not bone is Dictionary or not bone.get("name") is String or names.has(bone.name) or not bone.get("parent") is int or bone.parent < -1 or bone.parent >= i or not bone.get("position") is Vector3 or not bone.get("rotation") is Quaternion or not bone.get("scale") is Vector3 or not bone.get("rest") is Transform3D:
			return "bone_schema"
		if not Source._finite(bone) or not bone.rotation.is_normalized() or bone.scale.x == 0.0 or bone.scale.y == 0.0 or bone.scale.z == 0.0:
			return "bone_pose"
		names.append(bone.name)
	var seen: Dictionary = {}
	for i: int in source.tracks.size():
		var track: Variant = source.tracks[i]
		if not track is Dictionary or not track.get("bone") is int or track.bone < 0 or track.bone >= source.bones.size() or not track.get("type") is int or not track.get("enabled") is bool:
			return "track_schema"
		var type: int = animation.track_get_type(i)
		var interpolation: int = animation.track_get_interpolation_type(i)
		var path: NodePath = animation.track_get_path(i)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or type != track.type or animation.track_is_enabled(i) != track.enabled or animation.track_is_compressed(i) or interpolation not in [Animation.INTERPOLATION_NEAREST, Animation.INTERPOLATION_LINEAR] or path.get_subname_count() != 1 or String(path.get_subname(0)) != source.bones[track.bone].name:
			return "unsupported_native_track"
		var key: String = str(track.bone) + ":" + str(type)
		if seen.has(key) or animation.track_get_key_count(i) < 1:
			return "duplicate_or_empty_track"
		seen[key] = true
		var previous: float = -1.0
		for k: int in animation.track_get_key_count(i):
			var time: float = animation.track_get_key_time(i, k)
			var value: Variant = animation.track_get_key_value(i, k)
			if not is_finite(time) or _negative(time) or time > animation.length or (k > 0 and time - previous <= 4.0 * EPS):
				return "unsupported_key_time"
			if animation.track_get_key_transition(i, k) not in [0.0, 1.0] or not Source._finite(value) or (type == Animation.TYPE_ROTATION_3D and (not value is Quaternion or not value.is_normalized())) or (type != Animation.TYPE_ROTATION_3D and not value is Vector3):
				return "unsupported_key_value_or_transition"
			previous = time
	for bind: Variant in source.binds:
		if not bind is Dictionary or not bind.get("bone") is int or bind.bone < 0 or bind.bone >= source.bones.size() or not Source._affine(bind.get("inverse_bind")):
			return "bind_schema"
	for surface: Variant in source.surfaces:
		if not surface is Dictionary or not surface.get("arrays") is Array or surface.arrays.size() != Mesh.ARRAY_MAX:
			return "surface_schema"
		var arrays: Array = surface.arrays
		if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_BONES] is PackedInt32Array or not arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array or arrays[Mesh.ARRAY_VERTEX].is_empty() or arrays[Mesh.ARRAY_BONES].size() != arrays[Mesh.ARRAY_VERTEX].size() * 4 or arrays[Mesh.ARRAY_WEIGHTS].size() != arrays[Mesh.ARRAY_BONES].size() or not Source._finite(arrays):
			return "skin_schema"
		for i: int in arrays[Mesh.ARRAY_BONES].size():
			if arrays[Mesh.ARRAY_BONES][i] < 0 or arrays[Mesh.ARRAY_BONES][i] >= source.binds.size() or arrays[Mesh.ARRAY_WEIGHTS][i] < 0.0:
				return "skin_index_or_weight"
	for hoof: Variant in source.calibration.sole_patches:
		var patch: Variant = source.calibration.sole_patches[hoof]
		if not hoof is String or not names.has(hoof) or not patch is Dictionary or not Source._affine(patch.get("bone_from_sole")):
			return "sole_schema"
	return ""


static func _proof_error(arithmetic: Variant, identity: Dictionary) -> String:
	if not arithmetic is Dictionary or not arithmetic.get("receipt") is Dictionary or not arithmetic.get("capture_canonical") is String or not Source._finite(arithmetic):
		return "arithmetic_schema"
	var receipt: Dictionary = arithmetic.receipt
	var capture: Variant = JSON.parse_string(arithmetic.capture_canonical)
	if not capture is Dictionary or not capture.get("native") is Dictionary or not capture.get("engine") is Dictionary or not capture.get("acquisition") is Dictionary:
		return "capture_schema"
	var native: Dictionary = capture.native
	var engine: Dictionary = capture.engine
	var acquisition: Dictionary = capture.acquisition
	var platform: Variant = native.get("platform")
	if not platform is String or not PROFILES.has(platform) or receipt.get("schema") != "royal-native-arithmetic/1" or receipt.get("status") != "closed_scalar_value_proof" or receipt.get("verifier_sha256") != VERIFIER or receipt.get("profile") != platform + "/" + PROFILES[platform][0]:
		return "arithmetic_profile"
	if receipt.get("scope") != "scalar values only; no derivative, source-domain, JETS or physical E acceptance" or receipt.get("assumptions") != "IEEE binary32/binary64 basic operations/FMA/sqrt; all rounding directions; explicit FTZ allowances; intermediates below 2^100":
		return "arithmetic_receipt_assumptions"
	var keys: Array = receipt.keys()
	keys.sort()
	if keys != ["assumptions", "capture_sha256", "engine_sha256", "profile", "schema", "scope", "sha256", "status", "theorems", "verifier_sha256"]:
		return "arithmetic_receipt_schema"
	if capture.get("schema") != "royal-native-arithmetic/1" or native.get("schema") != 1:
		return "arithmetic_capture_schema"
	var unsigned: Dictionary = receipt.duplicate(true)
	unsigned.erase("sha256")
	if receipt.get("sha256") != _sha(_json(unsigned)) or receipt.get("capture_sha256") != _sha(arithmetic.capture_canonical) or _sha(_json(receipt.get("theorems"))) != PROFILES[platform][2]:
		return "arithmetic_digest_or_theorem"
	if not identity.get("godot") is Dictionary or not engine.get("version") is Dictionary:
		return "arithmetic_engine_version"
	for key: String in ["major", "minor", "patch"]:
		if not _integer(engine.version.get(key)):
			return "arithmetic_engine_version"
	for key: String in ["hash", "major", "minor", "patch", "status", "build"]:
		if engine.version.get(key) != identity.godot.get(key):
			return "arithmetic_engine_version"
	if not BUILDS.has(engine.version.hash) or receipt.get("engine_sha256") != BUILDS[engine.version.hash]:
		return "unproved_native_engine_build"
	for key: String in ["header_sha256", "collector_sha256", "source_sha256", "script_sha256", "engine_sha256"]:
		if not _hash_string(acquisition.get(key)):
			return "arithmetic_acquisition"
	if acquisition.source_sha256 != COLLECTOR or acquisition.script_sha256 != CAPTURE_SCRIPT or receipt.get("engine_sha256") != acquisition.engine_sha256 or engine.get("executable_sha256") != acquisition.engine_sha256 or native.get("selected_engine_sha256") != acquisition.engine_sha256 or native.get("header_sha256") != acquisition.header_sha256 or engine.get("collector_sha256") != acquisition.collector_sha256:
		return "arithmetic_acquisition_identity"
	if not _integer(native.get("pid")) or native.get("pid", 0.0) <= 0.0 or native.get("pid") != engine.get("pid") or native.get("engine_path") != engine.get("executable") or native.get("engine_image_id") != acquisition.get("engine_image_id"):
		return "arithmetic_process_identity"
	var ids: Variant = acquisition.get("selected_binary_image_ids")
	if not ids is Array or (native.get("engine_image_id") not in ids if not str(native.get("engine_image_id", "")).is_empty() else (platform != "linux-x86_64" or not ids.is_empty())):
		return "arithmetic_engine_image"
	if engine.get("architecture") != ("arm64" if platform == "macos-arm64" else "x86_64") or native.get("engine_version_components") != [engine.version.major, engine.version.minor, engine.version.patch]:
		return "arithmetic_engine_architecture"
	if not native.get("imports") is Array or native.imports.size() != 3:
		return "arithmetic_imports"
	var profiles: Dictionary = {}
	for i: int in 3:
		var name: String = ["sin", "sinf", "acosf"][i]
		if not native.imports[i] is Array or native.imports[i].is_empty():
			return "arithmetic_imports"
		for record: Variant in native.imports[i]:
			if not record is Dictionary or record.get("symbol") != name or record.get("image_id") != PROFILES[platform][0] or record.get("image_path") != PROFILES[platform][3] or record.get("dlsym_equal") != (not (platform == "linux-x86_64" and name == "acosf")) or not _address(record.get("target")) or not _address(record.get("image_base")):
				return "arithmetic_import_binding"
			if record.target.hex_to_int() - record.image_base.hex_to_int() != record.get("entry_offset"):
				return "arithmetic_import_address"
			var selected: Dictionary = {}
			for key: String in (["code_offset", "entry_offset", "code", "extra_code", "operands"] if platform == "linux-x86_64" else ["code_offset", "entry_offset", "code"]):
				selected[key] = record.get(key)
			if profiles.has(name) and profiles[name] != selected:
				return "arithmetic_duplicate_import"
			profiles[name] = selected
	if _sha(_json(profiles)) != PROFILES[platform][1]:
		return "arithmetic_instruction_profile"
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _address(value: Variant) -> bool:
	if not value is String or not value.begins_with("0x") or value.length() < 3 or value.length() > 18:
		return false
	for c: String in value.substr(2):
		if not c in "0123456789abcdef":
			return false
	return true


static func _hash_string(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for c: String in value:
		if not c in "0123456789abcdef":
			return false
	return true


static func _json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys(); keys.sort()
		var parts: Array[String] = []
		for key: Variant in keys:
			parts.append(JSON.stringify(str(key)) + ":" + _json(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item: Variant in value:
			parts.append(_json(item))
		return "[" + ",".join(parts) + "]"
	if value is float and is_finite(value) and value == floor(value):
		return str(int(value))
	return JSON.stringify(value)


static func _sha(value: String) -> String:
	return value.sha256_text()


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "authority": null, "locals": {}, "globals": [], "positions": [],
		"diagnostics": {"reason": reason}, "activation_pass": false}
