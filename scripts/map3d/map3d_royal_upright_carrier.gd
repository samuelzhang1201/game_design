class_name Map3DRoyalUprightCarrier
extends RefCounted
## Accepted239 §3: detached ordinary upright carrier, never placement or contact policy.
## extract is the IO boundary; prepare/evaluate/sample read copied values only.
## Native values and real one-sided extension derivatives have separate bounds.
## This is not a physical contact certificate or an error-budget decision.

const _CALIBRATION: String = "res://assets/3D/units/royal/royal_locomotion_source.tres"
const METHOD: String = "Terrain3DData::get_height/v1.0.2-stable/0077405b52e353c5e5dc3a094e7ede49833ba6fe"
const SHORTCUT_SQUARED: float = 0.00009999999747378752 # source's binary32 0.0001f
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
	"res://scripts/map3d/map3d_unit_rig.gd":"60891e8fb8ec0a21b0431d2994ff97a7bf7aa36cdf78a0887f102f62062348ae",
	"res://scripts/map3d/map3d_royal_locomotion_source.gd":"b4301e3953e92676cdb0386bf4324c9e779687c665dfd9c9433a0083d3e827e7",
	"res://scripts/map3d/map3d_world_loader.gd":"b59e4fb2cb7223fbd1989047fce0b2c5e05ab2cd0f3878a24fc212c9dc4c61bd",
	"res://scripts/engine/body_motion.gd":"3b1206a72c4785c72295bb2d0847b3c76ea3f7cf2c411adaf040202e33389c53",
	"res://scripts/engine/army_system.gd":"88927f0ba74acbd0917fce2c183405ad61c92620814d968fb25c73f00dc897e4",
	"res://scripts/engine/march_path.gd":"8f4b63b38c2f1e447ece94f09851939b1336a1a9f51880e05a07c8719264e568",
	"res://scripts/engine/unit_bodies.gd":"e5ef5385575531e95914d0adb6cd6dcf59751d093a29e428fc48284a8621b4ca",
	"res://scripts/engine/war_front.gd":"73c5fa064b95c84f4e5c5215bf120bd7ff7e496792179810ed59ba64d053a6dc",
	"res://scripts/map3d/map3d_battle_groups.gd":"7463362b4ebe22f4af6a0e45761de88070f420df3c780dc2456fd71164a6ba59",
	"res://scripts/map3d/map3d_units.gd":"e842566f033267ae5cbb8bf548bed2aefc88103a9234b344cdc1b3554e32fb4d",
	"res://scripts/map3d/map3d_formation.gd":"fc702e2e5371ec5f9a52a06f88962410d357da7ead28a22038762140a2a469e4",
	"res://scripts/map3d/map3d_geometry.gd":"64797a53505cff9bd849e9245107f9be9f73fbb78cc2d27ab9f58b71bfce9e4c",
	"res://scripts/map3d/map3d_layer_units.gd":"2dc1cbda7e4491d404d109d6501d9bf08286ede97a247509906f22f00e685176",
	"res://scripts/map3d/map3d_context.gd":"d7d45a27a77d7859a7df00b6d87980e106535c198b2828795d5f47837a5d3172"}

static func prepare(placement: Dictionary, terrain: Dictionary) -> Dictionary:
	if not _placement_ok(placement) or not _terrain_ok(terrain): return _reject("packet_schema")
	var packet := {"version": 1, "placement": placement.duplicate(true), "terrain": terrain.duplicate(true)}
	packet["sha256"] = _digest(packet)
	return {"ok": true, "packet": packet}

