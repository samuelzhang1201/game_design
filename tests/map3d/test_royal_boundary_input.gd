extends GutTest
## Boundary constraints only; no provider, policy, contact or activation acceptance.
const Bounds = preload("res://scripts/map3d/map3d_royal_carrier_bounds.gd")

func _api() -> GDScript:
	var path: String = "res://scripts/map3d/map3d_royal_boundary_input.gd"
	return load(path) if FileAccess.file_exists(path) else null

func _hand_side(kind: String, rate: float, duration: float, jet: float) -> Dictionary:
	var h: Array = []
	var hs: Array = []
	var m: Array = []
	var ms: Array = []
	for row: int in 3:
		for col: int in 4:
			var value: float = 1.0 if row == col else 0.0
			h.append([value,value]); hs.append([0.0,0.0])
			m.append([value,value]); ms.append([0.0,0.0])
	hs[3] = [rate,rate]
	ms[3] = [jet,jet]
	return {"kind":kind,"duration":duration,"H":h,"H_S":hs,"soles":{"hoof":{"value":m,"derivative":ms}},
		"materials":[{"value":[[1.0,1.0],[0.0,0.0],[0.0,0.0]],"derivative":[[jet,jet],[0.0,0.0],[0.0,0.0]]}]}

func test_shared_native_pivot_table_and_unequal_duration_chain_rule() -> void:
	var api: GDScript = _api()
	if api == null: return
	for kinds: Array in [["native","pivot",2.0],["pivot","native",6.0],["pivot","pivot",4.0]]:
		var left: Dictionary = _hand_side(kinds[0],2.0,.125,0.0)
		var right: Dictionary = _hand_side(kinds[1],6.0,.375,0.0)
		var shared: Dictionary = api._targets(left,right)
		assert_true(shared.ok,str(shared))
		if not shared.ok: continue
		assert_almost_eq(shared.materials[0][0][0],kinds[2],1e-12)
		assert_lte(shared.world_value.materials[0][0][0],1.0)
		assert_gte(shared.world_value.materials[0][0][1],1.0)
		for side: Dictionary in [left,right]:
			var constraint: Dictionary = api._constraints(side,shared)
			assert_true(constraint.ok,str(constraint))
			if not constraint.ok: continue
			var expected: float = side.duration*(kinds[2]-side.H_S[3][0])
			assert_lte(constraint.materials[0][0][0],expected)
			assert_gte(constraint.materials[0][0][1],expected)
			assert_lte(constraint.soles.hoof[3][0],expected)
			assert_gte(constraint.soles.hoof[3][1],expected)
	assert_false(api._targets(_hand_side("native",2.0,.1,0.0),_hand_side("native",6.0,.1,0.0)).ok)

func test_rotating_scaled_carrier_subtracts_before_inverse() -> void:
	var api: GDScript = _api()
	if api == null: return
	var side: Dictionary = _hand_side("pivot",0.0,.1,0.0)
	# H=2*R90; H_S*p=(0,2,0), world target=(0,4,0).
	side.H = [[0.,0.],[-2.,-2.],[0.,0.],[7.,7.],[2.,2.],[0.,0.],[0.,0.],[8.,8.],[0.,0.],[0.,0.],[2.,2.],[9.,9.]]
	side.H_S[7] = [2.0,2.0]
	var target: Dictionary = {"materials":[[[0.,0.],[4.,4.],[0.,0.]]],"soles":{"hoof":side.H_S}}
	var result: Dictionary = api._constraints(side,target)
	assert_true(result.ok,str(result))
	if not result.ok: return
	assert_lte(result.materials[0][0][0],.1)
	assert_gte(result.materials[0][0][1],.1)
	assert_almost_eq(result.materials[0][1][0],0.0,1e-12)

func test_detached_boundary_builder_exists() -> void:
	var path: String = "res://scripts/map3d/map3d_royal_boundary_input.gd"
	assert_true(FileAccess.file_exists(path), "accepted239 copied boundary builder exists")
	if not FileAccess.file_exists(path): return
	var api: GDScript = load(path)
	assert_true(api.has_method("prepare"))
	assert_true(api.new().has_method("build"))

const SuiteData = preload("res://tests/suite_data.gd")
const Personnel = preload("res://tests/engine/personnel_helpers.gd")
const Carrier = preload("res://scripts/map3d/map3d_royal_upright_carrier.gd")
const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const Phase = preload("res://scripts/map3d/map3d_royal_reference_phase.gd")
const Q: int = BodyMotion.LOCOMOTION_Q
var _arithmetic: Dictionary
var _native_component: Dictionary
var _native: Dictionary
var _control: Dictionary
var _builder: RefCounted
var _builder_identity: Dictionary
var _placement: Dictionary
var _projections: Array

