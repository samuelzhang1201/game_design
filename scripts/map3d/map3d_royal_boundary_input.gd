class_name Map3DRoyalBoundaryInput
extends RefCounted
## Accepted239 §§4–5: detached constraints, never a provider or motion/contact PASS.
## Admissions are trusted public projections supplied by the caller, not signatures.
## Each projection carries a COMPLETE accepted BodyMotion saved receipt and its carrier.

const Phase = preload("res://scripts/map3d/map3d_royal_reference_phase.gd")
const Jets = preload("res://scripts/map3d/map3d_royal_native_jets.gd")
const Math = preload("res://scripts/map3d/map3d_royal_jet_math.gd")
const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const Carrier = preload("res://scripts/map3d/map3d_royal_upright_carrier.gd")
const Bounds = preload("res://scripts/map3d/map3d_royal_carrier_bounds.gd")
const VERSION: String = "royal-boundary-input/1"
var _jets: Map3DRoyalNativeJets
var _source: Dictionary
var _config: Dictionary
var _law: Dictionary
var _identity: Dictionary
var _material_points: Array = []


static func prepare(source: Variant, identity: Variant, arithmetic: Variant, config: Variant) -> Dictionary:
	var native: Dictionary = Jets.prepare(source,identity,arithmetic)
	if not native.ok: return _reject("native_component",native.get("diagnostics",{}))
	var copied_sha: String = Source._source_digest(native.authority._source)
	if copied_sha != source.sha256: return _reject("native_component_copy_mismatch",{"expected":source.sha256,"actual":copied_sha})
	var contact: Dictionary = _contact_points(source)
	if not contact.ok: return contact
	var phase_source := {"length":source.animation.length,"identity":identity.duplicate(true)}
	var law: Dictionary = Phase.law(phase_source,config)
	if not law.ok: return _reject("phase_component",law)
	var authority := Map3DRoyalBoundaryInput.new()
	authority._jets = native.authority
	authority._material_points = contact.points
	authority._source = phase_source
	authority._config = config.duplicate(true)
	authority._law = law
	authority._identity = {"version":VERSION,"source":identity.duplicate(true),"law":law.sha256,
		"jets":native.domain.sha256,"arithmetic":arithmetic.receipt.sha256,"material_points":BodyMotion._hash(contact.points)}
	return {"ok":true,"authority":authority,"identity":authority._identity.duplicate(true),"activation_pass":false}


static func _contact_points(source: Dictionary) -> Dictionary:
	var points: Array = []
	var seen: Dictionary = {}
	for hoof: String in source.calibration.sole_patches:
		var patch: Dictionary = source.calibration.sole_patches[hoof]
		var surface: Variant = patch.get("surface")
		var vertices: Variant = patch.get("vertices")
		if not Phase._natural(surface) or surface >= source.surfaces.size() or not (vertices is Array or vertices is PackedInt32Array) or vertices.is_empty(): return _reject("contact_material_schema")
		for vertex: Variant in vertices:
			if not Phase._natural(vertex) or vertex >= source.surfaces[int(surface)].arrays[Mesh.ARRAY_VERTEX].size(): return _reject("contact_material_schema")
			var key: String = str(int(surface))+":"+str(int(vertex))
			if not seen.has(key):
				seen[key] = points.size()
				points.append({"surface":int(surface),"vertex":int(vertex),"patches":[]})
			if not points[seen[key]].patches.has(hoof): points[seen[key]].patches.append(hoof)
	for point: Dictionary in points: point.patches.sort()
	points.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.surface < b.surface or (a.surface == b.surface and a.vertex < b.vertex))
	return {"ok":true,"points":points}


