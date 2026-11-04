extends GutTest
## Controls do not establish native domain authority.
const SuiteData = preload("res://tests/suite_data.gd")

func _carrier() -> GDScript:
	var path := "res://scripts/map3d/map3d_royal_upright_carrier.gd"
	var script: GDScript = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(script, "upright carrier must supply copied placement and one-sided derivatives")
	return script

func _placement() -> Dictionary:
	return {"origin": Vector2.ZERO, "alpha": 1.0, "k": 1.0, "extent": Vector2(1,2),
		"height": 3.0, "clear": 0.0, "sink": 0.0, "ring": 8, "ancestor": Transform3D.IDENTITY,
		"identity": {"figure": "control", "stature": 1.0}}

func _grid(columns: Array = [0.0,2.0,4.0,6.0], sea: float = -100.0) -> Dictionary:
	var heights := PackedFloat32Array()
	var controls := PackedInt32Array()
	for z in 4:
		for x in 4:
			heights.append(float(columns[x]))
			controls.append(0)
	return {"kind": "control", "spacing": 20.0, "sea": sea, "region_size": 4,
		"regions": {Vector2i.ZERO: {"height": heights, "control": controls}},
		"identity": {"control": "hand grid"}}

func _packet(c: GDScript, placement: Dictionary = {}, grid: Dictionary = {}) -> Dictionary:
	var result: Dictionary = c.prepare(_placement() if placement.is_empty() else placement, _grid() if grid.is_empty() else grid)
	assert_true(result.ok, str(result))
	return result.get("packet", {})

func test_hand_carrier_derivative_keeps_ancestor_affine() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.ancestor = Transform3D(Basis.IDENTITY.scaled(Vector3(2,3,4)), Vector3(0,1,0))
	var packet := _packet(c,p)
	# Plane .1*x, ellipse(1,2), theta=pi/4: max x=1.5, dx/dtheta=.5.
	var r: Dictionary = c.evaluate(packet, Vector2(10,10), Vector2.ZERO, PI/4, 1.0, "right", packet.sha256)
	assert_true(r.ok, str(r))
	if not r.ok: return
	assert_almost_eq(r.H.origin.y, 2.15, .000001)
	assert_almost_eq(r.H_S.origin.y, .05, .000001)
	assert_almost_eq(r.H.basis.y.y, 3.0, .000001)
	assert_almost_eq(r.H_S.basis.x.x, -sqrt(2.0), .000001)
	assert_eq(r.H_S.homogeneous_w, 0)
	assert_false(r.native_covered, "a hand plane never acquires native domain authority")
	assert_eq(r.samples.size(), 17)

func test_max_tie_uses_opposite_one_sided_extrema() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2(1,0)
	p.ring = 4
	var packet := _packet(c,p,_grid([20.0,0.0,20.0,40.0]))
	for side: String in ["left","right"]:
		var r: Dictionary = c.evaluate(packet, Vector2(20,10), Vector2(1,0), 0.0, 0.0, side, packet.sha256)
		assert_true(r.ok,str(r))
		if r.ok:
			assert_almost_eq(r.H.origin.y,1.0,.000001)
			assert_almost_eq(r.H_S.origin.y,-1.0 if side == "left" else 1.0,.000001)
			assert_eq(r.active_samples.size(),2)

func test_cell_and_sea_sides_remain_distinct() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var packet := _packet(c,p,_grid([0.0,20.0,80.0,140.0]))
	for side: String in ["left","right"]:
		var r: Dictionary = c.evaluate(packet,Vector2(20,10),Vector2(1,0),0.0,0.0,side,packet.sha256)
		assert_true(r.ok,str(r))
		if r.ok: assert_almost_eq(r.H_S.origin.y,1.0 if side == "left" else 3.0,.000001)
	packet = _packet(c,p,_grid([-20.0,0.0,20.0,40.0],0.0))
	for side: String in ["left","right"]:
		var r: Dictionary = c.evaluate(packet,Vector2(20,10),Vector2(1,0),0.0,0.0,side,packet.sha256)
		assert_true(r.ok,str(r))
		if r.ok: assert_almost_eq(r.H_S.origin.y,0.0 if side == "left" else 1.0,.000001)