func before_all() -> void:
	var api: GDScript = _api()
	if api == null: return
	var scratch: String = ProjectSettings.globalize_path("res://.godot/boundary-math-"+str(ResourceUID.create_id()))
	var output: Array = []
	var status: int = OS.execute("python3",[ProjectSettings.globalize_path("res://tools/units3d/royal_native_arithmetic/prove.py"),"--capture",OS.get_executable_path(),"--scratch",scratch,"--receipt",scratch+"-receipt.json"],output,true)
	assert_eq(status,0,str(output))
	if status != 0: return
	output.clear()
	status = OS.execute("python3",["-c","import json,sys;print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True,separators=(',',':'),allow_nan=False))",scratch.path_join("capture.json")],output,true)
	assert_eq(status,0)
	if status != 0: return
	_arithmetic = {"receipt":JSON.parse_string(FileAccess.get_file_as_string(scratch+"-receipt.json")),"capture_canonical":str(output[0]).strip_edges()}
	var calibration: Resource = load("res://assets/3D/units/royal/royal_locomotion_source.tres")
	var extracted: Dictionary = calibration.extract()
	assert_true(extracted.ok,str(extracted.get("diagnostics",{})))
	if not extracted.ok: return
	_native = extracted.source
	_control = _literal_source()
	var prepared: Dictionary = api.prepare(_control,_control.identity,_arithmetic,_config())
	assert_true(prepared.ok,str(prepared.get("reason"))+str(prepared.get("witness",{})))
	if not prepared.ok: return
	_builder = prepared.authority
	_builder_identity = prepared.identity
	_placement = _carrier_packet()
	_projections = _commits(90,[[50,0],[50,0]],[100,100])
	print("ROYAL_BOUNDARY_INPUT native=",_native.sha256," arithmetic=",_arithmetic.receipt.sha256)

func after_each() -> void:
	MarchPath.forget()

func _config() -> Dictionary:
	return {"time_day_seconds":5.0,"battle_substeps":10,"identity":{"fixture":"frozen transaction config"}}

func _literal_source() -> Dictionary:
	var animation := Animation.new()
	animation.length = .5
	animation.loop_mode = Animation.LOOP_LINEAR
	var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track,NodePath("Skeleton3D:hoof"))
	animation.position_track_insert_key(track,0.0,Vector3.ZERO)
	animation.position_track_insert_key(track,.5,Vector3.ZERO)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(1,0,0)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([.75,0,0,0])
	var source := {"animation":animation,"tracks":[{"bone":0,"type":Animation.TYPE_POSITION_3D,"enabled":true}],
		"bones":[{"name":"hoof","parent":-1,"rest":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Quaternion.IDENTITY,"scale":Vector3.ONE}],
		"binds":[{"bone":0,"inverse_bind":Transform3D.IDENTITY}],"surfaces":[{"arrays":arrays}],
		"model_from_skeleton":Transform3D(Basis.IDENTITY,Vector3(7,8,9)),"calibration":{"sole_patches":{"hoof":{"bone_from_sole":Transform3D.IDENTITY,"surface":0,"vertices":PackedInt32Array([0])}}},
		"identity":{"godot":Engine.get_version_info(),"fixture":"literal raw-weight control"}}
	source.sha256 = Source._source_digest(source)
	source.identity["source_sha256"] = source.sha256
	return source

func _carrier_packet() -> Dictionary:
	var heights := PackedFloat32Array(); heights.resize(16); heights.fill(0.0)
	var controls := PackedInt32Array(); controls.resize(16); controls.fill(0)
	var placement := {"origin":Vector2(25,25),"alpha":1.0,"k":1.0,"extent":Vector2(.1,.1),"height":2.0,"clear":.05,"sink":0.0,"ring":4,"ancestor":Transform3D.IDENTITY,"identity":{"fixture":"analytic plane"}}
	var terrain := {"kind":"control","spacing":1000.0,"sea":-100.0,"region_size":4,"regions":{Vector2i.ZERO:{"height":heights,"control":controls}},"identity":{"fixture":"flat control"}}
	var result: Dictionary = Carrier.prepare(placement,terrain)
	assert_true(result.ok)
	return result.packet