## request={unit,slot,receipt,op_index,initial_native_phase,identity,shared:{entry,exit}}.
## projection={saved,admission:{unit,slot,receipt,piece,substep_count,classification,identity,future_authorized},carrier}.
## Empty expected shared records build a fresh packet; supplied records MUST match recomputation.
func build(projections: Variant, request: Variant) -> Dictionary:
	if not request is Dictionary or not BodyMotion._keys(request,["unit","slot","receipt","op_index","initial_native_phase","identity","shared"]): return _reject("request_schema")
	if not Phase.phase_seed(request.unit,request.slot).ok or not Phase._natural(request.op_index) or not request.receipt is String or not BodyMotion._digest(request.receipt): return _reject("request_identity")
	if not request.identity is Dictionary or not Phase._identity_json(request.identity) or BodyMotion._hash(request.identity) != BodyMotion._hash(_identity): return _reject("stale_component_identity")
	if not _acyclic(request.shared) or not request.shared is Dictionary or not BodyMotion._keys(request.shared,["entry","exit"]): return _reject("shared_boundary_mismatch")
	for end: String in ["entry","exit"]:
		if not request.shared[end] is Dictionary: return _reject("shared_boundary_mismatch")
	var copied: Dictionary = _operations(projections,request)
	if not copied.ok: return copied
	var rows: Array = copied.rows
	var index: int = -1
	for i: int in rows.size():
		if rows[i].binding.receipt == request.receipt and rows[i].binding.op_index == request.op_index: index = i
	if index < 0: return _reject("unadmitted_operation")
	var current: Dictionary = rows[index]
	if current.binding.classification == "endpoint_only": return _reject("endpoint_only")
	if current.binding.op.kind != "pivot": return _reject("current_not_pivot")
	if index == 0 or index == rows.size()-1: return _reject("UNAVAILABLE_NEIGHBOR")
	for pair: Array in [[rows[index-1],current],[current,rows[index+1]]]:
		if not Phase._adjacent(pair[0].binding,pair[1].binding): return _reject("UNAVAILABLE_NEIGHBOR",{"left":pair[0].binding,"right":pair[1].binding})
	var packet := {"version":VERSION,"identity":_identity.duplicate(true),"binding":current.binding.duplicate(true),
		"entry":{},"exit":{},"classification":"production_bound","motion_join_claim":false,
		"domain":{"native":_jets.domain(),"phase_pair":[[0.0,1.0],[0.0,1.0]],"production_phase_pair":"receipt-bound; independent torus retained for proof",
		"heading_udeg":[0,359999999],"turn_udeg":[-179999999,180000000],"duration_q":[1,BodyMotion.LOCOMOTION_Q]},
		"representation":{"status":"REQUIRES_PULLBACK_AND_PROVIDER_PROOF","scope":"world/local endpoint constraints only; no whole-pivot chart claim"},"activation_pass":false}
	for end: String in ["entry","exit"]:
		var left: Dictionary = rows[index-1] if end == "entry" else current
		var right: Dictionary = current if end == "entry" else rows[index+1]
		var shared: Dictionary = _shared(left,right,request.initial_native_phase if end == "entry" else null)
		if not shared.ok: return shared
		if not request.shared[end].is_empty() and Carrier._digest(request.shared[end]) != Carrier._digest(shared.record): return _reject("shared_boundary_mismatch",{"end":end})
		var side: Dictionary = shared.record.right if end == "entry" else shared.record.left
		var constraints: Dictionary = _constraints(side,shared.record.target)
		if not constraints.ok: return constraints
		packet[end] = {"shared":shared.record,"constraints":constraints}
		if shared.record.classification != "production_bound": packet.classification = "proof_domain_control"
	packet["sha256"] = Carrier._digest(packet)
	return {"ok":true,"prepared":packet,"activation_pass":false}


