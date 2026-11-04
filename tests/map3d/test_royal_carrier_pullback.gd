extends GutTest
## Hand controls exercise representation, never native physical-domain acceptance.
const Carrier = preload("res://scripts/map3d/map3d_royal_upright_carrier.gd")
const Pivot = preload("res://scripts/map3d/map3d_cavalry_pivot.gd")
const Math = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")
const Fixtures = preload("res://tests/map3d/test_cavalry_pivot.gd")

func _adapter() -> GDScript:
	var path: String = "res://scripts/map3d/map3d_royal_carrier_pullback.gd"
	var script: GDScript = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(script, "accepted239 needs the explicit carrier representation adapter")
	return script

func _zero() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

func _fixture(angle: float = 0.0, moving_seat: bool = false) -> Dictionary:
	var factory: GutTest = Fixtures.new()
	var f: Dictionary = factory._synthetic_case()
	factory.free()
	var p: Dictionary = {"origin":Vector2.ZERO,"alpha":1.0,"k":1.0,"extent":Vector2(1,2),
		"height":3.0,"clear":0.0,"sink":0.0,"ring":8,"ancestor":Transform3D.IDENTITY,
		"identity":{"source":"hand-control"}}
	var heights: PackedFloat32Array = PackedFloat32Array()
	var controls: PackedInt32Array = PackedInt32Array()
	for z: int in 4:
		for x: int in 4:
			heights.append(float(x)*2.0 if moving_seat else 0.0)
			controls.append(0)
	var terrain: Dictionary = {"kind":"control","spacing":20.0,"sea":-100.0,"region_size":4,
		"regions":{Vector2i.ZERO:{"height":heights,"control":controls}},"identity":{"source":"hand-plane"}}
	var prepared: Dictionary = Carrier.prepare(p,terrain)
	assert_true(prepared.ok)
	f["carrier"] = prepared.packet
	# A nonzero committed pivot is required; tiny turns also exercise cancellation.
	var turn: float = angle if angle != 0.0 else 0.000001
	f["native_op"] = {"kind":"pivot","t0_q":0,"t1_q":BodyMotion.LOCOMOTION_Q,"a":[10,10],"b":[10,10],"yaw0_udeg":0,"turn_udeg":roundi(turn*1000000.0)}
	f["op"] = {"start_heading":0.0,"end_heading":fposmod(turn,360.0),"turn_degrees":turn,
		"duration":2.0,"phase":0.5,"entry_phase":0.37,"exit_phase":0.37}
	f["pose"] = {"locals":f.native.duplicate(true),"entry":f.native.duplicate(true),"exit":f.native.duplicate(true)}
	f["F"] = Transform3D.IDENTITY
	f["identity"] = {"source_sha256":"synthetic-bind-and-native","reference_sha256":"synthetic-reference"}
	f["contacts"] = _contacts(f)
	return f