func _commits(facing: int, legs: Array, budgets: Array, day_cross: bool = false, start: Array = [100,100], first_day: int = 70) -> Array:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo,319)
	var codes: Array = state.regiments.keys(); codes.sort()
	var code: String = ""
	for candidate: String in codes:
		if MapObjects.army_piece(repo,state.army_roster[candidate]) == "royal": code = candidate; break
	assert_ne(code,"")
	if code.is_empty(): return []
	assert_false(Personnel.replace(repo,state,code,100).has("error"))
	state.regiments = {code:state.regiments[code]}; state.army_roster = {code:state.army_roster[code]}
	state.foes = {}; state.battles = []; state.military_rosters = {code:state.military_rosters[code]}
	var cohorts: Dictionary = {}
	for id: String in state.military_rosters[code].cohort_ids: cohorts[id] = state.military_cohorts[id]
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	state.regiments[code].group_next_slot = 1
	state.regiments[code].body_groups = [{"slot":0,"home_slot":0,"count":100,"x_m":start[0],"y_m":start[1],"role":"front","facing_deg":facing,"path_m":[]}]
	var piece: String = MapObjects.army_piece(repo,state.army_roster[code])
	repo.unit_footprints[piece] = {"radius_m":10,"pitch_m":40,"width_m":180,"depth_m":60,"files":5,"ranks":2,
		"locomotion_certificate":{"digest":"a".repeat(64),"turn_q":Q,"contact_um":100,"radius_m":10,"clips":["PIVOT_LEFT","PIVOT_RIGHT","MARCH"],"all_turns":true}}
	repo.balance["body_locomotion_"+piece+"_turn_q"] = Q
	repo.balance["body_locomotion_"+piece+"_contact_um"] = 100
	repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray(); slopes.resize(10000)
	MarchPath.use(repo,MarchPath.build(repo,100,100,maxi(10,ceili(float(maxi(start[0],start[1])+1000)/90.0)),slopes))
	assert_eq(UnitBodies.migrate_candidate(repo,state).status,"complete")
	var out: Array = []
	for i: int in legs.size():
		var row: Dictionary = state.regiments[code].body_groups[0]
		var intent := {"unit":code,"slot":0,"path_m":[[row.x_m,row.y_m],[row.x_m+legs[i][0],row.y_m+legs[i][1]]],"budget_m":budgets[i],"hostile":false}
		var plan: Dictionary = BodyMotion.plan_locomotion_candidate(repo,state,[intent],first_day+i if day_cross else first_day,0 if day_cross else i)
		assert_true(BodyMotion._loco_plan_ok(plan),str(plan))
		if not BodyMotion._loco_plan_ok(plan): return []
		var committed: Dictionary = BodyMotion.commit_locomotion_candidate(repo,state,plan)
		assert_eq(committed.status,"complete",str(committed.get("reason")))
		if committed.status != "complete": return []
		state = committed.candidate
		var saved: Dictionary = state.military_migration.body_motion.duplicate(true)
		out.append({"saved":saved,"admission":{"unit":code,"slot":"0","receipt":saved.receipt,"piece":piece,"substep_count":1 if day_cross else 10,
			"classification":"production_bound","identity":{"caller":"actual accepted fixture commit","source":plan.cursor.basis.result},"future_authorized":true},"carrier":_placement})
	return out

func _request(projections: Array, receipt_index: int = 0, op_index: int = 2) -> Dictionary:
	return {"unit":projections[receipt_index].admission.unit,"slot":"0","receipt":projections[receipt_index].saved.receipt,"op_index":op_index,
		"initial_native_phase":null,"identity":_builder_identity,"shared":{"entry":{},"exit":{}}}

func test_two_actual_complete_schedules_commute_json_and_sample_order() -> void:
	if _builder == null or _projections.size() != 2: return
	var left: Dictionary = _builder.build(_projections,_request(_projections))
	assert_true(left.ok,str(left.get("reason")))
	if not left.ok: return
	var right: Dictionary = _builder.build(_projections,_request(_projections,1,0))
	assert_true(right.ok,str(right.get("reason")))
	if not right.ok: return
	assert_eq(Carrier._digest(left.prepared.exit.shared),Carrier._digest(right.prepared.entry.shared))
	assert_eq(left.prepared.exit.shared.branch,"pivot/pivot")
	assert_eq(left.prepared.exit.shared.left.material_points,[{"surface":0,"vertex":0,"patches":["hoof"]}])
	assert_eq(left.prepared.exit.shared.left.native.positions[0][0].x,7.75,"raw sum=.75 and model translation once")
	assert_eq(left.prepared.classification,"proof_domain_control")
	assert_false(left.prepared.motion_join_claim)
	var reversed: Array = _projections.duplicate(); reversed.reverse()
	assert_eq(Carrier._digest(_builder.build(reversed,_request(_projections,1,0)).prepared.entry.shared),Carrier._digest(left.prepared.exit.shared))
	var restored: Array = _projections.duplicate(true)
	for p: Dictionary in restored:
		p.saved = JSON.parse_string(JSON.stringify(p.saved)); p.admission = JSON.parse_string(JSON.stringify(p.admission))
	var json_result: Dictionary = _builder.build(restored,JSON.parse_string(JSON.stringify(_request(_projections))))
	assert_true(json_result.ok,str(json_result.get("reason")))
	if json_result.ok: assert_eq(Carrier._digest(json_result.prepared),Carrier._digest(left.prepared))
	for ignored_speed: int in [0,1,4,4,1]:
		assert_eq(_builder.build(_projections,_request(_projections)).prepared.sha256,left.prepared.sha256,"identical envelope across pause/FPS/skipped frames")

	var transferred: Array = _projections.duplicate(true)
	for p: Dictionary in transferred: p.admission.identity["owner"] = "new admitted owner"
	var transfer_result: Dictionary = _builder.build(transferred,_request(transferred))
	assert_true(transfer_result.ok)
	if transfer_result.ok:
		assert_eq(transfer_result.prepared.exit.shared.right.phase.phase_identity,left.prepared.exit.shared.right.phase.phase_identity)
		assert_eq(transfer_result.prepared.exit.shared.target,left.prepared.exit.shared.target)
	var adopted: Dictionary = _request(_projections)
	adopted.initial_native_phase = left.prepared.entry.shared.right.phase.phase
	assert_eq(_builder.build(_projections,adopted).prepared.sha256,left.prepared.sha256)

