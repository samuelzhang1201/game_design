class_name Map3DRoyalCarrierSource
extends RefCounted
## Actual loaded source/native IO boundary; returns copied inputs, never placement.

const Bounds = preload("res://scripts/map3d/map3d_royal_carrier_bounds.gd")
const _CALIBRATION: String = "res://assets/3D/units/royal/royal_locomotion_source.tres"
const METHOD: String = "Terrain3DData::get_height/v1.0.2-stable/0077405b52e353c5e5dc3a094e7ede49833ba6fe"
# Verified against official release archive a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2.
const _PROFILE: Dictionary = {
	"libterrain.macos.debug":"12b4822ef56fb4396da974f4efcb2db26fa2d9c93179d353bd30ba647cc28b01",
	"libterrain.macos.release":"63449d6de24051669ea81464b1b6b2ae3dc0d72408845bec60b394867ed9b62a",
	"libterrain.linux.debug.x86_64.so":"178ae39467bb0743c1bbdf854a00f8e7d258a3691bcc1b63d4493beb6bde865e",
	"libterrain.linux.release.x86_64.so":"e79ebb2e48a63a5d6189a825f1d63ec847319dc8fa030936d95bf6fad8f294ef"}
# These exact accepted writers/predicates are the constant-A and domain proof's premises.
const _SOURCES: Dictionary = {
	"res://scripts/map3d/map3d_unit_glow.gd":"48aa3aecc97c901cb4f7e138962a49bf47a315676a241377c01807659c852874",
	"res://scripts/map3d/map3d_unit_settle.gd":"26ba22e211409286e6a750a34a3821a483811aae95ca1f086396c53b38f76a2f",
	"res://scripts/map3d/map3d_clip_chain.gd":"a435e3a8f481ddb68e1f4e636e3086aac89c9e15d1b46cc5a34c053b0fa3ed67",
	"res://scripts/map3d/map3d_unit_rig.gd":"71e683b7baabe3dd87e1185ec2ad34c9a8b41e35cf56b19d0dacd3bcc6fb8fec",
	"res://scripts/map3d/map3d_royal_locomotion_source.gd":"b4301e3953e92676cdb0386bf4324c9e779687c665dfd9c9433a0083d3e827e7",
	"res://scripts/map3d/map3d_world_loader.gd":"b59e4fb2cb7223fbd1989047fce0b2c5e05ab2cd0f3878a24fc212c9dc4c61bd",
	"res://scripts/engine/body_motion.gd":"f7d0928c7cfb0de7e2e56866f029b70a9d5b611a3ac9151a0d712a9af1d58eb7",
	"res://scripts/engine/army_system.gd":"8ca9982a4c5db6a2c792d76c87caab046c488934dc48c22360dfecbf7c540532",
	"res://scripts/engine/march_path.gd":"8f4b63b38c2f1e447ece94f09851939b1336a1a9f51880e05a07c8719264e568",
	"res://scripts/engine/unit_bodies.gd":"e5ef5385575531e95914d0adb6cd6dcf59751d093a29e428fc48284a8621b4ca",
	"res://scripts/engine/war_front.gd":"73c5fa064b95c84f4e5c5215bf120bd7ff7e496792179810ed59ba64d053a6dc",
	"res://scripts/map3d/map3d_battle_groups.gd":"8d5b66ff995eeb1db5a9eda90e2e37c0b30611bdca1d415e2a74169a2a24e372",
	"res://scripts/map3d/map3d_units.gd":"e842566f033267ae5cbb8bf548bed2aefc88103a9234b344cdc1b3554e32fb4d",
	"res://scripts/map3d/map3d_formation.gd":"374f643878041d8e3140506e7a06854fe295538b2431abdb6c449af617bbb970",
	"res://scripts/map3d/map3d_geometry.gd":"64797a53505cff9bd849e9245107f9be9f73fbb78cc2d27ab9f58b71bfce9e4c",
	"res://scripts/map3d/map3d_layer_units.gd":"864b603b941718b79d4cdfaf0466931d48dd85f14b27b666a345406cc14d93f0",
	"res://scripts/map3d/map3d_context.gd":"d7d45a27a77d7859a7df00b6d87980e106535c198b2828795d5f47837a5d3172"}


