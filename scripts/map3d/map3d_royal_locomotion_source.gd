@tool
class_name Map3DRoyalLocomotionSource
extends Resource
## R1 adapter; never a clock, pose solver, contact certificate or policy.
## extract() is the IO boundary. sample() uses a detached native Animation,
## not a reconstructed/quantized key atlas. Re-extract when source identity changes.
## Geometry is in native mesh coordinates; model_from_skeleton includes every
## authored parent affine. Skin weights are used exactly as packed, without division.
## Material patches identify bind-mesh triangles, not moving lowest-point anchors.

@export_file("*.tscn") var scene_path: String
@export var source_hashes: Dictionary[String, String] = {}
@export var provenance: Dictionary = {}
@export var landmarks: Dictionary = {}
@export var sole_patches: Dictionary = {}
@export var observations: Dictionary = {}
@export var support_intervals: Array[Dictionary] = []
@export var airborne_intervals: Array[Dictionary] = []
@export var contact_authority: String = "UNRESOLVED"
@export var calibration_sha256: String

const _HOOVES: Array[String] = ["FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R"]
const _UNIT_ROUNDOFF: float = 8.0 * 0.00000011920928955078125


func extract() -> Dictionary:
	if scene_path.is_empty() or not source_hashes.has(scene_path) or source_hashes.size() < 3:
		return _reject("source_identity_missing")
	var imports: Dictionary = {}
	for path: String in source_hashes:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != source_hashes[path]:
			return _reject("stale_source:" + path)
		if path.ends_with(".glb.import"):
			var imported: Dictionary = import_identity(path)
			if not imported.ok:
				return imported
			if not source_hashes.has(imported.source_file):
				return _reject("unbound_import_source")
			imports[path] = imported
	if imports.is_empty():
		return _reject("native_import_missing")
	# Ignore the shared resource cache, including dependencies: an old loaded scene
	# must not be labelled with the hashes of newly installed files.
	var scene: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if scene == null:
		return _reject("scene_missing")
	var root: Node = scene.instantiate()
	var result: Dictionary = _capture(root)
	root.free()
	if not result.ok:
		return result
	var source: Dictionary = result.source
	var reason: String = _calibration_error(source)
	if not reason.is_empty():
		return _reject(reason)
	source["calibration"] = calibration_data()
	source["identity"] = {"files": source_hashes.duplicate(), "godot": Engine.get_version_info(),
		"imports": imports, "calibration_sha256": calibration_sha256}
	source["sha256"] = _source_digest(source)
	source.identity["source_sha256"] = source.sha256
	return {"ok": true, "source": source, "diagnostics": {"contact_disposition": "UNRESOLVED", "activation_pass": false}}


static func import_identity(settings_path: String) -> Dictionary:
	var settings := ConfigFile.new()
	if not FileAccess.file_exists(settings_path) or settings.load(settings_path) != OK:
		return _reject("import_settings")
	for pair: Array in [["deps", "source_file"], ["deps", "dest_files"], ["remap", "path"]]:
		if not settings.has_section_key(pair[0], pair[1]):
			return _reject("import_settings_schema")
	var source: Variant = settings.get_value("deps", "source_file")
	var native: Variant = settings.get_value("remap", "path")
	if not source is String or not native is String or not FileAccess.file_exists(source) or not FileAccess.file_exists(native) or settings.get_value("deps", "dest_files") != [native]:
		return _reject("import_paths")
	var checksums := ConfigFile.new()
	var md5_path: String = native.get_basename() + ".md5"
	if not FileAccess.file_exists(md5_path) or checksums.load(md5_path) != OK:
		return _reject("import_receipt_missing")
	if not checksums.has_section_key("", "source_md5") or not checksums.has_section_key("", "dest_md5"):
		return _reject("import_receipt_schema")
	if checksums.get_value("", "source_md5") != FileAccess.get_md5(source) or checksums.get_value("", "dest_md5") != FileAccess.get_md5(native):
		return _reject("stale_or_corrupt_native_import")
	return {"ok": true, "source_file": source, "native_file": native, "native_sha256": FileAccess.get_sha256(native)}


