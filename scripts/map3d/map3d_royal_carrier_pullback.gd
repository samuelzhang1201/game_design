class_name Map3DRoyalCarrierPullback
extends RefCounted
## Accepted239 §6, pure instantaneous adapter; the legacy kernel stays unchanged.
## prepare binds copied immutable rest, exact native/reference locals, operation,
## carrier, fixed R1 model_from_skeleton F and WORLD physical contact segments.
## Physical derivatives are per normalized u; carrier H_S is converted with D.
## sample exposes both numerical one-sided jets, without fitting K into segments.
## Success means numerical reconstruction only: native arithmetic, finite solver
## branch continuity, whole-skin jets and physical E remain separate prerequisites.

const Pivot = preload("res://scripts/map3d/map3d_cavalry_pivot.gd")
const Math = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")
const Carrier = preload("res://scripts/map3d/map3d_royal_upright_carrier.gd")
const Bounds = preload("res://scripts/map3d/map3d_royal_carrier_bounds.gd")
const ZERO: Transform3D = Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
const PACKET_KEYS: Array[String] = ["version","rest","pose","operation","carrier","native_operation","model_from_skeleton","contacts","source_identity","sha256"]


static func prepare(rest: Variant, pose: Variant, operation: Variant, carrier: Variant,
		native_operation: Variant, model_from_skeleton: Variant, contacts: Variant, source_identity: Variant) -> Dictionary:
	if not _safe(carrier): return _reject("carrier_packet")
	var reason: String = _validate(rest,pose,operation,carrier,native_operation,model_from_skeleton,contacts,source_identity)
	if reason != "": return _reject(reason)
	var packet: Dictionary = {"version":1,"rest":rest.duplicate(true),"pose":pose.duplicate(true),
		"operation":operation.duplicate(true),"carrier":carrier.duplicate(true),"native_operation":native_operation.duplicate(true),
		"model_from_skeleton":model_from_skeleton,"contacts":contacts.duplicate(true),"source_identity":source_identity.duplicate(true)}
	packet["sha256"] = Carrier._digest(packet)
	return {"ok":true,"packet":packet}


