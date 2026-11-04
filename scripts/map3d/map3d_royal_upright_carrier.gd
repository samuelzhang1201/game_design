class_name Map3DRoyalUprightCarrier
extends RefCounted
## Accepted239 §3: detached ordinary upright carrier, never placement or contact policy.
## extract is the IO boundary; prepare/evaluate/sample read copied values only.
## The analytic extension is NOT a native arithmetic/physical certificate.

const METHOD: String = "Terrain3DData::get_height/v1.0.2-stable/0077405b52e353c5e5dc3a094e7ede49833ba6fe"
const SHORTCUT_SQUARED: float = 0.00009999999747378752 # source's binary32 0.0001f
# Verified against official release archive a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2.
const _PROFILE: Dictionary = {
	"libterrain.macos.debug":"12b4822ef56fb4396da974f4efcb2db26fa2d9c93179d353bd30ba647cc28b01",
	"libterrain.macos.release":"63449d6de24051669ea81464b1b6b2ae3dc0d72408845bec60b394867ed9b62a",
	"libterrain.linux.debug.x86_64.so":"178ae39467bb0743c1bbdf854a00f8e7d258a3691bcc1b63d4493beb6bde865e",
	"libterrain.linux.release.x86_64.so":"e79ebb2e48a63a5d6189a825f1d63ec847319dc8fa030936d95bf6fad8f294ef"}

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
			"reference": reference, "view_size": ctx.view_size, "meta": ctx.meta.duplicate(true),
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
		terrain.identity["method_bound"] = not binaries.is_empty()
		for path: String in binaries:
			terrain.identity.method_bound = terrain.identity.method_bound and _PROFILE.get(path.get_file(),"") == binaries[path]
		if not terrain.identity.method_bound: terrain.identity.method = "UNAVAILABLE_UNKNOWN_NATIVE_BINARY"
		terrain.identity["engine_binary"] = FileAccess.get_sha256(OS.get_executable_path())
	# No stored path, version string or sparse native agreement proves all arithmetic branches.
	terrain.identity["native_arithmetic"] = "UNAVAILABLE: footprint/yaw/ancestor-matrix enclosure not established; raw height operation enclosure is separate"
	return prepare(placement,terrain)

static func sample(packet: Dictionary, op: Dictionary, u: Variant, side: String, identity: String) -> Dictionary:
	if not _number(u) or u < 0.0 or u > 1.0 or not _op_ok(op): return _reject("operation")
	if not _valid(packet,identity): return _reject("stale_packet")
	var p: Dictionary = packet.placement
	var d: float = float(op.t1_q-op.t0_q)/BodyMotion.LOCOMOTION_Q
	var delta := Vector2(float(op.b[0]-op.a[0]),float(op.b[1]-op.a[1]))
	var position := Vector2(float(op.a[0])+delta.x*float(u),float(op.a[1])+delta.y*float(u))
	var yaw: float = -PI/2.0-(float(op.yaw0_udeg)+float(op.turn_udeg)*float(u))*PI/180000000.0
	var result := evaluate(packet,p.origin+position*float(p.alpha),delta*(float(p.alpha)/d),yaw,
		-float(op.turn_udeg)*PI/180000000.0/d,side,identity)
	if result.ok:
		result["operation_sha256"] = _digest(BodyMotion._loco_op(op.kind,int(op.t0_q),int(op.t1_q),
			[int(op.a[0]),int(op.a[1])],[int(op.b[0]),int(op.b[1])],int(op.yaw0_udeg),int(op.turn_udeg)))
	return result

## O and O_S are world XZ, yaw_S is per shared S, not per normalized u or seconds.
static func evaluate(packet: Dictionary, origin: Variant, origin_S: Variant, yaw: Variant,
		yaw_S: Variant, side: String, identity: String) -> Dictionary:
	if not _valid(packet,identity): return _reject("stale_packet")
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
		samples.append(h)
	var derivative: float = INF if side == "left" else -INF
	var active: Array[int] = []
	for i in samples.size():
		if samples[i].value == maximum:
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
	return {"ok":true,"H":H,"H_S":H_S,"samples":samples,"active_samples":active,"yaw_S":yaw_S,
		"identity":identity,"side":side,"native_covered":false,"carrier_status":"ANALYTIC_EXTENSION_ONLY",
		"domain":domain(packet),"native_rounding":{"status":"UNAVAILABLE","reason":t.identity.get("native_arithmetic","proof_domain_control")},
		"physical_allowance":{"status":"NOT_SELECTED"}}