func _contacts(f: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var globals: Dictionary = Math._fk(f.rest.bones,f.native)
	var first: Dictionary = Carrier.sample(f.carrier,f.native_op,0.0,"right",f.carrier.sha256)
	var last: Dictionary = Carrier.sample(f.carrier,f.native_op,1.0,"left",f.carrier.sha256)
	assert_true(first.ok); assert_true(last.ok)
	for hoof: String in f.rest.chains:
		out[hoof] = {"offset":Transform3D.IDENTITY,"segments":[{"start":0.0,"end":1.0,"mode":"swing",
			"from":first.H*f.F*globals[hoof],"to":last.H*f.F*globals[hoof],
			"from_derivative":_zero(),"to_derivative":_zero()}]}
	return out

func _prepare(a: GDScript, f: Dictionary) -> Dictionary:
	return a.prepare(f.rest,f.pose,f.op,f.carrier,f.native_op,f.F,f.contacts,f.identity)

func test_native_endpoints_reconstruct_exact_locals_with_variable_height() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture(90.0,true)
	for u: float in [0.0,1.0]:
		f.op.phase = u
		var p: Dictionary = _prepare(a,f)
		assert_true(p.ok,str(p))
		if not p.ok: continue
		var result: Dictionary = a.sample(f.rest,f.pose,f.op,p.packet,"right" if u == 0.0 else "left")
		assert_true(result.ok,str(result))
		if not result.ok: continue
		assert_eq(result.locals,f.native,"every native local stays exact")
		assert_eq(result.physical_allowance.status,"NOT_SELECTED")
		assert_eq(result.reconstruction_jets.status,"UNRESOLVED")

func _sample(a: GDScript, f: Dictionary, side: String = "right") -> Dictionary:
	var prepared: Dictionary = _prepare(a,f)
	assert_true(prepared.ok,str(prepared))
	if not prepared.ok: return {"ok":false,"locals":{},"diagnostics":{"reason":"prepare"}}
	return a.sample(f.rest,f.pose,f.op,prepared.packet,side)

func _close(a: Transform3D, b: Transform3D, message: String = "") -> void:
	assert_almost_eq(a.origin.distance_to(b.origin),0.0,Math.EPS,message+" origin")
	assert_almost_eq(Math._basis_error(a.basis,b.basis),0.0,Math.EPS,message+" basis")

func test_hand_affine_inverse_chain_rule_has_zero_derivative_bottom_row() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	# Hk=diag(2,3,4) + translation(1,2,3), Hk_u translation(0,6,0).
	# C=(5,8,11), C_u=(2,3,4); Y=I with angular rate +1 about Y.
	# Hk^-1*C=(2,2,2); its derivative=(1,-1,1).
	# K_u=hat(UP)*(2,2,2)+(1,-1,1)=(3,-1,-1).
	var h: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3(2,3,4)),Vector3(1,2,3))
	var hu: Transform3D = Transform3D(_zero().basis,Vector3(0,6,0))
	var c: Transform3D = Transform3D(Basis.IDENTITY,Vector3(5,8,11))
	var cu: Transform3D = Transform3D(_zero().basis,Vector3(2,3,4))
	var inv: Dictionary = a._inverse(h,hu)
	var local: Dictionary = a._product(inv.value,inv.derivative,c,cu)
	var k: Dictionary = a._product(Transform3D.IDENTITY,Transform3D(Math._hat(Vector3.UP),Vector3.ZERO),local.value,local.derivative)
	assert_eq(k.value.origin,Vector3(2,2,2))
	assert_eq(k.derivative.origin,Vector3(3,-1,-1))
	_close(k.value,Transform3D(Basis.IDENTITY.scaled(Vector3(.5,1.0/3.0,.25)),Vector3(2,2,2)))

func test_physical_Hermite_jet_matches_hand_midpoint_and_rotating_affine_control() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var segment: Dictionary = {"start":0.0,"end":1.0,"mode":"swing","from":Transform3D.IDENTITY,
		"to":Transform3D(Basis(Vector3.UP,PI/2),Vector3(2,4,6)),"from_derivative":_zero(),"to_derivative":_zero()}
	var c: Dictionary = {"offset":Transform3D.IDENTITY,"segments":[segment]}
	var jet: Dictionary = a._physical(c,.5,Vector3.UP,"right")
	assert_true(jet.ok)
	assert_eq(jet.value.origin,Vector3(1,2,3))
	assert_eq(jet.derivative.origin,Vector3(3,6,9))
	_close(jet.derivative,Transform3D(Math._hat(Vector3.UP*(3*PI/4))*Basis(Vector3.UP,PI/4),Vector3(3,6,9)))
	# Independent finite difference checks the general noncommuting angular path,
	# mirrored/sheared stretch and unequal declared endpoint derivatives.
	segment.from = Transform3D(Basis(Vector3.RIGHT,.2)*Basis(Vector3(-2,0,0),Vector3(.1,1,0),Vector3(0,.2,3)),Vector3(1,0,2))
	segment.to = Transform3D(Basis(Vector3.FORWARD,-.4)*Basis(Vector3(-1,0,0),Vector3(.2,2,0),Vector3(0,.1,2)),Vector3(-1,2,0))
	segment.from_derivative = Transform3D(Math._hat(Vector3(.1,.2,.3))*segment.from.basis,Vector3(.5,1,0))
	segment.to_derivative = Transform3D(Math._hat(Vector3(-.2,.1,.4))*segment.to.basis,Vector3(0,-.5,1))
	jet = a._physical(c,.37,Vector3.UP,"right")
	assert_true(jet.ok)
	var before: Dictionary = Math._contact_at(c,.369,Vector3.UP)
	var after: Dictionary = Math._contact_at(c,.371,Vector3.UP)
	assert_almost_eq(jet.derivative.origin.distance_to((after.value.origin-before.value.origin)/.002),0.0,.0003)
	assert_almost_eq(Math._basis_error(jet.derivative.basis,Math._scaled(Math._add(after.value.basis,before.value.basis,-1),500)),0.0,.0006)