## Capture actual runtime maps, not a renamed synthetic plane or saved-data assumption.
static func extract(ctx: Map3DContext, child: Dictionary, model_root: Node3D) -> Dictionary:
	if ctx == null or ctx.repo == null or not child.get("node") is Node3D or model_root == null:
		return Bounds._reject("placement_missing")
	var root: Node3D = child.node
	if root != model_root and not root.is_ancestor_of(model_root): return Bounds._reject("model_ancestry")
	var scene: String = GameArt.path(GameArt.ARMY_MODELS,"royal")
	if scene.is_empty() or model_root.scene_file_path != scene: return Bounds._reject("source_model_root")
	var calibration: Map3DRoyalLocomotionSource = ResourceLoader.load(_CALIBRATION,"Resource",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Map3DRoyalLocomotionSource
	var binding := _bind_source(child,model_root,calibration)
	if not binding.ok: return binding
	for key: String in ["reference_height_m", "size", "height_m", "extent"]:
		if not child.has(key): return Bounds._reject("placement_missing:"+key)
	var repo := ctx.repo
	var reference := Map3DGeometry.distance_for_bar(repo,ctx.meta,repo.bal("map3d_zoom_start_scale"),ctx.view_size.y)
	var origin: Array = ctx.meta.get("pack_origin", [])
	if origin.size() != 2: return Bounds._reject("pack_origin")
	var placement := {"origin": Vector2(origin[0],origin[1]),
		"alpha": float(ctx.meta.get("m_per_px",0.0))/ArmySystem.metres_per_pack_px(repo),
		"k": Map3DUnits.scale_for(repo,repo.bal("map3d_fov_deg"),ctx.view_size.y,reference,child.reference_height_m,child.size),
		"extent": child.extent, "height": child.height_m, "clear": repo.bal("map3d_unit_seat_clear"),
		"sink": repo.bal("map3d_unit_sink_m"), "ring": int(repo.bal("map3d_unit_seat_ring")),
		"ancestor": Map3DUnitRig._local_to(root,model_root),
		"identity": {"reference_height_m": child.reference_height_m, "size": child.size,
			"metres_per_pack_px":ArmySystem.metres_per_pack_px(repo),
			"reference": reference, "view_size": ctx.view_size, "meta": ctx.meta.duplicate(true),
			"r1":binding.identity,"root_generation":binding.generation,
			"source_scene": {"path":scene,"sha256":FileAccess.get_sha256(scene)},
			"ancestor_path": String(root.get_path_to(model_root)), "ancestry": _ancestry(root,model_root)}}
	var terrain := {"kind": "native", "spacing": 1.0, "sea": float(ctx.meta.get("sea_y",0.0)),
		"region_size": 1, "regions": {}, "identity": {"method": METHOD,"godot": Engine.get_version_info()}}
	if ctx.height_fn.is_valid():
		terrain.kind = "override"
		terrain.identity["override"] = {"method": String(ctx.height_fn.get_method()), "object": ctx.height_fn.get_object_id()}
	elif ctx.terrain == null or ctx.terrain.get("data") == null:
		terrain.kind = "missing"
	else:
		if not ctx.terrain is Terrain3D: return Bounds._reject("native_terrain_class")
		var world_path: String = DataRepository.map3d_scene_of(repo.map_id)
		var manifest_path: String = repo.map3d_dir().path_join("manifest.json")
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
		if not manifest is Dictionary or not manifest.get("meta") is Dictionary or not Map3DWorldLoader.same_meta(ctx.meta,manifest.meta) \
			or not Map3DWorldLoader.same_meta(ctx.meta,Map3DWorldLoader.scene_meta(world_path)) \
			or ctx.terrain.data_directory != repo.map3d_dir().path_join("terrain"): return Bounds._reject("native_pack_binding")
		terrain.identity["pack"] = {"scene":world_path,"scene_sha256":FileAccess.get_sha256(world_path),"manifest_sha256":FileAccess.get_sha256(manifest_path)}
		terrain.spacing = ctx.terrain.vertex_spacing
		terrain.region_size = ctx.terrain.region_size
		terrain.identity["terrain_transform"] = ctx.terrain.global_transform
		terrain.identity["data_directory"] = ctx.terrain.data_directory
		terrain.identity["files"] = {}
		for filename: String in DirAccess.get_files_at(ctx.terrain.data_directory):
			if filename.ends_with(".res"):
				var path: String = ctx.terrain.data_directory.path_join(filename)
				terrain.identity.files[path] = FileAccess.get_sha256(path)
		for region: Resource in ctx.terrain.data.get_regions_active():
			var height: Image = region.get_height_map()
			var control: Image = region.get_control_map()
			if height == null or control == null or height.get_format() != Image.FORMAT_RF or control.get_format() != Image.FORMAT_RF:
				return Bounds._reject("native_map_format")
			terrain.regions[region.get_location()] = {"height":height.get_data().to_float32_array(),
				"control":control.get_data().to_int32_array()}
		var binaries: Dictionary = {}
		for path: String in _binary_paths():
			if FileAccess.file_exists(path): binaries[path] = FileAccess.get_sha256(path)
		terrain.identity["binaries"] = binaries
		var extension_path: String = "res://addons/terrain_3d/terrain.gdextension"
		var extension: GDExtension = GDExtensionManager.get_extension(extension_path)
		var extension_sha: String = FileAccess.get_sha256(extension_path)
		terrain.identity["extension"] = {"path":extension_path,"sha256":extension_sha,"loaded":extension != null and extension.is_library_open()}
		terrain.identity["method_bound"] = not binaries.is_empty() and terrain.identity.extension.loaded \
			and extension_sha == "93d2f783ff7a62733ce6176746725a07750321b83bfb59feabf8f28ba76829db" \
			and Vector2(16777217.0,0.0).x == 16777216.0
		for path: String in binaries:
			terrain.identity.method_bound = terrain.identity.method_bound and _PROFILE.get(path.get_file(),"") == binaries[path]
		if not terrain.identity.method_bound: terrain.identity.method = "UNAVAILABLE_UNKNOWN_NATIVE_BINARY"
		terrain.identity["engine_binary"] = FileAccess.get_sha256(OS.get_executable_path())
	# No stored path, version string or sparse native agreement proves all arithmetic branches.
	terrain.identity["native_arithmetic"] = "source-operation-outward-v1; exact native primitives plus real extension; no physical E"
	return {"ok":true,"placement":placement,"terrain":terrain}


## Match loaded native contents, not a cache key relabelled with current disk hashes.
static func _bind_source(child: Dictionary, model: Node3D, calibration: Map3DRoyalLocomotionSource) -> Dictionary:
	if calibration == null or model == null or model.scene_file_path != calibration.scene_path: return Bounds._reject("r1_source_missing")
	if not child.get("figs") is Array or not child.get("slots") is Array: return Bounds._reject("source_figure_slot")
	var index: int = child.figs.find(model)
	if index < 0 or index >= child.slots.size() or not child.slots[index] is Vector3: return Bounds._reject("source_figure_slot")
	if model.get_parent() != child.get("node"): return Bounds._reject("unproved_ancestor_driver")
	var group: Node3D = child.node
	if not group.top_level or model.top_level or group.get_script() != null or child.figs.size() != 1:
		return Bounds._reject("unproved_ancestor_driver")
	for node: Node in [model]+model.find_children("*","Node",true,false):
		if node.get_script() != null: return Bounds._reject("unproved_source_script")
		if node is AnimationMixer and not node is AnimationPlayer: return Bounds._reject("unproved_source_mixer")
		if node is AnimationPlayer:
			var animation_root: Node = node.get_node_or_null(node.root_node)
			if animation_root == null: return Bounds._reject("unproved_animation_root")
			for name: StringName in node.get_animation_list():
				var animation: Animation = node.get_animation(name)
				for track in animation.get_track_count():
					if not animation.track_is_enabled(track): continue
					var target: Node = animation_root.get_node_or_null(animation.track_get_path(track))
					if animation.track_get_type(track) == Animation.TYPE_METHOD or target == model:
						return Bounds._reject("unproved_ancestor_animation")
	for node: Node in group.get_children():
		if node == model: continue
		for sibling: Node in [node]+node.find_children("*","Node",true,false):
			if sibling.get_script() != null or sibling is AnimationMixer: return Bounds._reject("unproved_ancestor_driver")
	var expected := calibration.extract()
	if not expected.ok: return Bounds._reject("r1_source_invalid",{"r1":expected.get("diagnostics",{}).duplicate(true)})
	var ignored: Array = []
	for modifier: Node in model.find_children("*","SkeletonModifier3D",true,false):
		var parent: Node = modifier.get_parent()
		# Official4.7 and4.7.2 have the identical non-simulating compatibility writer.
		if Engine.get_version_info().hash not in ["5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88","ed1daf0bf001b61586d9930840f2f1394092c079"] \
			or modifier.get_class() != "PhysicalBoneSimulator3D" or not parent is Skeleton3D \
			or parent.get_children().has(modifier) or modifier.owner != null or modifier.get_script() != null \
			or modifier.get_child_count(true) != 0 or modifier.call("is_simulating_physics"):
			return Bounds._reject("unproved_source_modifier")
		ignored.append({"class":modifier.get_class(),"internal":true,"children":0,"simulating":false})
	# Node.duplicate omits internal children; only the guarded empty compatibility
	# simulator can disappear. Its non-simulating source has no skeleton writer.
	var detached: Node3D = model.duplicate(0) as Node3D
	var actual := calibration._capture(detached)
	detached.free()
	if not actual.ok: return Bounds._reject("loaded_source_invalid",{"r1":actual.get("diagnostics",{}).duplicate(true)})
	# Reproduce only the two existing formation writers on the fresh authored root.
	var reference := Node3D.new()
	reference.transform = expected.source.node_frames["."]
	reference.position = child.slots[index]
	var stature: Variant = null
	if child.has("statures"):
		if not child.statures is Array or index >= child.statures.size() or not Bounds._number(child.statures[index]) or child.statures[index] <= 0:
			reference.free()
			return Bounds._reject("source_stature")
		stature = child.statures[index]
		reference.scale = Vector3.ONE*float(stature)
	var root_matches: bool = model.transform == reference.transform
	reference.free()
	if not root_matches: return Bounds._reject("loaded_root_transform")
	actual.source.node_frames["."] = expected.source.node_frames["."]
	# Enabled native tracks overwrite these live poses at every phase; only their
	# authored keys are source. Unwritten/disabled baseline components still match.
	for track: Dictionary in expected.source.tracks:
		if not track.enabled: continue
		var key: String = {Animation.TYPE_POSITION_3D:"position",Animation.TYPE_ROTATION_3D:"rotation",Animation.TYPE_SCALE_3D:"scale"}[track.type]
		actual.source.bones[track.bone][key] = expected.source.bones[track.bone][key]
	actual.source["calibration"] = expected.source.calibration
	if calibration._source_digest(actual.source) != expected.source.sha256: return Bounds._reject("loaded_source_mismatch")
	# Re-measure only the figure: a later selected Glow is not part of model bounds.
	var measured := Node3D.new()
	var copy: Node3D = model.duplicate(0) as Node3D
	measured.add_child(copy)
	var bounds := Map3DBattleGroups.model_bounds(measured)
	copy.transform = expected.source.node_frames["."]
	var reference_height: float = Map3DUnits.model_size(copy).y
	measured.free()
	if child.get("bounds_model") != bounds or child.get("height_m") != bounds.size.y \
		or child.get("extent") != Vector2(maxf(absf(bounds.position.x),absf(bounds.end.x)),maxf(absf(bounds.position.z),absf(bounds.end.z))) \
		or child.get("reference_height_m") != reference_height:
		return Bounds._reject("placement_measurement_mismatch")
	return {"ok":true,"identity":expected.source.identity.duplicate(true),
		"generation":{"slot_position":child.slots[index],"stature":stature,
			"inert_internal_compatibility":ignored,
			"ancestor_constancy":"direct top-level physical group; generated fixed figure; R1 bone-only MARCH; LayerUnits physical branch bypasses lag",
			"A_S":Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)}}


static func _ancestry(root: Node3D, model: Node3D) -> Array:
	var out: Array = []
	var node: Node = model
	while node != root:
		if node is Node3D: out.append([String(node.name),(node as Node3D).transform])
		node = node.get_parent()
	return out


static func _binary_paths() -> Array[String]:
	match OS.get_name():
		"macOS": return ["res://addons/terrain_3d/bin/libterrain.macos.debug.framework/libterrain.macos.debug", "res://addons/terrain_3d/bin/libterrain.macos.release.framework/libterrain.macos.release"]
		"Linux":
			if OS.has_feature("x86_64"): return ["res://addons/terrain_3d/bin/libterrain.linux.debug.x86_64.so", "res://addons/terrain_3d/bin/libterrain.linux.release.x86_64.so"]
	return []
