extends SceneTree
## Read-only material evidence. No contact allowance or continuous certificate.
## --request JSON: mode atlas (real window) or material (frozen input arrays).

static func digest(value: Variant) -> String:
	# JSON reads numbers as floats; freeze that representation without touching packed source bytes.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true).sha256_text()


static func matches_digest(value: Variant, expected: String) -> bool:
	return expected.length() == 64 and digest(value) == expected


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "error": message}


static func decode_surface(surface: Dictionary, bind_count: int) -> Dictionary:
	var fields: Array = ["vertices", "vertices_f32", "normals_f32", "indices_i32", "bones_i32", "weights_f32"]
	if surface.size() != fields.size() or not fields.all(func(k: String) -> bool: return surface.has(k)):
		return _bad("surface schema")
	if not surface.vertices is float and not surface.vertices is int:
		return _bad("vertex count type")
	var count: int = int(surface.vertices)
	if count <= 0 or count != surface.vertices or bind_count <= 0:
		return _bad("vertex/bind count")
	var decoded: Dictionary = {"ok": true, "count": count}
	var pattern: RegEx = RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]*={0,2}$")
	for key: String in fields.slice(1):
		if not surface[key] is String or surface[key].is_empty() or surface[key].length() % 4 != 0 or pattern.search(surface[key]) == null:
			return _bad("base64 " + key)
		var bytes: PackedByteArray = Marshalls.base64_to_raw(surface[key])
		if bytes.size() % 4 != 0 or Marshalls.raw_to_base64(bytes) != surface[key]:
			return _bad("byte encoding " + key)
		decoded[key] = bytes.to_int32_array() if key.ends_with("i32") else bytes.to_float32_array()
	if decoded.vertices_f32.size() != count * 3 or decoded.normals_f32.size() != count * 3:
		return _bad("position/normal width")
	if decoded.bones_i32.size() != decoded.weights_f32.size() or decoded.weights_f32.size() not in [count * 4, count * 8]:
		return _bad("influence width")
	if decoded.indices_i32.is_empty() or decoded.indices_i32.size() % 3 != 0:
		return _bad("triangle width")
	for index: int in decoded.indices_i32:
		if index < 0 or index >= count: return _bad("vertex index")
	for index: int in decoded.bones_i32:
		if index < 0 or index >= bind_count: return _bad("bind index")
	for key: String in ["vertices_f32", "normals_f32", "weights_f32"]:
		for value: float in decoded[key]:
			if not is_finite(value) or (key == "weights_f32" and value < 0.0): return _bad("nonfinite/negative " + key)
	decoded.width = decoded.weights_f32.size() / count
	return decoded


static func skin_points(decoded: Dictionary, transforms: Array[Transform3D], ancestor: Transform3D) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for v: int in decoded.count:
		var p: Vector3 = Vector3(decoded.vertices_f32[v*3], decoded.vertices_f32[v*3+1], decoded.vertices_f32[v*3+2])
		var skinned: Vector3 = Vector3.ZERO
		for j: int in decoded.width:
			var at: int = v * decoded.width + j
			skinned += (transforms[decoded.bones_i32[at]] * p) * decoded.weights_f32[at]
		points.append(ancestor * skinned)
	return points


static func material_point(points: PackedVector3Array, vertices: Array, barycentric: Vector3) -> Vector3:
	return points[vertices[0]] * barycentric.x + points[vertices[1]] * barycentric.y + points[vertices[2]] * barycentric.z