func test_mirrored_same_sign_and_unequal_duration_day_seam_schedules() -> void:
	if _builder == null: return
	for item: Array in [[270,[[50,0],[50,0]],[100,100],false],[90,[[50,0],[-50,0]],[100,100],false],[90,[[10,10],[7,-7]],[20,40],true]]:
		var projections: Array = _commits(item[0],item[1],item[2],item[3])
		if projections.size() != 2: continue
		var config: Dictionary = _config()
		if item[3]: config.battle_substeps = 1; config.time_day_seconds = .5
		var prepared: Dictionary = _api().prepare(_control,_control.identity,_arithmetic,config)
		assert_true(prepared.ok)
		if not prepared.ok: continue
		var request: Dictionary = _request(projections); request.identity = prepared.identity
		var left: Dictionary = prepared.authority.build(projections,request)
		assert_true(left.ok,str(left.get("reason")))
		if not left.ok: continue
		request = _request(projections,1,0); request.identity = prepared.identity
		var right: Dictionary = prepared.authority.build(projections,request)
		assert_true(right.ok,str(right.get("reason")))
		if not right.ok: continue
		assert_eq(Carrier._digest(left.prepared.exit.shared),Carrier._digest(right.prepared.entry.shared))
		if item[3]:
			assert_eq(left.prepared.exit.shared.left.duration,.125)
			assert_eq(left.prepared.exit.shared.right.duration,.375)
			assert_almost_eq(left.prepared.exit.shared.left.carrier.yaw_S,-TAU,.000001)
			assert_almost_eq(left.prepared.exit.shared.right.carrier.yaw_S,TAU,.000001)

func _rejects(result: Dictionary, reason: String = "") -> void:
	assert_false(result.ok,str(result.get("reason")))
	assert_eq(result.get("prepared",{}),{})
	if not reason.is_empty(): assert_eq(result.get("reason","unexpected_success"),reason)

func test_every_operation_receipt_admission_and_missing_neighbor_rejects_atomically() -> void:
	assert_not_null(_builder)
	if _builder == null: return
	var request: Dictionary = _request(_projections)
	_rejects(_builder.build([_projections[0]],request),"UNAVAILABLE_NEIGHBOR")
	for key: String in _projections[0].saved.plan.moves[0].ops[0]:
		var changed: Array = _projections.duplicate(true)
		changed[0].saved.plan.moves[0].ops[0].erase(key)
		_rejects(_builder.build(changed,request),"receipt_or_partition")
	for key: String in ["receipt","unit","slot","piece","identity","future_authorized","classification","substep_count"]:
		var changed: Array = _projections.duplicate(true)
		changed[0].admission.erase(key)
		_rejects(_builder.build(changed,request))
	var changed: Array = _projections.duplicate(true)
	changed[0].admission.piece = "infantry"
	_rejects(_builder.build(changed,request),"nonroyal_admission")
	changed[0].admission.piece = "royal"
	changed[0].admission.future_authorized = false
	_rejects(_builder.build(changed,request),"unobserved_hostile_future")
	changed[0].admission.future_authorized = true
	changed[0].admission.classification = "endpoint_only"
	_rejects(_builder.build(changed,request),"endpoint_only")
	changed = _projections.duplicate(true)
	changed[1].saved.receipt = "0".repeat(64)
	_rejects(_builder.build(changed,request),"receipt_or_partition")
	changed = _projections.duplicate(true)
	changed[1].admission.substep_count = 10.5
	_rejects(_builder.build(changed,request),"substep_count")
	for field: String in request:
		var bad: Dictionary = request.duplicate(true); bad.erase(field)
		_rejects(_builder.build(_projections,bad),"request_schema")
	var wrong_row: Dictionary = request.duplicate(true)
	wrong_row.unit += "missing"
	_rejects(_builder.build(_projections,wrong_row),"admission_mismatch")
	wrong_row = request.duplicate(true); wrong_row.op_index = 1
	_rejects(_builder.build(_projections,wrong_row),"current_not_pivot")
	wrong_row = request.duplicate(true); wrong_row.initial_native_phase = .73
	_rejects(_builder.build(_projections,wrong_row),"initial_native_phase_mismatch")
	wrong_row = request.duplicate(true); wrong_row.identity.source.source_sha256 = "stale"
	_rejects(_builder.build(_projections,wrong_row),"stale_component_identity")

	var cyclic: Dictionary = request.duplicate(true)
	cyclic.shared.exit["self"] = cyclic.shared.exit
	_rejects(_builder.build(_projections,cyclic),"shared_boundary_mismatch")
	cyclic.shared.exit.clear()
	changed = _projections.duplicate(true); changed[0].carrier.placement.identity["object"] = RefCounted.new()
	_rejects(_builder.build(changed,request),"projection_schema")