func calibration_data() -> Dictionary:
	return {"provenance": provenance.duplicate(true), "landmarks": landmarks.duplicate(true),
		"sole_patches": sole_patches.duplicate(true), "observations": observations.duplicate(true),
		"support_intervals": support_intervals.duplicate(true), "airborne_intervals": airborne_intervals.duplicate(true),
		"contact_authority": contact_authority}


func _capture(root: Node) -> Dictionary:
	var skeletons: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	var players: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if not root is Node3D or skeletons.size() != 1 or players.size() != 1 or meshes.size() != 1:
		return _reject("royal_scene_shape")
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	var player: AnimationPlayer = players[0] as AnimationPlayer
	var mesh: MeshInstance3D = meshes[0] as MeshInstance3D
	if skeleton.get_bone_count() != 59 or not skeleton.find_children("*", "SkeletonModifier3D", true, false).is_empty():
		return _reject("skeleton_shape_or_modifier")
	if not mesh.mesh is ArrayMesh or mesh.mesh.get_blend_shape_count() != 0 or mesh.skin == null or mesh.skin.get_bind_count() != 59 or mesh.get_node_or_null(mesh.skeleton) != skeleton:
		return _reject("mesh_skin_shape")
	if not player.has_animation("MARCH"):
		return _reject("march_missing")
	var animation: Animation = player.get_animation("MARCH").duplicate(true) as Animation
	if animation == null or animation.length <= 0.0 or animation.loop_mode != Animation.LOOP_LINEAR or not _finite(_animation_data(animation)):
		return _reject("native_animation")
	var bones: Array[Dictionary] = []
	var names: Dictionary = {}
	for i: int in skeleton.get_bone_count():
		var name: String = skeleton.get_bone_name(i)
		var parent: int = skeleton.get_bone_parent(i)
		if names.has(name) or parent >= i or parent < -1 or not skeleton.is_bone_enabled(i):
			return _reject("native_hierarchy")
		names[name] = i
		bones.append({"name": name, "parent": parent, "rest": skeleton.get_bone_rest(i),
			"position": skeleton.get_bone_pose_position(i), "rotation": skeleton.get_bone_pose_rotation(i),
			"scale": skeleton.get_bone_pose_scale(i)})
	var tracks: Array[Dictionary] = []
	var seen: Dictionary = {}
	for i: int in animation.get_track_count():
		var path: NodePath = animation.track_get_path(i)
		var type: int = animation.track_get_type(i)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or path.get_subname_count() != 1 or not names.has(String(path.get_subname(0))):
			return _reject("unsupported_track:" + str(path))
		if player.get_node(player.root_node).get_node_or_null(NodePath(path.get_concatenated_names())) != skeleton:
			return _reject("track_target")
		var bone: int = names[String(path.get_subname(0))]
		var id: String = str(bone) + ":" + str(type)
		if seen.has(id) or animation.track_get_key_count(i) == 0:
			return _reject("duplicate_or_empty_track")
		seen[id] = true
		tracks.append({"bone": bone, "type": type, "enabled": animation.track_is_enabled(i)})
	var binds: Array[Dictionary] = []
	for i: int in mesh.skin.get_bind_count():
		var name: String = mesh.skin.get_bind_name(i)
		if not names.has(name) or not _affine(mesh.skin.get_bind_pose(i)):
			return _reject("skin_bind")
		binds.append({"name": name, "bone": names[name], "stored_bone": mesh.skin.get_bind_bone(i), "inverse_bind": mesh.skin.get_bind_pose(i)})
	var surfaces: Array[Dictionary] = []
	var vertices: int = 0
	for surface: int in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface).duplicate(true)
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		if mesh.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or arrays[Mesh.ARRAY_BONES].size() != count * 4 or arrays[Mesh.ARRAY_WEIGHTS].size() != count * 4:
			return _reject("geometry_shape")
		for i: int in count * 4:
			if arrays[Mesh.ARRAY_BONES][i] < 0 or arrays[Mesh.ARRAY_BONES][i] >= binds.size() or arrays[Mesh.ARRAY_WEIGHTS][i] < 0.0:
				return _reject("packed_skin_data")
		vertices += count
		var packed: Dictionary = RenderingServer.mesh_get_surface(mesh.mesh.get_rid(), surface)
		surfaces.append({"arrays": arrays, "format": mesh.mesh.surface_get_format(surface),
			"lods": packed.get("lods", []).duplicate(true), "packed_skin": packed.get("skin_data", PackedByteArray())})
	if vertices != 23774:
		return _reject("vertex_count")
	var frames: Dictionary = {}
	for node: Node in [root] + root.find_children("*", "Node3D", true, false):
		frames[str(root.get_path_to(node))] = (node as Node3D).transform
	var source: Dictionary = {"animation": animation, "tracks": tracks, "bones": bones, "binds": binds,
		"surfaces": surfaces, "node_frames": frames, "model_from_skeleton": _model_frame(root, skeleton),
		"model_from_mesh": _model_frame(root, mesh)}
	var plain: Dictionary = source.duplicate()
	plain.erase("animation")
	if not _finite(plain) or not _affine(source.model_from_skeleton) or not _affine(source.model_from_mesh):
		return _reject("nonfinite_native")
	return {"ok": true, "source": source}