func test_vertex_shortcut_and_pixel_jump_are_not_bilinear() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var packet := _packet(c,p)
	var near: Dictionary = c.evaluate(packet,Vector2(20.005,20),Vector2(1,0),0.0,0.0,"right",packet.sha256)
	assert_true(near.ok,str(near))
	if near.ok:
		assert_eq(near.samples[0].branch,"vertex_shortcut")
		assert_eq(near.H.origin.y,2.0)
		assert_eq(near.H_S.origin.y,0.0)
	var cut: Dictionary = c.evaluate(packet,Vector2(20,20),Vector2(1,0),0.0,0.0,"left",packet.sha256)
	assert_false(cut.ok)
	assert_eq(cut.reason,"terrain_jump")
	assert_eq(cut.evidence.value,2.0)
	assert_eq(cut.evidence.limit,0.0)
	assert_true(c.evaluate(packet,Vector2(20,20),Vector2.ZERO,0.0,0.0,"left",packet.sha256).ok)

func test_missing_hole_nan_and_override_never_become_flat_land() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var grid := _grid()
	grid.regions[Vector2i.ZERO].control[5] = 4
	var packet := _packet(c,p,grid)
	var hole: Dictionary = c.evaluate(packet,Vector2(25,25),Vector2.ZERO,0.0,0.0,"right",packet.sha256)
	assert_false(hole.ok)
	assert_eq(hole.reason,"terrain_hole")
	assert_eq(hole.evidence.fallback_sea,-100.0)
	assert_eq(c.evaluate(packet,Vector2(1000,1000),Vector2.ZERO,0.0,0.0,"right",packet.sha256).reason,"terrain_missing_region")
	grid = _grid()
	grid.regions[Vector2i.ZERO].height[5] = NAN
	packet = _packet(c,p,grid)
	assert_eq(c.evaluate(packet,Vector2(25,25),Vector2.ZERO,0.0,0.0,"right",packet.sha256).reason,"terrain_nan")
	grid = _grid()
	grid.kind = "override"
	packet = _packet(c,p,grid)
	assert_eq(c.evaluate(packet,Vector2(10,10),Vector2.ZERO,0.0,0.0,"right",packet.sha256).reason,"height_override_unproved")

func test_fractional_metres_and_one_quantum_rates() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.origin = Vector2(10,10)
	p.alpha = .2
	p.extent = Vector2.ZERO
	var packet := _packet(c,p)
	var op := BodyMotion._loco_op("move",0,1000000,[0,0],[1,0],0)
	var r: Dictionary = c.sample(packet,op,.5,"right",packet.sha256)
	assert_true(r.ok,str(r))
	if r.ok:
		assert_almost_eq(r.H.origin.x,10.1,.000001)
		assert_almost_eq(r.H_S.origin.x,.2,.000001)
	op = BodyMotion._loco_op("pivot",0,1,[0,0],[0,0],76000012,180000000)
	r = c.sample(packet,op,.73,"right",packet.sha256)
	assert_true(r.ok,str(r))
	if r.ok: assert_almost_eq(r.yaw_S,-PI*1000000.0,.000001)
	for turn: int in [-1,1,-179999999,180000000]:
		op = BodyMotion._loco_op("pivot",0,1000000,[0,0],[0,0],350000000,turn)
		for u: float in [0.0,.73,1.0]: assert_true(c.sample(packet,op,u,"left",packet.sha256).ok)

func test_packet_mutation_invalidates_every_frozen_field() -> void:
	var c := _carrier()
	if c == null: return
	var packet := _packet(c)
	var cases: Array[Dictionary] = []
	for section: String in ["placement","terrain"]:
		for key: Variant in packet[section]:
			var changed := packet.duplicate(true)
			changed[section].erase(key)
			cases.append(changed)
	var changed := packet.duplicate(true)
	changed.terrain.regions[Vector2i.ZERO].height[0] += 1.0
	cases.append(changed)
	changed = packet.duplicate(true)
	changed.terrain.regions[Vector2i.ZERO].control[0] = 4
	cases.append(changed)
	changed = packet.duplicate(true)
	changed.placement.ancestor.origin.y += .1
	cases.append(changed)
	for stale: Dictionary in cases:
		var r: Dictionary = c.evaluate(stale,Vector2(10,10),Vector2.ZERO,0.0,0.0,"right",packet.sha256)
		assert_false(r.ok)
		assert_false(r.has("H"))
	assert_false(c.evaluate(packet,Vector2(10,10),Vector2.ZERO,0.0,0.0,"right","wrong").ok)

