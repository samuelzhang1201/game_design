@tool
extends EditorScenePostImport
## Unwired GLB-only seam: native paths/rest, exact source LINEAR/STEP TRS keys.

const PAIR: Array[String] = ["PIVOT_LEFT", "PIVOT_RIGHT"]
const TYPES: Dictionary = {"translation": Animation.TYPE_POSITION_3D, "rotation": Animation.TYPE_ROTATION_3D, "scale": Animation.TYPE_SCALE_3D}


func _post_import(scene: Node) -> Object:
	var result: Dictionary = process(scene, get_source_file())
	if not result.ok:
		push_error(result.error)
		return null
	return scene


static func process(scene: Node, source: String) -> Dictionary:
	if scene == null:
		return _failure(scene, "Missing imported scene")
	var parsed: Dictionary = _read(source)
	if parsed.has("error"):
		return _failure(scene, parsed.error)
	if parsed.clips.is_empty():
		return {"ok": true, "scene": scene, "error": ""}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.create_animations = false
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_DISCARD_TEXTURES
	var json: Dictionary = parsed.json.duplicate(true)
	# Native conversion determines only hierarchy/rest/paths, never bakes a curve.
	json.animations = []
	if document.append_from_buffer(_glb(json, parsed.binary), source.get_base_dir(), state) != OK:
		return _failure(scene, "Native GLB conversion failed")
	var temporary: Node = document.generate_scene(state)
	if temporary == null:
		return _failure(scene, "Native scene generation failed")
	var result: Dictionary = _stage(scene, temporary, state, parsed.clips)
	temporary.free()
	if not result.ok:
		return result
	var library: AnimationLibrary = result.library
	# Both resources and their complete schemas are validated before either is published.
	for name: String in PAIR:
		library.remove_animation(name)
		library.add_animation(name, result.replacements[name])
	return {"ok": true, "scene": scene, "error": ""}


static func _failure(scene: Node, error: String) -> Dictionary:
	return {"ok": false, "scene": scene, "error": error}


static func _integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= maximum and float(value) == floorf(float(value))