func test_shared_duplicates_stale_carrier_source_and_domain_cannot_reuse_a_packet() -> void:
	assert_not_null(_builder)
	if _builder == null: return
	var request: Dictionary = _request(_projections)
	var result: Dictionary = _builder.build(_projections,request)
	assert_true(result.ok,str(result.get("reason")))
	if not result.ok: return
	request.shared.exit = result.prepared.exit.shared.duplicate(true)
	assert_true(_builder.build(_projections,request).ok)
	for field: String in ["left","right","left_id","right_id","placement_identity","terrain_identity","target","sha256","branch"]:
		var bad: Dictionary = request.duplicate(true); bad.shared.exit.erase(field)
		_rejects(_builder.build(_projections,bad),"shared_boundary_mismatch")
	var changed: Array = _projections.duplicate(true)
	changed[1].carrier.placement.k += .01
	_rejects(_builder.build(changed,request),"stale_carrier")
	for kind: String in ["missing","override"]:
		changed = _projections.duplicate(true)
		changed[1].carrier.terrain.kind = kind
		changed[1].carrier = Carrier.prepare(changed[1].carrier.placement,changed[1].carrier.terrain).packet
		_rejects(_builder.build(changed,request),"carrier_branch")
	changed = _projections.duplicate(true)
	changed[1].carrier.placement.identity["r1"] = {"source_sha256":"stale"}
	changed[1].carrier = Carrier.prepare(changed[1].carrier.placement,changed[1].carrier.terrain).packet
	_rejects(_builder.build(changed,request),"carrier_source_mismatch")
	assert_eq(result.prepared.sha256,_builder.build(_projections,_request(_projections)).prepared.sha256,"failures do not mutate prior packet or authority")

	var relabelled: Dictionary = request.duplicate(true)
	relabelled.shared.exit.left.kind = "native"
	_rejects(_builder.build(_projections,relabelled),"shared_boundary_mismatch")
	var swapped: Dictionary = request.duplicate(true)
	var old_left: Dictionary = swapped.shared.exit.left_id
	swapped.shared.exit.left_id = swapped.shared.exit.right_id
	swapped.shared.exit.right_id = old_left
	_rejects(_builder.build(_projections,swapped),"shared_boundary_mismatch")

func _prepare_native() -> Dictionary:
	if _native_component.is_empty(): _native_component = _api().prepare(_native,_native.identity,_arithmetic,_config())
	return _native_component

func test_r1_component_receipts_and_whole_phase_domain_are_mandatory() -> void:
	assert_false(_native.is_empty())
	if _native.is_empty(): return
	var api: GDScript = _api()
	for field: String in ["sha256","capture_sha256","verifier_sha256"]:
		var bad: Dictionary = _arithmetic.duplicate(true); bad.receipt[field] = "0".repeat(64)
		_rejects(api.prepare(_native,_native.identity,bad,_config()),"native_component")
	var prepared: Dictionary = _prepare_native()
	assert_true(prepared.ok,str(prepared.get("reason")))
	if not prepared.ok: return
	var domain: Dictionary = prepared.authority._jets.domain()
	assert_true(domain.complete_phase_domain)
	assert_eq(domain.phase,[0.0,1.0])
	assert_eq(domain.source_sha256,_native.sha256)
	assert_eq(domain.arithmetic_sha256,_arithmetic.receipt.sha256)
	assert_eq(domain.vertex_count,_native.surfaces[0].arrays[Mesh.ARRAY_VERTEX].size())
	var expected_points: Dictionary = {}
	for patch: Dictionary in _native.calibration.sole_patches.values():
		for vertex: int in patch.vertices: expected_points[str(patch.surface)+":"+str(vertex)] = true
	assert_eq(prepared.authority._material_points.size(),expected_points.size())
	assert_lt(prepared.authority._material_points.size(),domain.vertex_count,"all contact patch vertices; full mesh native evidence stays intact")
	var copied: Array = _projections.duplicate(true)
	var request: Dictionary = _request(copied); request.identity = prepared.identity
	var result: Dictionary = prepared.authority.build(copied,request)
	# This has actual native jets, but analytic terrain cannot become native coverage.
	assert_true(result.ok,str(result.get("reason")))
	if result.ok:
		assert_eq(result.prepared.classification,"proof_domain_control")
		assert_eq(result.prepared.domain.native.sha256,domain.sha256)
		assert_false(result.prepared.motion_join_claim)
	print("ROYAL_BOUNDARY_NATIVE_RESULT ",result.get("reason","constraints_only")," domain=",domain.sha256)