func _calibration_error(source: Dictionary) -> String:
	if calibration_sha256.is_empty() or _digest(calibration_data()) != calibration_sha256:
		return "corrupt_calibration"
	if contact_authority != "UNRESOLVED" or not support_intervals.is_empty() or not airborne_intervals.is_empty():
		return "unapproved_contact_authority"
	if not _finite(provenance) or provenance.is_empty() or not _finite(landmarks) or landmarks.size() != source.bones.size() or not _finite(sole_patches) or sole_patches.size() != 4 or not _finite(observations) or observations.size() != 3:
		return "calibration_schema"
	for bone: Dictionary in source.bones:
		var landmark: Variant = landmarks.get(bone.name)
		if not landmark is Dictionary or not landmark.get("head") is Vector3 or not landmark.get("tail") is Vector3 or landmark.head == landmark.tail or not landmark.get("provenance") is String or landmark.provenance.is_empty():
			return "anatomical_landmark:" + bone.name
	for hoof: String in _HOOVES:
		var patch: Variant = sole_patches.get(hoof)
		if not patch is Dictionary or not patch.get("triangles") is PackedInt32Array or not patch.get("vertices") is PackedInt32Array or not _affine(patch.get("bind_frame")) or not _affine(patch.get("bone_from_sole")) or patch.get("role") != "measured_material_patch_not_stance" or not patch.get("provenance") is String or patch.provenance.is_empty():
			return "sole_patch:" + hoof
		if not patch.get("surface") is int or patch.surface < 0 or patch.surface >= source.surfaces.size() or patch.triangles.is_empty():
			return "sole_surface:" + hoof
		var arrays: Array = source.surfaces[patch.surface].arrays
		var expected: PackedInt32Array = PackedInt32Array()
		for triangle: int in patch.triangles:
			if triangle < 0 or triangle * 3 + 2 >= arrays[Mesh.ARRAY_INDEX].size():
				return "sole_triangle:" + hoof
			for corner: int in 3:
				expected.append(arrays[Mesh.ARRAY_INDEX][triangle * 3 + corner])
		if expected != patch.vertices:
			return "stale_sole_topology:" + hoof
	return ""


static func validate(source: Variant, identity: Variant) -> Dictionary:
	if not source is Dictionary or not source.get("animation") is Animation or source.animation.get_script() != null or not source.get("sha256") is String or not source.get("identity") is Dictionary:
		return _reject("source_schema")
	if not identity is Dictionary or not _finite(identity) or source.identity != identity or identity.get("source_sha256") != source.sha256:
		return _reject("stale_identity")
	var digest: String = _source_digest(source)
	if digest.is_empty() or digest != source.sha256:
		return _reject("corrupt_source")
	return {"ok": true}


