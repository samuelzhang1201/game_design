class_name Map3DRoyalJetInput
extends RefCounted
## Closed copied-source/receipt boundary. Success is explicit, never an empty error string.

const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const Math = preload("res://scripts/map3d/map3d_royal_jet_math.gd")
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


static func validate(source: Variant, identity: Variant, arithmetic: Variant) -> Dictionary:
	var schema: Dictionary = _source_check(source)
	if schema.get("ok") != true:
		return {"ok": false, "reason": str(schema.get("reason", "source_schema_failed"))}
	var source_check: Dictionary = Source.validate(source, identity)
	if source_check.get("ok") != true:
		return {"ok": false, "reason": "source:" + str(source_check.get("diagnostics", {}).get("reason", "validation_failed"))}
	return _proof_check(arithmetic, identity)


static func _source_check(source: Variant) -> Dictionary:
	if not source is Dictionary or not source.get("animation") is Animation or source.animation.get_script() != null:
		return {"ok": false, "reason": "source_schema"}
	for name: String in ["bones", "binds", "surfaces", "tracks"]:
		if not source.get(name) is Array or source[name].is_empty():
			return {"ok": false, "reason": "source_array:" + name}
	if not source.get("calibration") is Dictionary or not source.calibration.get("sole_patches") is Dictionary or not Source._affine(source.get("model_from_skeleton")):
		return {"ok": false, "reason": "source_frames"}
	var animation: Animation = source.animation
	if not is_finite(animation.length) or animation.length <= 0.0 or animation.length > 1.0 or animation.loop_mode not in [Animation.LOOP_LINEAR, Animation.LOOP_NONE] or animation.get_track_count() != source.tracks.size():
		return {"ok": false, "reason": "unsupported_animation"}
	var names: Array[String] = []
	for i: int in source.bones.size():
		var bone: Variant = source.bones[i]
		if not bone is Dictionary or not bone.get("name") is String or names.has(bone.name) or not bone.get("parent") is int or bone.parent < -1 or bone.parent >= i or not bone.get("position") is Vector3 or not bone.get("rotation") is Quaternion or not bone.get("scale") is Vector3 or not bone.get("rest") is Transform3D:
			return {"ok": false, "reason": "bone_schema"}
		if not Source._finite(bone) or not bone.rotation.is_normalized() or bone.scale.x == 0.0 or bone.scale.y == 0.0 or bone.scale.z == 0.0:
			return {"ok": false, "reason": "bone_pose"}
		names.append(bone.name)
	var seen: Dictionary = {}
	for i: int in source.tracks.size():
		var track: Variant = source.tracks[i]
		if not track is Dictionary or not track.get("bone") is int or track.bone < 0 or track.bone >= source.bones.size() or not track.get("type") is int or not track.get("enabled") is bool:
			return {"ok": false, "reason": "track_schema"}
		var type: int = animation.track_get_type(i)
		var interpolation: int = animation.track_get_interpolation_type(i)
		var path: NodePath = animation.track_get_path(i)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or type != track.type or animation.track_is_enabled(i) != track.enabled or animation.track_is_compressed(i) or interpolation not in [Animation.INTERPOLATION_NEAREST, Animation.INTERPOLATION_LINEAR] or path.get_subname_count() != 1 or String(path.get_subname(0)) != source.bones[track.bone].name:
			return {"ok": false, "reason": "unsupported_native_track"}
		var key: String = str(track.bone) + ":" + str(type)
		if seen.has(key) or animation.track_get_key_count(i) < 1:
			return {"ok": false, "reason": "duplicate_or_empty_track"}
		seen[key] = true
		var previous: float = -1.0
		for k: int in animation.track_get_key_count(i):
			var time: float = animation.track_get_key_time(i, k)
			var value: Variant = animation.track_get_key_value(i, k)
			if not is_finite(time) or Math._negative(time) or time > animation.length or (k > 0 and time - previous <= 4.0 * Math.EPS):
				return {"ok": false, "reason": "unsupported_key_time"}
			if animation.track_get_key_transition(i, k) not in [0.0, 1.0] or not Source._finite(value) or (type == Animation.TYPE_ROTATION_3D and (not value is Quaternion or not value.is_normalized())) or (type != Animation.TYPE_ROTATION_3D and not value is Vector3):
				return {"ok": false, "reason": "unsupported_key_value_or_transition"}
			previous = time
	for bind: Variant in source.binds:
		if not bind is Dictionary or not bind.get("bone") is int or bind.bone < 0 or bind.bone >= source.bones.size() or not Source._affine(bind.get("inverse_bind")):
			return {"ok": false, "reason": "bind_schema"}
	for surface: Variant in source.surfaces:
		if not surface is Dictionary or not surface.get("arrays") is Array or surface.arrays.size() != Mesh.ARRAY_MAX:
			return {"ok": false, "reason": "surface_schema"}
		var arrays: Array = surface.arrays
		if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_BONES] is PackedInt32Array or not arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array or arrays[Mesh.ARRAY_VERTEX].is_empty() or arrays[Mesh.ARRAY_BONES].size() != arrays[Mesh.ARRAY_VERTEX].size() * 4 or arrays[Mesh.ARRAY_WEIGHTS].size() != arrays[Mesh.ARRAY_BONES].size() or not Source._finite(arrays):
			return {"ok": false, "reason": "skin_schema"}
		for i: int in arrays[Mesh.ARRAY_BONES].size():
			if arrays[Mesh.ARRAY_BONES][i] < 0 or arrays[Mesh.ARRAY_BONES][i] >= source.binds.size() or arrays[Mesh.ARRAY_WEIGHTS][i] < 0.0:
				return {"ok": false, "reason": "skin_index_or_weight"}
	for hoof: Variant in source.calibration.sole_patches:
		var patch: Variant = source.calibration.sole_patches[hoof]
		if not hoof is String or not names.has(hoof) or not patch is Dictionary or not Source._affine(patch.get("bone_from_sole")):
			return {"ok": false, "reason": "sole_schema"}
	return {"ok": true}


