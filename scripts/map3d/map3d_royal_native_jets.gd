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
const Math = preload("res://scripts/map3d/map3d_royal_jet_math.gd")
const InputGate = preload("res://scripts/map3d/map3d_royal_jet_input.gd")
var _math: Map3DRoyalJetMath = Math.new()

var _source: Dictionary
var _tracks: Array[Dictionary] = []
var _cells: Array[Dictionary] = []
var _cuts: Array[float] = []
var _domain: Dictionary
var _geometry: Array[float] = [0.0, 0.0, 0.0, 0.0]


## arithmetic={receipt:Dictionary, capture_canonical:String}. The latter is the
## accepted producer's canonical capture bytes, not a reserialized float JSON.
static func prepare(source: Variant, identity: Variant, arithmetic: Variant) -> Dictionary:
	var checked: Dictionary = InputGate.validate(source, identity, arithmetic)
	if checked.get("ok") != true:
		return _reject(str(checked.get("reason", "input_validation_failed")))
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
	if not phase is float or not is_finite(phase) or Math._negative(phase) or phase > 1.0 or not side is String or side not in ["left", "right"] or (phase == 1.0 and side != "left"):
		return _reject("phase_or_side")
	var length: float = _source.animation.length
	var time: float = phase * length
	if phase == 0.0 and side == "left":
		time = length
	var cell: int = _cell_at(time, side)
	var selected: Dictionary = _cells[cell]
	var lookup: float = time
	if side == "left" and _native_cut(time):
		lookup = -Math._next(-time)
	var input_error: float = Math._ua(Math._up(absf(time - lookup)), Math._ua(Math._um(absf(time), Math.U64), Math.TINY64))
	_math.issue = ""
	var box: Dictionary = _pose_box(selected.branches, time, time, input_error)
	if not _math.issue.is_empty():
		return _reject(_math.issue)
	var native: Dictionary = _native(lookup)
	if not native.ok:
		return native
	var locals_out: Array[Dictionary] = []
	var globals_out: Array[Dictionary] = []
	var skin_out: Array[Dictionary] = []
	for matrix: Array in box.locals:
		locals_out.append(Math._packet(matrix, length))
	for matrix: Array in box.globals:
		globals_out.append(Math._packet(matrix, length))
	for matrix: Array in box.skin:
		skin_out.append(Math._packet(matrix, length))
	var soles: Dictionary = {}
	for hoof: String in _source.calibration.sole_patches:
		var patch: Dictionary = _source.calibration.sole_patches[hoof]
		var bone: int = _bone_index(hoof)
		var matrix: Array = _math._matmul(_math._matmul(Math._constant_matrix(_source.model_from_skeleton), box.globals[bone]), Math._constant_matrix(patch.bone_from_sole))
		soles[hoof] = Math._packet(matrix, length)
		soles[hoof]["native_value"] = _source.model_from_skeleton * native.globals[bone] * patch.bone_from_sole
	var materials: Array[Dictionary] = _materials(box.skin, box.material_error, length)
	if not _math.issue.is_empty():
		return _reject(_math.issue)
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
		if not _math.issue.is_empty():
			return _reject(_math.issue)
	_math.issue = ""
	var box: Dictionary = _pose_box(branches, start, end, Math._ua(Math._um(end, Math.U64), Math.TINY64))
	if not _math.issue.is_empty():
		var failed: String = _math.issue
		_math.issue = ""
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
	var delta: float = Math._f32(track.times[next] - track.times[index])
	if not track.wrap and (start_edge or end_edge):
		delta = 0.0
	var offset: float = -track.times[index]
	if track.wrap and start_edge:
		var endtime: float = maxf(0.0, Math._f32(_source.animation.length - track.times[index]))
		delta = Math._f32(endtime + track.times[next])
		offset = endtime
	elif track.wrap and end_edge:
		delta = Math._f32((_source.animation.length - track.times[index]) + track.times[next])
	var direct: bool = track.times.size() == 1 or track.step or track.transitions[index] == 0.0
	var zero_delta: bool = absf(delta) < Math._f32(Math.EPS)
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
		result.spherical = Math._f32(1.0 - absf(dot)) > Math._f32(Math.EPS)
		if result.negative_dot:
			result.b = -b
		if result.spherical:
			if result.cosom < 0.9 or result.cosom > 1.0:
				_math.issue = "acosf_domain"
				return result
			# get_angle exposes real_t acos(w); the factor two is exact here.
			# Enclose native sinf(omega) with #244, including its output rounding.
			result.omega = Quaternion(0.0, 0.0, 0.0, result.cosom).get_angle() * 0.5
			var sine: Array[float] = Math._trig_point(result.omega, false)
			result.sinom = PackedFloat64Array([Math._down(sine[0] - Math.SINF_ERROR), Math._up(sine[1] + Math.SINF_ERROR), 0.0, 0.0, 0.0])
			if result.omega < 0.0 or result.omega >= 0.48 or result.sinom[0] <= 0.0:
				_math.issue = "native_slerp_constants"
	return result