func test_bad_requests_reject_atomically() -> void:
	var c := _carrier()
	if c == null: return
	var packet := _packet(c)
	for bad: Variant in [NAN,INF,"0",null,true]:
		assert_false(c.evaluate(packet,Vector2(10,10),Vector2.ZERO,bad,0.0,"right",packet.sha256).ok)
	for side: String in ["", "middle"]:
		assert_false(c.evaluate(packet,Vector2(10,10),Vector2.ZERO,0.0,0.0,side,packet.sha256).ok)
	var op := BodyMotion._loco_op("hold",0,1000000,[0,0],[0,0],0)
	for key: String in op:
		var bad := op.duplicate(true)
		bad.erase(key)
		assert_false(c.sample(packet,bad,.5,"right",packet.sha256).ok,key)
	for u: Variant in [-.1,1.1,NAN,INF,"0",null]: assert_false(c.sample(packet,op,u,"right",packet.sha256).ok)
	for key: String in ["ring","k","alpha","height"]:
		var p := _placement()
		p[key] = -1
		assert_false(c.prepare(p,_grid()).ok,key)

func test_sea_hides_raw_shortcut_jump_and_raw_enclosure_is_separate() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var packet := _packet(c,p,_grid([0.0,2.0,4.0,6.0],5.0))
	var r: Dictionary = c.evaluate(packet,Vector2(20,20),Vector2(1,0),0.0,0.0,"left",packet.sha256)
	assert_true(r.ok,"raw shortcut discontinuity below sea is hidden by the actual max(raw,sea)")
	if r.ok:
		assert_eq(r.H.origin.y,5.0)
		assert_eq(r.H_S.origin.y,0.0)
	packet = _packet(c,p)
	r = c.evaluate(packet,Vector2(10.73,10.73),Vector2(1,0),0.0,0.0,"right",packet.sha256)
	assert_true(r.ok)
	if r.ok:
		assert_true(r.samples[0].has("raw_enclosure"))
		if r.samples[0].has("raw_enclosure"):
			assert_lte(r.samples[0].raw_enclosure[0],1.073)
			assert_gte(r.samples[0].raw_enclosure[1],1.073)
		assert_eq(r.physical_allowance.status,"NOT_SELECTED")

func test_ancestor_translation_derivative_and_tangent_pixel_cut() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.k = 2.0
	p.ancestor = Transform3D(Basis.IDENTITY,Vector3(1,2,3))
	var packet := _packet(c,p,_grid([0.0,0.0,0.0,0.0]))
	var r: Dictionary = c.evaluate(packet,Vector2(10,10),Vector2(1,2),0.0,2.0,"right",packet.sha256)
	assert_true(r.ok)
	if r.ok:
		assert_eq(r.H.origin,Vector3(12,4,16))
		assert_eq(r.H_S.origin,Vector3(13,0,-2))
	p = _placement()
	p.extent = Vector2(1,0)
	p.ring = 4
	packet = _packet(c,p,_grid([0.0,20.0,80.0,140.0]))
	for side: String in ["left","right"]:
		r = c.evaluate(packet,Vector2(19,20),Vector2.ZERO,0.0,1.0,side,packet.sha256)
		assert_false(r.ok,"tangent q_x,S=0 but q_x,SS<0 enters the incoming pixel on both sides")
		assert_eq(r.reason,"terrain_jump")

func test_json_operations_keep_results_and_source_nan_control_is_hole() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	p.origin = Vector2(10,10)
	var packet := _packet(c,p)
	var op := BodyMotion._loco_op("pivot",0,1000000,[0,0],[0,0],350000000,10000000)
	var direct: Dictionary = c.sample(packet,op,.73,"right",packet.sha256)
	var restored: Dictionary = c.sample(packet,JSON.parse_string(JSON.stringify(op)),.73,"right",packet.sha256)
	assert_eq(restored,direct)
	var grid := _grid()
	grid.regions[Vector2i.ZERO].control[5] = 0x7fc00000
	packet = _packet(c,p,grid)
	assert_eq(c.evaluate(packet,Vector2(25,25),Vector2.ZERO,0.0,0.0,"right",packet.sha256).get("reason",""),"terrain_hole")