## Capture actual runtime maps, not a renamed synthetic plane or saved-data assumption.
static func extract(ctx: Map3DContext, child: Dictionary, model_root: Node3D) -> Dictionary:
	if ctx == null or ctx.repo == null or not child.get("node") is Node3D or model_root == null:
		return _reject("placement_missing")
	var root: Node3D = child.node
	if root != model_root and not root.is_ancestor_of(model_root): return _reject("model_ancestry")
	var scene: String = GameArt.path(GameArt.ARMY_MODELS,"royal")
	if scene.is_empty() or model_root.scene_file_path != scene: return _reject("source_model_root")
	var calibration: Map3DRoyalLocomotionSource = ResourceLoader.load(_CALIBRATION,"Resource",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Map3DRoyalLocomotionSource
	var binding := _bind_source(child,model_root,calibration)
	if not binding.ok: return binding
	for key: String in ["reference_height_m", "size", "height_m", "extent"]:
		if not child.has(key): return _reject("placement_missing:"+key)
	var repo := ctx.repo
	var reference := Map3DGeometry.distance_for_bar(repo,ctx.meta,repo.bal("map3d_zoom_start_scale"),ctx.view_size.y)
	var origin: Array = ctx.meta.get("pack_origin", [])
	if origin.size() != 2: return _reject("pack_origin")
	var placement := {"origin": Vector2(origin[0],origin[1]),
		"alpha": float(ctx.meta.get("m_per_px",0.0))/ArmySystem.metres_per_pack_px(repo),
		"k": Map3DUnits.scale_for(repo,repo.bal("map3d_fov_deg"),ctx.view_size.y,reference,child.reference_height_m,child.size),
		"extent": child.extent, "height": child.height_m, "clear": repo.bal("map3d_unit_seat_clear"),
		"sink": repo.bal("map3d_unit_sink_m"), "ring": int(repo.bal("map3d_unit_seat_ring")),
		"ancestor": Map3DUnitRig._local_to(root,model_root),
		"identity": {"reference_height_m": child.reference_height_m, "size": child.size,
			"metres_per_pack_px":ArmySystem.metres_per_pack_px(repo),"admission":_domain_source(repo),
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
		if not ctx.terrain is Terrain3D: return _reject("native_terrain_class")
		var world_path: String = DataRepository.map3d_scene_of(repo.map_id)
		var manifest_path: String = repo.map3d_dir().path_join("manifest.json")
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
		if not manifest is Dictionary or not manifest.get("meta") is Dictionary or not Map3DWorldLoader.same_meta(ctx.meta,manifest.meta) \
			or not Map3DWorldLoader.same_meta(ctx.meta,Map3DWorldLoader.scene_meta(world_path)) \
			or ctx.terrain.data_directory != repo.map3d_dir().path_join("terrain"): return _reject("native_pack_binding")
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
				return _reject("native_map_format")
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
	return prepare(placement,terrain)

## Match loaded native contents, not a cache key relabelled with current disk hashes.
static func _bind_source(child: Dictionary, model: Node3D, calibration: Map3DRoyalLocomotionSource) -> Dictionary:
	if calibration == null or model == null or model.scene_file_path != calibration.scene_path: return _reject("r1_source_missing")
	if not child.get("figs") is Array or not child.get("slots") is Array: return _reject("source_figure_slot")
	var index: int = child.figs.find(model)
	if index < 0 or index >= child.slots.size() or not child.slots[index] is Vector3: return _reject("source_figure_slot")
	if model.get_parent() != child.get("node"): return _reject("unproved_ancestor_driver")
	var group: Node3D = child.node
	if not group.top_level or model.top_level or group.get_script() != null or child.figs.size() != 1:
		return _reject("unproved_ancestor_driver")
	for node: Node in [model]+model.find_children("*","Node",true,false):
		if node.get_script() != null: return _reject("unproved_source_script")
		if node is AnimationPlayer:
			var animation_root: Node = node.get_node_or_null(node.root_node)
			if animation_root == null: return _reject("unproved_animation_root")
			for name: StringName in node.get_animation_list():
				var animation: Animation = node.get_animation(name)
				for track in animation.get_track_count():
					if not animation.track_is_enabled(track): continue
					var target: Node = animation_root.get_node_or_null(animation.track_get_path(track))
					if animation.track_get_type(track) == Animation.TYPE_METHOD or target == model:
						return _reject("unproved_ancestor_animation")
	for node: Node in group.get_children():
		if node == model: continue
		for sibling: Node in [node]+node.find_children("*","Node",true,false):
			if sibling.get_script() != null or sibling is AnimationMixer: return _reject("unproved_ancestor_driver")
	var expected := calibration.extract()
	if not expected.ok: return _reject("r1_source_invalid",{"r1":expected.get("diagnostics",{}).duplicate(true)})
	var ignored: Array = []
	for modifier: Node in model.find_children("*","SkeletonModifier3D",true,false):
		var parent: Node = modifier.get_parent()
		# Official4.7 and4.7.2 have the identical non-simulating compatibility writer.
		if Engine.get_version_info().hash not in ["5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88","ed1daf0bf001b61586d9930840f2f1394092c079"] \
			or modifier.get_class() != "PhysicalBoneSimulator3D" or not parent is Skeleton3D \
			or parent.get_children().has(modifier) or modifier.owner != null or modifier.get_script() != null \
			or modifier.get_child_count(true) != 0 or modifier.call("is_simulating_physics"):
			return _reject("unproved_source_modifier")
		ignored.append({"class":modifier.get_class(),"internal":true,"children":0,"simulating":false})
	# Node.duplicate omits internal children; only the guarded empty compatibility
	# simulator can disappear. Its non-simulating source has no skeleton writer.
	var detached: Node3D = model.duplicate(0) as Node3D
	var actual := calibration._capture(detached)
	detached.free()
	if not actual.ok: return _reject("loaded_source_invalid",{"r1":actual.get("diagnostics",{}).duplicate(true)})
	# Reproduce only the two existing formation writers on the fresh authored root.
	var reference := Node3D.new()
	reference.transform = expected.source.node_frames["."]
	reference.position = child.slots[index]
	var stature: Variant = null
	if child.has("statures"):
		if not child.statures is Array or index >= child.statures.size() or not _number(child.statures[index]) or child.statures[index] <= 0:
			reference.free()
			return _reject("source_stature")
		stature = child.statures[index]
		reference.scale = Vector3.ONE*float(stature)
	var root_matches: bool = model.transform == reference.transform
	reference.free()
	if not root_matches: return _reject("loaded_root_transform")
	actual.source.node_frames["."] = expected.source.node_frames["."]
	# Enabled native tracks overwrite these live poses at every phase; only their
	# authored keys are source. Unwritten/disabled baseline components still match.
	for track: Dictionary in expected.source.tracks:
		if not track.enabled: continue
		var key: String = {Animation.TYPE_POSITION_3D:"position",Animation.TYPE_ROTATION_3D:"rotation",Animation.TYPE_SCALE_3D:"scale"}[track.type]
		actual.source.bones[track.bone][key] = expected.source.bones[track.bone][key]
	actual.source["calibration"] = expected.source.calibration
	if calibration._source_digest(actual.source) != expected.source.sha256: return _reject("loaded_source_mismatch")
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
		return _reject("placement_measurement_mismatch")
	return {"ok":true,"identity":expected.source.identity.duplicate(true),
		"generation":{"slot_position":child.slots[index],"stature":stature,
			"inert_internal_compatibility":ignored,
			"ancestor_constancy":"direct top-level physical group; generated fixed figure; R1 bone-only MARCH; LayerUnits physical branch bypasses lag",
			"A_S":Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)}}

static func sample(packet: Dictionary, op: Dictionary, u: Variant, side: String, identity: String) -> Dictionary:
	if not _number(u) or u < 0.0 or u > 1.0 or not _op_ok(op): return _reject("operation")
	if not _valid(packet,identity): return _reject("stale_packet")
	var p: Dictionary = packet.placement
	var operation_sha: String = _digest(BodyMotion._loco_op(op.kind,int(op.t0_q),int(op.t1_q),
		[int(op.a[0]),int(op.a[1])],[int(op.b[0]),int(op.b[1])],int(op.yaw0_udeg),int(op.turn_udeg)))
	var request: Dictionary = {"packet_sha256":identity,"operation_sha256":operation_sha,"u":u,"side":side}
	var admission := _admission(packet,op)
	if packet.terrain.kind == "native" and not admission.ok:
		admission["request"] = request
		return admission
	var d: float = float(op.t1_q-op.t0_q)/BodyMotion.LOCOMOTION_Q
	var ds: Array = _interval([float(op.t1_q-op.t0_q),float(op.t1_q-op.t0_q)],[float(BodyMotion.LOCOMOTION_Q),float(BodyMotion.LOCOMOTION_Q)],"/",64)
	var alpha: Array = [float(p.alpha),float(p.alpha)]
	if p.identity.has("metres_per_pack_px"):
		alpha = _hull(alpha,_interval([float(p.identity.meta.m_per_px),float(p.identity.meta.m_per_px)],
			[float(p.identity.metres_per_pack_px),float(p.identity.metres_per_pack_px)],"/",64))
	var coordinates: Array[float] = []
	var origin_box: Array = []
	var velocity_box: Array = []
	var velocity: Array[float] = []
	for axis in 2:
		var a: float = float(op.a[axis])
		var delta: float = float(int(op.b[axis])-int(op.a[axis]))
		coordinates.append(a if u == 0.0 else (float(op.b[axis]) if u == 1.0 else a+delta*float(u)))
		var position: Array = [coordinates[axis],coordinates[axis]] if u == 0.0 or u == 1.0 else _interval([a,a],_interval([delta,delta],[float(u),float(u)],"*",64),"+",64)
		origin_box.append(_interval([float(p.origin[axis]),float(p.origin[axis])],_interval(position,alpha,"*",64),"+",64))
		velocity_box.append(_interval(_interval([delta,delta],alpha,"*",64),ds,"/",64))
		velocity.append(delta*float(p.alpha)/d)
	var heading: float = float(op.yaw0_udeg)+float(op.turn_udeg)*float(u)
	var heading_box: Array = _interval([float(op.yaw0_udeg),float(op.yaw0_udeg)],_interval([float(op.turn_udeg),float(op.turn_udeg)],[float(u),float(u)],"*",64),"+",64)
	var radians: Array = _interval([PI,_next64(PI,1)],[180000000.0,180000000.0],"/",64)
	var angle_box: Array = _neg(_interval(_interval([PI,_next64(PI,1)],[2.0,2.0],"/",64),_interval(heading_box,radians,"*",64),"+",64))
	var rate_box: Array = _neg(_interval(_interval([float(op.turn_udeg),float(op.turn_udeg)],radians,"*",64),ds,"/",64))
	var position := Vector2(coordinates[0],coordinates[1])
	var native_origin: Vector2 = p.origin+position*float(p.alpha)
	if p.identity.has("metres_per_pack_px"):
		var measure: float = p.identity.metres_per_pack_px
		native_origin = Map3DGeometry.pack_to_world(p.identity.meta,Vector2(coordinates[0]/measure,coordinates[1]/measure))
	var yaw: float = -PI/2.0-heading*PI/180000000.0
	var native_yaw: float = Map3DUnits.facing_yaw(Vector2.from_angle(deg_to_rad(heading/1000000.0)))
	var result := _evaluate(packet,{"origin":p.origin+position*float(p.alpha),"origin_S":Vector2(velocity[0],velocity[1]),
		"yaw":yaw,"yaw_S":-float(op.turn_udeg)*PI/180000000.0/d,"native_origin":native_origin,"native_yaw":native_yaw,
		"origin_box":origin_box,"velocity_box":velocity_box,"angle_box":angle_box,"rate_box":rate_box,"admission":admission},side,identity)
	result["operation_sha256"] = operation_sha
	result["request"] = request
	return result

## O and O_S are world XZ, yaw_S is per shared S, not per normalized u or seconds.
static func evaluate(packet: Dictionary, origin: Variant, origin_S: Variant, yaw: Variant,
		yaw_S: Variant, side: String, identity: String) -> Dictionary:
	if not _valid(packet,identity): return _reject("stale_packet")
	var result := _evaluate(packet,{"origin":origin,"origin_S":origin_S,"yaw":yaw,"yaw_S":yaw_S,
		"native_origin":origin,"native_yaw":yaw},side,identity)
	result["request"] = {"packet_sha256":identity,"origin":origin,"origin_S":origin_S,"yaw":yaw,"yaw_S":yaw_S,"side":side,"authority":"PROOF_DOMAIN_CONTROL"}
	return result

static func _evaluate(packet: Dictionary, query: Dictionary, side: String, identity: String) -> Dictionary:
	var origin: Variant = query.origin
	var origin_S: Variant = query.origin_S
	var yaw: Variant = query.yaw
	var yaw_S: Variant = query.yaw_S
	if not origin is Vector2 or not origin.is_finite() or not origin_S is Vector2 or not origin_S.is_finite() \
		or not _number(yaw) or not _number(yaw_S) or side not in ["left","right"]: return _reject("query")
	var p: Dictionary = packet.placement
	var t: Dictionary = packet.terrain
	if t.kind == "override": return _reject("height_override_unproved", {"identity":t.identity})
	if t.kind == "missing": return _reject("terrain_missing", {"fallback_sea":t.sea})
	if t.kind == "native" and not t.identity.get("method_bound",false): return _reject("native_height_method_unproved",{"identity":t.identity})
	var points: Array[Vector2] = [Vector2.ZERO]
	for share: float in [.5,1.0]:
		for i: int in p.ring:
			var angle: float = TAU*float(i)/float(p.ring)
			points.append(Vector2(p.extent.x*cos(angle),p.extent.y*sin(angle))*share*float(p.k))
	var samples: Array[Dictionary] = []
	var maximum: float = -INF
	var side_maximum: float = -INF
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	for local: Vector2 in points:
		var offset := Vector2(local.x*c+local.y*s,-local.x*s+local.y*c)
		var velocity: Vector2 = origin_S + Vector2(offset.y,-offset.x)*float(yaw_S)
		var acceleration: Vector2 = -offset*float(yaw_S)*float(yaw_S)
		var h := _height(t,origin+offset,velocity,acceleration,-1 if side == "left" else 1)
		if not h.ok:
			h.evidence["sample"] = samples.size()
			h.evidence["q"] = origin+offset
			return h
		maximum = maxf(maximum,h.value)
		side_maximum = maxf(side_maximum,h.limit)
		samples.append(h)
	if maximum != side_maximum:
		return _reject("native_side_jump_unresolved" if t.kind == "native" else "terrain_jump",{"value":maximum,"limit":side_maximum,"samples":samples,"side":side,"query":query})
	var derivative: float = INF if side == "left" else -INF
	var active: Array[int] = []
	for i in samples.size():
		if samples[i].limit == side_maximum:
			active.append(i)
			derivative = minf(derivative,samples[i].derivative) if side == "left" else maxf(derivative,samples[i].derivative)
	var y: float = maximum+float(p.height)*float(p.k)*float(p.clear)-float(p.sink)
	var basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*float(p.k))
	var basis_S := Basis(Vector3(-s,0,-c),Vector3.ZERO,Vector3(c,0,-s))
	basis_S = Basis(basis_S.x*float(p.k)*float(yaw_S),Vector3.ZERO,basis_S.z*float(p.k)*float(yaw_S))
	var A: Transform3D = p.ancestor
	var H := Transform3D(basis,Vector3(origin.x,y,origin.y))*A
	var H_S := {"basis": basis_S*A.basis,
		"origin":basis_S*A.origin+Vector3(origin_S.x,derivative,origin_S.y), "homogeneous_w":0}
	if not H.is_finite() or not H_S.basis.is_finite() or not H_S.origin.is_finite(): return _reject("carrier_numeric_range",{"yaw_S":yaw_S})
	query["side"] = side
	var enclosures := _enclose(packet,query)
	var admitted: bool = query.get("admission",{}).get("ok",false)
	var native: bool = t.kind == "native" and admitted and enclosures.status == "ENCLOSED_CONTROL" \
		and p.identity.has("r1") and p.identity.has("root_generation")
	if native: enclosures.status = "NATIVE_ENCLOSED"
	return {"ok":true,"H":H,"H_S":H_S,"enclosures":enclosures,"samples":samples,"active_samples":active,"yaw_S":yaw_S,
		"identity":identity,"side":side,"native_covered":native,"disposition":"COVERED" if native else "UNAVAILABLE","carrier_status":"NATIVE_ENCLOSED" if native else "ANALYTIC_EXTENSION_ONLY","H_semantics":"nominal real extension; native value authority is enclosures.H",
		"domain":domain(packet),"native_rounding":{"status":"ENCLOSED" if native else "UNAVAILABLE","reason":enclosures.get("reason","source-operation-outward-v1" if native else "unadmitted_control"),"exact_nominal_equality":false},
		"physical_allowance":{"status":"NOT_SELECTED"}}

## A complete implicit partition: no sampled atlas can erase unvisited headings or land.
static func domain(packet: Dictionary) -> Dictionary:
	var regions: Array = packet.terrain.regions.keys()
	regions.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var admission: Dictionary = packet.placement.identity.get("admission",{"status":"UNAVAILABLE","reason":"unadmitted_control"}).duplicate(true)
	admission.erase("grid")
	return {"operations":["move","pivot","hold"],"heading_udeg":[0,359999999],
		"turn_udeg":[-179999999,180000000],"duration_q":[1,BodyMotion.LOCOMOTION_Q],"u":[0.0,1.0],
		"placement":"all admitted measured-circle land/bounds operations; every footprint curve",
		"regions":regions,"outside_regions":"UNAVAILABLE_MISSING_DATA","admission":admission,
		"partition":["bilinear cells","vertex-shortcut disks","pixel cuts","sea cuts","holes","missing maps","overrides"],
		"classifier":"sample(packet,op,u,left|right); exhaustive implicit cell/address/branch partition, not a sampled atlas",
		"classifier_sha256":admission.get("classifier_sha256","proof_domain_control"),
		"native_status":"SOURCE_BOUND_CLASSIFIER" if packet.terrain.kind == "native" and admission.status == "BOUND_GEOMETRIC_SUPERSET" else "PROOF_DOMAIN_CONTROL",
		"whole_skin_and_rendered_LOD":"UNAVAILABLE_PHYSICAL_AUTHORITY"}

## Bind the actual land grid, including cached-engine equality. The predicate is
## a geometric superset: it grants no receipt, collision, cost or order authority.
static func _domain_source(repo: DataRepository) -> Dictionary:
	for path: String in _SOURCES:
		var script: GDScript = load(path) as GDScript
		if script == null or FileAccess.get_sha256(path) != _SOURCES[path] or script.source_code.sha256_text() != _SOURCES[path]:
			return {"status":"UNAVAILABLE","reason":"domain_source_changed","path":path}
	var self_path: String = "res://scripts/map3d/map3d_royal_upright_carrier.gd"
	var self_script: GDScript = load(self_path) as GDScript
	if self_script == null or self_script.source_code.sha256_text() != FileAccess.get_sha256(self_path): return {"status":"UNAVAILABLE","reason":"stale_classifier"}
	var grid := MarchPath.load_pack(repo)
	var cached := MarchPath.of_pack(repo)
	if not BodyMotion._loco_grid_ok(grid) or not BodyMotion._loco_grid_ok(cached): return {"status":"UNAVAILABLE","reason":"land_grid_missing"}
	var copied := {"cols":grid.cols,"rows":grid.rows,"cell_m":grid.cell_m,"closed":grid.closed.duplicate(),"water":grid.water.duplicate(),"water_open":grid.water_open}
	var live := {"cols":cached.cols,"rows":cached.rows,"cell_m":cached.cell_m,"closed":cached.closed,"water":cached.water,"water_open":cached.water_open}
	if _digest(copied) != _digest(live): return {"status":"UNAVAILABLE","reason":"cached_land_grid_mismatch"}
	var radius: Variant = repo.unit_footprints.get("royal",{}).get("radius_m")
	if not BodyMotion._loco_integer(radius) or radius <= 0 or radius > BodyMotion.LOCAL_LIMIT: return {"status":"UNAVAILABLE","reason":"body_radius"}
	var path: String = String(repo.maps[repo.map_id].data_dir)+"/geography/march_grid.png"
	return {"status":"BOUND_GEOMETRIC_SUPERSET","grid":copied,"grid_sha256":_digest(copied),"radius_m":int(radius),
		"map":repo.map_id,"map_row":repo.maps[repo.map_id].duplicate(true),"grid_file":{"path":path,"sha256":FileAccess.get_sha256(path)},
		"sources":_SOURCES.duplicate(),"classifier_sha256":FileAccess.get_sha256(self_path),
		"configuration":{"army_march_grid_px":repo.bal("army_march_grid_px"),"army_max_slope":repo.bal("army_max_slope"),"footprint":repo.unit_footprints.royal.duplicate(true)},
		"predicate":"BodyMotion._loco_grid_ok AND ArmySystem._body_path_terrain([a,b],radius_m)==empty"}

static func _admission(packet: Dictionary, op: Dictionary) -> Dictionary:
	var receipt: Dictionary = packet.placement.identity.get("admission",{})
	if receipt.get("status") != "BOUND_GEOMETRIC_SUPERSET": return _reject("domain_unavailable",{"receipt":receipt})
	var copied: Dictionary = receipt.grid
	var grid := MarchPath.new()
	for key: String in ["cols","rows","cell_m","closed","water","water_open"]: grid.set(key,copied[key])
	if not BodyMotion._loco_grid_ok(grid): return _reject("domain_grid_invalid")
	var error: String = ArmySystem._body_path_terrain(grid,[op.a,op.b],int(receipt.radius_m))
	if not error.is_empty(): return _reject("outside_admitted_terrain",{"reason":error,"operation":op.duplicate(true),"radius_m":receipt.radius_m,"grid_sha256":receipt.grid_sha256})
	return {"ok":true,"authority":"GEOMETRIC_SUPERSET_ONLY","grid_sha256":receipt.grid_sha256,"radius_m":receipt.radius_m}

static func _height(t: Dictionary, q: Vector2, v: Vector2, a: Vector2, side: int) -> Dictionary:
	var at := _branch(t,q,Vector2.ZERO,Vector2.ZERO,0)
	if not at.ok: return at
	var limit := _branch(t,q,v,a,side)
	if not limit.ok: return limit
	var raw: float = limit.value
	var d: float = limit.gradient.dot(v)
	var sea: float = t.sea
	var selected := "raw" if raw > sea else "sea"
	if raw < sea: d = 0.0
	elif raw == sea:
		d = minf(d,0.0) if side < 0 else maxf(d,0.0)
		selected = "sea_tie"
	return {"ok":true,"value":maxf(at.value,sea),"limit":maxf(raw,sea),"raw":at.value,"limit_raw":raw,"derivative":d,"branch":limit.branch,
		"cell":limit.cell,"sea_branch":selected,"gradient":limit.gradient,"raw_enclosure":at.raw_enclosure}

static func _branch(t: Dictionary, q: Vector2, v: Vector2, a: Vector2, side: int) -> Dictionary:
	var step: float = t.spacing
	if not q.is_finite() or absf(float(q.x)/step) > 2147483646.0 or absf(float(q.y)/step) > 2147483646.0:
		return _reject("native_index_range",{"q":q,"spacing":step})
	var index := Vector2i(_coordinate(q.x,step,v.x,a.x,side),_coordinate(q.y,step,v.y,a.y,side))
	var pixel := _pixel(t,index)
	if not pixel.ok: return pixel
	if (int(pixel.control)&4) != 0: return _reject("terrain_hole",{"fallback_sea":t.sea,"cell":index})
	var snapped := Vector2(floor(q.x/step+.5)*step,floor(q.y/step+.5)*step)
	var delta: Vector2 = q-snapped
	var radius: float = float(delta.x)*delta.x+float(delta.y)*delta.y
	var shortcut: bool = radius < SHORTCUT_SQUARED
	if radius == SHORTCUT_SQUARED and side != 0:
		var first: float = 2.0*delta.dot(v)*side
		var second: float = v.dot(v)+delta.dot(a)
		if first == 0.0 and second == 0.0: return _reject("shortcut_tangent_unproved",{"q":q})
		shortcut = first < 0.0 or (first == 0.0 and second < 0.0)
	if shortcut:
		if not is_finite(pixel.height): return _reject("terrain_nan" if is_nan(pixel.height) else "terrain_infinite",{"fallback_sea":t.sea,"cell":index,"word":pixel.height_word})
		return {"ok":true,"value":pixel.height,"gradient":Vector2.ZERO,"branch":"vertex_shortcut","cell":index,"raw_enclosure":[pixel.height,pixel.height]}
	var values: Array[float] = []
	for offset: Vector2i in [Vector2i.ZERO,Vector2i(0,1),Vector2i(1,0),Vector2i.ONE]:
		var corner := _pixel(t,index+offset)
		if not corner.ok: return corner
		if not is_finite(corner.height): return _reject("terrain_nan" if is_nan(corner.height) else "terrain_infinite",{"fallback_sea":t.sea,"cell":index+offset,"word":corner.height_word})
		values.append(corner.height)
	var x: float = (float(q.x)-float(index.x)*step)/step
	var z: float = (float(q.y)-float(index.y)*step)/step
	# Shared edges reduce to identical endpoint interpolation on both sides.
	var row0: float = values[0] if x == 0.0 else (values[2] if x == 1.0 else values[0]+(values[2]-values[0])*x)
	var row1: float = values[1] if x == 0.0 else (values[3] if x == 1.0 else values[1]+(values[3]-values[1])*x)
	var h: float = row0 if z == 0.0 else (row1 if z == 1.0 else row0+(row1-row0)*z)
	var gradient := Vector2(((values[2]-values[0])*(1-z)+(values[3]-values[1])*z)/step,
		((values[1]-values[0])*(1-x)+(values[3]-values[2])*x)/step)
	return {"ok":true,"value":h,"gradient":gradient,"branch":"bilinear","cell":index,"raw_enclosure":_height_enclosure(values,q,index,step)}

## Source bilerp's operation tree, with each binary32 result rounded OUTWARD.
## Keeping the exact real intermediate as well covers fused multiply/add contraction.
static func _height_enclosure(h: Array[float], q: Vector2, index: Vector2i, step: float) -> Array:
	var base := Vector2(float(index.x)*step,float(index.y)*step)
	var end: Vector2 = base+Vector2(step,step)
	var dx: Array = _interval([end.x,end.x],[base.x,base.x],"-")
	var dz: Array = _interval([end.y,end.y],[base.y,base.y],"-")
	var x0: Array = _interval([end.x,end.x],[q.x,q.x],"-")
	var z0: Array = _interval([end.y,end.y],[q.y,q.y],"-")
	var x1: Array = _interval([q.x,q.x],[base.x,base.x],"-")
	var z1: Array = _interval([q.y,q.y],[base.y,base.y],"-")
	var total: Array = [0.0,0.0]
	for i in 4:
		var term: Array = _interval([h[i],h[i]],x0 if i < 2 else x1,"*")
		term = _interval(term,z0 if i % 2 == 0 else z1,"*")
		total = term if i == 0 else _interval(total,term,"+")
	return _interval(total,_interval(dx,dz,"*"),"/")

## All 32-bit endpoints are exact in binary64. Products use at most48 bits;
## +/- with exponent gap<=28 uses at most53. Otherwise pad one binary64 ULP.
## Directed brackets contain BOTH real intermediates and every IEEE32 rounding,
## so multiply/add contraction is included. FTZ/DAZ is included below normal range.
static func _interval(a: Array, b: Array, op: String, bits: int = 32) -> Array:
	if not _bounded(a) or not _bounded(b): return [-INF,INF]
	if bits == 64 and (_subnormal64(a[0]) or _subnormal64(a[1]) or _subnormal64(b[0]) or _subnormal64(b[1])): return [-INF,INF]
	var aa: Array = _seed32(a) if bits == 32 else a
	var bb: Array = _seed32(b) if bits == 32 else b
	if not _bounded(aa) or not _bounded(bb) or (op == "/" and bb[0] <= 0.0 and bb[1] >= 0.0): return [-INF,INF]
	if bb == [0.0,0.0] and op in ["+","-"]: return aa
	if aa == [0.0,0.0] and op == "+": return bb
	if (aa == [0.0,0.0] or bb == [0.0,0.0]) and op == "*": return [0.0,0.0]
	if aa == [0.0,0.0] and op == "/": return [0.0,0.0]
	if bb == [1.0,1.0] and op in ["*","/"]: return aa
	if aa == [1.0,1.0] and op == "*": return bb
	var lower: float = INF
	var upper: float = -INF
	for x: float in aa:
		for y: float in bb:
			var value: float = x+y if op == "+" else (x-y if op == "-" else (x*y if op == "*" else x/y))
			if not is_finite(value): return [-INF,INF]
			var enclosure: Array
			if bits == 32 and (absf(value) < 1.1754943508222875e-38 and value != 0.0):
				enclosure = [-1.1754943508222875e-38,1.1754943508222875e-38]
			elif bits == 32 and op == "/":
				var rounded: float = PackedFloat32Array([value])[0]
				if not is_finite(rounded): return [-INF,INF]
				var relation: float = (rounded*y-x)*y # product exact; nearby subtraction exact (Sterbenz)
				enclosure = [rounded if relation <= 0 else _next32(rounded,-1),rounded if relation >= 0 else _next32(rounded,1)]
				enclosure = _seed32(enclosure)
			elif bits == 32:
				var exact: bool = op == "*" or x == 0.0 or y == 0.0 or absi(_exponent32(x)-_exponent32(y)) <= 28
				enclosure = _seed32([value,value] if exact else [_next64(value,-1),_next64(value,1)])
			else:
				enclosure = [_next64(value,-1),_next64(value,1)]
				if absf(value) < 2.2250738585072014e-308: enclosure = [minf(enclosure[0],-2.2250738585072014e-308),maxf(enclosure[1],2.2250738585072014e-308)]
			lower = minf(lower,enclosure[0])
			upper = maxf(upper,enclosure[1])
	return [lower,upper]

static func _bounded(a: Array) -> bool:
	return a.size() == 2 and is_finite(a[0]) and is_finite(a[1]) and a[0] <= a[1]

static func _seed32(a: Array) -> Array:
	var expanded: Array = a.duplicate()
	if _subnormal64(a[0]) or _subnormal64(a[1]) or (a[0] != 0.0 and absf(a[0]) < 1.1754943508222875e-38) or (a[1] != 0.0 and absf(a[1]) < 1.1754943508222875e-38):
		expanded = [minf(a[0],-1.1754943508222875e-38),maxf(a[1],1.1754943508222875e-38)]
	var lo: float = PackedFloat32Array([expanded[0]])[0]
	var hi: float = PackedFloat32Array([expanded[1]])[0]
	if not is_finite(lo) or not is_finite(hi): return [-INF,INF]
	lo = lo if lo <= expanded[0] else _next32(lo,-1)
	hi = hi if hi >= expanded[1] else _next32(hi,1)
	return [lo,hi]

static func _subnormal64(x: float) -> bool:
	var word: int = PackedFloat64Array([x]).to_byte_array().decode_s64(0)
	return (word & 0x7ff0000000000000) == 0 and (word & 0x000fffffffffffff) != 0

static func _exponent32(x: float) -> int:
	return maxi(1,(PackedFloat32Array([x]).to_byte_array().decode_u32(0)>>23)&255)

static func _next64(x: float, direction: int) -> float:
	if not is_finite(x): return x
	if x == 0.0: return float(direction)*4.9406564584124654e-324
	var data: PackedByteArray = PackedFloat64Array([x]).to_byte_array()
	data.encode_s64(0,data.decode_s64(0)+(direction if x > 0.0 else -direction))
	return data.decode_double(0)

## Taylor degree at most96/97, interval-evaluated. Lagrange remainder <= |x|^(n+1)/(n+1)!;
## sin/cos are1-Lipschitz, so the argument interval adds its radius. No libm ULP guess.
static func _trig_interval(angle: Array, cosine: bool) -> Array:
	if not _bounded(angle): return [-1.0,1.0]
	if angle == [0.0,0.0]: return [1.0,1.0] if cosine else [0.0,0.0]
	var center: float = angle[0]+(angle[1]-angle[0])*.5
	if absf(center) > 4.0*PI: return [-1.0,1.0]
	var square: Array = _interval([center,center],[center,center],"*",64)
	var term: Array = [1.0,1.0] if cosine else [center,center]
	var total: Array = term.duplicate()
	var degree: int = 0 if cosine else 1
	for n in range(1,49):
		var denominator: float = float((2*n)*(2*n-1 if cosine else 2*n+1))
		term = _interval(_interval(term,[-square[1],-square[0]],"*",64),[denominator,denominator],"/",64)
		total = _interval(total,term,"+",64)
		degree = 2*n if cosine else 2*n+1
		if maxf(absf(term[0]),absf(term[1])) <= maxf(absf(total[0]),absf(total[1]))*2.220446049250313e-16: break
	var remainder: Array = _interval(_interval([0.0,maxf(absf(term[0]),absf(term[1]))],[absf(center),absf(center)],"*",64),[float(degree+1),float(degree+1)],"/",64)
	var radius: float = maxf(_next64(absf(angle[0]-center),1),_next64(absf(angle[1]-center),1))
	var error: float = _next64(remainder[1]+radius,1)
	return [maxf(-1.0,_next64(total[0]-error,-1)),minf(1.0,_next64(total[1]+error,1))]

static func _next32(value: float, direction: int) -> float:
	if not is_finite(value): return value
	var bytes: PackedByteArray = PackedFloat32Array([value]).to_byte_array()
	var rounded: float = bytes.decode_float(0)
	if not is_finite(rounded):
		return 3.4028234663852886e38 if rounded > 0 and direction < 0 else (-3.4028234663852886e38 if rounded < 0 and direction > 0 else rounded)
	if rounded == 0.0: return float(direction)*1.401298464324817e-45
	var bits: int = bytes.decode_s32(0)
	bytes.encode_s32(0,bits+(direction if rounded > 0 else -direction))
	return bytes.decode_float(0)

static func _coordinate(q: float, step: float, v: float, a: float, side: int) -> int:
	var cell: int = floori(q/step)
	if q == float(cell)*step and side != 0 and (v*side < 0.0 or (v == 0.0 and a < 0.0)): cell -= 1
	return cell

static func _pixel(t: Dictionary, index: Vector2i) -> Dictionary:
	var size: int = t.region_size
	var region := Vector2i(floori(float(index.x)/size),floori(float(index.y)/size))
	if not t.regions.has(region): return _reject("terrain_missing_region",{"region":region,"cell":index,"fallback_sea":t.sea})
	var local: Vector2i = index-region*size
	var offset: int = local.y*size+local.x
	var control: int = int(t.regions[region].control[offset])
	if is_nan(PackedInt32Array([control]).to_byte_array().decode_float(0)): control = -1
	return {"ok":true,"height":float(t.regions[region].height[offset]),"control":control,"height_word":t.regions[region].height.slice(offset,offset+1).to_byte_array().decode_u32(0)}

static func _placement_ok(p: Dictionary) -> bool:
	if not BodyMotion._keys(p,["origin","alpha","k","extent","height","clear","sink","ring","ancestor","identity"]): return false
	if not p.origin is Vector2 or not p.origin.is_finite() or not p.extent is Vector2 or not p.extent.is_finite() or p.extent.x < 0 or p.extent.y < 0: return false
	for key: String in ["alpha","k","height","clear","sink"]:
		if not _number(p[key]): return false
	if p.alpha <= 0 or p.k <= 0 or p.height <= 0 or not p.ring is int or p.ring < 1: return false
	return p.ancestor is Transform3D and p.ancestor.is_finite() and p.ancestor.basis.determinant() != 0.0 and p.identity is Dictionary and not p.identity.is_empty()

static func _terrain_ok(t: Dictionary) -> bool:
	if not BodyMotion._keys(t,["kind","spacing","sea","region_size","regions","identity"]): return false
	if t.kind not in ["native","control","missing","override"] or not _number(t.spacing) or t.spacing <= .02 or not _number(t.sea): return false
	if not t.region_size is int or t.region_size < 1 or not t.regions is Dictionary or not t.identity is Dictionary or t.identity.is_empty(): return false
	for key: Variant in t.regions:
		if not key is Vector2i or not t.regions[key] is Dictionary or not BodyMotion._keys(t.regions[key],["height","control"]): return false
		var r: Dictionary = t.regions[key]
		if not r.height is PackedFloat32Array or not r.control is PackedInt32Array or r.height.size() != t.region_size*t.region_size or r.control.size() != r.height.size(): return false
	return true

static func _op_ok(op: Dictionary) -> bool:
	if not BodyMotion._keys(op,["kind","t0_q","t1_q","a","b","yaw0_udeg","turn_udeg"]): return false
	if not op.kind is String or op.kind not in ["move","pivot","hold"] or not BodyMotion._loco_point(op.a) or not BodyMotion._loco_point(op.b): return false
	for key: String in ["t0_q","t1_q","yaw0_udeg","turn_udeg"]:
		if not BodyMotion._loco_integer(op[key]): return false
	if op.t0_q < 0 or op.t1_q > BodyMotion.LOCOMOTION_Q or op.t1_q <= op.t0_q or op.yaw0_udeg < 0 or op.yaw0_udeg >= BodyMotion.LOCOMOTION_TURN: return false
	if op.kind == "move": return op.a != op.b and op.turn_udeg == 0
	if op.a != op.b: return false
	return op.turn_udeg == 0 if op.kind == "hold" else op.turn_udeg != 0 and op.turn_udeg > -180000000 and op.turn_udeg <= 180000000

static func _valid(packet: Dictionary, identity: String) -> bool:
	if not BodyMotion._keys(packet,["version","placement","terrain","sha256"]) or not packet.version is int or packet.version != 1 or packet.get("sha256") != identity: return false
	if not packet.placement is Dictionary or not packet.terrain is Dictionary: return false
	var plain := packet.duplicate()
	plain.erase("sha256")
	return _digest(plain) == identity and _placement_ok(packet.placement) and _terrain_ok(packet.terrain)

static func _digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(_canonical(value)))
	return hash.finish().hex_encode()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant,b: Variant) -> bool: return str(a)<str(b))
		var out: Dictionary = {}
		for key: Variant in keys: out[key] = _canonical(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(_canonical(item))
		return out
	return value

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

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

static func _reject(reason: String, evidence: Dictionary = {}) -> Dictionary:
	return {"ok":false,"reason":reason,"evidence":evidence,"native_covered":false,"disposition":"ADVERSE" if reason == "terrain_jump" else "UNAVAILABLE"}

static func _neg(a: Array) -> Array:
	return [-a[1],-a[0]]

static func _hull(a: Array, b: Array) -> Array:
	return [minf(a[0],b[0]),maxf(a[1],b[1])]

static func _square(a: Array) -> Array:
	var lo: Array = _interval([a[0],a[0]],[a[0],a[0]],"*")
	var hi: Array = _interval([a[1],a[1]],[a[1],a[1]],"*")
	return [0.0 if a[0] <= 0.0 and a[1] >= 0.0 else maxf(0.0,minf(lo[0],hi[0])),maxf(lo[1],hi[1])]

## The same two divisions, floor, local truncation and clamp as native get_pixel.
## A non-singleton integer image address is unavailable, never a guessed neighbor.
static func _pixel_index_box(t: Dictionary, q: Array) -> Dictionary:
	var out: Array[int] = []
	for coordinate: Array in q:
		var scaled: Array = _interval(coordinate,[float(t.spacing),float(t.spacing)],"/")
		if not _bounded(scaled) or scaled[0] < -2147483647.0 or scaled[1] > 2147483647.0: return _reject("native_index_range",{"scaled":scaled})
		var region: Array = _interval(scaled,[float(t.region_size),float(t.region_size)],"/")
		if floori(region[0]) != floori(region[1]): return _reject("native_region_rounding_cut",{"q":q,"region":region})
		var base: int = floori(region[0])*int(t.region_size)
		if base < -2147483648 or base > 2147483647: return _reject("native_region_index_range",{"base":base})
		var local: Array = _interval(scaled,[float(base),float(base)],"-")
		var lo: int = clampi(int(local[0]),0,int(t.region_size)-1)
		var hi: int = clampi(int(local[1]),0,int(t.region_size)-1)
		if lo != hi: return _reject("native_pixel_rounding_cut",{"q":q,"local":local})
		out.append(base+lo)
	return {"ok":true,"index":Vector2i(out[0],out[1])}

static func _source_pixel_box(t: Dictionary, q: Array) -> Dictionary:
	var address := _pixel_index_box(t,q)
	if not address.ok: return address
	var pixel := _pixel(t,address.index)
	if not pixel.ok: return pixel
	if not is_finite(pixel.height): return _reject("native_nonfinite_height",{"cell":address.index,"word":pixel.height_word})
	if (int(pixel.height_word)&0x7f800000) == 0 and (int(pixel.height_word)&0x007fffff) != 0:
		return _reject("native_subnormal_height_unavailable",{"cell":address.index,"word":pixel.height_word})
	pixel["index"] = address.index
	return pixel

## A point/one-sided branch witness. Exact cuts with nonconstant coordinates stay
## unavailable if address/shortcut rounding cannot select that side uniquely.
static func _sample_enclosure(t: Dictionary, q: Array, velocity: Array, acceleration: Array, side: String) -> Dictionary:
	var pixel := _source_pixel_box(t,q)
	if not pixel.ok: return pixel
	if (pixel.control&4) != 0: return _reject("terrain_hole",{"cell":pixel.index,"fallback_sea":t.sea})
	var step: float = t.spacing
	var scaled: Array = []
	var snapped: Array = []
	for axis in 2:
		var divided: Array = _interval(q[axis],[step,step],"/")
		if not _bounded(divided): return _reject("native_coordinate_range",{"q":q})
		if q[axis][0] == q[axis][1] and q[axis][0] == floor(q[axis][0]/step)*step and (velocity[axis] != [0.0,0.0] or acceleration[axis] != [0.0,0.0]):
			return _reject("native_cell_side_unresolved",{"q":q,"velocity":velocity,"acceleration":acceleration,"side":side})
		scaled.append(divided)
		var round_cell: Array = _interval(divided,[.5,.5],"+")
		var first: int = floori(round_cell[0])
		var last: int = floori(round_cell[1])
		if last-first > 1: return _reject("native_coordinate_box_too_wide",{"q":q,"snap_cells":[first,last]})
		var candidates: Array = []
		for index: int in range(first,last+1): candidates.append(_interval([float(index),float(index)],[step,step],"*"))
		snapped.append(candidates)
	var radius: Array = [INF,-INF]
	for sx: Array in snapped[0]:
		for sz: Array in snapped[1]:
			var squared: Array = _interval(_square(_interval(q[0],sx,"-")),_square(_interval(q[1],sz,"-")),"+")
			radius = _hull(radius,squared)
	if not _bounded(radius): return _reject("native_radius_range",{"q":q,"radius":radius})
	var value: Array
	var gradient: Array
	var branch: String
	if radius[1] < SHORTCUT_SQUARED:
		value = [pixel.height,pixel.height]
		gradient = [[0.0,0.0],[0.0,0.0]]
		branch = "vertex_shortcut"
	elif radius[0] >= SHORTCUT_SQUARED:
		var cell: Array[int] = []
		for axis in 2:
			if floori(scaled[axis][0]) != floori(scaled[axis][1]): return _reject("native_bilinear_cell_cut",{"q":q,"scaled":scaled})
			cell.append(floori(scaled[axis][0]))
		var base: Array = [_interval([float(cell[0]),float(cell[0])],[step,step],"*"),_interval([float(cell[1]),float(cell[1])],[step,step],"*")]
		var end: Array = [_interval(base[0],[step,step],"+"),_interval(base[1],[step,step],"+")]
		var corners: Array = []
		for i in 4:
			var at: Array = [base[0] if i < 2 else end[0],base[1] if i%2 == 0 else end[1]]
			var corner := _source_pixel_box(t,at)
			if not corner.ok: return corner
			corners.append([corner.height,corner.height])
		var dx: Array = _interval(end[0],base[0],"-")
		var dz: Array = _interval(end[1],base[1],"-")
		if dx[0] <= 0.0 or dz[0] <= 0.0: return _reject("native_cell_width",{"dx":dx,"dz":dz})
		var x0: Array = _interval(end[0],q[0],"-")
		var x1: Array = _interval(q[0],base[0],"-")
		var z0: Array = _interval(end[1],q[1],"-")
		var z1: Array = _interval(q[1],base[1],"-")
		var total: Array = [0.0,0.0]
		for i in 4:
			var term: Array = _interval(_interval(corners[i],x0 if i < 2 else x1,"*"),z0 if i%2 == 0 else z1,"*")
			total = term if i == 0 else _interval(total,term,"+")
		var area: Array = _interval(dx,dz,"*")
		value = _interval(total,area,"/")
		gradient = [_interval(_interval(_interval(_interval(corners[2],corners[0],"-"),z0,"*"),_interval(_interval(corners[3],corners[1],"-"),z1,"*"),"+"),area,"/"),
			_interval(_interval(_interval(_interval(corners[1],corners[0],"-"),x0,"*"),_interval(_interval(corners[3],corners[2],"-"),x1,"*"),"+"),area,"/")]
		branch = "bilinear"
	else:
		return _reject("native_shortcut_rounding_cut",{"q":q,"radius":radius,"threshold":SHORTCUT_SQUARED})
	var derivative: Array = _interval(_interval(gradient[0],velocity[0],"*"),_interval(gradient[1],velocity[1],"*"),"+")
	var sea: float = t.sea
	if value[1] < sea: derivative = [0.0,0.0]
	elif value[0] <= sea:
		if value == [sea,sea]: derivative = [minf(0.0,derivative[0]),minf(0.0,derivative[1])] if side == "left" else [maxf(0.0,derivative[0]),maxf(0.0,derivative[1])]
		else: derivative = _hull(derivative,[0.0,0.0])
	return {"ok":true,"value":[maxf(value[0],sea),maxf(value[1],sea)],"raw":value,"derivative":derivative,"gradient":gradient,"branch":branch,"cell":pixel.index,"q":q}

static func _matrix_values(at: Transform3D) -> Array:
	var values: Array = []
	for row in 3:
		for column in 3: values.append(float(at.basis[column][row]))
		values.append(float(at.origin[row]))
	return values

static func _matrix_enclosure(left: Array, right: Transform3D) -> Array:
	var a: Array = _matrix_values(right)
	var result: Array = []
	for row in 3:
		for column in 4:
			var total: Array = [0.0,0.0]
			for k in 3: total = _interval(total,_interval(left[row*4+k],[a[k*4+column],a[k*4+column]],"*"),"+")
			result.append(_interval(total,left[row*4+3],"+") if column == 3 else total)
	return result

## Real trig/curve boxes and the EXACT copied-input native footprint value are
## united before source-branch selection. This reuses placement's primitives;
## it does not infer a global sin/cos error allowance from test observations.
static func _enclose(packet: Dictionary, query: Dictionary) -> Dictionary:
	var p: Dictionary = packet.placement
	var t: Dictionary = packet.terrain
	var origin: Vector2 = query.origin
	var velocity: Vector2 = query.origin_S
	var yaw: float = query.yaw
	var rate: float = query.yaw_S
	var origin_box: Array = query.get("origin_box",[[float(origin.x),float(origin.x)],[float(origin.y),float(origin.y)]])
	var velocity_box: Array = query.get("velocity_box",[[float(velocity.x),float(velocity.x)],[float(velocity.y),float(velocity.y)]])
	var angle_box: Array = query.get("angle_box",[yaw,yaw])
	var rate_box: Array = query.get("rate_box",[rate,rate])
	var c: Array = _trig_interval(angle_box,true)
	var s: Array = _trig_interval(angle_box,false)
	var source_origin: Vector2 = query.native_origin
	var native_offsets: PackedVector2Array = Map3DUnits.footprint(p.extent,query.native_yaw,p.k,p.ring)
	var frozen_offsets: PackedVector2Array = Map3DUnits.footprint(p.extent,0.0,p.k,p.ring)
	var locals: Array = [[[0.0,0.0],[0.0,0.0]]]
	for share: float in [.5,1.0]:
		for i: int in p.ring:
			var angle: Array = _interval(_interval([TAU,_next64(TAU,1)],[float(i),float(i)],"*",64),[float(p.ring),float(p.ring)],"/",64)
			locals.append([_interval(_interval(_trig_interval(angle,true),[float(p.extent.x),float(p.extent.x)],"*"),[share*float(p.k),share*float(p.k)],"*"),
				_interval(_interval(_trig_interval(angle,false),[float(p.extent.y),float(p.extent.y)],"*"),[share*float(p.k),share*float(p.k)],"*")])
	var samples: Array = []
	var maximum: Array = [-INF,-INF]
	for i in locals.size():
		var local: Array = locals[i]
		for axis in 2: local[axis] = _hull(local[axis],[float(frozen_offsets[i][axis]),float(frozen_offsets[i][axis])])
		var offset: Array = [_interval(_interval(local[0],c,"*"),_interval(local[1],s,"*"),"+"),_interval(_interval(local[1],c,"*"),_interval(local[0],s,"*"),"-")]
		var native_point: Vector2 = source_origin+native_offsets[i]
		var q: Array = [_hull(_interval(origin_box[0],offset[0],"+"),[float(native_point.x),float(native_point.x)]),_hull(_interval(origin_box[1],offset[1],"+"),[float(native_point.y),float(native_point.y)])]
		var v: Array = [_interval(velocity_box[0],_interval(rate_box,offset[1],"*"),"+"),_interval(velocity_box[1],_interval(rate_box,offset[0],"*"),"-")]
		var acceleration: Array = [_neg(_interval(offset[0],_square(rate_box),"*")),_neg(_interval(offset[1],_square(rate_box),"*"))]
		var sample := _sample_enclosure(t,q,v,acceleration,query.get("side","right"))
		if not sample.ok: return {"status":"UNAVAILABLE","reason":sample.reason,"evidence":sample.evidence,"sample":i}
		samples.append(sample)
		maximum = [maxf(maximum[0],sample.value[0]),maxf(maximum[1],sample.value[1])]
	var derivative: Array = [INF,-INF]
	var possible: Array[int] = []
	for i in samples.size():
		if samples[i].value[1] >= maximum[0]:
			possible.append(i)
			derivative = _hull(derivative,samples[i].derivative)
	var clear: Array = _interval(_interval([float(p.height),float(p.height)],[float(p.k),float(p.k)],"*",64),[float(p.clear),float(p.clear)],"*",64)
	var y: Array = _interval(_interval(maximum,clear,"+",64),[float(p.sink),float(p.sink)],"-",64)
	var ck: Array = _interval(c,[float(p.k),float(p.k)],"*")
	var sk: Array = _interval(s,[float(p.k),float(p.k)],"*")
	var zero: Array = [0.0,0.0]
	var pm: Array = [ck,zero,sk,_hull(origin_box[0],[float(source_origin.x),float(source_origin.x)]),zero,[float(p.k),float(p.k)],zero,y,_neg(sk),zero,ck,_hull(origin_box[1],[float(source_origin.y),float(source_origin.y)])]
	# Native axis-angle construction is itself reused at the exact copied inputs.
	for native_angle: float in [yaw,query.native_yaw]:
		var native_basis := Transform3D(Basis(Vector3.UP,native_angle).scaled(Vector3.ONE*float(p.k)),Vector3.ZERO)
		var native_values: Array = _matrix_values(native_basis)
		for row in 3:
			for column in 3: pm[row*4+column] = _hull(pm[row*4+column],[native_values[row*4+column],native_values[row*4+column]])
	var ds: Array = _interval(sk,rate_box,"*")
	var dc: Array = _interval(ck,rate_box,"*")
	var ps: Array = [_neg(ds),zero,dc,velocity_box[0],zero,zero,zero,derivative,_neg(dc),zero,_neg(ds),velocity_box[1]]
	var result: Dictionary = {"status":"ENCLOSED_CONTROL","H":_matrix_enclosure(pm,p.ancestor),"H_S":_matrix_enclosure(ps,p.ancestor),"samples":samples,"possible_active_samples":possible,"derivative_bottom_row":[0,0,0,0]}
	for field: String in ["H","H_S"]:
		for bound: Array in result[field]:
			if not _bounded(bound): return {"status":"UNAVAILABLE","reason":"native_matrix_range","evidence":{"field":field,"bound":bound}}
	return result