func _pose_box(branches: Array[Dictionary], start: float, end: float, time_error: float) -> Dictionary:
	var components: Array[Dictionary] = []
	for bone: Dictionary in _source.bones:
		components.append({"p": Math._vector(bone.position), "q": Math._vector(bone.rotation), "s": Math._vector(bone.scale)})
	var time: PackedFloat64Array = PackedFloat64Array([start, end, 1.0, 1.0, time_error])
	for branch: Dictionary in branches:
		if not branch.enabled:
			continue
		var a: Array = Math._vector(branch.a)
		var b: Array = Math._vector(branch.b)
		var out: Array = []
		if branch.direct:
			out = a
		else:
			var coefficient: PackedFloat64Array = Math._c(0.0)
			if not branch.zero_delta:
				coefficient = _math._div(_math._cast(_math._add(time, Math._c(branch.offset), 64), 32), Math._c(branch.delta), 32)
			if coefficient[0] - coefficient[4] < -1.0 / 512.0 or coefficient[1] + coefficient[4] > 513.0 / 512.0:
				_math.issue = "native_coefficient_domain"
				return {}
			if branch.type != Animation.TYPE_ROTATION_3D:
				for axis: int in 3:
					out.append(_math._add(a[axis], _math._mul(_math._sub(b[axis], a[axis]), coefficient)))
			else:
				var scale0: PackedFloat64Array = _math._sub(Math._c(1.0), coefficient)
				var scale1: PackedFloat64Array = coefficient
				if branch.spherical:
					scale0 = _math._cast(_math._div(_math._sin(_math._mul(_math._sub(Math._c(1.0), coefficient, 64), Math._c(branch.omega), 64), 64), branch.sinom, 64), 32)
					scale1 = _math._div(_math._sin(_math._mul(coefficient, Math._c(branch.omega)), 32), branch.sinom)
				for axis: int in 4:
					out.append(_math._add(_math._mul(scale0, a[axis]), _math._mul(scale1, b[axis])))
		var key: String = "q" if branch.type == Animation.TYPE_ROTATION_3D else "p" if branch.type == Animation.TYPE_POSITION_3D else "s"
		components[branch.bone][key] = out
	var locals_out: Array[Array] = []
	var globals_out: Array[Array] = []
	for i: int in components.size():
		for scale: PackedFloat64Array in components[i].s:
			if scale[0] - scale[4] <= 0.0 and scale[1] + scale[4] >= 0.0:
				_math.issue = "scale_not_separated"
		var local: Array = _local(components[i])
		locals_out.append(local)
		var parent: int = _source.bones[i].parent
		globals_out.append(local if parent == -1 else _math._matmul(globals_out[parent], local))
		if not Math._matrix_finite(globals_out[-1]):
			_math.issue = "nonfinite_global_jet"
		if not _math.issue.is_empty():
			return {}
	var skin: Array[Array] = []
	for bind: Dictionary in _source.binds:
		skin.append(_math._matmul(globals_out[bind.bone], Math._constant_matrix(bind.inverse_bind)))
	for matrix: Array in skin:
		if not Math._matrix_finite(matrix):
			_math.issue = "nonfinite_skin_jet"
			return {}
	var material_error: PackedFloat64Array = _uniform_material_error(skin)
	return {"locals": locals_out, "globals": globals_out, "skin": skin, "material_error": material_error}