func test_extraction_binds_actual_royal_model_root_and_keeps_override_unavailable() -> void:
	var c := _carrier()
	if c == null: return
	var repo := SuiteData.repo()
	var reg: Dictionary = {}
	for r: Dictionary in MapObjects.regiments_of(repo,repo.resolve_realm("player_realm")):
		if String(r.get("is_royal","0")) == "1": reg = r; break
	assert_false(reg.is_empty())
	if reg.is_empty(): return
	var piece := Map3DBattleGroups.build(repo,reg,{"rows":[{"slot":0,"count":1,"role":"front","x_m":0,"y_m":0}],"facing_deg":0})
	autofree(piece.node)
	var child: Dictionary = piece.groups[0].piece
	var model: Node3D = child.figs[0]
	var ctx := Map3DContext.new(repo,{"pack_origin":[0,0],"m_per_px":50.0,"sea_y":5.0})
	ctx.height_fn = func(_q: Vector2) -> float: return 100.0
	var captured: Dictionary = c.extract(ctx,child,model)
	assert_true(captured.ok,str(captured))
	if not captured.ok: return
	var skeleton: Node3D = model.find_children("*","Skeleton3D",true,false)[0]
	assert_false(c.extract(ctx,child,skeleton).ok,"R1 model carrier cannot silently become the skeleton carrier")
	assert_false(c.evaluate(captured.packet,Vector2.ZERO,Vector2.ZERO,0.0,0.0,"right",captured.packet.sha256).ok)

func test_nonmaximal_pixel_jump_does_not_reject_continuous_seat() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2(1,0)
	p.ring = 4
	var packet := _packet(c,p)
	for side: String in ["left","right"]:
		var result: Dictionary = c.evaluate(packet,Vector2(20,20),Vector2(1,0),0.0,0.0,side,packet.sha256)
		assert_true(result.ok,"center jumps2→0 but x=21 stays the unique seat maximum")
		if result.ok:
			assert_almost_eq(result.H.origin.y,2.1,.000001)
			assert_almost_eq(result.H_S.origin.y,.1,.000001)

func _royal_input() -> Dictionary:
	var repo := SuiteData.repo()
	var reg: Dictionary = {}
	for row: Dictionary in MapObjects.regiments_of(repo,repo.resolve_realm("player_realm")):
		if String(row.get("is_royal","0")) == "1": reg = row; break
	var piece := Map3DBattleGroups.build(repo,reg,{"rows":[{"slot":0,"count":1,"role":"front","x_m":0,"y_m":0}],"facing_deg":0})
	autofree(piece.node)
	return {"ctx":Map3DContext.new(repo,{"pack_origin":[0,0],"m_per_px":50.0,"sea_y":5.0}),
		"child":piece.groups[0].piece,"model":piece.groups[0].piece.figs[0]}

func test_loaded_source_provenance_binds_r1_and_rejects_same_bounds_stale_native_data() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	var captured: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_true(captured.ok)
	if not captured.ok: return
	assert_true(captured.packet.placement.identity.has("r1"),"outer tscn path/hash cannot bind inherited native animation/skin")
	var player: AnimationPlayer = input.model.find_children("*","AnimationPlayer",true,false)[0]
	var library_name: StringName = player.get_animation_library_list()[0]
	var library: AnimationLibrary = player.get_animation_library(library_name).duplicate(true)
	player.remove_animation_library(library_name)
	player.add_animation_library(library_name,library)
	var before: Transform3D = input.model.transform
	var bounds: AABB = input.child.bounds_model
	library.get_animation("MARCH").length += .001
	var stale: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_false(stale.ok,"same scene path, root and bounds with different loaded MARCH bytes must reject")
	assert_false(stale.has("packet"))
	assert_eq(input.model.transform,before)
	assert_eq(input.child.bounds_model,bounds)

