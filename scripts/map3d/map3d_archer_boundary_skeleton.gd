class_name Map3DArcherBoundarySkeleton
extends RefCounted
## Pure bone/segment/split/affine residuals for the validated full native poses.
## Lengths are native skeleton metres; origin displacement is in model metres.


static func measure(rest: Dictionary, reference: Dictionary, poses: Array[Dictionary], raw: Dictionary, candidate: Dictionary, model_from_native: Transform3D, arithmetic_epsilon: float) -> Dictionary:
	var bones: Dictionary = {}
	var segments: Array = []
	for name: String in reference:
		var gram_raw: Basis = raw[name].basis.transposed() * raw[name].basis
		var gram_candidate: Basis = candidate[name].basis.transposed() * candidate[name].basis
		var gram_rest: Basis = rest.locals[name].basis.transposed() * rest.locals[name].basis
		var raw_rest_residual: float = 0.0
		var candidate_rest_residual: float = 0.0
		var affine_residual: float = 0.0
		for axis: int in range(3):
			affine_residual = maxf(affine_residual, gram_raw[axis].distance_to(gram_candidate[axis]))
			raw_rest_residual = maxf(raw_rest_residual, gram_raw[axis].distance_to(gram_rest[axis]))
			candidate_rest_residual = maxf(candidate_rest_residual, gram_candidate[axis].distance_to(gram_rest[axis]))
		var row: Dictionary = {"origin_displacement_m": (model_from_native * poses[0][name].origin).distance_to(model_from_native * poses[1][name].origin), "local_gram_residual": affine_residual, "raw_rest_gram_residual": raw_rest_residual, "candidate_rest_gram_residual": candidate_rest_residual}
		var parent: String = rest.parents[name]
		if not parent.is_empty():
			var length: float = reference[name].origin.distance_to(reference[parent].origin)
			row.raw_length_residual_native_m = poses[0][name].origin.distance_to(poses[0][parent].origin) - length
			row.candidate_length_residual_native_m = poses[1][name].origin.distance_to(poses[1][parent].origin) - length
		for field: String in row:
			if not is_finite(row[field]):
				return _failure("boundary: overflowing bone metric")
		bones[name] = row
	for segment: Variant in rest.segments:
		if not segment is Dictionary or not reference.has(segment.get("a")) or not reference.has(segment.get("b")):
			return _failure("boundary: invalid anatomical segment")
		var a: String = segment.a
		var b: String = segment.b
		var span: Vector3 = reference[b].origin - reference[a].origin
		if span.length() <= arithmetic_epsilon:
			return _failure("boundary: degenerate anatomical segment")
		var row: Dictionary = {"a": a, "b": b, "raw_length_residual_native_m": poses[0][a].origin.distance_to(poses[0][b].origin) - span.length(),
			"candidate_length_residual_native_m": poses[1][a].origin.distance_to(poses[1][b].origin) - span.length()}
		if segment.has("split"):
			if not reference.has(segment.split):
				return _failure("boundary: unknown split bone")
			var fraction: float = (reference[segment.split].origin - reference[a].origin).dot(span) / span.length_squared()
			row.split = segment.split
			row.rest_fraction = fraction
			row.raw_split_residual_native_m = poses[0][segment.split].origin.distance_to(poses[0][a].origin.lerp(poses[0][b].origin, fraction))
			row.candidate_split_residual_native_m = poses[1][segment.split].origin.distance_to(poses[1][a].origin.lerp(poses[1][b].origin, fraction))
		for field: String in row:
			if typeof(row[field]) == TYPE_FLOAT and not is_finite(row[field]):
				return _failure("boundary: overflowing segment metric")
		segments.append(row)
	return {"ok": true, "bones": bones, "segments": segments}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "locals": {}, "diagnostics": [reason]}