func test_solve_interior_preserves_all_origins_nonlimbs_stretch_and_world_bounds() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture(4.0,true)
	var saved: Dictionary = f.duplicate(true)
	var result: Dictionary = _sample(a,f)
	assert_true(result.ok,str(result.get("diagnostics")))
	if not result.ok: return
	assert_eq(f,saved,"no source/seat/root/scale mutation")
	assert_eq(_sample(a,f),result,"repeat sampling has no mutable iteration history")
	assert_eq(a._restrictions(f.rest,f.native,result.locals),"")
	assert_eq(result.locals.R_Hips,f.native.R_Hips)
	assert_eq(result.locals.Lance,f.native.Lance)
	assert_eq(result.locals.root,f.native.root)
	var globals: Dictionary = Math._fk(f.rest.bones,result.locals)
	for hoof: String in Pivot._HOOVES:
		var s: Dictionary = result.sides.right
		var world: Transform3D = s.H_k*globals[hoof]*f.contacts[hoof].offset
		_close(world,s.targets[hoof].physical.value,hoof)
		var residual: Array = Carrier.Bounds._matrix_values(world)
		var target: Array = Carrier.Bounds._matrix_values(s.targets[hoof].physical.value)
		for i: int in 12:
			var bound: Array = result.world_residual_bounds.hooves[hoof][i]
			assert_true(residual[i]-target[i] >= bound[0] and residual[i]-target[i] <= bound[1],hoof+" outward world residual")
	assert_false(result.physical_pass)
	assert_false(result.activation_pass)
	assert_eq(result.reconstruction_jets.status,"UNRESOLVED","four solved sole frames never prove material/branch jets")

func test_packet_rejects_raw_stale_sources_operations_frames_and_unknown_fields() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture()
	var p: Dictionary = _prepare(a,f).packet
	for field: String in ["rest","pose","operation","carrier","native_operation","model_from_skeleton","contacts","source_identity"]:
		var wrong: Dictionary = p.duplicate(true)
		if field == "model_from_skeleton": wrong[field].origin.y += .1
		else: wrong[field]["extra"] = 1
		var result: Dictionary = a.sample(f.rest,f.pose,f.op,wrong,"right")
		assert_false(result.ok,field)
		assert_eq(result.locals,{})
		assert_eq(result.diagnostics.reason,"stale_packet")
	var modified: Dictionary = f.pose.duplicate(true)
	modified.locals.root.origin.y += .1
	assert_eq(a.sample(f.rest,modified,f.op,p,"right").diagnostics.reason,"packet_input_mismatch")
	var op: Dictionary = f.op.duplicate(true)
	op.phase = .4
	assert_eq(a.sample(f.rest,f.pose,op,p,"right").diagnostics.reason,"packet_input_mismatch")
	assert_eq(a.sample(f.rest,f.pose,f.op,p,"middle").diagnostics.reason,"side")
	var cycle: Dictionary = p.duplicate(true)
	cycle.carrier["cycle"] = cycle
	assert_eq(a.sample(f.rest,f.pose,f.op,cycle,"right").diagnostics.reason,"packet_raw_type")
	cycle.carrier.erase("cycle")
	for raw: Variant in [null,[],{},1,Vector3.ZERO]:
		assert_false(a.sample(f.rest,f.pose,f.op,raw,"right").ok)
	f.F.basis.x = Vector3.ZERO
	assert_eq(_prepare(a,f).diagnostics.reason,"model_from_skeleton")