## Packet is deliberately bound to the exact supplied reference pose at this u.
## Re-prepare for another reference pose/u; never substitute a cached solved pose.
static func sample(rest: Variant, pose: Variant, operation: Variant, packet: Variant, side: Variant) -> Dictionary:
	if not _safe(packet): return _reject("packet_raw_type")
	if not Pivot._keys(packet,PACKET_KEYS) or not packet.version is int or packet.version != 1 or not packet.sha256 is String:
		return _reject("packet_schema")
	var plain: Dictionary = packet.duplicate()
	plain.erase("sha256")
	if Carrier._digest(plain) != packet.sha256: return _reject("stale_packet")
	var reason: String = _validate(rest,pose,operation,packet.carrier,packet.native_operation,packet.model_from_skeleton,packet.contacts,packet.source_identity)
	if reason != "": return _reject(reason)
	if rest != packet.rest or pose != packet.pose or operation != packet.operation: return _reject("packet_input_mismatch")
	if not side is String or side not in ["left","right"]: return _reject("side")
	var u: float = operation.phase
	var turn: Transform3D = Transform3D(Basis(rest.turn_axis,deg_to_rad(operation.turn_degrees*u)),Vector3.ZERO)
	var turn_u: Transform3D = Transform3D(Math._hat(rest.turn_axis*deg_to_rad(operation.turn_degrees))*turn.basis,Vector3.ZERO)
	var sides: Dictionary = {}
	for selected: String in ["left","right"]:
		var evaluated: Dictionary = Carrier.sample(packet.carrier,packet.native_operation,u,selected,packet.carrier.sha256)
		if not evaluated.ok: return _reject("carrier:"+evaluated.reason,{"carrier":evaluated})
		if evaluated.enclosures.status == "UNAVAILABLE": return _reject("carrier_arithmetic_unavailable",{"carrier":evaluated})
		var d: float = float(packet.native_operation.t1_q-packet.native_operation.t0_q)/float(BodyMotion.LOCOMOTION_Q)
		var h_u: Transform3D = Transform3D(Math._scaled(evaluated.H_S.basis,d),evaluated.H_S.origin*d)
		var hk: Dictionary = _product(evaluated.H,h_u,packet.model_from_skeleton,ZERO)
		if not Math._finite(hk.value) or not Math._affine(hk.value): return _reject("carrier_singular")
		var inverse: Dictionary = _inverse(hk.value,hk.derivative)
		var numerical: Dictionary = {}
		for hoof: String in Pivot._HOOVES:
			var physical: Dictionary = _physical(packet.contacts[hoof],u,rest.turn_axis,selected)
			if not physical.ok: return _reject(hoof+":"+physical.reason)
			var local: Dictionary = _product(inverse.value,inverse.derivative,physical.value,physical.derivative)
			var target: Dictionary = _product(turn,turn_u,local.value,local.derivative)
			if not Math._finite(target.value) or not Math._affine(target.value) or not Math._finite(target.derivative):
				return _reject(hoof+":pullback_numeric_range")
			var undo_y: Dictionary = _inverse(turn,turn_u)
			var undo: Dictionary = _product(hk.value,hk.derivative,undo_y.value,undo_y.derivative)
			var rebuilt: Dictionary = _product(undo.value,undo.derivative,target.value,target.derivative)
			if not Math._close(rebuilt.value,physical.value) or not Math._close(rebuilt.derivative,physical.derivative):
				return _reject(hoof+":pullback_identity_residual")
			numerical[hoof] = {"K":target.value,"K_u":target.derivative,"physical":physical,
				"identity_reconstruction":rebuilt,"identity_reconstruction_semantics":"coordinate identity only, not solved-pose jets"}
		sides[selected] = {"carrier":evaluated,"H_k":hk.value,"H_k_u":hk.derivative,"D":d,"S":float(packet.native_operation.t0_q)/float(BodyMotion.LOCOMOTION_Q)+d*u,"u":u,"Y":turn,"Y_u":turn_u,"targets":numerical}
	# Validate BOTH exact native endpoints, irrespective of the requested interior.
	for endpoint: float in [0.0,1.0]:
		var native: Dictionary = Math._fk(rest.bones,pose.entry if endpoint == 0.0 else pose.exit)
		var at: Dictionary = Carrier.sample(packet.carrier,packet.native_operation,endpoint,"right" if endpoint == 0.0 else "left",packet.carrier.sha256)
		if not at.ok: return _reject("endpoint_carrier:"+at.reason)
		if at.enclosures.status == "UNAVAILABLE": return _reject("endpoint_carrier_arithmetic_unavailable",{"carrier":at})
		for hoof: String in Pivot._HOOVES:
			var contact: Dictionary = packet.contacts[hoof]
			var target: Transform3D = contact.segments[0].from if endpoint == 0.0 else contact.segments[-1].to
			if not Math._close(at.H*packet.model_from_skeleton*native[hoof]*contact.offset,target):
				return _reject(hoof+":incompatible_native_endpoint")
	var locals: Dictionary = pose.locals.duplicate(true)
	var globals: Dictionary = Math._fk(rest.bones,locals)
	var selected: Dictionary = sides[side]
	var iterations: int = 0
	for hoof: String in Pivot._HOOVES:
		var contact: Dictionary = packet.contacts[hoof]
		var chain: Dictionary = rest.chains[hoof]
		var first: Dictionary = Math._bone(rest.bones,chain.bones[0])
		var attachment: Vector3 = globals[first.name]*first.head
		var solved: Dictionary = Math._solve(rest,chain,locals,selected.targets[hoof].K,globals[first.parent],turn,contact.offset)
		iterations += solved.iterations
		if not solved.ok: return _reject(hoof+":"+solved.reason,{"iterations":iterations,"sides":sides})
		for name: String in chain.bones: locals[name] = solved.locals[name]
		globals = Math._fk(rest.bones,locals)
		if (globals[first.name]*first.head).distance_to(attachment) > Math.EPS: return _reject(hoof+":attachment_residual")
		if not Math._close(turn*globals[hoof]*contact.offset,selected.targets[hoof].K): return _reject(hoof+":contact_residual")
		if not Math._close(selected.H_k*globals[hoof]*contact.offset,selected.targets[hoof].physical.value): return _reject(hoof+":world_contact_residual")
	reason = _restrictions(rest,pose.locals,locals)
	if reason != "": return _reject(reason)
	if (u == 0.0 or u == 1.0) and locals != pose.locals: return _reject("native_endpoint_requires_correction")
	var residuals: Dictionary = _world_bounds(rest,locals,packet.model_from_skeleton,selected.carrier,selected.targets,packet.contacts)
	if not residuals.ok: return _reject("world_residual_unbounded",residuals)
	return {"ok":true,"locals":locals,"diagnostics":{"reason":"","iterations":iterations},"sides":sides,
		"world_residual_bounds":residuals,"source_identity":packet.source_identity.duplicate(true),
		"reconstruction_jets":{"status":"UNRESOLVED","reason":"finite solver branch and whole skin derivative bounds required; target identities are not solved jets"},
		"physical_allowance":{"status":"NOT_SELECTED"},"physical_pass":false,"activation_pass":false}