## A complete implicit partition: no sampled atlas can erase unvisited headings or land.
static func domain(packet: Dictionary) -> Dictionary:
	return {"operations":["move","pivot","hold"],"heading_udeg":[0,359999999],
		"turn_udeg":[-179999999,180000000],"duration_q":[1,BodyMotion.LOCOMOTION_Q],"u":[0.0,1.0],
		"placement":"all admitted measured-circle land/bounds operations; every footprint curve",
		"regions":packet.terrain.regions.keys(),"outside_regions":"UNAVAILABLE_MISSING_DATA",
		"partition":["bilinear cells","vertex-shortcut disks","pixel cuts","sea cuts","holes","missing maps","overrides"],
		"native_status":"UNAVAILABLE_PLACEMENT_ARITHMETIC" if packet.terrain.kind == "native" else "PROOF_DOMAIN_CONTROL",
		"whole_skin_and_rendered_LOD":"UNAVAILABLE_PHYSICAL_AUTHORITY"}

static func _height(t: Dictionary, q: Vector2, v: Vector2, a: Vector2, side: int) -> Dictionary:
	var at := _branch(t,q,Vector2.ZERO,Vector2.ZERO,0)
	if not at.ok: return at
	var limit := _branch(t,q,v,a,side)
	if not limit.ok: return limit
	if maxf(at.value,float(t.sea)) != maxf(limit.value,float(t.sea)):
		return _reject("terrain_jump", {"value":at.value,"limit":limit.value,"actual":at,"side":limit})
	var raw: float = at.value
	var d: float = limit.gradient.dot(v)
	var sea: float = t.sea
	var selected := "raw" if raw > sea else "sea"
	if raw < sea: d = 0.0
	elif raw == sea:
		d = minf(d,0.0) if side < 0 else maxf(d,0.0)
		selected = "sea_tie"
	return {"ok":true,"value":maxf(raw,sea),"raw":raw,"derivative":d,"branch":limit.branch,
		"cell":limit.cell,"sea_branch":selected,"gradient":limit.gradient,"raw_enclosure":at.raw_enclosure}

static func _branch(t: Dictionary, q: Vector2, v: Vector2, a: Vector2, side: int) -> Dictionary:
	var step: float = t.spacing
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
		if not is_finite(pixel.height): return _reject("terrain_nan",{"fallback_sea":t.sea,"cell":index})
		return {"ok":true,"value":pixel.height,"gradient":Vector2.ZERO,"branch":"vertex_shortcut","cell":index,"raw_enclosure":[pixel.height,pixel.height]}
	var values: Array[float] = []
	for offset: Vector2i in [Vector2i.ZERO,Vector2i(0,1),Vector2i(1,0),Vector2i.ONE]:
		var corner := _pixel(t,index+offset)
		if not corner.ok: return corner
		if not is_finite(corner.height): return _reject("terrain_nan",{"fallback_sea":t.sea,"cell":index+offset})
		values.append(corner.height)
	var x: float = (float(q.x)-float(index.x)*step)/step
	var z: float = (float(q.y)-float(index.y)*step)/step
	var h: float = values[0]+(values[2]-values[0])*x+(values[1]-values[0])*z+(values[3]-values[2]-values[1]+values[0])*x*z
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

static func _interval(a: Array, b: Array, op: String) -> Array:
	var values: Array[float] = []
	for x: float in a:
		for y: float in b:
			match op:
				"+": values.append(x+y)
				"-": values.append(x-y)
				"*": values.append(x*y)
				"/":
					if b[0] <= 0 and b[1] >= 0: return [-INF,INF]
					values.append(x/y)
	return [_next32(float(values.min()),-1),_next32(float(values.max()),1)]

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
	return {"ok":true,"height":float(t.regions[region].height[offset]),"control":control}

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
		"Linux": return ["res://addons/terrain_3d/bin/libterrain.linux.debug.x86_64.so", "res://addons/terrain_3d/bin/libterrain.linux.release.x86_64.so"]
	return []

static func _reject(reason: String, evidence: Dictionary = {}) -> Dictionary:
	return {"ok":false,"reason":reason,"evidence":evidence,"native_covered":false}