func _operations(projections: Variant, request: Dictionary) -> Dictionary:
	if not _acyclic(projections) or not projections is Array or projections.is_empty(): return _reject("projection_schema")
	var rows: Array = []
	var receipts: Dictionary = {}
	for p: Variant in projections:
		if not p is Dictionary or not BodyMotion._keys(p,["saved","admission","carrier"]) or not p.admission is Dictionary or not p.carrier is Dictionary: return _reject("projection_schema")
		var saved: Variant = p.saved
		if not BodyMotion._loco_saved_ok(saved) and not BodyMotion._loco_saved_ok(saved,true): return _reject("receipt_or_partition")
		if receipts.has(saved.receipt): return _reject("duplicate_receipt")
		receipts[saved.receipt] = true
		var a: Dictionary = p.admission
		if not BodyMotion._keys(a,["unit","slot","receipt","piece","substep_count","classification","identity","future_authorized"]) or a.unit != request.unit or a.slot != request.slot or a.receipt != saved.receipt or not a.future_authorized is bool: return _reject("admission_mismatch")
		if a.piece != "royal": return _reject("nonroyal_admission")
		if not Phase._natural(a.substep_count) or a.substep_count < 1: return _reject("substep_count")
		if a.classification not in ["production_bound","endpoint_only"] or not a.identity is Dictionary or a.identity.is_empty() or not Phase._identity_json(a.identity): return _reject("admission_schema")
		if not a.future_authorized and a.classification != "endpoint_only": return _reject("unobserved_hostile_future")
		if not Carrier._valid(p.carrier,p.carrier.get("sha256","")): return _reject("stale_carrier")
		var r1: Variant = p.carrier.placement.identity.get("r1")
		if r1 != null and r1 != _source.identity: return _reject("carrier_source_mismatch")
		var found: bool = false
		for move: Dictionary in saved.plan.moves:
			if move.unit != request.unit or str(int(move.slot)) != request.slot: continue
			found = true
			for i: int in move.ops.size():
				var b := {"unit":a.unit,"slot":a.slot,"abs_day":int(saved.abs_day),"substep":int(saved.substep),
					"substep_count":int(a.substep_count),"receipt":saved.receipt,"op_index":i,"op":BodyMotion._canonical(move.ops[i]),
					"placement_identity":Carrier._digest(p.carrier.placement),"law_identity":_law.sha256,
					"previous":{},"next":{},"classification":a.classification}
				var error: String = Phase._binding_error(b,_law)
				if not error.is_empty(): return _reject(error)
				rows.append({"binding":b,"carrier":p.carrier.duplicate(true),"admission":BodyMotion._canonical(a)})
		if not found: return _reject("absent_admitted_row")
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var x: Dictionary = a.binding; var y: Dictionary = b.binding
		return x.abs_day < y.abs_day or (x.abs_day == y.abs_day and (x.substep < y.substep or (x.substep == y.substep and x.op.t0_q < y.op.t0_q))))
	for i: int in range(1,rows.size()):
		var a: Dictionary = rows[i-1].binding; var b: Dictionary = rows[i].binding
		if a.abs_day == b.abs_day and a.substep == b.substep and a.receipt != b.receipt: return _reject("conflicting_cursor")
	return {"ok":true,"rows":rows}


func _side(row: Dictionary, end: String, initial: Variant = null) -> Dictionary:
	var binding: Dictionary = row.binding
	if binding.classification == "endpoint_only": return _reject("endpoint_only")
	var q: int = int(binding.op.t1_q if end == "left" else binding.op.t0_q)
	var phase: Dictionary = Phase.sample(_source,_config,{"binding":binding,"time_q":q,"initial_native_phase":initial},binding)
	if not phase.ok: return _reject(phase.reason)
	var native: Dictionary = _native_sample(phase,end)
	if not native.ok: return _reject("native_branch",native.get("diagnostics",{}))
	var carrier: Dictionary = Carrier.sample(row.carrier,binding.op,1.0 if end == "left" else 0.0,end,row.carrier.sha256)
	if not carrier.ok: return _reject("carrier_branch",carrier)
	if carrier.enclosures.status not in ["NATIVE_ENCLOSED","ENCLOSED_CONTROL"]: return _reject("carrier_enclosure_unavailable",carrier.enclosures)
	var rate_box: Array = _i(_i([float(_config.time_day_seconds),float(_config.time_day_seconds)],
		[float(_config.battle_substeps),float(_config.battle_substeps)],"/"),[_source.length,_source.length],"/")
	if not Bounds._bounded(rate_box) or rate_box[0] <= 0.0: return _reject("rate_unrepresentable",{"rate":rate_box})
	var soles: Dictionary = {}
	for name: String in native.sole_jets: soles[name] = _native_jet(native.sole_jets[name],rate_box)
	var materials: Array = []
	for point: Dictionary in _material_points:
		materials.append(_native_jet(native.material_jets[point.surface],rate_box,point.vertex*3,3))
	var production: bool = carrier.native_covered and _source.identity.has("imports") and _source.identity.has("files") and row.carrier.placement.identity.get("r1") == _source.identity
	return {"ok":true,"id":{"abs_day":binding.abs_day,"substep":binding.substep,"receipt":binding.receipt,"op_index":binding.op_index,"operation_sha256":BodyMotion._hash(binding.op)},
		"binding":binding.duplicate(true),"admission":row.admission.duplicate(true),"kind":"pivot" if binding.op.kind == "pivot" else "native",
		"duration":float(binding.op.t1_q-binding.op.t0_q)/BodyMotion.LOCOMOTION_Q,"phase":phase,"side":end,
		"H":carrier.enclosures.H,"H_S":carrier.enclosures.H_S,"carrier":carrier,
		"soles":soles,"materials":materials,"material_points":_material_points.duplicate(true),"native":native,"classification":"production_bound" if production else "proof_domain_control"}