func test_full_physical_partition_C0_C1_support_parity_and_native_endpoint_fail_closed() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	for fault: String in ["gap","C0","C1","stance","parity","unknown","nonfinite","endpoint"]:
		var f: Dictionary = _fixture(1.0,true)
		var first: Dictionary = f.contacts["FrontHoof.L"].segments[0]
		var second: Dictionary = first.duplicate(true)
		first.end = .5; second.start = .5
		first.to = first.from; second.from = first.to
		f.contacts["FrontHoof.L"].segments = [first,second]
		match fault:
			"gap": second.start = .6
			"C0": second.from.origin.y += .01
			"C1": second.from_derivative.origin.y = 1
			"stance": second.mode = "stance"
			"parity": second.to.basis.x *= -1
			"unknown": second["extra"] = 1
			"nonfinite": second.to.origin.x = NAN
			"endpoint": second.to.origin.y += .1
		var p: Dictionary = _prepare(a,f)
		if fault == "endpoint":
			assert_true(p.ok)
			var result: Dictionary = a.sample(f.rest,f.pose,f.op,p.packet,"right")
			assert_false(result.ok)
			assert_eq(result.locals,{})
			assert_eq(result.diagnostics.reason,"FrontHoof.L:incompatible_native_endpoint")
		else: assert_false(p.ok,fault)

func test_nonrepresentable_targets_and_limits_retain_atomic_failure() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	for fault: String in ["far_target","joint_limit","bad_bind","root_frame","operation_identity"]:
		var f: Dictionary = _fixture(2.0,true)
		match fault:
			"far_target":
				for contact: Dictionary in f.contacts.values():
					contact.segments[0].from_derivative.origin.y = 1000.0
			"joint_limit":
				for chain: Dictionary in f.rest.chains.values(): chain.rotation_limits.fill(0.0)
			"bad_bind": f.rest.bones[0].bind_global.origin.y += .1
			"root_frame": f.pose.locals.root.origin.x = INF
			"operation_identity": f.native_op.turn_udeg += 1
		var p: Dictionary = _prepare(a,f)
		var result: Dictionary = a.sample(f.rest,f.pose,f.op,p.packet,"right") if p.ok else p
		assert_false(result.ok,fault)
		assert_eq(result.locals,{})

func test_legacy_segment_kernel_still_rejects_variable_carrier_endpoint_contact() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture(90.0,true)
	var result: Dictionary = Pivot.sample(f.rest,f.pose,f.op,f.contacts)
	assert_false(result.ok)
	assert_eq(result.locals,{})
	assert_true(str(result.diagnostics.reason).ends_with("incompatible_native_endpoint"))

func test_scalar_seat_kink_has_distinct_numerical_jets_and_identical_world_jet() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	# H=Translation_y(max(2u,-u)); C=(0,3,0), Y=I. At zero K_y=3,
	# K_y,u=+1 on the left and -2 on the right; world C_u=0 on both.
	var c: Transform3D = Transform3D(Basis.IDENTITY,Vector3(0,3,0))
	for rate: float in [-1.0,2.0]:
		var hu: Transform3D = Transform3D(_zero().basis,Vector3(0,rate,0))
		var inverse: Dictionary = a._inverse(Transform3D.IDENTITY,hu)
		var k: Dictionary = a._product(inverse.value,inverse.derivative,c,_zero())
		assert_eq(k.value.origin,c.origin)
		assert_eq(k.derivative.origin.y,-rate)
		var rebuilt: Dictionary = a._product(Transform3D.IDENTITY,hu,k.value,k.derivative)
		assert_eq(rebuilt.derivative,_zero())
		_close(rebuilt.value,c)
	# A kinked numerical stance is rejected by the UNCHANGED legacy validator.
	var zero: Transform3D = _zero()
	var first: Dictionary = {"start":0.0,"end":.5,"mode":"swing","from":c,"to":c,"from_derivative":zero,"to_derivative":zero}
	var second: Dictionary = first.duplicate(true)
	first.to_derivative.origin.y = 1
	second.start = .5; second.end = 1.0; second.from_derivative.origin.y = -2
	assert_eq(Pivot._validate_contact({"offset":Transform3D.IDENTITY,"segments":[first,second]}),"contact_C1_boundary")