func test_source_binding_checks_existing_r1_source_and_import_receipts() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	assert_true(c.Source.has_method("_bind_source"),"extract needs one shared loaded-source verifier")
	if not c.Source.has_method("_bind_source"): return
	var calibration: Map3DRoyalLocomotionSource = load("res://assets/3D/units/royal/royal_locomotion_source.tres")
	var current: Dictionary = c.Source._bind_source(input.child,input.model,calibration)
	assert_true(current.ok,str(current))
	if not current.ok: return
	assert_true(current.identity.has("source_sha256"))
	assert_false(current.identity.imports.is_empty())
	for path: String in calibration.source_hashes:
		if not path.ends_with(".glb") and not path.ends_with(".glb.import"): continue
		var bad: Map3DRoyalLocomotionSource = calibration.duplicate(true)
		bad.source_hashes[path] = "0".repeat(64)
		var result: Dictionary = c.Source._bind_source(input.child,input.model,bad)
		assert_false(result.ok,path)
		assert_false(result.has("identity"))
	var mesh: MeshInstance3D = input.model.find_children("*","MeshInstance3D",true,false)[0]
	mesh.skin = mesh.skin.duplicate(true)
	var bind: Transform3D = mesh.skin.get_bind_pose(0)
	bind.origin.x += .001
	mesh.skin.set_bind_pose(0,bind)
	assert_false(c.Source._bind_source(input.child,input.model,calibration).ok,"loaded skin changes cannot retain native source identity")

func test_outward_source_math_bounds_do_not_choose_a_physical_budget() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	p.ancestor = Transform3D(Basis.IDENTITY,Vector3(1,2,3))
	var packet := _packet(c,p)
	var result: Dictionary = c.evaluate(packet,Vector2(10.75,10.75),Vector2(1,0),0.0,0.0,"right",packet.sha256)
	assert_true(result.ok)
	assert_true(result.has("enclosures"),"H and per-S derivative need source-operation bounds")
	if not result.has("enclosures"): return
	assert_eq(result.enclosures.status,"ENCLOSED_CONTROL")
	assert_lte(result.enclosures.H[7][0],3.075)
	assert_gte(result.enclosures.H[7][1],3.075)
	assert_lte(result.enclosures.H_S[7][0],.1)
	assert_gte(result.enclosures.H_S[7][1],.1)
	assert_false(result.native_covered,"synthetic grid remains a control even with valid interval algebra")
	assert_eq(result.physical_allowance.status,"NOT_SELECTED")

func test_trig_enclosure_and_exact_native_scalar_cases() -> void:
	var c := _carrier()
	if c == null: return
	assert_true(c.Bounds.has_method("_trig_interval"))
	if not c.Bounds.has_method("_trig_interval"): return
	assert_eq(c.Bounds._interval([0.0,0.0],[20.0,20.0],"*"),[0.0,0.0])
	assert_eq(c.Bounds._interval([20.0,20.0],[20.0,20.0],"/"),[1.0,1.0])
	for angle: float in [0.0,PI/4,PI/2,-PI/2,PI,TAU,-3.5*PI]:
		var box: Array = c.Bounds._trig_interval([angle,angle],false)
		assert_lte(box[0],sin(angle))
		assert_gte(box[1],sin(angle))
		assert_gte(box[0],-1.0)
		assert_lte(box[1],1.0)
	var sin_zero: Array = c.Bounds._trig_interval([0.0,0.0],false)
	assert_eq(sin_zero,[0.0,0.0])
	var cos_zero: Array = c.Bounds._trig_interval([0.0,0.0],true)
	assert_eq(cos_zero,[1.0,1.0])

func test_actual_domain_receipt_keeps_terrain_bounds_and_full_parameter_family() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	var captured: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_true(captured.ok)
	if not captured.ok: return
	var packet: Dictionary = captured.packet
	var receipt: Dictionary = c.domain(packet)
	assert_eq(receipt.heading_udeg,[0,359999999])
	assert_eq(receipt.turn_udeg,[-179999999,180000000])
	assert_eq(receipt.duration_q,[1,BodyMotion.LOCOMOTION_Q])
	assert_true(receipt.has("admission"),"domain needs copied actual engine-circle terrain, not a descriptive range")
	if not receipt.has("admission"): return
	assert_eq(receipt.admission.status,"BOUND_GEOMETRIC_SUPERSET")
	assert_eq(receipt.admission.radius_m,int(input.ctx.repo.unit_footprints.royal.radius_m))
	var op := BodyMotion._loco_op("hold",0,BodyMotion.LOCOMOTION_Q,[0,0],[0,0],0,0)
	assert_false(c._admission(packet,op).ok,"a stationary center outside the measured circle bounds is excluded by actual terrain predicate")
	assert_true(receipt.has("classifier_sha256"))
	assert_false(receipt.has("physical_E"))