## Compose the accepted JETS evaluators at PHASE's directly rounded lookup time.
## Reconstructing it as rounded_phi*L loses valid native arguments (and cut sides).
func _native_sample(phase: Dictionary, side: String) -> Dictionary:
	var length: float = _source.length
	var time: float = phase.native_time
	if side == "left" and phase.phase_numerator == "0": time = length
	var cell: int = _jets._cell_at(time,side)
	var branches: Array = _jets._cells[cell].branches
	var lookup: float = -Math._next(-time) if side == "left" and _jets._native_cut(time) else time
	var error: float = Math._ua(Math._up(absf(time-lookup)),Math._ua(Math._um(absf(time),Math.U64),Math.TINY64))
	_jets._math.issue = ""
	var box: Dictionary = _jets._pose_box(branches,time,time,error)
	if not _jets._math.issue.is_empty(): return _reject(_jets._math.issue)
	var native: Dictionary = _jets._native(lookup)
	if not native.ok: return native
	var soles: Dictionary = {}
	for hoof: String in _jets._source.calibration.sole_patches:
		var patch: Dictionary = _jets._source.calibration.sole_patches[hoof]
		var bone: int = _jets._bone_index(hoof)
		var matrix: Array = _jets._math._matmul(_jets._math._matmul(Math._constant_matrix(_jets._source.model_from_skeleton),box.globals[bone]),Math._constant_matrix(patch.bone_from_sole))
		soles[hoof] = Math._packet(matrix,length)
		soles[hoof]["native_value"] = _jets._source.model_from_skeleton*native.globals[bone]*patch.bone_from_sole
	var matrices := {"locals":[],"globals":[],"skin":[]}
	for kind: String in matrices:
		for matrix: Array in box[kind]: matrices[kind].append(Math._packet(matrix,length))
	var materials: Array = _jets._materials(box.skin,box.material_error,length)
	if not _jets._math.issue.is_empty(): return _reject(_jets._math.issue)
	return {"ok":true,"native_time":time,"lookup_time":lookup,"coordinate":phase.duplicate(true),"side":side,"cell":cell,
		"branches":branches.duplicate(true),"locals":native.locals,"positions":native.positions,
		"sole_jets":soles,"material_jets":materials,"affine_jets":matrices,"source_sha256":_source.identity.source_sha256,
		"arithmetic_sha256":_identity.arithmetic,"domain_sha256":_identity.jets,
		"derivative_kind":"one_sided_branch_extension","crossing_derivative":null,"activation_pass":false}