func test_one_quantum_full_duration_turn_seams_and_large_rates_are_not_clamped() -> void:
	assert_false(_placement.is_empty())
	if _placement.is_empty(): return
	var api: GDScript = _api()
	for pair: Array in [[0,1],[0,-1],[0,179999999],[0,-179999999],[76000012,180000000],[350000000,20000000],[10000000,-20000000]]:
		for duration: int in [1,Q]:
			var op: Dictionary = BodyMotion._loco_op("pivot",0,duration,[100,100],[100,100],pair[0],pair[1])
			for u: float in [0.0,1.0]:
				var carrier: Dictionary = Carrier.sample(_placement,op,u,"right" if u == 0.0 else "left",_placement.sha256)
				assert_true(carrier.ok,str(carrier.get("reason")))
				if not carrier.ok: continue
				var expected: float = -float(pair[1])*PI/180000000.0*float(Q)/float(duration)
				assert_almost_eq(carrier.yaw_S,expected,absf(expected)*1e-12+1e-12)
				var side: Dictionary = _hand_side("pivot",0.0,float(duration)/Q,0.0)
				side.H = carrier.enclosures.H; side.H_S = carrier.enclosures.H_S
				var target: Dictionary = api._targets(side,side)
				var constrained: Dictionary = api._constraints(side,target)
				assert_true(constrained.ok,str(constrained.get("reason")))
				assert_lte(constrained.materials[0][0][0],0.0)
				assert_gte(constrained.materials[0][0][1],0.0)
	var singular: Dictionary = _hand_side("pivot",0.0,.1,0.0)
	singular.H[0] = [0.,0.]
	_rejects(api._constraints(singular,{"soles":{},"materials":[]}),"singular_carrier")

func test_returned_jets_with_exact_endpoint_values_cannot_fake_C1() -> void:
	assert_not_null(_builder)
	if _builder == null: return
	var result: Dictionary = _builder.build(_projections,_request(_projections))
	assert_true(result.ok)
	if not result.ok: return
	var solved := {"entry":{"soles":{},"materials":[]},"exit":{"soles":{},"materials":[]}}
	for end: String in ["entry","exit"]:
		var shared: Dictionary = result.prepared[end].shared
		var side: Dictionary = shared.right if end == "entry" else shared.left
		for category: String in ["soles","materials"]:
			var keys: Array = side[category].keys() if category == "soles" else range(side[category].size())
			for key: Variant in keys:
				var jet := {"value":side[category][key].value.duplicate(true),"derivative":result.prepared[end].constraints[category][key].duplicate(true)}
				if category == "soles": solved[end][category][key] = jet
				else: solved[end][category].append(jet)
	_rejects(_builder.check_output(result.prepared,solved),"UNRESOLVED")
	var bad: Dictionary = solved.duplicate(true)
	bad.exit.materials[0].derivative[0] = [1000000.,1000000.]
	_rejects(_builder.check_output(result.prepared,bad),"solved_boundary_jet_mismatch")
	bad = result.prepared.duplicate(true); bad.binding.op.turn_udeg += 1
	_rejects(_builder.check_output(bad,solved),"stale_prepared")
	bad = solved.duplicate(true); bad.entry.soles.hoof.derivative[0] = [NAN,NAN]
	_rejects(_builder.check_output(result.prepared,bad),"solved_schema")

	bad = result.prepared.duplicate(true); bad.exit = {}
	bad.erase("sha256"); bad["sha256"] = Carrier._digest(bad)
	_rejects(_builder.check_output(bad,solved),"prepared_schema")