static func inventory(decoded: Dictionary, points: PackedVector3Array, labels: Array) -> Dictionary:
	if not decoded.get("ok", false) or points.size() != decoded.count or labels.size() * 3 != decoded.indices_i32.size():
		return _bad("incomplete material inventory")
	var triangles: Array = []
	var edges: Dictionary = {}
	for face: int in labels.size():
		if not labels[face] is String or labels[face].is_empty(): return _bad("unlabelled face")
		var ids: Array = []
		for j: int in 3: ids.append(int(decoded.indices_i32[face * 3 + j]))
		var cross: Vector3 = (points[ids[2]] - points[ids[0]]).cross(points[ids[1]] - points[ids[0]])
		var normal: Vector3 = cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO
		triangles.append({"id": face, "vertices": ids, "area_m2": cross.length() / 2.0, "normal": _v(normal), "label": labels[face]})
		for j: int in 3:
			var key: Vector2i = Vector2i(mini(ids[j], ids[(j+1)%3]), maxi(ids[j], ids[(j+1)%3]))
			if not edges.has(key): edges[key] = []
			edges[key].append(face)
	var boundary: Array = []
	var nonmanifold: Array = []
	for key: Vector2i in edges:
		var row: Array = [key.x, key.y, edges[key]]
		if edges[key].size() == 1: boundary.append(row)
		elif edges[key].size() > 2: nonmanifold.append(row)
	var coincident: Dictionary = {}
	for v: int in decoded.count:
		var key: String = Marshalls.raw_to_base64(PackedFloat32Array([decoded.vertices_f32[v*3], decoded.vertices_f32[v*3+1], decoded.vertices_f32[v*3+2]]).to_byte_array())
		if not coincident.has(key): coincident[key] = []
		coincident[key].append(v)
	var seams: Array = []
	for group: Array in coincident.values():
		if group.size() > 1: seams.append(group)
	return {"ok": true, "triangles": triangles, "boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "coincident_vertex_groups": seams}


static func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _t(rows: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]), Vector3(rows[0][1],rows[1][1],rows[2][1]), Vector3(rows[0][2],rows[1][2],rows[2][2])), Vector3(rows[0][3],rows[1][3],rows[2][3]))


static func read_bound(path: String, sha256: String) -> Dictionary:
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != sha256:
		return _bad("input hash: " + path)
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return {"ok": true, "value": value} if value is Dictionary else _bad("input JSON schema: " + path)


static func _pose_points(native: Dictionary, mesh: Dictionary, decoded: Dictionary, pose: Array) -> PackedVector3Array:
	var transforms: Array[Transform3D] = []
	for bind: Dictionary in mesh.skin:
		transforms.append(_t(pose[int(bind.bone)]) * _t(bind.pose))
	return skin_points(decoded, transforms, _t(native.skeleton_to_model))


static func compact_inventory(full: Dictionary) -> Dictionary:
	var areas: PackedFloat64Array = []
	var normals: PackedFloat64Array = []
	var labels: Array = []
	var codes: PackedInt32Array = []
	for triangle: Dictionary in full.triangles:
		areas.append(triangle.area_m2)
		normals.append_array(PackedFloat64Array(triangle.normal))
		if not labels.has(triangle.label): labels.append(triangle.label)
		codes.append(labels.find(triangle.label))
	return {"triangle_id": "zero-based original index-buffer triple; ordered vertex IDs in unchanged arrays.indices_i32",
		"area_f64_le": Marshalls.raw_to_base64(areas.to_byte_array()), "clockwise_normal_xyz_f64_le": Marshalls.raw_to_base64(normals.to_byte_array()),
		"label_palette": labels, "label_i32_le": Marshalls.raw_to_base64(codes.to_byte_array()),
		"boundary_edges": full.boundary_edges, "nonmanifold_edges": full.nonmanifold_edges, "coincident_vertex_groups": full.coincident_vertex_groups}


static func chart_topology(triangles: Array) -> Dictionary:
	var vertices: Dictionary = {}
	var edges: Dictionary = {}
	var by_id: Dictionary = {}
	for triangle: Dictionary in triangles:
		by_id[triangle.id] = triangle
		for j: int in 3:
			var v: int = triangle.vertices[j]
			if not vertices.has(v): vertices[v] = []
			vertices[v].append(triangle.id)
			var other: int = triangle.vertices[(j+1)%3]
			var edge: Vector2i = Vector2i(mini(v,other),maxi(v,other))
			if not edges.has(edge): edges[edge] = []
			edges[edge].append(triangle.id)
	var boundaries: Array = []
	for edge: Vector2i in edges:
		if edges[edge].size() == 1: boundaries.append([edge.x,edge.y,edges[edge][0]])
	var components: Array = []
	var unseen: Dictionary = by_id.duplicate()
	while not unseen.is_empty():
		var stack: Array = [unseen.keys()[0]]
		var component: Array = []
		while not stack.is_empty():
			var id: int = stack.pop_back()
			if not unseen.has(id): continue
			unseen.erase(id)
			component.append(id)
			for v: int in by_id[id].vertices:
				for neighbour: int in vertices[v]:
					if unseen.has(neighbour): stack.append(neighbour)
		component.sort()
		components.append(component)
	var ids: Array = vertices.keys()
	ids.sort()
	return {"vertices": ids, "boundary_edges": boundaries, "original_vertex_connected_components": components,
		"seam_rule": "No welding; coincident original vertex groups are reported separately in the surface inventory."}