func _shared(left: Dictionary, right: Dictionary, initial: Variant) -> Dictionary:
	var l: Dictionary = _side(left,"left")
	if not l.ok: return l
	var r: Dictionary = _side(right,"right",initial)
	if not r.ok: return r
	if l.phase.phase_numerator != r.phase.phase_numerator or l.phase.phase_denominator != r.phase.phase_denominator or l.phase.winding != r.phase.winding: return _reject("phase_discontinuity")
	# Equal placement/terrain functions at an exact common XZ/yaw prove carrier C0,
	# including modulo-2pi endpoints whose floating trig evaluations differ.
	for name: String in ["placement","terrain"]:
		var a: Dictionary = left.carrier[name].duplicate(); a.erase("identity")
		var b: Dictionary = right.carrier[name].duplicate(); b.erase("identity")
		if Carrier._digest(a) != Carrier._digest(b): return _reject("carrier_C0_unresolved",{"component":name})
	for category: String in ["locals","globals","skin"]:
		for i: int in l.native.affine_jets[category].size():
			var component: int = _extension_jump(l.native.affine_jets[category][i],r.native.affine_jets[category][i])
			if component >= 0: return _reject("native_C0_discontinuity",{"category":category,"index":i,"component":component,"left_branches":l.native.branches,"right_branches":r.native.branches})
	for i: int in l.native.material_jets.size():
		var component: int = _extension_jump(l.native.material_jets[i],r.native.material_jets[i])
		if component >= 0: return _reject("native_C0_discontinuity",{"category":"material","surface":i,"component":component})
	if Carrier._digest(l.native.locals) != Carrier._digest(r.native.locals): return _reject("native_C0_unresolved",{"left":l.native,"right":r.native})
	var target: Dictionary = _targets(l,r)
	if not target.ok: return target
	var record := {"version":VERSION,"unit":l.binding.unit,"slot":l.binding.slot,
		"S":{"abs_day":r.binding.abs_day,"substep":r.binding.substep,"time_q":r.binding.op.t0_q,"substep_count":r.binding.substep_count},
		"left_id":l.id,"right_id":r.id,"law_identity":_law.sha256,"source_identity":_source.identity.duplicate(true),
		"placement_identity":[l.binding.placement_identity,r.binding.placement_identity],"terrain_identity":[Carrier._digest(left.carrier.terrain),Carrier._digest(right.carrier.terrain)],
		"left":l,"right":r,"branch":l.kind+"/"+r.kind,"target":target,
		"classification":"production_bound" if l.classification == "production_bound" and r.classification == "production_bound" else "proof_domain_control"}
	record["sha256"] = Carrier._digest(record)
	return {"ok":true,"record":record}


## A numeric overlap is not a reconstruction/whole-pivot derivative proof.
## Supplied provider jets are diagnostic copied locals, NEVER provider callbacks.
func check_output(packet: Variant, solved: Variant) -> Dictionary:
	if not _acyclic(packet) or not packet is Dictionary or not packet.get("sha256") is String: return _reject("prepared_schema")
	if not BodyMotion._keys(packet,["version","identity","binding","entry","exit","classification","motion_join_claim","domain","representation","activation_pass","sha256"]): return _reject("prepared_schema")
	var unsigned: Dictionary = packet.duplicate(); unsigned.erase("sha256")
	if Carrier._digest(unsigned) != packet.sha256 or packet.get("identity") != _identity: return _reject("stale_prepared")
	if not solved is Dictionary or not BodyMotion._keys(solved,["entry","exit"]): return _reject("solved_schema")
	for end: String in ["entry","exit"]:
		if not packet[end] is Dictionary or not BodyMotion._keys(packet[end],["shared","constraints"]) or not packet[end].shared is Dictionary: return _reject("prepared_schema")
		var shared: Dictionary = packet[end].shared
		for name: String in ["left","right","target"]:
			if not shared.get(name) is Dictionary: return _reject("prepared_schema")
		var side: Dictionary = shared.right if end == "entry" else shared.left
		if not _boxes(side.get("H"),12) or not _boxes(side.get("H_S"),12) or not Bounds._number(side.get("duration")) or side.duration <= 0.0 or not side.get("soles") is Dictionary or not side.get("materials") is Array: return _reject("prepared_schema")
		if not shared.target.get("soles") is Dictionary or shared.target.soles.keys() != side.soles.keys() or not shared.target.get("materials") is Array or shared.target.materials.size() != side.materials.size(): return _reject("prepared_schema")
		var candidate: Variant = solved[end]
		if not candidate is Dictionary or not BodyMotion._keys(candidate,["soles","materials"]): return _reject("solved_schema")
		if not candidate.soles is Dictionary or candidate.soles.keys() != side.soles.keys() or not candidate.materials is Array or candidate.materials.size() != side.materials.size(): return _reject("solved_schema")
		for category: String in ["soles","materials"]:
			var keys: Array = side[category].keys() if category == "soles" else range(side[category].size())
			for key: Variant in keys:
				if not side[category][key] is Dictionary or not _boxes(side[category][key].get("value"),12 if category == "soles" else 3) or not _boxes(shared.target[category][key],12 if category == "soles" else 3): return _reject("prepared_schema")
				var jet: Variant = candidate[category][key]
				var count: int = 12 if category == "soles" else 3
				if not jet is Dictionary or not BodyMotion._keys(jet,["value","derivative"]) or not _boxes(jet.value,count) or not _boxes(jet.derivative,count): return _reject("solved_schema")
				if not _overlap(jet.value,side[category][key].value): return _reject("solved_boundary_pose_mismatch",{"end":end,"category":category,"key":key})
				var local_s: Array = []
				var duration: Array = [Bounds._next64(side.duration,-1),Bounds._next64(side.duration,1)]
				for box: Array in jet.derivative: local_s.append(_i(box,duration,"/"))
				var world: Array = _add(_multiply(side.H_S,jet.value,1),_multiply(side.H,local_s,0))
				if not _overlap(world,shared.target[category][key]): return _reject("solved_boundary_jet_mismatch",{"end":end,"category":category,"key":key,"actual":world,"target":shared.target[category][key]})
	return _reject("UNRESOLVED",{"required":"proved provider reconstruction and whole-pivot derivative enclosure; numerical overlap alone is insufficient"})


