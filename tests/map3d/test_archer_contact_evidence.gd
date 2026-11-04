extends GutTest
## Independent geometry fixtures; none defines anatomical or contact policy.

func _collector() -> Script:
	var path: String = "res://tools/units3d/archer_arp/contact_evidence.gd"
	assert_true(FileAccess.file_exists(path), "material collector exists")
	return load(path) if FileAccess.file_exists(path) else null


func _surface() -> Dictionary:
	return {"vertices": 4,
		"vertices_f32": Marshalls.raw_to_base64(PackedFloat32Array([0,0,0, 2,0,0, 0,0,2, 0,0,0]).to_byte_array()),
		"normals_f32": Marshalls.raw_to_base64(PackedFloat32Array([0,1,0, 0,1,0, 0,1,0, 0,1,0]).to_byte_array()),
		"indices_i32": Marshalls.raw_to_base64(PackedInt32Array([0,1,2, 3,1,2, 0,0,1]).to_byte_array()),
		"bones_i32": Marshalls.raw_to_base64(PackedInt32Array([0,1,0,0, 0,1,0,0, 0,1,0,0, 0,1,0,0]).to_byte_array()),
		"weights_f32": Marshalls.raw_to_base64(PackedFloat32Array([0.5,0.25,0,0, 0.5,0.25,0,0, 0.5,0.25,0,0, 0.5,0.25,0,0]).to_byte_array())}


func test_raw_weights_affine_ancestor_and_skinned_vertex_barycentric_authority() -> void:
	var c: Script = _collector()
	if c == null: return
	var decoded: Dictionary = c.decode_surface(_surface(), 2)
	assert_true(decoded.ok)
	if not decoded.ok: return
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(4,0,0))]
	var ancestor: Transform3D = Transform3D(Basis.from_scale(Vector3(2,3,4)), Vector3(10,20,30))
	var points: PackedVector3Array = c.skin_points(decoded, transforms, ancestor)
	assert_eq(points[0], Vector3(12,20,30), "0.75 total weight is not normalized; ancestor is applied afterward")
	assert_eq(points[1], Vector3(15,20,30))
	assert_eq(points[2], Vector3(12,20,36))
	assert_eq(c.material_point(points, [0,1,2], Vector3(0.5,0.25,0.25)), Vector3(12.75,20,31.5))


func test_full_index_inventory_includes_seams_degenerate_faces_and_mixed_weights() -> void:
	var c: Script = _collector()
	if c == null: return
	var d: Dictionary = c.decode_surface(_surface(), 2)
	var points: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(2,0,0), Vector3(0,0,2), Vector3.ZERO])
	var inventory: Dictionary = c.inventory(d, points, ["left.outsole.heel", "left.upper", "left.degenerate"])
	assert_true(inventory.ok)
	assert_eq(inventory.triangles.size(), 3, "every supplied face is retained, including duplicates and degenerate faces")
	assert_eq(inventory.triangles[0].vertices, [0,1,2])
	assert_eq(inventory.triangles[0].area_m2, 2.0)
	assert_eq(inventory.triangles[0].normal, [0.0,1.0,0.0], "Godot clockwise exterior winding")
	assert_eq(inventory.triangles[2].area_m2, 0.0)
	assert_eq(inventory.coincident_vertex_groups, [[0,3]], "report seams without welding")
	assert_false(c.inventory(d, points, ["left.outsole.heel"]).ok, "missing face annotation rejects")
	var chart: Dictionary = c.chart_topology(inventory.triangles.slice(0,2))
	assert_eq(chart.vertices, [0,1,2,3], "seam copies keep distinct material IDs")
	assert_eq(chart.original_vertex_connected_components, [[0,1]])
	assert_eq(chart.boundary_edges.size(), 4, "the original shared edge is interior; unwelded seam edges remain explicit")


func test_rejects_corrupt_schema_indices_and_weights_without_repair() -> void:
	var c: Script = _collector()
	if c == null: return
	for kind: int in range(11):
		var s: Dictionary = _surface()
		match kind:
			0: s.erase("normals_f32")
			1: s.vertices = 3
			2: s.indices_i32 = Marshalls.raw_to_base64(PackedInt32Array([0,1,4]).to_byte_array())
			3: s.weights_f32 = Marshalls.raw_to_base64(PackedFloat32Array([-1,0,0,0]).to_byte_array())
			4: s.vertices_f32 = "not base64"
			5: s.indices_i32 = Marshalls.raw_to_base64(PackedInt32Array([0,1]).to_byte_array())
			6: s.unrecognized = true
			7:
				var weights: PackedFloat32Array = Marshalls.base64_to_raw(s.weights_f32).to_float32_array()
				weights[0] = -0.5
				s.weights_f32 = Marshalls.raw_to_base64(weights.to_byte_array())
			8:
				var weights: PackedFloat32Array = Marshalls.base64_to_raw(s.weights_f32).to_float32_array()
				weights[0] = NAN
				s.weights_f32 = Marshalls.raw_to_base64(weights.to_byte_array())
			9:
				var bones: PackedInt32Array = Marshalls.base64_to_raw(s.bones_i32).to_int32_array()
				bones[0] = 2
				s.bones_i32 = Marshalls.raw_to_base64(bones.to_byte_array())
			10:
				var positions: PackedFloat32Array = Marshalls.base64_to_raw(s.vertices_f32).to_float32_array()
				positions[0] = INF
				s.vertices_f32 = Marshalls.raw_to_base64(positions.to_byte_array())
		var before: PackedByteArray = var_to_bytes(s)
		assert_false(c.decode_surface(s, 2).ok, str(kind))
		assert_eq(var_to_bytes(s), before, "no repair")