func _local(components: Dictionary) -> Array:
	var q: Array = components.q
	var d: PackedFloat64Array = Math._c(0.0)
	for component: PackedFloat64Array in q:
		d = _math._add(d, _math._square(component))
	var s: PackedFloat64Array = _math._div(Math._c(2.0), d)
	var xs: PackedFloat64Array = _math._mul(q[0], s)
	var ys: PackedFloat64Array = _math._mul(q[1], s)
	var zs: PackedFloat64Array = _math._mul(q[2], s)
	var wx: PackedFloat64Array = _math._mul(q[3], xs)
	var wy: PackedFloat64Array = _math._mul(q[3], ys)
	var wz: PackedFloat64Array = _math._mul(q[3], zs)
	var xx: PackedFloat64Array = _math._mul(q[0], xs)
	var xy: PackedFloat64Array = _math._mul(q[0], ys)
	var xz: PackedFloat64Array = _math._mul(q[0], zs)
	var yy: PackedFloat64Array = _math._mul(q[1], ys)
	var yz: PackedFloat64Array = _math._mul(q[1], zs)
	var zz: PackedFloat64Array = _math._mul(q[2], zs)
	var entries: Array = [_math._sub(Math._c(1.0), _math._add(yy, zz)), _math._sub(xy, wz), _math._add(xz, wy),
		_math._add(xy, wz), _math._sub(Math._c(1.0), _math._add(xx, zz)), _math._sub(yz, wx),
		_math._sub(xz, wy), _math._add(yz, wx), _math._sub(Math._c(1.0), _math._add(xx, yy))]
	var matrix: Array = []
	# R1 composes Basis(q)*Basis.from_scale, including its native multiply/adds.
	for row: int in 3:
		for col: int in 3:
			var value: PackedFloat64Array = Math._c(0.0)
			for k: int in 3:
				value = _math._add(value, _math._mul(entries[row * 3 + k], components.s[k] if k == col else Math._c(0.0)))
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
			var p: PackedFloat64Array = Math._c(0.0)
			for col: int in 3:
				p = _math._add(p, _math._mul(matrix[axis * 4 + col], input[col]))
			p = _math._add(p, matrix[axis * 4 + 3])
			scalar[0] = minf(scalar[0], p[0])
			scalar[1] = maxf(scalar[1], p[1])
			scalar[4] = maxf(scalar[4], p[4])
		hull.append(scalar)
	var sum: Array = [Math._c(0.0), Math._c(0.0), Math._c(0.0)]
	var weight: PackedFloat64Array = PackedFloat64Array([0.0, _geometry[3], 0.0, 0.0, 0.0])
	for k: int in 4:
		for axis: int in 3:
			sum[axis] = _math._add(sum[axis], _math._mul(hull[axis], weight))
	var world: Array = _math._point(Math._constant_matrix(_source.model_from_skeleton), sum)
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
							bounds[axis][kind] = Math._down(bounds[axis][kind] + Math._down(minf(scalar[kind] * factor, scalar[kind + 1] * factor)))
							bounds[axis][kind + 1] = Math._up(bounds[axis][kind + 1] + Math._up(maxf(scalar[kind] * factor, scalar[kind + 1] * factor)))
			for axis: int in 3:
				var result: Array[float] = [float(frame.origin[axis]), float(frame.origin[axis]), 0.0, 0.0]
				for col: int in 3:
					var factor: float = frame.basis[col][axis]
					for kind: int in [0, 2]:
						result[kind] = Math._down(result[kind] + Math._down(minf(bounds[col][kind] * factor, bounds[col][kind + 1] * factor)))
						result[kind + 1] = Math._up(result[kind + 1] + Math._up(maxf(bounds[col][kind] * factor, bounds[col][kind + 1] * factor)))
				lower.append(result[0]); upper.append(result[1])
				dl.append(result[2]); du.append(result[3])
				derivative.append(result[2] + (result[3] - result[2]) * 0.5)
				phase_derivative.append(derivative[-1] * length)
				phase_dl.append(Math._down(result[2] * length)); phase_du.append(Math._up(result[3] * length))
		out.append({"extension_lower": lower, "extension_upper": upper,
			"time_derivative": derivative, "time_derivative_lower": dl, "time_derivative_upper": du,
			"phase_derivative": phase_derivative, "phase_derivative_lower": phase_dl, "phase_derivative_upper": phase_du,
			"native_error_uniform": error.duplicate()})
	return out


static func _find(times: Array[float], time: float) -> int:
	var low: int = 0
	var high: int = times.size() - 1
	var middle: int = 0
	while low <= high:
		middle = (low + high) / 2
		if absf(time - times[middle]) < Math.EPS or time == times[middle]:
			return middle
		if time < times[middle]: high = middle - 1
		else: low = middle + 1
	return middle - 1 if times[middle] > time else middle


## First binary64 argument accepted by the native approximate-equality test.
## Disjoint key bands (checked below) make this independent of binary-search order.
static func _early_cut(time: float) -> float:
	if time == 0.0 or absf(time) < Math.EPS:
		return 0.0
	var low: float = maxf(0.0, time - 2.0 * Math.EPS)
	var high: float = time
	for iteration: int in 64:
		if Math._next(low) >= high:
			break
		var middle: float = low + (high - low) * 0.5
		if absf(middle - time) < Math.EPS: high = middle
		else: low = middle
	return high


func _native_cut(time: float) -> bool:
	if time == _source.animation.length:
		return true
	for track: Dictionary in _tracks:
		if track.enabled and _find(track.times, time) != _find(track.times, -Math._next(-time)):
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


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "authority": null, "locals": {}, "globals": [], "positions": [],
		"diagnostics": {"reason": reason}, "activation_pass": false}