func _stance_exit(f: Dictionary) -> void:
	var at: Dictionary = Carrier.sample(f.carrier,f.native_op,1.0,"left",f.carrier.sha256)
	var turn: Transform3D = Transform3D(Basis(f.rest.turn_axis,deg_to_rad(f.op.turn_degrees)),Vector3.ZERO)
	var locals: Dictionary = f.native.duplicate(true)
	var globals: Dictionary = Math._fk(f.rest.bones,locals)
	for hoof: String in Pivot._HOOVES:
		var contact: Dictionary = f.contacts[hoof]
		contact.segments[0].mode = "stance"
		contact.segments[0].to = contact.segments[0].from
		var chain: Dictionary = f.rest.chains[hoof]
		var first: Dictionary = Math._bone(f.rest.bones,chain.bones[0])
		var k: Transform3D = turn*(at.H*f.F).affine_inverse()*contact.segments[0].from
		var solved: Dictionary = Math._solve(f.rest,chain,locals,k,globals[first.parent],turn,contact.offset)
		assert_true(solved.ok,"hand control native exit must be representable: "+str(solved.get("reason")))
		if not solved.ok: return
		for name: String in chain.bones: locals[name] = solved.locals[name]
		globals = Math._fk(f.rest.bones,locals)
	f.pose.exit = locals

func test_actual_carrier_seat_switch_keeps_stance_physical_and_exposes_both_sides() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture(2.0,true)
	f.native_op.yaw0_udeg = 314000000
	f.op.start_heading = 314.0; f.op.end_heading = 316.0
	var p: Dictionary = f.carrier.placement.duplicate(true)
	p.extent = Vector2.ONE; p.ring = 4
	f.carrier = Carrier.prepare(p,f.carrier.terrain).packet
	f.contacts = _contacts(f)
	_stance_exit(f)
	var result: Dictionary = _sample(a,f)
	assert_true(result.ok,str(result.get("diagnostics")))
	if not result.ok: return
	var l: Dictionary = result.sides.left
	var r: Dictionary = result.sides.right
	assert_eq(l.carrier.H,r.carrier.H)
	assert_ne(l.carrier.H_S.origin.y,r.carrier.H_S.origin.y,"actual max footprint branches keep both derivatives")
	for hoof: String in Pivot._HOOVES:
		assert_eq(l.targets[hoof].physical.support,"stance")
		assert_eq(r.targets[hoof].physical.support,"stance")
		assert_eq(l.targets[hoof].physical.derivative,_zero())
		assert_ne(l.targets[hoof].K_u.origin,r.targets[hoof].K_u.origin)
		_close(l.targets[hoof].identity_reconstruction.derivative,_zero())
		_close(r.targets[hoof].identity_reconstruction.derivative,_zero())

func test_shared_pivot_boundary_uses_separate_durations_carriers_and_numerical_charts() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var first: Dictionary = _fixture(4.0,true)
	first.native_op.t1_q = BodyMotion.LOCOMOTION_Q/4
	first.op.phase = 1.0
	var second: Dictionary = _fixture(-3.0,true)
	second.native_op.t0_q = BodyMotion.LOCOMOTION_Q/4
	second.native_op.yaw0_udeg = 4000000
	second.op.start_heading = 4.0; second.op.end_heading = 1.0; second.op.phase = 0.0
	second.contacts = _contacts(second)
	var left: Dictionary = _sample(a,first,"left")
	var right: Dictionary = _sample(a,second,"right")
	assert_true(left.ok,str(left.get("diagnostics"))); assert_true(right.ok,str(right.get("diagnostics")))
	if not left.ok or not right.ok: return
	var l: Dictionary = left.sides.left
	var r: Dictionary = right.sides.right
	assert_eq(l.D,.25); assert_eq(r.D,.75)
	assert_eq(l.u,1.0); assert_eq(r.u,0.0)
	assert_eq(l.S,.25); assert_eq(r.S,.25)
	assert_eq(l.carrier.H,r.carrier.H)
	assert_ne(l.Y,r.Y)
	assert_ne(l.H_k_u,r.H_k_u)
	for hoof: String in Pivot._HOOVES:
		_close(l.targets[hoof].physical.value,r.targets[hoof].physical.value)
		assert_ne(l.targets[hoof].K,r.targets[hoof].K)
		_close(l.targets[hoof].identity_reconstruction.derivative,r.targets[hoof].identity_reconstruction.derivative)
		# Actual solved finite endpoint affines agree; derivative certification stays
		# unresolved until actual solved sole/material jet bounds are supplied.
		_close(l.H_k*Math._fk(first.rest.bones,left.locals)[hoof],r.H_k*Math._fk(second.rest.bones,right.locals)[hoof])
	assert_eq(left.reconstruction_jets.status,"UNRESOLVED")
	assert_eq(right.reconstruction_jets.status,"UNRESOLVED")