func test_frozen_charts_and_anchors_detect_mutation() -> void:
	var c: Script = _collector()
	if c == null: return
	var material: Dictionary = {"charts": [{"id":"left.heel", "triangles":[0], "vertices":[0,1,2]}],
		"anchors": [{"chart":"left.heel", "surface":"fixture-plane", "normal":[0,1,0], "points":[[0,0,0],[2,0,0],[0,0,2]]}]}
	var frozen: String = c.digest(material)
	assert_true(c.matches_digest(material, frozen))
	assert_true(c.matches_digest(JSON.parse_string(JSON.stringify(material, "", true, true)), frozen), "freeze survives JSON storage")
	material.charts[0].triangles = [1]
	assert_false(c.matches_digest(material, frozen), "chart cannot change after freeze")
	material.charts[0].triangles = [0]
	material.anchors[0].points[0][0] = 0.1
	assert_false(c.matches_digest(material, frozen), "anchors cannot follow moving points")
	var path: String = "user://archer-contact-hash-%d.json" % get_instance_id()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"weights":[0.5,0.25]}')
	file.close()
	var pin: String = FileAccess.get_sha256(path)
	assert_true(c.read_bound(path, pin).ok)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"weights":[0.5,0.5]}')
	file.close()
	assert_false(c.read_bound(path, pin).ok, "valid JSON with changed raw weights rejects against input pin")
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)), OK)


func test_retained_evidence_replays_complete_frozen_arrays_and_anatomical_inventory() -> void:
	var c: Script = _collector()
	if c == null: return
	var path: String = "res://docs/reviews/cluster-formations/evidence/archers-contact/material-support.json"
	assert_true(FileAccess.file_exists(path), "substantive material evidence is retained")
	if not FileAccess.file_exists(path): return
	assert_eq(FileAccess.get_sha256(path), "c27538df347f1daeb1955040ccd0c07b761bc4738a7865b72e21b3501d4c6d30", "frozen anatomy, raw skin, rest/binds and fixed anchors cannot be silently replaced")
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var expected_arrays: Array[String] = [
		"23f91375895b6c5aeb74f743a6cdfe144d2956f6ce16364ecb6c5d2080eee24e",
		"9b6934aecde820274600fa74009320c996fd808b0ccea739956f1b9dd70f1bd3",
		"ade96834ffef961880341163fb50df7fb3ad81203f356dce5e54499cf4784722",
		"98b803b142dfcdaeca967e129a2791f363e6c4f4661a97d1f77d62c5f5b0f646"]
	assert_eq(evidence.surfaces.size(), 4)
	assert_eq(evidence.inputs.native.sha256, "e70eb095008dbd3179119d652cb874884b4e0cbc2a1fb3af7ad4a865114184bc")
	assert_true(c.matches_digest(evidence.annotation, evidence.annotation_digest))
	assert_true(c.matches_digest(evidence.charts, evidence.charts_digest))
	var rest: Array = []
	for bone: Dictionary in evidence.bones: rest.append(bone.global_rest)
	for index: int in 4:
		var surface: Dictionary = evidence.surfaces[index]
		var raw_hash: HashingContext = HashingContext.new()
		raw_hash.start(HashingContext.HASH_SHA256)
		for field: String in ["vertices_f32", "normals_f32", "indices_i32", "bones_i32", "weights_f32"]:
			raw_hash.update(Marshalls.base64_to_raw(surface.arrays[field]))
		assert_eq(raw_hash.finish().hex_encode(), expected_arrays[index], "original CERT topology, vertices, normals, all weights and palette bytes")
		var decoded: Dictionary = c.decode_surface(surface.arrays, surface.skin.size())
		assert_true(decoded.ok)
		if not decoded.ok: continue
		var points: PackedVector3Array = c._pose_points(evidence, surface, decoded, rest)
		var key: String = "%d/%d" % [surface.mesh,surface.surface]
		var inventory: Dictionary = c.inventory(decoded, points, evidence.annotation.labels[key])
		assert_true(inventory.ok)
		assert_eq(c.digest(inventory.boundary_edges), c.digest(surface.inventory.boundary_edges))
		assert_eq(c.digest(inventory.nonmanifold_edges), c.digest(surface.inventory.nonmanifold_edges))
		assert_eq(c.digest(inventory.coincident_vertex_groups), c.digest(surface.inventory.coincident_vertex_groups))
		var areas: PackedFloat64Array = Marshalls.base64_to_raw(surface.inventory.area_f64_le).to_float64_array()
		var normals: PackedFloat64Array = Marshalls.base64_to_raw(surface.inventory.clockwise_normal_xyz_f64_le).to_float64_array()
		var codes: PackedInt32Array = Marshalls.base64_to_raw(surface.inventory.label_i32_le).to_int32_array()
		assert_eq(areas.size(), inventory.triangles.size())
		assert_eq(normals.size(), areas.size()*3)
		assert_eq(codes.size(), areas.size())
		var valid: bool = true
		for face: int in areas.size():
			var normal: Vector3 = Vector3(normals[face*3],normals[face*3+1],normals[face*3+2])
			valid = valid and is_finite(areas[face]) and areas[face] >= 0.0 and normal.is_finite()
			valid = valid and (normal == Vector3.ZERO if areas[face] == 0.0 else absf(normal.length()-1.0) < 0.000001)
			valid = valid and codes[face] >= 0 and codes[face] < surface.inventory.label_palette.size()
			if valid: valid = surface.inventory.label_palette[codes[face]] == evidence.annotation.labels[key][face]
		assert_true(valid, "complete finite area/normal/label columns, preserving all original face IDs")
		if index == 0:
			# Arithmetic replay guard in square metres; never a contact budget.
			assert_almost_eq(areas[80753], 0.00010571228856475105, 0.00000001)
			assert_almost_eq(areas[13891], 0.00015227095922581654, 0.00000001)
	assert_eq(evidence.resource_sha256.size(), 35)
	for resource: String in evidence.resource_sha256:
		assert_eq(FileAccess.get_sha256("res://" + resource), evidence.resource_sha256[resource], resource)
	var chart_faces: Dictionary = {}
	var valid_chart_faces: bool = true
	for chart: Dictionary in evidence.charts:
		assert_gt(chart.rest_area_m2, 0.0)
		for face: int in chart.triangle_ids:
			valid_chart_faces = valid_chart_faces and not chart_faces.has(face) and evidence.annotation.labels["0/0"][face] == chart.id
			chart_faces[face] = true
	assert_true(valid_chart_faces, "fixed charts partition the selected underside without changing labels")
	var labels: Array = evidence.annotation.labels["0/0"]
	var complete_chart_coverage: bool = true
	for face: int in labels.size():
		complete_chart_coverage = complete_chart_coverage and chart_faces.has(face) == (".outsole." in String(labels[face]))
	assert_true(complete_chart_coverage, "no selected support face is lost")
	for old: Dictionary in evidence.annotation.legacy_diagnostics:
		assert_false(String(labels[int(old.triangle)]).begins_with("excluded"), "original diagnostics remain in collision domain")
	assert_eq(FileAccess.get_sha256("res://docs/reviews/cluster-formations/evidence/archers-contact/anatomy-atlas.png"), evidence.atlas.sha256)