static func _validate(rest: Variant, pose: Variant, op: Variant, carrier: Variant, native_op: Variant, f: Variant, contacts: Variant, identity: Variant) -> String:
	for value: Variant in [rest,pose,op,contacts,f,identity]:
		if not Math._finite(value): return "nonfinite_or_raw_type"
	if not Pivot._keys(rest,["version","turn_axis","bones","chains"]) or not Pivot._keys(pose,["locals","entry","exit"]) or not Pivot._keys(op,Pivot._OP_KEYS) or not Pivot._keys(contacts,Pivot._HOOVES): return "schema"
	if not identity is Dictionary or not Pivot._keys(identity,["source_sha256","reference_sha256"]): return "source_identity"
	for key: String in identity:
		if not identity[key] is String or identity[key].is_empty(): return "source_identity"
	if not Math._affine(f): return "model_from_skeleton"
	var reason: String = Pivot._validate_rest(rest)
	if reason != "": return reason
	reason = Pivot._validate_operation(op)
	if reason != "": return reason
	for key: String in ["locals","entry","exit"]:
		reason = Pivot._validate_pose(rest,pose[key])
		if reason != "": return key+":"+reason
	if op.phase == 0.0 and pose.locals != pose.entry: return "entry_pose_mismatch"
	if op.phase == 1.0 and pose.locals != pose.exit: return "exit_pose_mismatch"
	if not carrier is Dictionary or not carrier.get("sha256") is String or not Carrier._valid(carrier,carrier.sha256): return "carrier_packet"
	if carrier.placement.identity.has("r1"):
		var r1: Variant = carrier.placement.identity.r1
		if not r1 is Dictionary or r1.get("source_sha256") != identity.source_sha256: return "carrier_source_identity"
	if not native_op is Dictionary or not Carrier._op_ok(native_op) or native_op.kind != "pivot": return "native_operation"
	var start: float = float(native_op.yaw0_udeg)/1000000.0
	var turn: float = float(native_op.turn_udeg)/1000000.0
	if op.start_heading != start or op.turn_degrees != turn or op.end_heading != fposmod(start+turn,360.0): return "operation_identity"
	for hoof: String in Pivot._HOOVES:
		reason = Pivot._validate_contact(contacts[hoof])
		if reason != "": return hoof+":"+reason
	return ""


## Full affine derivative product; derivative homogeneous bottom row is ZERO.
static func _product(a: Transform3D, au: Transform3D, b: Transform3D, bu: Transform3D) -> Dictionary:
	return {"value":a*b,"derivative":Transform3D(Math._add(au.basis*b.basis,a.basis*bu.basis),
		au.basis*b.origin+a.basis*bu.origin+au.origin)}


static func _inverse(a: Transform3D, au: Transform3D) -> Dictionary:
	var inverse: Transform3D = a.affine_inverse()
	return {"value":inverse,"derivative":Transform3D(Math._scaled(inverse.basis*au.basis*inverse.basis,-1.0),
		-(inverse.basis*(au.basis*inverse.origin+au.origin)))}


static func _physical(contact: Dictionary, u: float, axis: Vector3, side: String) -> Dictionary:
	for segment: Dictionary in contact.segments:
		if u < segment.start or u > segment.end or (u == segment.end and u != 1.0 and side == "right") or (u == segment.start and u != 0.0 and side == "left"): continue
		var value: Dictionary = Math._contact_at({"segments":[segment]},u,axis)
		if not value.ok: return value
		var derivative: Transform3D = ZERO
		if segment.mode != "stance":
			if u == segment.start: derivative = segment.from_derivative
			elif u == segment.end: derivative = segment.to_derivative
			else:
				var first: Dictionary = Math._polar_derivative(segment.from,segment.from_derivative)
				var last: Dictionary = Math._polar_derivative(segment.to,segment.to_derivative)
				if not first.ok or not last.ok: return {"ok":false,"reason":"contact_polar"}
				var dt: float = segment.end-segment.start
				var t: float = (u-segment.start)/dt
				var h00: float = 2*t*t*t-3*t*t+1
				var h10: float = t*t*t-2*t*t+t
				var h01: float = -2*t*t*t+3*t*t
				var h11: float = t*t*t-t*t
				var d00: float = (6*t*t-6*t)/dt
				var d10: float = 3*t*t-4*t+1
				var d01: float = (-6*t*t+6*t)/dt
				var d11: float = 3*t*t-2*t
				var vector: Vector3 = Math._rotation_vector(last.rotation*first.rotation.transposed(),axis)
				var tangent: Vector3 = Math._left_jacobian_inverse(vector)*last.angular
				var rotation: Vector3 = first.angular*dt*h10+vector*h01+tangent*dt*h11
				var rate: Vector3 = first.angular*d10+vector*d01+tangent*d11
				var angle: float = rotation.length()
				var skew: Basis = Math._hat(rotation)
				var square: float = angle*angle
				var a: float = 0.5-square/24.0+square*square/720.0 if angle < 0.0001 else (1-cos(angle))/square
				var b: float = 1.0/6.0-square/120.0+square*square/5040.0 if angle < 0.0001 else (angle-sin(angle))/(square*angle)
				var jacobian: Basis = Math._add(Math._add(Basis.IDENTITY,skew,a),skew*skew,b)
				var stretch: Basis = Math._add(Math._add(Math._add(Math._scaled(first.stretch,h00),first.stretch_derivative,dt*h10),last.stretch,h01),last.stretch_derivative,dt*h11)
				var stretch_u: Basis = Math._add(Math._add(Math._add(Math._scaled(first.stretch,d00),first.stretch_derivative,d10),last.stretch,d01),last.stretch_derivative,d11)
				var r: Basis = Math._exp(rotation)*first.rotation
				derivative = Transform3D(Math._add(Math._hat(jacobian*rate)*r*stretch,r*stretch_u)*first.parity,
					segment.from.origin*d00+segment.from_derivative.origin*d10+segment.to.origin*d01+segment.to_derivative.origin*d11)
		if not Math._finite(derivative): return {"ok":false,"reason":"contact_derivative_nonfinite"}
		return {"ok":true,"value":value.value,"derivative":derivative,"support":segment.mode}
	return {"ok":false,"reason":"contact_partition"}