static func _canonical(native: Dictionary, author: Dictionary, charts: Array) -> Dictionary:
	var schedules: Array = []
	var mesh: Dictionary = native.meshes[0]
	var decoded: Dictionary = decode_surface(mesh.surfaces[0], mesh.skin.size())
	for clip: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		var selected: Dictionary = {}
		for case: Dictionary in author.cases:
			if case.id == clip + "/0": selected = case; break
		if selected.is_empty(): return _bad("missing canonical author case")
		var operation: Dictionary = {}
		for key: String in ["turn_rad", "duration_s", "march_entry_phase", "march_exit_phase", "yaw_rad"]: operation[key] = selected.operation[key]
		for side: String in ["l", "r"]:
			var prefix: String = "left." if side == "l" else "right."
			for support: Dictionary in selected.contacts[side].support:
				var entry: Dictionary = {}
				for sample: Dictionary in native.samples:
					if sample.clip == clip and sample.phase == support.start: entry = sample; break
				if entry.is_empty(): return _bad("missing exact original native support entry")
				var points: PackedVector3Array = _pose_points(native, mesh, decoded, entry.globals)
				var external: Basis = Basis(Vector3.UP, -float(operation.turn_rad) * float(support.start))
				var bindings: Array = []
				for chart: Dictionary in charts:
					if not chart.id.begins_with(prefix): continue
					var anchors: Array = []
					var material_positions: Array = []
					for v: int in chart.vertices:
						var at: Vector3 = external * points[v]
						material_positions.append(_v(at))
						anchors.append([at.x, 0.0, at.z])
					bindings.append({"chart": chart.id, "vertices": chart.vertices, "entry_material_points": material_positions, "fixed_plane_anchors": anchors})
				schedules.append({"clip": clip, "operation": operation, "side": side, "start": support.start, "end": support.end,
					"author_sole_frame": support.sole, "author_toe_frame": support.toe, "chart_bindings": bindings,
					"start_left_branch": "native_entry" if support.start == 0.0 else "incoming_swing", "start_right_branch": "intended_support",
					"end_left_branch": "intended_support", "end_right_branch": "native_exit" if support.end == 1.0 else "outgoing_swing",
					"anchor_entry_native_time_s": entry.time_s, "entry_native_globals": entry.globals, "anchor_surface": "diagnostic model plane y=0; not native terrain", "normal": [0,1,0],
					"anchor_rule": "Project each fixed material vertex once at stance entry; extend barycentrically on each triangle. Never reselect or move anchors inside stance. Noncontact entry is not corrected."})
	return {"ok": true, "kind": "canonical author eight-step INTENT, kept separate from observed raw MARCH support", "schedules": schedules,
		"reference_phase_law": "At phase 0 use march_entry_phase; at 1 use march_exit_phase; inside use (entry + ((exit-entry) mod 1)*phase) mod 1. Canonical cases have entry=exit=0. No arbitrary P1 phase extrapolation.",
		"physical_authority": "The author holds sole/toe frames. That intent does not establish physical whole-chart contact. These fixed planar diagnostic anchors do not supply actual terrain anchors or a contact budget; E2 must bind actual placement/terrain separately."}


