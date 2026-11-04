class_name Map3DRoyalUprightCarrier
extends RefCounted
## Accepted239 §3: detached ordinary upright carrier, never placement or contact policy.
## extract is the IO boundary; prepare/evaluate/sample read copied values only.
## Native values and real one-sided extension derivatives have separate bounds.
## This is not a physical contact certificate or an error-budget decision.

const Source = preload("res://scripts/map3d/map3d_royal_carrier_source.gd")
const Bounds = preload("res://scripts/map3d/map3d_royal_carrier_bounds.gd")
const METHOD: String = Source.METHOD


static func prepare(placement: Dictionary, terrain: Dictionary) -> Dictionary:
	if not _placement_ok(placement) or not _terrain_ok(terrain): return Bounds._reject("packet_schema")
	var packet := {"version": 1, "placement": placement.duplicate(true), "terrain": terrain.duplicate(true)}
	packet["sha256"] = _digest(packet)
	return {"ok": true, "packet": packet}


## Source IO is separate from the pure copied carrier.
static func extract(ctx: Map3DContext, child: Dictionary, model_root: Node3D) -> Dictionary:
	var captured := Source.extract(ctx,child,model_root)
	if not captured.ok: return captured
	captured.placement.identity["admission"] = _domain_source(ctx.repo)
	return prepare(captured.placement,captured.terrain)


