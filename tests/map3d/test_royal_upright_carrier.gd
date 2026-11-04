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