func _material(request: Dictionary) -> Dictionary:
	var inputs: Dictionary = {}
	for key: String in request.inputs:
		var pin: Dictionary = request.inputs[key]
		var bound: Dictionary = read_bound(pin.path, pin.sha256)
		if not bound.ok: return bound
		inputs[key] = bound.value
	var native: Dictionary = inputs.native
	var annotation: Dictionary = inputs.annotation
	var annotation_digest: String = digest(annotation)
	var resources: Dictionary = {}
	for path: String in inputs.source.input_sha256:
		if path.begins_with("assets/3D/units/archers/") or path in ["scenes/models/units/archers.tscn", "tools/units3d/archer_arp/pivot_import.gd"]:
			var expected: String = inputs.source.input_sha256[path]
			if FileAccess.get_sha256("res://" + path) != expected: return _bad("installed resource changed: " + path)
			resources[path] = expected
	if resources.size() != 35: return _bad("expected all 35 original equipped resources")
	var surfaces: Array = []
	var charts: Array = []
	var collision_domains: Array = []
	var rest: Array = []
	for bone: Dictionary in native.bones: rest.append(bone.global_rest)
	for mesh_index: int in native.meshes.size():
		var mesh: Dictionary = native.meshes[mesh_index]
		for surface_index: int in mesh.surfaces.size():
			var id: String = "%d/%d" % [mesh_index,surface_index]
			var raw: Dictionary = mesh.surfaces[surface_index]
			var decoded: Dictionary = decode_surface(raw, mesh.skin.size())
			if not decoded.ok: return decoded
			var points: PackedVector3Array = _pose_points(native, mesh, decoded, rest)
			var full: Dictionary = inventory(decoded, points, annotation.labels.get(id, []))
			if not full.ok: return full
			var groups: Dictionary = {}
			var footwear: Dictionary = {"left": [], "right": []}
			for triangle: Dictionary in full.triangles:
				if not annotation.reasons.has(triangle.label): return _bad("missing anatomical reason: " + triangle.label)
				for side: String in footwear:
					if triangle.label.begins_with(side + "."): footwear[side].append(triangle)
				if ".outsole." in triangle.label:
					if triangle.area_m2 <= 0.0: return _bad("degenerate support chart")
					if not groups.has(triangle.label): groups[triangle.label] = []
					groups[triangle.label].append(triangle)
			for label: String in groups:
				var chart: Dictionary = chart_topology(groups[label])
				chart.merge({"id": label, "mesh": mesh_index, "surface": surface_index, "triangle_ids": groups[label].map(func(t: Dictionary) -> int: return t.id),
					"coordinates": "For each original ordered triangle: fixed barycentric (u,v,w), u+v+w=1, all nonnegative, applied AFTER raw vertex skinning.",
					"rest_area_m2": groups[label].reduce(func(total: float, t: Dictionary) -> float: return total + t.area_m2, 0.0)})
				charts.append(chart)
			for side: String in footwear:
				if footwear[side].is_empty(): continue
				var domain: Dictionary = chart_topology(footwear[side])
				domain.merge({"id": side + ".complete_footwear", "mesh": mesh_index, "surface": surface_index,
					"triangle_ids": footwear[side].map(func(t: Dictionary) -> int: return t.id), "includes": "All upper, sidewall, shaft, cuff margin, outsole and degenerate labelled faces; swing included. Not a support chart."})
				collision_domains.append(domain)
			surfaces.append({"mesh": mesh_index, "mesh_name": mesh.name, "mesh_path": mesh.path, "surface": surface_index,
				"arrays": raw, "arrays_digest": digest(raw), "skin": mesh.skin, "mesh_to_model": mesh.mesh_to_model,
				"inventory": compact_inventory(full)})
	var canonical: Dictionary = _canonical(native, inputs.canonical_author_input, charts)
	if not canonical.ok: return canonical
	return {"ok": true, "schema": "archer-material-support-v1", "status": "finite material evidence; no contact allowance or D2/CERT pass",
		"inputs": request.inputs, "resource_sha256": resources, "annotation_digest": annotation_digest,
		"annotation": annotation, "charts": charts, "charts_digest": digest(charts), "collision_domains": collision_domains, "surfaces": surfaces, "bones": native.bones, "skeleton_to_model": native.skeleton_to_model,
		"units": {"positions":"model metres after complete raw-weight LBS and skeleton ancestor affine", "native_frames":"Native skeleton metres for bones, pose globals and literal author sole/toe frames. Retain their source spaces; do not substitute them for skinned model/world positions.", "world":"No ordinary-terrain world placement or simulation-distance conversion is collected in E1.", "areas":"model square metres", "normals":"clockwise oriented unit normal; zero for exactly degenerate faces"},
		"authority": "Fixed barycentric combinations of skinned vertices; all original influence bytes retained without normalization. No remeshing, welding, lowest-point reselection or weight cutoff.",
		"canonical_support": canonical, "observed_native_march": request.observed_native_march,
		"atlas": request.atlas, "preservation": request.preservation, "limitations": request.limitations}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--request":
		push_error("Expected --request JSON")
		quit(2)
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not request is Dictionary:
		push_error("Invalid request")
		quit(2)
		return
	var output: String = String(request.get("output", ""))
	if output.is_empty() or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		push_error("Evidence output must be a new file/directory; preserve prior inputs and captures")
		quit(2)
		return
	if request.get("mode") == "atlas":
		if DisplayServer.get_name() == "headless":
			push_error("Atlas requires a real native window")
			quit(2)
			return
		var window: AtlasWindow = AtlasWindow.new()
		window.request = request
		root.add_child(window)
	elif request.get("mode") == "material":
		var result: Dictionary = _material(request)
		if not result.ok:
			push_error(result.error)
			quit(2)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write evidence")
			quit(2)
			return
		file.store_string(JSON.stringify(result, "", true, true) + "\n")
		file.close()
		print("Material inventory written: ", request.output)
		quit()
	else:
		push_error("Unknown material evidence mode")
		quit(2)