func test_transfer_observations_keep_tilted_samples_and_bind_unbounded_envelopes() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reviews/cluster-formations/evidence/archers-contact/material-support.json"))
	var observed: Dictionary = evidence.observed_native_march
	for example: Array in [[8,"left","heel-low/toe-up"], [24,"right","heel-low/toe-up"], [24,"left","heel-high/toe-low"], [25,"left","heel-high/toe-low"], [26,"left","heel-high/toe-low"], [10,"right","heel-high/toe-low"]]:
		assert_true(String(observed.phase_sample_labels[example[0]][example[1]]).begins_with(example[2]), "finite morphology at sample " + str(example))
	var frames: Dictionary = {}
	for frame: Dictionary in observed.native_frames: frames[frame.shot.id] = frame
	for transfer: Dictionary in observed.unresolved_transfers:
		assert_null(transfer.phase_bracket, "no finite image envelope is a physical transition bound")
		assert_eq(transfer.get("bound_status", ""), "unbounded")
		if transfer.get("bound_status") != "unbounded": continue
		for envelope: Dictionary in transfer.finite_sample_envelopes:
			for endpoint: String in ["start_query", "end_query"]:
				var query: Dictionary = envelope[endpoint]
				assert_eq(query.clip, "MARCH")
				assert_eq(query.frames.size(), 2)
				for ref: Dictionary in query.frames:
					assert_true(frames.has(ref.id))
					if not frames.has(ref.id): continue
					assert_eq(frames[ref.id].sha256, ref.sha256)
					assert_eq(frames[ref.id].shot.phase, query.phase)
					assert_eq(frames[ref.id].native_time_s, query.native_time_s)
		var covered: Array = []
		for envelope: Dictionary in transfer.finite_sample_envelopes:
			covered.append_array(envelope.inspected_sample_phases)
		var disputed: Array = [0.25] if transfer.side == "left" else [0.75]
		if transfer.kind == "heel rise through toe-off":
			disputed = [0.75,0.78125,0.8125] if transfer.side == "left" else [0.3125]
		for phase: float in disputed:
			assert_true(covered.has(phase), "all disputed finite transfer samples remain inside the inspected envelope")