static func _restrictions(rest: Dictionary, native: Dictionary, locals: Dictionary) -> String:
	var reason: String = Pivot._validate_pose(rest,locals)
	if reason != "": return "solved:"+reason
	var allowed: Array = []
	for hoof: String in Pivot._HOOVES:
		allowed.append_array(rest.chains[hoof].bones)
		if not Math._limits(rest,rest.chains[hoof],locals): return hoof+":joint_limits"
	for name: String in native:
		if locals[name].origin != native[name].origin: return name+":local_origin"
		if not name in allowed:
			if locals[name] != native[name]: return name+":nonlimb_changed"
		elif Math._basis_error(locals[name].basis.transposed()*locals[name].basis,native[name].basis.transposed()*native[name].basis) > Math.EPS or signf(locals[name].basis.determinant()) != signf(native[name].basis.determinant()): return name+":native_stretch_shear"
	return ""


## Outward native FK/carrier products, against the RETURNED numerical physical
## target. This is no bound on interpolation real-extension error or whole skin.
static func _world_bounds(rest: Dictionary, locals: Dictionary, f: Transform3D, carrier: Dictionary, targets: Dictionary, contacts: Dictionary) -> Dictionary:
	var globals: Dictionary = {}
	for bone: Dictionary in rest.bones:
		globals[bone.name] = _constant(locals[bone.name]) if bone.parent == "" else Bounds._matrix_enclosure(globals[bone.parent],locals[bone.name])
	var h: Array = Bounds._matrix_enclosure(carrier.enclosures.H,f)
	var out: Dictionary = {"ok":true,"scope":"native reconstructed full sole frame versus returned physical target only","carrier_status":carrier.carrier_status,"hooves":{}}
	for hoof: String in Pivot._HOOVES:
		var world: Array = _multiply(h,globals[hoof])
		world = Bounds._matrix_enclosure(world,contacts[hoof].offset)
		var target: Array = Bounds._matrix_values(targets[hoof].physical.value)
		var residual: Array = []
		for i: int in 12:
			var bound: Array = Bounds._interval(world[i],[target[i],target[i]],"-")
			if not Bounds._bounded(bound): return {"ok":false,"hoof":hoof,"component":i}
			residual.append(bound)
		out.hooves[hoof] = residual
	return out


static func _constant(t: Transform3D) -> Array:
	var out: Array = []
	for value: float in Bounds._matrix_values(t): out.append([value,value])
	return out


static func _multiply(a: Array, b: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		for column: int in 4:
			var total: Array = [0.0,0.0]
			for k: int in 3: total = Bounds._interval(total,Bounds._interval(a[row*4+k],b[k*4+column],"*"),"+")
			out.append(Bounds._interval(total,a[row*4+3],"+") if column == 3 else total)
	return out


static func _reject(reason: String, evidence: Dictionary = {}) -> Dictionary:
	return Pivot._reject(reason,evidence)


static func _safe(value: Variant, depth: int = 0) -> bool:
	if depth > 20: return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String and not key is Vector2i: return false
			if not _safe(value[key],depth+1): return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _safe(item,depth+1): return false
		return true
	if value is PackedFloat32Array or value is PackedFloat64Array:
		for item: float in value:
			if not is_finite(item): return false
		return true
	if value == null or value is PackedByteArray or value is PackedStringArray or value is PackedInt32Array or value is PackedInt64Array or value is bool: return true
	return Math._finite(value)