static func sample(source: Variant, identity: Variant, phase: Variant) -> Dictionary:
	var valid: Dictionary = validate(source, identity)
	if not valid.ok:
		return valid
	if not phase is float or not is_finite(phase) or phase < 0.0 or phase >= 1.0:
		return _reject("native_phase")
	var animation: Animation = source.animation
	var components: Array = source.bones.duplicate(true)
	var time: float = phase * animation.length
	for i: int in source.tracks.size():
		var track: Dictionary = source.tracks[i]
		if not track.enabled:
			continue
		match track.type:
			Animation.TYPE_POSITION_3D:
				components[track.bone].position = animation.position_track_interpolate(i, time)
			Animation.TYPE_ROTATION_3D:
				components[track.bone].rotation = animation.rotation_track_interpolate(i, time)
			Animation.TYPE_SCALE_3D:
				components[track.bone].scale = animation.scale_track_interpolate(i, time)
	var locals: Dictionary = {}
	var globals: Array[Transform3D] = []
	for bone: Dictionary in components:
		# Local scaling matches Skeleton3D's native pose TRS composition.
		var local: Transform3D = Transform3D(Basis(bone.rotation) * Basis.from_scale(bone.scale), bone.position)
		if not _affine(local):
			return _reject("native_singular_pose:" + bone.name)
		locals[bone.name] = local
		globals.append(local if bone.parent == -1 else globals[bone.parent] * local)
	var skin: Array[Transform3D] = []
	for bind: Dictionary in source.binds:
		skin.append(globals[bind.bone] * bind.inverse_bind)
	var positions: Array[PackedVector3Array] = []
	for surface: Dictionary in source.surfaces:
		var vertices: PackedVector3Array = _skin_vertices(surface.arrays, skin)
		for i: int in vertices.size():
			vertices[i] = source.model_from_skeleton * vertices[i]
		positions.append(vertices)
	return {"ok": true, "locals": locals, "globals": globals, "positions": positions, "phase": phase, "diagnostics": {"activation_pass": false}}


static func _skin_vertices(arrays: Array, skin: Array[Transform3D]) -> PackedVector3Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(vertices.size())
	for v: int in vertices.size():
		var p: Vector3 = Vector3.ZERO
		for k: int in 4:
			p += (skin[bones[4 * v + k]] * vertices[v]) * weights[4 * v + k]
		out[v] = p
	return out


## Physical points and fixed ground/anchor are supplied independently of pose.
## A planar point observation is not a Terrain3D surface/domain certificate.
static func point_error(point: Vector3, ground: Vector3, normal: Vector3, anchor: Vector3,
		world_per_model_m: float, mode: String) -> Dictionary:
	if not point.is_finite() or not ground.is_finite() or not normal.is_finite() or not anchor.is_finite() or not is_finite(world_per_model_m) or world_per_model_m <= 0.0 or absf(normal.length_squared() - 1.0) > _UNIT_ROUNDOFF or mode not in ["stance", "swing"]:
		return _reject("physical_point")
	var distance: float = normal.dot(point - ground)
	var delta: Vector3 = point - anchor
	var slip: float = (delta - normal * normal.dot(delta)).length()
	var penetration: float = maxf(0.0, -distance)
	var error: float = maxf(absf(distance), slip) if mode == "stance" else penetration
	return {"ok": true, "separation_m": distance / world_per_model_m, "slip_m": slip / world_per_model_m,
		"penetration_m": penetration / world_per_model_m, "error_m": error / world_per_model_m,
		"error_world": error, "scope": "one_material_point", "activation_pass": false}