static func _read(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() < 28 or file.get_length() > 67108864:
		return {"error": "Expected a GLB between 28 bytes and 64 MiB"}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return {"error": "Invalid GLB header"}
	var size: int = bytes.decode_u32(12)
	if size % 4 != 0 or size > bytes.size() - 28:
		return {"error": "Invalid GLB JSON chunk"}
	var parser := JSON.new()
	if parser.parse(bytes.slice(20, 20 + size).get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"error": "Invalid GLB JSON"}
	var json: Dictionary = parser.data
	var animations: Variant = json.get("animations", [])
	if not animations is Array or animations.size() > 128:
		return {"error": "Invalid animation list"}
	var pair: Dictionary = {}
	for animation: Variant in animations:
		if not animation is Dictionary:
			return {"error": "Invalid animation"}
		var name: String = str(animation.get("name", ""))
		if name in PAIR:
			if pair.has(name):
				return {"error": "Duplicate pivot clip"}
			pair[name] = animation
	if pair.is_empty():
		return {"clips": {}}
	if pair.size() != 2:
		return {"error": "Both pivot clips are required"}
	var offset: int = 20 + size
	if bytes.decode_u32(offset + 4) != 0x004e4942 or bytes.decode_u32(offset) != bytes.size() - offset - 8:
		return {"error": "Expected one embedded BIN chunk"}
	var binary: PackedByteArray = bytes.slice(offset + 8)
	for key: String in ["nodes", "accessors", "bufferViews", "buffers"]:
		if not json.get(key) is Array:
			return {"error": "Missing GLB table " + key}
	if json.nodes.is_empty() or json.nodes.size() > 1024 or json.buffers.size() != 1 or not json.buffers[0] is Dictionary or json.buffers[0].has("uri"):
		return {"error": "Unsupported GLB layout"}
	if not _integer(json.buffers[0].get("byteLength"), binary.size()) or binary.size() - int(json.buffers[0].byteLength) > 3:
		return {"error": "Invalid embedded buffer length"}
	var clips: Dictionary = {}
	var total_keys: int = 0
	for name: String in PAIR:
		var animation: Dictionary = pair[name]
		if not animation.get("channels") is Array or not animation.get("samplers") is Array or animation.channels.is_empty() or animation.channels.size() > 1024:
			return {"error": "Invalid pivot channels"}
		var channels: Array[Dictionary] = []
		var seen: Dictionary = {}
		var duration: float = 0.0
		for channel: Variant in animation.channels:
			if not channel is Dictionary or channel.has("extensions") or not channel.get("target") is Dictionary or not _integer(channel.get("sampler"), animation.samplers.size() - 1):
				return {"error": "Invalid pivot channel"}
			var target: Dictionary = channel.target
			if not _integer(target.get("node"), json.nodes.size() - 1) or not TYPES.has(target.get("path", "")) or target.has("extensions"):
				return {"error": "Only node TRS pivot channels are supported"}
			var id: String = str(target.node) + ":" + target.path
			if seen.has(id):
				return {"error": "Duplicate pivot target"}
			seen[id] = true
			var sampler: Variant = animation.samplers[int(channel.sampler)]
			if not sampler is Dictionary or sampler.has("extensions") or sampler.get("interpolation", "LINEAR") not in ["LINEAR", "STEP"]:
				return {"error": "Unsupported pivot interpolation"}
			var width: int = 4 if target.path == "rotation" else 3
			var times: Array = _floats(json, binary, sampler.get("input"), 1)
			var values: Array = _floats(json, binary, sampler.get("output"), width)
			if times.is_empty() or values.size() != times.size() * width:
				return {"error": "Invalid pivot sampler accessors"}
			var previous: float = -1.0
			for time: float in times:
				if time <= previous or time < 0.0 or time > 60.0:
					return {"error": "Pivot times must increase within 0..60 seconds"}
				previous = time
			if times[0] != 0.0:
				return {"error": "Pivot channels must start at zero"}
			if width == 4:
				for i: int in range(times.size()):
					var q := Quaternion(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3])
					if absf(q.length_squared() - 1.0) > .0001:
						return {"error": "Invalid pivot quaternion"}
			total_keys += times.size()
			if total_keys > 1000000:
				return {"error": "Pivot key budget exceeded"}
			duration = maxf(duration, times[-1])
			channels.append({"node": int(target.node), "component": target.path, "times": times, "values": values, "step": sampler.get("interpolation", "LINEAR") == "STEP"})
		if duration <= 0.0:
			return {"error": "Pivot duration must be positive"}
		clips[name] = {"channels": channels, "duration": duration}
	return {"json": json, "binary": binary, "clips": clips}


static func _floats(json: Dictionary, binary: PackedByteArray, index: Variant, width: int) -> Array:
	if not _integer(index, json.accessors.size() - 1):
		return []
	var accessor: Variant = json.accessors[int(index)]
	if not accessor is Dictionary or accessor.get("componentType") != 5126 or accessor.get("type") != {1: "SCALAR", 3: "VEC3", 4: "VEC4"}[width] or accessor.has("sparse") or accessor.get("normalized", false):
		return []
	if not _integer(accessor.get("count"), 4096) or int(accessor.count) < 1 or not _integer(accessor.get("bufferView"), json.bufferViews.size() - 1):
		return []
	var view: Variant = json.bufferViews[int(accessor.bufferView)]
	if not view is Dictionary or view.get("buffer") != 0:
		return []
	for item: Variant in [view.get("byteOffset", 0), view.get("byteLength"), view.get("byteStride", width * 4), accessor.get("byteOffset", 0)]:
		if not _integer(item, binary.size()):
			return []
	var stride: int = int(view.get("byteStride", width * 4))
	var start: int = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var end: int = start + (int(accessor.count) - 1) * stride + width * 4
	if stride < width * 4 or stride > 252 or stride % 4 != 0 or start % 4 != 0 or end > binary.size() or end > int(view.get("byteOffset", 0)) + int(view.byteLength) or int(view.get("byteOffset", 0)) + int(view.byteLength) > binary.size():
		return []
	var out: Array = []
	for i: int in range(int(accessor.count)):
		for axis: int in range(width):
			var value: float = binary.decode_float(start + i * stride + axis * 4)
			if not is_finite(value):
				return []
			out.append(value)
	return out