static func _acyclic(value: Variant, ancestors: Array = []) -> bool:
	if ancestors.size() > 64 or value is Object or value is Callable or value is Signal: return false
	if value is Dictionary or value is Array:
		for ancestor: Variant in ancestors:
			if is_same(value,ancestor): return false
		var next: Array = ancestors+[value]
		for item: Variant in (value.values() if value is Dictionary else value):
			if not _acyclic(item,next): return false
	return true


static func _boxes(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for box: Variant in value:
		if not box is Array or box.size() != 2 or not Bounds._number(box[0]) or not Bounds._number(box[1]) or box[0] > box[1]: return false
	return true


static func _overlap(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i][1] < b[i][0] or b[i][1] < a[i][0]: return false
	return true


static func _extension_jump(left: Dictionary, right: Dictionary) -> int:
	for i: int in left.extension_lower.size():
		if left.extension_upper[i] < right.extension_lower[i] or right.extension_upper[i] < left.extension_lower[i]: return i
	return -1


static func _native_jet(jet: Dictionary, rate: Array, start: int = 0, count: int = 12) -> Dictionary:
	var value: Array = []
	var derivative: Array = []
	for i: int in range(start,start+count):
		value.append([jet.extension_lower[i],jet.extension_upper[i]])
		derivative.append(_i([jet.phase_derivative_lower[i],jet.phase_derivative_upper[i]],rate,"*"))
	return {"value":value,"derivative":derivative,"native_value_error":jet.get("native_error",jet.get("native_error_uniform",[]))}


static func _targets(left: Dictionary, right: Dictionary) -> Dictionary:
	var target := {"ok":true,"soles":{},"materials":[],"world_value":{"soles":{},"materials":[]},"references":{"left":{"soles":{},"materials":[]},"right":{"soles":{},"materials":[]}}}
	if left.kind not in ["native","pivot"] or right.kind not in ["native","pivot"] or left.soles.keys() != right.soles.keys() or left.materials.size() != right.materials.size(): return _reject("jet_schema")
	for category: String in ["soles","materials"]:
		var keys: Array = left[category].keys() if category == "soles" else range(left[category].size())
		for key: Variant in keys:
			var common: Array = _multiply(left.H,left[category][key].value,1)
			var other: Array = _multiply(right.H,right[category][key].value,1)
			for i: int in common.size(): common[i] = Bounds._hull(common[i],other[i])
			if not _finite_boxes(common): return _reject("C0_numeric_range")
			if category == "soles": target.world_value[category][key] = common
			else: target.world_value[category].append(common)
			var refs: Array = []
			for side: Dictionary in [left,right]:
				var jet: Dictionary = side[category][key]
				refs.append(_add(_multiply(side.H_S,jet.value,1),_multiply(side.H,jet.derivative,0)))
			for k: int in 2:
				if category == "soles": target.references[["left","right"][k]][category][key] = refs[k]
				else: target.references[["left","right"][k]][category].append(refs[k])
			var shared: Array = refs[0] if left.kind == "native" else refs[1]
			if left.kind == "pivot" and right.kind == "pivot": shared = _scale(_add(refs[0],refs[1]),[.5,.5])
			if left.kind == "native" and right.kind == "native" and refs[0] != refs[1]: return _reject("native_C1_unresolved",{"left":refs[0],"right":refs[1]})
			if not _finite_boxes(shared): return _reject("reference_numeric_range")
			if category == "soles": target[category][key] = shared
			else: target[category].append(shared)
	return target


static func _constraints(side: Dictionary, target: Dictionary) -> Dictionary:
	var inverse: Array = _inverse_basis(side.H)
	if inverse.is_empty(): return _reject("singular_carrier")
	var out := {"ok":true,"soles":{},"materials":[],"units":"d/d normalized u; homogeneous derivative w=0","actual_output_claim":false}
	for category: String in ["soles","materials"]:
		var keys: Array = side[category].keys() if category == "soles" else range(side[category].size())
		for key: Variant in keys:
			var remainder: Array = _add(target[category][key],_scale(_multiply(side.H_S,side[category][key].value,1),[-1.0,-1.0]))
			var result: Array = _scale(_multiply(inverse,remainder,0),[Bounds._next64(side.duration,-1),Bounds._next64(side.duration,1)])
			if not _finite_boxes(result): return _reject("constraint_numeric_range")
			if category == "soles": out[category][key] = result
			else: out[category].append(result)
	return out


static func _i(a: Array, b: Array, op: String) -> Array:
	return Bounds._interval(a,b,op,64)


static func _add(a: Array, b: Array) -> Array:
	var out: Array = []
	for i: int in a.size(): out.append(_i(a[i],b[i],"+"))
	return out


static func _scale(a: Array, b: Array) -> Array:
	var out: Array = []
	for bound: Array in a: out.append(_i(bound,b,"*"))
	return out


## A is3x4; B is3x4 affine or3-vector. w belongs to B, never to A.
static func _multiply(a: Array, b: Array, w: int) -> Array:
	var out: Array = []
	var columns: int = 4 if b.size() == 12 else 1
	for row: int in 3:
		for col: int in columns:
			var sum: Array = a[row*4+3] if w == 1 and (columns == 1 or col == 3) else [0.0,0.0]
			for k: int in 3: sum = _i(sum,_i(a[row*4+k],b[k*columns+col],"*"),"+")
			out.append(sum)
	return out


static func _inverse_basis(a: Array) -> Array:
	var cofactors: Array = []
	for row: int in 3:
		for col: int in 3:
			var r1: int = (row+1)%3; var r2: int = (row+2)%3
			var c1: int = (col+1)%3; var c2: int = (col+2)%3
			cofactors.append(_i(_i(a[r1*4+c1],a[r2*4+c2],"*"),_i(a[r1*4+c2],a[r2*4+c1],"*"),"-"))
	var determinant: Array = [0.0,0.0]
	for col: int in 3: determinant = _i(determinant,_i(a[col],cofactors[col],"*"),"+")
	if not Bounds._bounded(determinant) or (determinant[0] <= 0.0 and determinant[1] >= 0.0): return []
	var out: Array = []
	for row: int in 3:
		for col: int in 3: out.append(_i(cofactors[col*3+row],determinant,"/"))
		out.append([0.0,0.0])
	return out


static func _finite_boxes(value: Array) -> bool:
	for box: Array in value:
		if not Bounds._bounded(box): return false
	return true


static func _reject(reason: String, witness: Dictionary = {}) -> Dictionary:
	return {"ok":false,"prepared":{},"reason":reason,"witness":witness.duplicate(true),"activation_pass":false}