func test_unknown_ancestor_drivers_and_nonfinite_derived_math_are_unavailable() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	input.model.top_level = true
	assert_false(c.extract(input.ctx,input.child,input.model).ok,"a top-level model does not inherit constant A")
	var p := _placement()
	p.extent = Vector2.ZERO
	var packet := _packet(c,p)
	var result: Dictionary = c.evaluate(packet,Vector2(10,10),Vector2.ZERO,0.0,1e308,"right",packet.sha256)
	assert_false(result.ok,"finite input is not permission to return a nonfinite derived matrix")
	assert_eq(result.reason,"carrier_numeric_range")
	var grid := _grid()
	grid.regions[Vector2i.ZERO].height[5] = INF
	packet = _packet(c,p,grid)
	assert_eq(c.evaluate(packet,Vector2(25,25),Vector2.ZERO,0.0,0.0,"right",packet.sha256).reason,"terrain_infinite")

func test_live_tree_generated_empty_simulator_does_not_relabel_a_source_modifier() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	add_child(input.child.node.get_parent())
	var captured: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_true(captured.ok,"entering the real tree creates an empty internal compatibility simulator; actual R1 source is unchanged")
	var skeleton: Skeleton3D = input.model.find_children("*","Skeleton3D",true,false)[0]
	var authored := PhysicalBoneSimulator3D.new()
	skeleton.add_child(authored)
	assert_false(c.extract(input.ctx,input.child,input.model).ok,"an authored or populated modifier must remain unavailable")

func test_native_corner_control_does_not_replace_query_control() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var grid := _grid()
	grid.regions[Vector2i.ZERO].control[5] = 4
	var packet := _packet(c,p,grid)
	var result: Dictionary = c.evaluate(packet,Vector2(10.75,10.75),Vector2(1,0),0.0,0.0,"right",packet.sha256)
	assert_true(result.ok,"native bilerp reads corner HEIGHT without testing corner CONTROL")
	if not result.ok: return
	assert_eq(result.enclosures.status,"ENCLOSED_CONTROL")
	assert_lte(result.enclosures.H[7][0],1.075)
	assert_gte(result.enclosures.H[7][1],1.075)

func test_injected_cached_land_grid_cannot_be_relabelled_as_pack_domain() -> void:
	var c := _carrier()
	if c == null: return
	var repo := SuiteData.repo()
	var original := MarchPath.of_pack(repo)
	assert_not_null(original)
	if original == null: return
	var altered := MarchPath.load_pack(repo)
	altered.closed[0] = 1-altered.closed[0]
	MarchPath.use(repo,altered)
	var receipt: Dictionary = c._domain_source(repo)
	MarchPath.use(repo,original)
	assert_eq(receipt.status,"UNAVAILABLE")
	assert_eq(receipt.reason,"cached_land_grid_mismatch")

func test_bilinear_shared_edge_cannot_become_a_roundoff_jump() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.extent = Vector2.ZERO
	var grid := _grid([0.0,0.0,0.0,0.0],-10000.0)
	for item: Array in [[0,-5880.82568359375],[1,3607.99951171875],[4,-1448.1539306640625],[5,-3717.056640625]]:
		grid.regions[Vector2i.ZERO].height[int(item[0])] = item[1]
	var packet := _packet(c,p,grid)
	# Both cells share b,d. Polynomial cancellation differs by 2^-40; geometry is continuous.
	var result: Dictionary = c.evaluate(packet,Vector2(20,11.711236953735352),Vector2(1,0),0.0,0.0,"left",packet.sha256)
	assert_true(result.ok,"a shared bilerp edge is continuous even when expanded-polynomial rounding differs")
	if result.ok: assert_almost_eq(result.H_S.origin.y,130.19741592511596,.00001)