static func _glb(json: Dictionary, binary: PackedByteArray) -> PackedByteArray:
	var encoded: PackedByteArray = JSON.stringify(json).to_utf8_buffer()
	while encoded.size() % 4:
		encoded.append(32)
	var bytes := PackedByteArray()
	bytes.resize(20)
	bytes.encode_u32(0, 0x46546c67)
	bytes.encode_u32(4, 2)
	bytes.encode_u32(8, 28 + encoded.size() + binary.size())
	bytes.encode_u32(12, encoded.size())
	bytes.encode_u32(16, 0x4e4f534a)
	bytes.append_array(encoded)
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, binary.size())
	header.encode_u32(4, 0x004e4942)
	bytes.append_array(header)
	bytes.append_array(binary)
	return bytes


static func _stage(scene: Node, temporary: Node, state: GLTFState, clips: Dictionary) -> Dictionary:
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return _failure(scene, "Expected one native AnimationPlayer")
	var player: AnimationPlayer = players[0] as AnimationPlayer
	if player.get_node_or_null(player.root_node) != scene or not player.has_animation_library(""):
		return _failure(scene, "Unsupported AnimationPlayer root/library")
	var library: AnimationLibrary = player.get_animation_library("")
	for name: String in PAIR:
		if not library.has_animation(name):
			return _failure(scene, "Imported pivot pair is incomplete")
	var nodes: Array[GLTFNode] = state.get_nodes()
	var paths: Dictionary = {}
	var rests: Dictionary = {}
	for clip: Dictionary in clips.values():
		for channel: Dictionary in clip.channels:
			var index: int = channel.node
			if paths.has(index):
				continue
			var native: Node = state.get_scene_node(index)
			if not native is Skeleton3D:
				return _failure(scene, "Pivot channels must target native skeleton bones")
			var skeleton: Skeleton3D = native as Skeleton3D
			var path: NodePath = temporary.get_path_to(skeleton)
			var target: Node = scene.get_node_or_null(path)
			if not target is Skeleton3D or not _same_rest(scene, temporary, target, skeleton):
				return _failure(scene, "Native skeleton path/rest disagreement")
			var bone: int = skeleton.find_bone(nodes[index].resource_name)
			if bone < 0:
				return _failure(scene, "Missing native bone mapping")
			var rest: Transform3D = skeleton.get_bone_rest(bone)
			if not _close(rest, nodes[index].xform):
				return _failure(scene, "Source/native local affine disagreement")
			paths[index] = NodePath(str(path) + ":" + skeleton.get_bone_name(bone))
			rests[index] = rest
	var replacements: Dictionary = {}
	for name: String in PAIR:
		var replacement := Animation.new()
		replacement.resource_name = name
		replacement.step = library.get_animation(name).step
		replacement.length = clips[name].duration
		replacement.loop_mode = Animation.LOOP_NONE
		var present: Dictionary = {}
		var animated_nodes: Dictionary = {}
		for channel: Dictionary in clips[name].channels:
			var path: NodePath = paths[channel.node]
			var type: int = TYPES[channel.component]
			var track: int = replacement.add_track(type)
			replacement.track_set_path(track, path)
			replacement.track_set_imported(track, true)
			replacement.track_set_interpolation_loop_wrap(track, false)
			replacement.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST if channel.step else Animation.INTERPOLATION_LINEAR)
			present[str(path) + ":" + str(type)] = true
			animated_nodes[channel.node] = true
			var width: int = 4 if type == Animation.TYPE_ROTATION_3D else 3
			for i: int in range(channel.times.size()):
				var v: Array = channel.values
				var value: Variant = Quaternion(v[i * width], v[i * width + 1], v[i * width + 2], v[i * width + 3]).normalized() if width == 4 else Vector3(v[i * width], v[i * width + 1], v[i * width + 2])
				replacement.track_insert_key(track, channel.times[i], value)
			if replacement.track_get_key_count(track) != channel.times.size():
				return _failure(scene, "Native animation cannot retain every source key")
		# Only absent components get native-rest padding; source tracks are never dropped.
		for index: int in animated_nodes:
			var rest: Transform3D = rests[index]
			var rotation: Quaternion = rest.basis.get_rotation_quaternion()
			var scale: Vector3 = rest.basis.get_scale()
			if not _close(Transform3D(Basis(rotation).scaled_local(scale), rest.origin), rest):
				return _failure(scene, "Static native rest cannot be represented by TRS")
			for type: int in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				var path: NodePath = paths[index]
				if present.has(str(path) + ":" + str(type)):
					continue
				var track: int = replacement.add_track(type)
				replacement.track_set_path(track, path)
				replacement.track_set_imported(track, true)
				replacement.track_set_interpolation_loop_wrap(track, false)
				var value: Variant = rest.origin if type == Animation.TYPE_POSITION_3D else (rotation if type == Animation.TYPE_ROTATION_3D else scale)
				replacement.track_insert_key(track, 0.0, value)
		var original: Animation = library.get_animation(name)
		for i: int in range(original.get_track_count()):
			var type: int = original.track_get_type(i)
			var target: int = replacement.find_track(original.track_get_path(i), type)
			if target < 0:
				return _failure(scene, "Imported track has no source/native mapping")
			var id: String = str(original.track_get_path(i)) + ":" + str(type)
			if not present.has(id) and original.track_get_key_count(i) > 0:
				var first: Variant = original.track_get_key_value(i, 0)
				for key: int in range(1, original.track_get_key_count(i)):
					if original.track_get_key_value(i, key) != first:
						return _failure(scene, "Cannot pad a missing dynamic source component")
				var expected: Variant = replacement.track_get_key_value(target, 0)
				var observed_component := Transform3D.IDENTITY
				var rest_component := Transform3D.IDENTITY
				match type:
					Animation.TYPE_POSITION_3D:
						observed_component.origin = first
						rest_component.origin = expected
					Animation.TYPE_ROTATION_3D:
						observed_component.basis = Basis(first)
						rest_component.basis = Basis(expected)
					Animation.TYPE_SCALE_3D:
						observed_component.basis = Basis.IDENTITY.scaled(first)
						rest_component.basis = Basis.IDENTITY.scaled(expected)
				if not _close(observed_component, rest_component):
					return _failure(scene, "Static native component disagrees with rest")
		replacements[name] = replacement
	return {"ok": true, "library": library, "replacements": replacements}


static func _close(a: Transform3D, b: Transform3D) -> bool:
	if not a.is_finite() or not b.is_finite():
		return false
	if a.origin.distance_to(b.origin) > .00001:
		return false
	for axis: int in range(3):
		if a.basis[axis].distance_to(b.basis[axis]) > .00001:
			return false
	return true


static func _same_rest(scene: Node, temporary: Node, target: Skeleton3D, source: Skeleton3D) -> bool:
	if target.get_bone_count() != source.get_bone_count():
		return false
	for bone: int in range(source.get_bone_count()):
		if target.get_bone_name(bone) != source.get_bone_name(bone) or target.get_bone_parent(bone) != source.get_bone_parent(bone) or not _close(target.get_bone_rest(bone), source.get_bone_rest(bone)):
			return false
	var a: Node = target
	var b: Node = source
	while a != scene and b != temporary:
		if not a is Node3D or not b is Node3D or not _close(a.transform, b.transform):
			return false
		a = a.get_parent()
		b = b.get_parent()
	return a == scene and b == temporary