func test_fixed_R1_affine_and_sole_offsets_are_preserved_at_native_endpoints() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture(-7.0,true)
	f.F = Transform3D(Basis(Vector3(-2,0,0),Vector3(.1,3,0),Vector3(.2,.3,4)),Vector3(.4,-.3,.2))
	f.contacts = _contacts(f)
	for hoof: String in Pivot._HOOVES:
		var offset: Transform3D = Transform3D(Basis(Vector3.RIGHT,.2),Vector3(.1,-.2,.3))
		f.contacts[hoof].offset = offset
		for segment: Dictionary in f.contacts[hoof].segments:
			segment.from *= offset; segment.to *= offset
	for u: float in [0.0,1.0]:
		f.op.phase = u
		var result: Dictionary = _sample(a,f)
		assert_true(result.ok,str(result.get("diagnostics")))
		if result.ok: assert_eq(result.locals,f.native)

func test_actual_R1_59_bone_native_affines_and_measured_soles_without_physical_authority() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var calibration: Resource = load("res://assets/3D/units/royal/royal_locomotion_source.tres")
	var capture: Dictionary = calibration.extract()
	assert_true(capture.ok,str(capture.get("diagnostics")))
	if not capture.ok: return
	var source: Dictionary = capture.source
	var native: Dictionary = Map3DRoyalLocomotionSource.sample(source,source.identity,.37)
	assert_true(native.ok,str(native.get("diagnostics")))
	if not native.ok: return
	var f: Dictionary = _fixture(0.000001,true)
	var bones: Array = []
	var inverse_binds: Dictionary = {}
	for bind: Dictionary in source.binds:
		inverse_binds[bind.name] = source.model_from_skeleton.affine_inverse()*source.model_from_mesh*bind.inverse_bind.affine_inverse()
	for bone: Dictionary in source.bones:
		var landmark: Dictionary = source.calibration.landmarks[bone.name]
		bones.append({"name":bone.name,"parent":"" if bone.parent == -1 else source.bones[bone.parent].name,
			"bind":bone.rest,"bind_global":inverse_binds[bone.name],"head":landmark.head,"tail":landmark.tail})
	var factory: GutTest = Fixtures.new()
	var chains: Dictionary = {}
	for hoof: String in Pivot._HOOVES: chains[hoof] = factory._chain(Pivot._names(hoof),bones)
	factory.free()
	# PI controls exercise numerical source compatibility only. The accepted R1
	# retains actual royal anatomical limits/support as unresolved prerequisites.
	f.rest = {"version":1,"turn_axis":Vector3.UP,"bones":bones,"chains":chains}
	f.native = native.locals
	f.pose = {"locals":native.locals.duplicate(true),"entry":native.locals.duplicate(true),"exit":native.locals.duplicate(true)}
	f.F = source.model_from_skeleton
	f.identity = {"source_sha256":source.sha256,"reference_sha256":Carrier._digest(native.locals)}
	f.contacts = _contacts(f)
	for hoof: String in Pivot._HOOVES:
		var offset: Transform3D = source.calibration.sole_patches[hoof].bone_from_sole
		f.contacts[hoof].offset = offset
		for segment: Dictionary in f.contacts[hoof].segments:
			segment.from *= offset; segment.to *= offset
	for u: float in [0.0,.5,1.0]:
		f.op.phase = u
		var result: Dictionary = _sample(a,f)
		assert_true(result.ok,str(result.get("diagnostics")))
		if not result.ok: continue
		assert_eq(result.locals.size(),59)
		assert_eq(a._restrictions(f.rest,native.locals,result.locals),"")
		if u != .5: assert_eq(result.locals,native.locals)
		assert_false(result.physical_pass)
	assert_eq(calibration.contact_authority,"UNRESOLVED")
	assert_true(calibration.support_intervals.is_empty())