static func sample(packet: Dictionary, op: Dictionary, u: Variant, side: String, identity: String) -> Dictionary:
	if not Bounds._number(u) or u < 0.0 or u > 1.0 or not _op_ok(op): return Bounds._reject("operation")
	if not _valid(packet,identity): return Bounds._reject("stale_packet")
	var p: Dictionary = packet.placement
	var operation_sha: String = _digest(BodyMotion._loco_op(op.kind,int(op.t0_q),int(op.t1_q),
		[int(op.a[0]),int(op.a[1])],[int(op.b[0]),int(op.b[1])],int(op.yaw0_udeg),int(op.turn_udeg)))
	var request: Dictionary = {"packet_sha256":identity,"operation_sha256":operation_sha,"u":u,"side":side}
	var admission := _admission(packet,op)
	if packet.terrain.kind == "native" and not admission.ok:
		admission["request"] = request
		return admission
	var d: float = float(op.t1_q-op.t0_q)/BodyMotion.LOCOMOTION_Q
	var ds: Array = Bounds._interval([float(op.t1_q-op.t0_q),float(op.t1_q-op.t0_q)],[float(BodyMotion.LOCOMOTION_Q),float(BodyMotion.LOCOMOTION_Q)],"/",64)
	var alpha: Array = [float(p.alpha),float(p.alpha)]
	if p.identity.has("metres_per_pack_px"):
		alpha = Bounds._hull(alpha,Bounds._interval([float(p.identity.meta.m_per_px),float(p.identity.meta.m_per_px)],
			[float(p.identity.metres_per_pack_px),float(p.identity.metres_per_pack_px)],"/",64))
	var coordinates: Array[float] = []
	var origin_box: Array = []
	var velocity_box: Array = []
	var velocity: Array[float] = []
	for axis in 2:
		var a: float = float(op.a[axis])
		var delta: float = float(int(op.b[axis])-int(op.a[axis]))
		coordinates.append(a if u == 0.0 else (float(op.b[axis]) if u == 1.0 else a+delta*float(u)))
		var position: Array = [coordinates[axis],coordinates[axis]] if u == 0.0 or u == 1.0 else Bounds._interval([a,a],Bounds._interval([delta,delta],[float(u),float(u)],"*",64),"+",64)
		origin_box.append(Bounds._interval([float(p.origin[axis]),float(p.origin[axis])],Bounds._interval(position,alpha,"*",64),"+",64))
		velocity_box.append(Bounds._interval(Bounds._interval([delta,delta],alpha,"*",64),ds,"/",64))
		velocity.append(delta*float(p.alpha)/d)
	var heading: float = float(op.yaw0_udeg)+float(op.turn_udeg)*float(u)
	var heading_box: Array = Bounds._interval([float(op.yaw0_udeg),float(op.yaw0_udeg)],Bounds._interval([float(op.turn_udeg),float(op.turn_udeg)],[float(u),float(u)],"*",64),"+",64)
	var radians: Array = Bounds._interval([PI,Bounds._next64(PI,1)],[180000000.0,180000000.0],"/",64)
	var angle_box: Array = Bounds._neg(Bounds._interval(Bounds._interval([PI,Bounds._next64(PI,1)],[2.0,2.0],"/",64),Bounds._interval(heading_box,radians,"*",64),"+",64))
	var rate_box: Array = Bounds._neg(Bounds._interval(Bounds._interval([float(op.turn_udeg),float(op.turn_udeg)],radians,"*",64),ds,"/",64))
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
	if not _valid(packet,identity): return Bounds._reject("stale_packet")
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
		or not Bounds._number(yaw) or not Bounds._number(yaw_S) or side not in ["left","right"]: return Bounds._reject("query")
	var p: Dictionary = packet.placement
	var t: Dictionary = packet.terrain
	if t.kind == "override": return Bounds._reject("height_override_unproved", {"identity":t.identity})
	if t.kind == "missing": return Bounds._reject("terrain_missing", {"fallback_sea":t.sea})
	if t.kind == "native" and not t.identity.get("method_bound",false): return Bounds._reject("native_height_method_unproved",{"identity":t.identity})
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
		return Bounds._reject("native_side_jump_unresolved" if t.kind == "native" else "terrain_jump",{"value":maximum,"limit":side_maximum,"samples":samples,"side":side,"query":query})
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
	if not H.is_finite() or not H_S.basis.is_finite() or not H_S.origin.is_finite(): return Bounds._reject("carrier_numeric_range",{"yaw_S":yaw_S})
	query["side"] = side
	var enclosures := Bounds._enclose(packet,query)
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
	for path: String in Source._SOURCES:
		var script: GDScript = load(path) as GDScript
		if script == null or FileAccess.get_sha256(path) != Source._SOURCES[path] or script.source_code.sha256_text() != Source._SOURCES[path]:
			return {"status":"UNAVAILABLE","reason":"domain_source_changed","path":path}
	var self_path: String = "res://scripts/map3d/map3d_royal_upright_carrier.gd"
	var code_sources: Dictionary = {}
	for path: String in [self_path,"res://scripts/map3d/map3d_royal_carrier_source.gd","res://scripts/map3d/map3d_royal_carrier_bounds.gd"]:
		var script: GDScript = load(path) as GDScript
		var sha: String = FileAccess.get_sha256(path)
		if script == null or script.source_code.sha256_text() != sha: return {"status":"UNAVAILABLE","reason":"stale_classifier","path":path}
		code_sources[path] = sha
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
		"sources":Source._SOURCES.duplicate(),"classifier_sha256":code_sources[self_path],"classifier_sources":code_sources,
		"configuration":{"army_march_grid_px":repo.bal("army_march_grid_px"),"army_max_slope":repo.bal("army_max_slope"),"footprint":repo.unit_footprints.royal.duplicate(true)},
		"predicate":"BodyMotion._loco_grid_ok AND ArmySystem._body_path_terrain([a,b],radius_m)==empty"}