func test_touching_cell_box_never_excludes_the_endpoint_one_sided_slope() -> void:
	var c := _carrier()
	if c == null: return
	var p := _placement()
	p.origin = Vector2(21,10)
	p.extent = Vector2(0,21)
	p.ring = 4
	var grid := _grid([0.0,0.0,0.0,0.0],-1000.0)
	grid.regions.clear()
	for rx: int in [-1,0]:
		var height := PackedFloat32Array()
		for z in 4:
			for x in 4: height.append(20.0-absf(float(rx*4+x))*20.0)
		grid.regions[Vector2i(rx,0)] = {"height":height,"control":PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])}
	var packet := _packet(c,p,grid)
	# Unique maximum20 at q_x=0: h=20-|x|, so left slope+1, right slope-1.
	for endpoints: Array in [[-1,0,1.0],[0,1,0.0],[1,0,1.0],[0,-1,0.0]]:
		var heading: int = 0 if endpoints[1] > endpoints[0] else 180000000
		var op := BodyMotion._loco_op("move",0,BodyMotion.LOCOMOTION_Q,[endpoints[0],0],[endpoints[1],0],heading)
		for side: String in ["left","right"]:
			var result: Dictionary = c.sample(packet,op,endpoints[2],side,packet.sha256)
			assert_true(result.ok,str(result))
			if not result.ok: continue
			assert_almost_eq(result.H_S.origin.y,1.0 if side == "left" else -1.0,.000001)
			assert_eq(result.enclosures.status,"UNAVAILABLE","a box touching a moving cell cut cannot certify just the cell on its interior")
			assert_eq(result.enclosures.get("reason"),"native_cell_side_unresolved")
	var direct: Dictionary = c.Bounds._sample_enclosure(grid,[[0.0,0.0000019073486328125],[10.0,10.0]],
		[[1.0,1.0],[0.0,0.0]],[[0.0,0.0],[0.0,0.0]],"left")
	assert_false(direct.ok,"the box permits x=0 and its incoming x<0 branch")
	assert_eq(direct.get("reason"),"native_cell_side_unresolved")

func test_extra_animation_tree_root_writer_rejects_without_a_packet() -> void:
	var c := _carrier()
	if c == null: return
	var input := _royal_input()
	add_child(input.child.node.get_parent())
	var baseline: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_true(baseline.ok)
	var tree := AnimationTree.new()
	input.model.add_child(tree)
	var animation := Animation.new()
	animation.length = 1.0
	var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track,NodePath(".:position"))
	animation.track_insert_key(track,0.0,input.model.position)
	animation.track_insert_key(track,1.0,input.model.position+Vector3(5,0,0))
	var library := AnimationLibrary.new()
	library.add_animation("write_root",animation)
	tree.add_animation_library("",library)
	tree.root_node = NodePath("..")
	var branch := AnimationNodeAnimation.new()
	branch.animation = "write_root"
	tree.tree_root = branch
	tree.active = true
	var before: Transform3D = input.model.transform
	var result: Dictionary = c.extract(input.ctx,input.child,input.model)
	assert_false(result.ok,"a second mixer can write A independently of the validated AnimationPlayer")
	assert_eq(result.get("reason"),"unproved_source_mixer")
	assert_false(result.has("packet"),"reject atomically instead of retaining the baseline identity")
	assert_eq(input.model.transform,before,"source extraction leaves the live actor untouched")
	tree.advance(0.0)
	tree.advance(.5)
	tree.advance(.25)
	assert_almost_eq(input.model.position.x,before.origin.x+3.75,.000001,"the rejected script-free mixer really can move the root")

func test_shortcut_radius_box_touch_remains_unavailable() -> void:
	var c := _carrier()
	if c == null: return
	assert_true(c.Bounds.SHORTCUT_SQUARED == float(PackedFloat32Array([.0001])[0]),"comparison uses the exact native binary32 constant")
	# Directed binary32 squared-distance bounds touch0.0001f at this input.
	var result: Dictionary = c.Bounds._sample_enclosure(_grid(),[[.01,.01],[.000003,.000003]],
		[[1.0,1.0],[0.0,0.0]],[[0.0,0.0],[0.0,0.0]],"left")
	assert_false(result.ok,"touching the shortcut comparison is not strict branch separation")
	assert_eq(result.get("reason"),"native_shortcut_rounding_cut")

func test_current_domain_rejects_stale_loaded_army_writer_and_recovers_after_restore() -> void:
	var c := _carrier()
	if c == null: return
	var repo := SuiteData.repo()
	assert_eq(c._domain_source(repo).status, "BOUND_GEOMETRIC_SUPERSET")
	var path := "res://scripts/engine/army_system.gd"
	var writer: GDScript = load(path)
	var original := writer.source_code
	writer.source_code = original + "\n# Deliberately stale loaded writer for the domain boundary test.\n"
	var refused: Dictionary = c._domain_source(repo)
	writer.source_code = original
	assert_eq(refused.status, "UNAVAILABLE")
	assert_eq(refused.get("reason"), "domain_source_changed")
	assert_eq(refused.get("path"), path)
	assert_eq(c._domain_source(repo).status, "BOUND_GEOMETRIC_SUPERSET")