static func _proof_check(arithmetic: Variant, identity: Dictionary) -> Dictionary:
	if not arithmetic is Dictionary or not arithmetic.get("receipt") is Dictionary or not arithmetic.get("capture_canonical") is String or not Source._finite(arithmetic):
		return {"ok": false, "reason": "arithmetic_schema"}
	var receipt: Dictionary = arithmetic.receipt
	var capture: Variant = JSON.parse_string(arithmetic.capture_canonical)
	if not capture is Dictionary or not capture.get("native") is Dictionary or not capture.get("engine") is Dictionary or not capture.get("acquisition") is Dictionary:
		return {"ok": false, "reason": "capture_schema"}
	var native: Dictionary = capture.native
	var engine: Dictionary = capture.engine
	var acquisition: Dictionary = capture.acquisition
	var platform: Variant = native.get("platform")
	if not platform is String or not PROFILES.has(platform) or receipt.get("schema") != "royal-native-arithmetic/1" or receipt.get("status") != "closed_scalar_value_proof" or receipt.get("verifier_sha256") != VERIFIER or receipt.get("profile") != platform + "/" + PROFILES[platform][0]:
		return {"ok": false, "reason": "arithmetic_profile"}
	if receipt.get("scope") != "scalar values only; no derivative, source-domain, JETS or physical E acceptance" or receipt.get("assumptions") != "IEEE binary32/binary64 basic operations/FMA/sqrt; all rounding directions; explicit FTZ allowances; intermediates below 2^100":
		return {"ok": false, "reason": "arithmetic_receipt_assumptions"}
	var keys: Array = receipt.keys()
	keys.sort()
	if keys != ["assumptions", "capture_sha256", "engine_sha256", "profile", "schema", "scope", "sha256", "status", "theorems", "verifier_sha256"]:
		return {"ok": false, "reason": "arithmetic_receipt_schema"}
	if capture.get("schema") != "royal-native-arithmetic/1" or native.get("schema") != 1:
		return {"ok": false, "reason": "arithmetic_capture_schema"}
	var unsigned: Dictionary = receipt.duplicate(true)
	unsigned.erase("sha256")
	if receipt.get("sha256") != _sha(_json(unsigned)) or receipt.get("capture_sha256") != _sha(arithmetic.capture_canonical) or _sha(_json(receipt.get("theorems"))) != PROFILES[platform][2]:
		return {"ok": false, "reason": "arithmetic_digest_or_theorem"}
	if not identity.get("godot") is Dictionary or not engine.get("version") is Dictionary:
		return {"ok": false, "reason": "arithmetic_engine_version"}
	for version: Dictionary in [engine.version, identity.godot]:
		for key: String in ["major", "minor", "patch"]:
			if not _integer(version.get(key)) or version[key] < 0:
				return {"ok": false, "reason": "arithmetic_engine_version"}
		for key: String in ["hash", "status", "build"]:
			if not version.get(key) is String or version[key].is_empty():
				return {"ok": false, "reason": "arithmetic_engine_version"}
	for key: String in ["hash", "major", "minor", "patch", "status", "build"]:
		if engine.version.get(key) != identity.godot.get(key):
			return {"ok": false, "reason": "arithmetic_engine_version"}
	if not BUILDS.has(engine.version.hash) or receipt.get("engine_sha256") != BUILDS[engine.version.hash]:
		return {"ok": false, "reason": "unproved_native_engine_build"}
	for key: String in ["header_sha256", "collector_sha256", "source_sha256", "script_sha256", "engine_sha256"]:
		if not _hash_string(acquisition.get(key)):
			return {"ok": false, "reason": "arithmetic_acquisition"}
	if acquisition.source_sha256 != COLLECTOR or acquisition.script_sha256 != CAPTURE_SCRIPT or receipt.get("engine_sha256") != acquisition.engine_sha256 or engine.get("executable_sha256") != acquisition.engine_sha256 or native.get("selected_engine_sha256") != acquisition.engine_sha256 or native.get("header_sha256") != acquisition.header_sha256 or engine.get("collector_sha256") != acquisition.collector_sha256:
		return {"ok": false, "reason": "arithmetic_acquisition_identity"}
	if not _integer(native.get("pid")) or not _integer(engine.get("pid")) or native.pid <= 0 or native.pid != engine.pid:
		return {"ok": false, "reason": "arithmetic_process_identity"}
	if not native.get("engine_path") is String or native.engine_path.is_empty() or not engine.get("executable") is String or engine.executable.is_empty() or native.engine_path != engine.executable:
		return {"ok": false, "reason": "arithmetic_engine_path"}
	if not native.get("engine_image_id") is String or not acquisition.get("engine_image_id") is String or native.engine_image_id != acquisition.engine_image_id:
		return {"ok": false, "reason": "arithmetic_engine_image"}
	var ids: Variant = acquisition.get("selected_binary_image_ids")
	if not ids is Array:
		return {"ok": false, "reason": "arithmetic_engine_image"}
	for image_id: Variant in ids:
		if not image_id is String or image_id.is_empty():
			return {"ok": false, "reason": "arithmetic_engine_image"}
	if (native.engine_image_id not in ids if not native.engine_image_id.is_empty() else (platform != "linux-x86_64" or not ids.is_empty())):
		return {"ok": false, "reason": "arithmetic_engine_image"}
	if engine.get("architecture") != ("arm64" if platform == "macos-arm64" else "x86_64") or native.get("engine_version_components") != [engine.version.major, engine.version.minor, engine.version.patch]:
		return {"ok": false, "reason": "arithmetic_engine_architecture"}
	if not native.get("imports") is Array or native.imports.size() != 3:
		return {"ok": false, "reason": "arithmetic_imports"}
	var profiles: Dictionary = {}
	for i: int in 3:
		var name: String = ["sin", "sinf", "acosf"][i]
		if not native.imports[i] is Array or native.imports[i].is_empty():
			return {"ok": false, "reason": "arithmetic_imports"}
		for record: Variant in native.imports[i]:
			if not record is Dictionary or record.get("symbol") != name or record.get("image_id") != PROFILES[platform][0] or record.get("image_path") != PROFILES[platform][3] or record.get("dlsym_equal") != (not (platform == "linux-x86_64" and name == "acosf")) or not _address(record.get("target")) or not _address(record.get("image_base")):
				return {"ok": false, "reason": "arithmetic_import_binding"}
			if record.target.hex_to_int() - record.image_base.hex_to_int() != record.get("entry_offset"):
				return {"ok": false, "reason": "arithmetic_import_address"}
			var selected: Dictionary = {}
			for key: String in (["code_offset", "entry_offset", "code", "extra_code", "operands"] if platform == "linux-x86_64" else ["code_offset", "entry_offset", "code"]):
				selected[key] = record.get(key)
			if profiles.has(name) and profiles[name] != selected:
				return {"ok": false, "reason": "arithmetic_duplicate_import"}
			profiles[name] = selected
	if _sha(_json(profiles)) != PROFILES[platform][1]:
		return {"ok": false, "reason": "arithmetic_instruction_profile"}
	return {"ok": true}


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