static func _admission(packet: Dictionary, op: Dictionary) -> Dictionary:
	var receipt: Dictionary = packet.placement.identity.get("admission",{})
	if receipt.get("status") != "BOUND_GEOMETRIC_SUPERSET": return Bounds._reject("domain_unavailable",{"receipt":receipt})
	var copied: Dictionary = receipt.grid
	var grid := MarchPath.new()
	for key: String in ["cols","rows","cell_m","closed","water","water_open"]: grid.set(key,copied[key])
	if not BodyMotion._loco_grid_ok(grid): return Bounds._reject("domain_grid_invalid")
	var error: String = ArmySystem._body_path_terrain(grid,[op.a,op.b],int(receipt.radius_m))
	if not error.is_empty(): return Bounds._reject("outside_admitted_terrain",{"reason":error,"operation":op.duplicate(true),"radius_m":receipt.radius_m,"grid_sha256":receipt.grid_sha256})
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
		return Bounds._reject("native_index_range",{"q":q,"spacing":step})
	var index := Vector2i(_coordinate(q.x,step,v.x,a.x,side),_coordinate(q.y,step,v.y,a.y,side))
	var pixel := Bounds._pixel(t,index)
	if not pixel.ok: return pixel
	if (int(pixel.control)&4) != 0: return Bounds._reject("terrain_hole",{"fallback_sea":t.sea,"cell":index})
	var snapped := Vector2(floor(q.x/step+.5)*step,floor(q.y/step+.5)*step)
	var delta: Vector2 = q-snapped
	var radius: float = float(delta.x)*delta.x+float(delta.y)*delta.y
	var shortcut: bool = radius < Bounds.SHORTCUT_SQUARED
	if radius == Bounds.SHORTCUT_SQUARED and side != 0:
		var first: float = 2.0*delta.dot(v)*side
		var second: float = v.dot(v)+delta.dot(a)
		if first == 0.0 and second == 0.0: return Bounds._reject("shortcut_tangent_unproved",{"q":q})
		shortcut = first < 0.0 or (first == 0.0 and second < 0.0)
	if shortcut:
		if not is_finite(pixel.height): return Bounds._reject("terrain_nan" if is_nan(pixel.height) else "terrain_infinite",{"fallback_sea":t.sea,"cell":index,"word":pixel.height_word})
		return {"ok":true,"value":pixel.height,"gradient":Vector2.ZERO,"branch":"vertex_shortcut","cell":index,"raw_enclosure":[pixel.height,pixel.height]}
	var values: Array[float] = []
	for offset: Vector2i in [Vector2i.ZERO,Vector2i(0,1),Vector2i(1,0),Vector2i.ONE]:
		var corner := Bounds._pixel(t,index+offset)
		if not corner.ok: return corner
		if not is_finite(corner.height): return Bounds._reject("terrain_nan" if is_nan(corner.height) else "terrain_infinite",{"fallback_sea":t.sea,"cell":index+offset,"word":corner.height_word})
		values.append(corner.height)
	var x: float = (float(q.x)-float(index.x)*step)/step
	var z: float = (float(q.y)-float(index.y)*step)/step
	# Shared edges reduce to identical endpoint interpolation on both sides.
	var row0: float = values[0] if x == 0.0 else (values[2] if x == 1.0 else values[0]+(values[2]-values[0])*x)
	var row1: float = values[1] if x == 0.0 else (values[3] if x == 1.0 else values[1]+(values[3]-values[1])*x)
	var h: float = row0 if z == 0.0 else (row1 if z == 1.0 else row0+(row1-row0)*z)
	var gradient := Vector2(((values[2]-values[0])*(1-z)+(values[3]-values[1])*z)/step,
		((values[1]-values[0])*(1-x)+(values[3]-values[2])*x)/step)
	return {"ok":true,"value":h,"gradient":gradient,"branch":"bilinear","cell":index,"raw_enclosure":Bounds._height_enclosure(values,q,index,step)}


static func _coordinate(q: float, step: float, v: float, a: float, side: int) -> int:
	var cell: int = floori(q/step)
	if q == float(cell)*step and side != 0 and (v*side < 0.0 or (v == 0.0 and a < 0.0)): cell -= 1
	return cell


static func _placement_ok(p: Dictionary) -> bool:
	if not BodyMotion._keys(p,["origin","alpha","k","extent","height","clear","sink","ring","ancestor","identity"]): return false
	if not p.origin is Vector2 or not p.origin.is_finite() or not p.extent is Vector2 or not p.extent.is_finite() or p.extent.x < 0 or p.extent.y < 0: return false
	for key: String in ["alpha","k","height","clear","sink"]:
		if not Bounds._number(p[key]): return false
	if p.alpha <= 0 or p.k <= 0 or p.height <= 0 or not p.ring is int or p.ring < 1: return false
	return p.ancestor is Transform3D and p.ancestor.is_finite() and p.ancestor.basis.determinant() != 0.0 and p.identity is Dictionary and not p.identity.is_empty()


static func _terrain_ok(t: Dictionary) -> bool:
	if not BodyMotion._keys(t,["kind","spacing","sea","region_size","regions","identity"]): return false
	if t.kind not in ["native","control","missing","override"] or not Bounds._number(t.spacing) or t.spacing <= .02 or not Bounds._number(t.sea): return false
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