func test_direct_native_arguments_preserve_all_keys_offkeys_and_seam_sides() -> void:
	assert_false(_native.is_empty())
	if _native.is_empty(): return
	var prepared: Dictionary = _prepare_native()
	assert_true(prepared.ok)
	if not prepared.ok: return
	var native: RefCounted = prepared.authority
	var times: Array[float] = [0.0,_native.animation.length*.73,_native.animation.length*.3123456789,_native.animation.length]
	for track: int in _native.animation.get_track_count():
		for key: int in _native.animation.track_get_key_count(track):
			var time: float = _native.animation.track_get_key_time(track,key)
			if not times.has(time): times.append(time)
	for time: float in times:
		for side: String in ["left","right"]:
			if time == _native.animation.length and side == "right": continue
			var phase := {"native_time":time,"phase_numerator":"0" if time == 0.0 else "1","classification":"proof_domain_control"}
			var sample: Dictionary = native._native_sample(phase,side)
			assert_true(sample.ok,str(sample.get("reason")))
			if not sample.ok: continue
			var expected: Dictionary = native._jets._native(sample.lookup_time)
			assert_eq(sample.locals,expected.locals)
			assert_eq(sample.positions[0][0],expected.positions[0][0])
			assert_eq(sample.domain_sha256,native._jets.domain().sha256)
			assert_eq(sample.affine_jets.skin.size(),_native.binds.size())
			var material: Dictionary = sample.material_jets[0]
			for axis: int in 3:
				assert_lte(material.extension_lower[axis]-material.native_error_uniform[axis],float(expected.positions[0][0][axis]))
				assert_gte(material.extension_upper[axis]+material.native_error_uniform[axis],float(expected.positions[0][0][axis]))

func test_actual_carrier_receipt_binds_r1_and_classifies_its_admitted_domain() -> void:
	assert_false(_native.is_empty())
	if _native.is_empty(): return
	var repo := SuiteData.repo()
	var reg: Dictionary = {}
	for row: Dictionary in MapObjects.regiments_of(repo,repo.resolve_realm("player_realm")):
		if str(row.get("is_royal","0")) == "1": reg = row; break
	assert_false(reg.is_empty())
	if reg.is_empty(): return
	var piece: Dictionary = Map3DBattleGroups.build(repo,reg,{"rows":[{"slot":0,"count":1,"role":"front","x_m":0,"y_m":0}],"facing_deg":0})
	autofree(piece.node)
	var world: Node3D = load(DataRepository.map3d_scene_of(repo.map_id)).instantiate()
	var terrain: Terrain3D = world.get_node("Terrain3D")
	terrain.collision_mode = 0
	add_child(world)
	var ctx := Map3DContext.new(repo,world.get_meta("map3d_world"))
	ctx.terrain = terrain
	var captured: Dictionary = Carrier.extract(ctx,piece.groups[0].piece,piece.groups[0].piece.figs[0])
	world.free()
	assert_true(captured.ok,str(captured.get("reason")))
	if not captured.ok: return
	assert_eq(captured.packet.placement.identity.r1,_native.identity)
	var domain: Dictionary = Carrier.domain(captured.packet)
	assert_eq(domain.native_status,"SOURCE_BOUND_CLASSIFIER")
	assert_eq(domain.heading_udeg,[0,359999999])
	assert_eq(domain.duration_q,[1,Q])
	assert_false(captured.packet.terrain.regions.is_empty())
	assert_true(captured.packet.terrain.identity.method_bound)
	var prepared: Dictionary = _prepare_native()
	assert_true(prepared.ok)
	if not prepared.ok: return
	var projections: Array = _projections.duplicate(true)
	for p: Dictionary in projections: p.carrier = captured.packet
	var request: Dictionary = _request(projections); request.identity = prepared.identity
	var result: Dictionary = prepared.authority.build(projections,request)
	if result.ok:
		assert_eq(result.prepared.classification,"production_bound")
		assert_false(result.prepared.motion_join_claim)
	else:
		_rejects(result,"carrier_branch")
		assert_true(result.witness.has("reason"))
		assert_eq(result.witness.reason,"outside_admitted_terrain")
	print("ROYAL_BOUNDARY_CARRIER_RESULT ",result.get("reason","constraints_only")," method=",captured.packet.terrain.identity.method," native_regions=",captured.packet.terrain.regions.size())

	# Select the FIRST geometrically admitted land point; never search for a passing
	# numerical/physical cell or replace an unavailable terrain branch by flat land.
	var grid: Dictionary = captured.packet.placement.identity.admission.grid
	var land: Array = []
	for i: int in grid.closed.size():
		if grid.closed[i] != 0 or (not grid.water_open and grid.water[i] != 0): continue
		@warning_ignore("integer_division")
		var point: Array = [(i%grid.cols)*grid.cell_m+grid.cell_m/2+17,(i/grid.cols)*grid.cell_m+grid.cell_m/2+17]
		var op: Dictionary = BodyMotion._loco_op("move",0,Q,point,[point[0]+100,point[1]],0)
		if Carrier._admission(captured.packet,op).ok: land = point; break
	assert_false(land.is_empty(),"actual native geometric domain has land")
	if land.is_empty(): return
	var schedules: Array = _commits(90,[[50,0],[50,0]],[100,100],false,land)
	assert_eq(schedules.size(),2)
	if schedules.size() != 2: return
	for p: Dictionary in schedules: p.carrier = captured.packet
	request = _request(schedules); request.identity = prepared.identity
	result = prepared.authority.build(schedules,request)
	if result.ok:
		assert_eq(result.prepared.classification,"production_bound")
		assert_eq(result.prepared.exit.shared.left.carrier.domain.native_status,"SOURCE_BOUND_CLASSIFIER")
		assert_false(result.prepared.motion_join_claim)
	else:
		_rejects(result)
		assert_true(result.reason in ["carrier_branch","carrier_enclosure_unavailable"],result.reason)
		assert_true(not result.witness.is_empty())
	print("ROYAL_BOUNDARY_FIRST_LAND_RESULT ",result.get("reason","constraints_only")," land=",land)