func test_world_residual_bounds_do_not_erase_scale_amplification() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture()
	var p: Dictionary = f.carrier.placement.duplicate(true)
	p.k = 100.0; p.extent = Vector2.ZERO
	f.carrier = Carrier.prepare(p,f.carrier.terrain).packet
	var at: Dictionary = Carrier.sample(f.carrier,f.native_op,.5,"right",f.carrier.sha256)
	assert_true(at.ok)
	var globals: Dictionary = Math._fk(f.rest.bones,f.native)
	var targets: Dictionary = {}
	for hoof: String in Pivot._HOOVES:
		var world: Transform3D = at.H*globals[hoof]
		world.origin.y -= .0009
		targets[hoof] = {"physical":{"value":world}}
	var bounded: Dictionary = a._world_bounds(f.rest,f.native,Transform3D.IDENTITY,at,targets,f.contacts)
	assert_true(bounded.ok)
	for hoof: String in Pivot._HOOVES:
		var bound: Array = bounded.hooves[hoof][7]
		assert_gt(bound[1],.0008,"world amplification retained; EPS is never physical E")
		assert_false(bounded.has("physical_pass"))

func test_accepted_carrier_copied_metadata_survives_without_native_authority_fabrication() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture()
	var p: Dictionary = f.carrier.placement.duplicate(true)
	# The accepted admission packet stores packed land grids and source metadata.
	p.identity["copied"] = {"closed":PackedByteArray([0,1]),"water":PackedByteArray([1,0]),
		"names":PackedStringArray(["copied"]),"optional":null}
	f.carrier = Carrier.prepare(p,f.carrier.terrain).packet
	assert_true(_prepare(a,f).ok)
	var terrain: Dictionary = f.carrier.terrain.duplicate(true)
	terrain.kind = "native"; terrain.identity["method_bound"] = false
	f.carrier = Carrier.prepare(p,terrain).packet
	var result: Dictionary = _sample(a,f)
	assert_false(result.ok,"missing native binary/method evidence never becomes a control pass")
	assert_eq(result.locals,{})
	assert_true(str(result.diagnostics.reason).begins_with("carrier:"))


func test_carrier_R1_source_identity_must_match_the_packet_source() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	var f: Dictionary = _fixture()
	var p: Dictionary = f.carrier.placement.duplicate(true)
	p.identity["r1"] = {"source_sha256":f.identity.source_sha256}
	f.carrier = Carrier.prepare(p,f.carrier.terrain).packet
	assert_true(_prepare(a,f).ok)
	f.identity.source_sha256 = "different-source"
	assert_eq(_prepare(a,f).diagnostics.reason,"carrier_source_identity")
	p.identity.r1 = 1
	f.carrier = Carrier.prepare(p,f.carrier.terrain).packet
	assert_eq(_prepare(a,f).diagnostics.reason,"carrier_source_identity")

func test_fractional_integer_heading_half_turn_and_wrap_keep_exact_operation_identity() -> void:
	var a: GDScript = _adapter()
	if a == null: return
	# Literal accepted239 control, then positive/negative wrap controls. Endpoints
	# are converted from committed integers, never recomputed with a float sum.
	for row: Array in [[76000012,180000000,256000012],[256000012,180000000,76000012],
		[359000012,2000000,1000012],[1000012,-2000000,359000012]]:
		var f: Dictionary = _fixture()
		f.native_op.yaw0_udeg = row[0]; f.native_op.turn_udeg = row[1]
		f.op.start_heading = float(row[0])/1000000.0
		f.op.turn_degrees = float(row[1])/1000000.0
		f.op.end_heading = float(row[2])/1000000.0
		assert_eq(Pivot._validate_operation(f.op),"")
		assert_true(Carrier._op_ok(f.native_op))
		assert_true(_prepare(a,f).ok,str(row))
		f.op.end_heading += .000001
		assert_false(_prepare(a,f).ok,"different committed endpoint remains rejected")