## All vertices, including rider/gear and swing hooves. For this explicitly
## planar surface, triangle-interior separation is linear in the three corners.
## A measured Terrain3D witness must remain separate; it is not this plane.
static func plane_observation(points: PackedVector3Array, physical: Dictionary) -> Dictionary:
	if points.is_empty() or not _finite(physical) or physical.get("surface_kind") != "independent_plane" or not _affine(physical.get("model_to_world")) or not physical.get("ground") is Vector3 or not physical.get("normal") is Vector3 or not physical.get("provenance") is String or physical.provenance.is_empty():
		return _reject("physical_plane_schema")
	var at: Transform3D = physical.model_to_world
	var scale: float = at.basis.x.length()
	if not is_finite(scale) or scale <= 0.0:
		return _reject("invalid_placement_scale")
	var rotation: Basis = at.basis / scale
	if not rotation.is_equal_approx(rotation.orthonormalized()):
		return _reject("nonuniform_placement")
	var penetration: float = 0.0
	var witness: int = 0
	for i: int in points.size():
		var error: Dictionary = point_error(at * points[i], physical.ground, physical.normal, physical.ground, scale, "swing")
		if not error.ok:
			return error
		if error.penetration_m > penetration:
			penetration = error.penetration_m
			witness = i
	return {"ok": true, "penetration_m": penetration, "vertex": witness, "vertex_count": points.size(),
		"scope": "single_pose_whole_mesh_against_supplied_plane", "contact_disposition": "UNRESOLVED", "activation_pass": false}


## L/U already include independently justified uncertainty and directed rounding.
## Unknown is null, never zero. WITHIN_BOUND concerns this supplied bound only.
static func decide(lower_um: Variant, upper_um: Variant, contact_um: Variant) -> Dictionary:
	for value: Variant in [lower_um, upper_um]:
		if value != null and (not value is float or not is_finite(value) or value < 0.0):
			return _reject("error_bound")
	if contact_um != null and (not contact_um is int or contact_um < 0):
		return _reject("contact_budget")
	if lower_um != null and upper_um != null and lower_um > upper_um:
		return _reject("bound_order")
	var disposition: String = "UNRESOLVED"
	if contact_um != null:
		if lower_um != null and lower_um > contact_um:
			disposition = "FAIL"
		elif upper_um != null and upper_um <= contact_um:
			disposition = "WITHIN_BOUND"
	return {"ok": true, "disposition": disposition, "activation_pass": false}


static func _model_frame(root: Node3D, node: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != root:
		if parent is Node3D:
			result = parent.transform * result
		parent = parent.get_parent()
	return result


static func _animation_data(animation: Animation) -> Array:
	var tracks: Array = []
	for i: int in animation.get_track_count():
		var keys: Array = []
		for k: int in animation.track_get_key_count(i):
			keys.append([animation.track_get_key_time(i, k), animation.track_get_key_value(i, k), animation.track_get_key_transition(i, k)])
		tracks.append([animation.track_get_type(i), animation.track_get_path(i), animation.track_get_interpolation_type(i),
			animation.track_get_interpolation_loop_wrap(i), animation.track_is_enabled(i), animation.track_is_imported(i), keys])
	return [animation.length, animation.step, animation.loop_mode, tracks]


static func _source_digest(source: Dictionary) -> String:
	var plain: Dictionary = source.duplicate()
	plain.erase("sha256")
	plain.erase("identity")
	plain["animation"] = _animation_data(source.animation)
	return _digest(plain)


static func _digest(value: Variant) -> String:
	if not _finite(value):
		return ""
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(_canonical(value)))
	return hash.finish().hex_encode()


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var out: Dictionary = {}
		for key: Variant in keys:
			out[key] = _canonical(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_canonical(item))
		return out
	return value


static func _affine(value: Variant) -> bool:
	return value is Transform3D and _finite(value) and value.basis.determinant() > 0.0


static func _finite(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION:
			return value.is_finite()
		TYPE_BASIS:
			return value.x.is_finite() and value.y.is_finite() and value.z.is_finite()
		TYPE_TRANSFORM3D:
			return value.origin.is_finite() and _finite(value.basis)
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			for item: Variant in value:
				if not _finite(item, depth + 1):
					return false
			return true
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_DICTIONARY:
			for key: Variant in value:
				if (not key is String and not key is StringName) or not _finite(value[key], depth + 1):
					return false
			return true
	return false


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "source": {}, "locals": {}, "diagnostics": {"reason": reason, "activation_pass": false}}