class AtlasWindow extends Node:
	var request: Dictionary = {}
	var actor: Node3D
	var camera: Camera3D
	var player: AnimationPlayer
	var skeleton: Skeleton3D
	var shot: int = 0
	var records: Array = []
	var overlay: MeshInstance3D
	var reference_grid: MeshInstance3D
	var _frames: int = 0
	var snapshot: Node

	func _matrix(value: Transform3D) -> Array:
		return [[value.basis.x.x,value.basis.y.x,value.basis.z.x,value.origin.x], [value.basis.x.y,value.basis.y.y,value.basis.z.y,value.origin.y], [value.basis.x.z,value.basis.y.z,value.basis.z.z,value.origin.z], [0,0,0,1]]


	func _ready() -> void:
		# Attach after readiness: reuse the native-window saver without its gameplay setup.
		snapshot = Node.new()
		add_child(snapshot)
		snapshot.set_script(load("res://tools/snapshot_screen.gd"))
		snapshot.set_process(false)
		for path: String in request.get("resource_sha256", {}):
			if FileAccess.get_sha256("res://" + path) != request.resource_sha256[path]:
				push_error("Atlas input changed: " + path)
				get_tree().quit(2)
				return
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(2560,1600))
		get_window().size = Vector2i(2560,1600)
		get_viewport().msaa_3d = Viewport.MSAA_4X
		actor = (load("res://scenes/models/units/archers.tscn") as PackedScene).instantiate()
		add_child(actor)
		player = actor.find_children("*", "AnimationPlayer", true, false)[0]
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		skeleton = actor.find_children("*", "Skeleton3D", true, false)[0]
		if request.has("annotation"):
			_make_overlay()
		var grid: ImmediateMesh = ImmediateMesh.new()
		grid.surface_begin(Mesh.PRIMITIVE_LINES)
		for i: int in range(-10,11):
			for p: Vector3 in [Vector3(i*.1,0,-1),Vector3(i*.1,0,1),Vector3(-1,0,i*.1),Vector3(1,0,i*.1)]: grid.surface_add_vertex(p)
		grid.surface_end()
		reference_grid = MeshInstance3D.new()
		reference_grid.mesh = grid
		var ink: StandardMaterial3D = StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = Color(0.32,0.34,0.36)
		reference_grid.material_override = ink
		add_child(reference_grid)
		camera = Camera3D.new()
		add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.near = 0.01
		camera.far = 20.0
		camera.current = true
		var world: WorldEnvironment = WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color(0.10,0.11,0.12)
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color.WHITE
		world.environment.ambient_light_energy = 0.65
		add_child(world)
		for direction: Vector3 in [Vector3(-1,-1,-1), Vector3(1,1,1)]:
			var light: DirectionalLight3D = DirectionalLight3D.new()
			add_child(light)
			light.look_at(direction)
			light.light_energy = 1.1
		_apply()


	func _make_overlay() -> void:
		var annotation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(request.annotation))
		var body: MeshInstance3D = actor.find_child("archers", true, false)
		var arrays: Array = body.mesh.surface_get_arrays(0)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var width: int = weights.size() / source.size()
		var points: PackedVector3Array = []
		for v: int in source.size():
			var point: Vector3 = Vector3.ZERO
			for j: int in width:
				var bind: int = bones[v*width+j]
				var bone: int = skeleton.find_bone(body.skin.get_bind_name(bind))
				point += (skeleton.get_bone_global_rest(bone) * body.skin.get_bind_pose(bind) * source[v]) * weights[v*width+j]
			points.append(skeleton.global_transform * point)
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face: int in indices.size()/3:
			var label: String = annotation.labels["0/0"][face]
			var color: Color = Color(0.25,0.27,0.3)
			if label.ends_with("heel"): color = Color(0.85,0.28,0.16)
			elif label.ends_with("midsole"): color = Color(0.12,0.65,0.45)
			elif label.ends_with("toe"): color = Color(0.18,0.45,0.95)
			elif label.ends_with("coverage_margin"): color = Color(0.8,0.75,0.35)
			elif not label.begins_with("excluded"): color = Color(0.65,0.4,0.2)
			if face in [80753,13891]: color = Color(1,0,1)
			for j: int in 3:
				surface.set_color(color)
				surface.add_vertex(points[indices[face*3+j]])
		overlay = MeshInstance3D.new()
		overlay.mesh = surface.commit()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.material_override = material
		add_child(overlay)


	func _apply() -> void:
		var spec: Dictionary = request.shots[shot]
		var annotated: bool = bool(spec.get("annotated", false))
		actor.visible = not annotated
		if overlay != null: overlay.visible = annotated
		reference_grid.visible = bool(spec.get("reference_plane", false))
		player.stop()
		skeleton.reset_bone_poses()
		if spec.get("clip", "rest") != "rest":
			player.play(spec.clip)
			player.seek(player.get_animation(spec.clip).length * float(spec.phase), true)
			skeleton.force_update_all_bone_transforms()
		camera.size = float(spec.get("size", 0.8))
		camera.position = Vector3(spec.eye[0],spec.eye[1],spec.eye[2])
		var target: Vector3 = Vector3(spec.target[0],spec.target[1],spec.target[2])
		var up: Vector3 = Vector3.FORWARD if absf((target-camera.position).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
		camera.look_at(target, up)
		_frames = 0


	func _process(_delta: float) -> void:
		_frames += 1
		if _frames != 12: return
		await RenderingServer.frame_post_draw
		var path: String = request.output.path_join(String(request.shots[shot].id) + ".png")
		snapshot._frames = _frames
		if snapshot._save_shot(path) != OK:
			get_tree().quit(2)
			return
		var pose: Array = []
		for index: int in skeleton.get_bone_count(): pose.append(_matrix(skeleton.get_bone_global_pose(index)))
		records.append({"shot": request.shots[shot], "path": ProjectSettings.globalize_path(path), "sha256": FileAccess.get_sha256(path),
			"engine_frame": Engine.get_process_frames(), "viewport_size": [get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],
			"window_size": [get_window().size.x,get_window().size.y], "camera": _matrix(camera.global_transform), "orthographic_size": camera.size,
			"actor": _matrix(actor.global_transform), "skeleton": _matrix(skeleton.global_transform), "globals": pose,
			"native_time_s": player.get_animation(String(request.shots[shot].clip)).length * float(request.shots[shot].phase) if request.shots[shot].get("clip", "rest") != "rest" else null})
		shot += 1
		if shot == request.shots.size():
			var file: FileAccess = FileAccess.open(request.output.path_join("frames.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify({"godot": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
				"resource_sha256": request.get("resource_sha256", {}), "collector_sha256": FileAccess.get_sha256("res://tools/units3d/archer_arp/contact_evidence.gd"),
				"capture_method": "SnapshotScreen._save_shot on real native window; diagnostic anatomical camera; unchanged equipped actor", "frames": records}, "\t") + "\n")
			file.close()
			get_tree().quit()
		else:
			_apply()