func test_step_jump_rejects_complete_receipts_before_any_partial_packet() -> void:
	assert_not_null(_builder)
	if _builder == null: return
	var source: Dictionary = _literal_source()
	var seed: Dictionary = Phase.phase_seed(_projections[0].admission.unit,"0")
	var seed_time: float = Phase.coordinate(1.0,1,.5,0,0,0,seed.h).native_time
	var key: float = .375
	var cut: float = _api().Jets._early_cut(key)
	if cut == seed_time: key = .4375; cut = _api().Jets._early_cut(key)
	var delta: float = cut-seed_time
	if delta < 0.0: delta += .5
	# Seed and cut are multiples of2^-54. The positive wrapped difference<.5
	# is exact; dividing by64 is exact. S=64 therefore reaches this copied cut.
	var config: Dictionary = _config(); config.battle_substeps = 1; config.time_day_seconds = delta/64.0
	assert_eq(Phase.coordinate(config.time_day_seconds,1,.5,63,0,Q,seed.h).native_time,cut)
	source.animation.track_set_interpolation_type(0,Animation.INTERPOLATION_NEAREST)
	source.animation.position_track_insert_key(0,key,Vector3.RIGHT)
	source.sha256 = Source._source_digest(source); source.identity["source_sha256"] = source.sha256
	var prepared: Dictionary = _api().prepare(source,source.identity,_arithmetic,config)
	assert_true(prepared.ok,str(prepared.get("reason")))
	if not prepared.ok: return
	var projections: Array = _commits(90,[[50,0],[50,0]],[100,100],true,[100,100],63)
	assert_eq(projections.size(),2)
	if projections.size() != 2: return
	var request: Dictionary = _request(projections); request.identity = prepared.identity
	_rejects(prepared.authority.build(projections,request),"native_C0_discontinuity")
	var unrepresentable: Dictionary = _literal_source()
	unrepresentable.animation.position_track_insert_key(0,.123456789012345,Vector3.RIGHT)
	unrepresentable.sha256 = Source._source_digest(unrepresentable); unrepresentable.identity["source_sha256"] = unrepresentable.sha256
	_rejects(_api().prepare(unrepresentable,unrepresentable.identity,_arithmetic,_config()),"native_component_copy_mismatch")

func test_scalar_native_rates_translation_and_xy_rotation_hand_values() -> void:
	var api: GDScript = _api()
	assert_not_null(api)
	if api == null: return
	for rate: float in [1.0,2.0]:
		for translation: float in [0.0,3.0]:
			var native: Dictionary = _hand_side("native",translation,.1,rate)
			var pivot: Dictionary = _hand_side("pivot",0.0,.1,rate)
			var result: Dictionary = api._constraints(pivot,api._targets(native,pivot))
			assert_true(result.ok)
			var expected: float = .1*(rate+translation)
			assert_lte(result.materials[0][0][0],expected)
			assert_gte(result.materials[0][0][1],expected)
	var adjacent: Dictionary = _hand_side("native",3.0,.1,0.0)
	var pivot: Dictionary = _hand_side("pivot",0.0,.1,0.0)
	pivot.H_S[4] = [2.0,2.0]
	var result: Dictionary = api._constraints(pivot,api._targets(adjacent,pivot))
	assert_true(result.ok)
	assert_lte(result.materials[0][0][0],.3); assert_gte(result.materials[0][0][1],.3)
	assert_lte(result.materials[0][1][0],-.2); assert_gte(result.materials[0][1][1],-.2)
