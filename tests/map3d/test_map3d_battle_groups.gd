extends GutTest

const SuiteData = preload("res://tests/suite_data.gd")

func test_saved_rows_drive_actual_nodes() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)[0]
	var code := String(reg["regiment_code"])
	var fit := ArmySystem.fit_count(repo, state, code)
	var rows: Array = []
	for n: int in BattleGroups.counts(fit, int(repo.bal("battle_group_size"))):
		rows.append({"count": n, "role": "front", "x_m": 200, "y_m": 300})
	state.battles = [{"place_x_m": 200, "place_y_m": 300, "att": [code], "def": [], "group_size_version": 2, "group_size_men": 100, "groups": {code: rows}, "group_facing": {code: 90}}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [-100, 50], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd") if ResourceLoader.exists("res://scripts/map3d/map3d_battle_groups.gd") else null
	assert_not_null(helper, "saved physical groups need a real player-map consumer")
	if helper == null:
		return
	var sample: Dictionary = helper.sample(ctx, code)
	assert_eq(sample["mode"], "groups")
	assert_eq(sample["rows"].size(), rows.size())
	assert_eq(helper.sample(ctx, "hidden")["rows"], [])
	var before := SaveLoad.state_hash(state)
	var piece: Dictionary = helper.build(repo, reg, sample)
	add_child_autofree(piece["node"])
	helper.place(ctx, piece, Vector2.ZERO, 1.6, false)
	assert_eq(piece["figures"], rows.size())
	assert_eq(helper.evidence(piece).size(), rows.size())
	assert_eq(SaveLoad.state_hash(state), before)

func test_real_encounter_retains_ordinary_figure_size_and_returns_to_it() -> void:
	var repo := SuiteData.repo()
	var state := preload("res://tests/fixtures/battle_scenario.gd").contact(repo, 10)
	var foe := String(state.foes.keys()[0])
	state.foes[foe]["order"] = ArmySystem.ORDER_GARRISON
	var own := ""
	for code: String in state.regiments:
		if Vector2(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])).distance_to(
				Vector2(int(state.foes[foe]["x_m"]), int(state.foes[foe]["y_m"]))) < 2000:
			own = code
			break
	assert_ne(own, "")
	if own == "": return
	state.regiments[own]["order"] = ArmySystem.ORDER_MARCH
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var scales := {}
	for code: String in [own, foe]:
		var piece := layer._piece_of(code)
		layer._shown_xz[code] = Vector2.ZERO
		layer._place(code, piece)
		scales[code] = (piece["node"] as Node3D).scale.x
	var contacts := BattleSystem.discover_contacts(repo, state)
	assert_false(contacts.is_empty(), "real contact starts the encounter")
	assert_false(state.battles.is_empty())
	assert_eq(state.battles[0]["att"], [own], "marching into the enemy garrison makes the player attack")
	var frozen := SaveLoad.state_hash(state)
	for code: String in [own, foe]:
		var piece := layer._piece_of(code)
		assert_eq(piece.get("layout", ""), "physical_groups")
		layer._place(code, piece)
		for group: Dictionary in piece["groups"]:
			assert_almost_eq((group["piece"]["node"] as Node3D).scale.x, float(scales[code]), 0.0001,
				code + " keeps its ordinary miniature size on contact")
	assert_eq(SaveLoad.state_hash(state), frozen, "drawing never changes saved battle points/counts/facing")
	state.battles.clear()
	for code: String in [own, foe]:
		var piece := layer._piece_of(code)
		assert_ne(piece.get("layout", ""), "physical_groups")
		layer._shown_xz[code] = Vector2.ZERO
		layer._place(code, piece)
		assert_almost_eq((piece["node"] as Node3D).scale.x, float(scales[code]), 0.0001)

func test_every_battle_arm_uses_its_ordinary_reference_scale() -> void:
	var repo := SuiteData.repo()
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.view_size = Vector2(2560, 1600)
	var checked := {}
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var arm := MapObjects.army_piece(repo, reg)
		if checked.has(arm) or String(reg.get("is_naval", "0")) == "1": continue
		var ordinary := Map3DFormation.of_regiment(repo, reg, {"figures": 1, "slots": [Vector2.ZERO]}, 1.6)
		autofree(ordinary["node"])
		var piece := Map3DBattleGroups.build(repo, reg, {"rows": [
			{"slot": 0, "count": 1, "role": "front", "x_m": 0, "y_m": 0}], "facing_deg": 90})
		add_child_autofree(piece["node"])
		var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
		var expected := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y,
			reference, ordinary["height_m"], ordinary["size"])
		for gap: float in [0.8, 1.6, 3.2]:
			Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, gap, false)
			assert_almost_eq((piece["groups"][0]["piece"]["node"] as Node3D).scale.x, expected, 0.0001,
				arm + " battle figure keeps its original size independently of spacing")
		checked[arm] = true
	assert_true(checked.has("infantry"))
	assert_true(checked.has("archers"))
	assert_true(checked.has("cavalry"))

func test_empty_legacy_and_invalid_groups() -> void:
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd") if ResourceLoader.exists("res://scripts/map3d/map3d_battle_groups.gd") else null
	assert_not_null(helper)
	if helper == null:
		return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var battle := {"place_x_m": 200, "place_y_m": 300, "att": [code], "def": []}
	state.battles = [battle]
	assert_eq(helper.sample(ctx, code)["mode"], "fallback")
	var personnel := preload("res://tests/engine/personnel_helpers.gd")
	personnel.replace(repo, state, code, 0)
	battle["groups"] = {code: []}
	battle["group_facing"] = {code: 0}
	assert_eq(helper.sample(ctx, code)["mode"], "groups")
	battle["groups"][code] = [{"count": 1, "role": "front", "x_m": 1, "y_m": 2}]
	assert_eq(helper.sample(ctx, code)["mode"], "invalid", "present mismatched rows cannot use fallback")
	personnel.replace(repo, state, code, 1)
	assert_eq(helper.sample(ctx, code)["mode"], "groups")
	for bad: Variant in [null, "1", 1.5]:
		battle["groups"][code][0]["x_m"] = bad
		assert_eq(helper.sample(ctx, code)["mode"], "invalid")
	battle["groups"][code][0]["x_m"] = 1.0
	assert_eq(helper.sample(ctx, code)["mode"], "groups", "integral JSON numbers accepted")
	battle["group_facing"][code] = "90"
	assert_eq(helper.sample(ctx, code)["mode"], "invalid")

func test_hand_computed_world_points_and_facing() -> void:
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd") if ResourceLoader.exists("res://scripts/map3d/map3d_battle_groups.gd") else null
	assert_not_null(helper)
	if helper == null:
		return
	var repo := SuiteData.repo()
	repo.map_info["distance_unit"] = "km"
	repo.map_info["distance_scale"] = "0.01"
	var ctx := Map3DContext.new(repo, {"pack_origin": [-100, 50], "m_per_px": 2.0})
	ctx.height_fn = func(xz: Vector2) -> float: return xz.x * 0.1
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var sample := {"mode": "groups", "rows": [
		{"slot": 7, "count": 50, "role": "front", "x_m": 200, "y_m": 300},
		{"slot": 9, "count": 1, "role": "reserve", "x_m": 230, "y_m": 340}], "facing_deg": 0}
	var piece: Dictionary = helper.build(repo, reg, sample)
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.rotation = Vector3(0.2, 0.3, 0.1)
	parent.scale = Vector3.ONE * 3.0
	parent.add_child(piece["node"])
	for facing: int in [0, 90, 180, 270, 37]:
		piece["facing_deg"] = facing
		helper.place(ctx, piece, Vector2(-70, 100), 1.6, false)
		ctx.distance += 500.0
		ctx.target += Vector2(10, 20)
		var evidence: Array = helper.evidence(piece)
		assert_almost_eq(float(evidence[1]["y_world"]) - float(evidence[0]["y_world"]), 0.6, 0.001)
		assert_almost_eq(Vector2(evidence[0]["xz_world"][0], evidence[0]["xz_world"][1]).distance_to(Vector2(-60, 110)), 0.0, 0.0001)
		assert_almost_eq(Vector2(evidence[1]["xz_world"][0], evidence[1]["xz_world"][1]).distance_to(Vector2(-54, 118)), 0.0, 0.0001)
		var expected := Map3DUnits.facing_yaw(WarFront.facing_vector(facing), 55.0)
		assert_almost_eq(wrapf(float(evidence[0]["yaw_rad"]) - expected, -PI, PI), 0.0, 0.0001)

func test_counts_are_one_saved_row_per_live_model() -> void:
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd") if ResourceLoader.exists("res://scripts/map3d/map3d_battle_groups.gd") else null
	assert_not_null(helper)
	if helper == null:
		return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var personnel := preload("res://tests/engine/personnel_helpers.gd")
	var wants := [0, 1, 1, 2, 9, 10]
	var ns := [0, 1, 100, 101, 900, 1000]
	for i in ns.size():
		personnel.replace(repo, state, code, ns[i])
		var rows: Array = []
		for n: int in BattleGroups.counts(ns[i], int(repo.bal("battle_group_size"))):
			rows.append({"count": n, "role": "front", "x_m": rows.size() * 50, "y_m": 100})
		state.battles = [{"place_x_m": 200, "place_y_m": 300, "att": [code], "def": [], "group_size_version": 2, "group_size_men": 100, "groups": {code: rows}, "group_facing": {code: 0}}]
		var sample: Dictionary = helper.sample(ctx, code)
		assert_eq(sample["mode"], "groups")
		assert_eq(sample["rows"].size(), wants[i])
		var piece: Dictionary = helper.build(repo, ArmySystem.regiment(repo, code, state), sample)
		autofree(piece["node"])
		assert_eq(piece["figures"], wants[i])
	assert_eq(BattleGroups.counts(10000, 100).size(), 100, "pure count stress remains independent of legal unit size")
	var origin: Dictionary = state.military_cohorts[state.military_rosters[code].cohort_ids[0]]
	var path := MilitaryPopulation.path(origin.source_province, origin.source_population_field)
	state.world[path] = maxi(int(WorldLedger.value_of(repo, state, path)), MilitaryPopulation.occupied(state, origin.source_province, origin.source_population_field) + 20000)
	var before := SaveLoad.state_hash(state)
	var refused := MilitaryRoster.mobilize(repo, state, "oversized-model-input", [{"id": "oversized-model-input", "unit_code": code,
		"source_province": origin.source_province, "source_population_field": origin.source_population_field,
		"identity": "commoner", "stage": "active", "count": 10000}], "Rejected oversized model fixture")
	assert_true(refused.has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.battles[0].groups[code] = [{"count": 10000, "role": "front", "x_m": 0, "y_m": 100}]
	assert_eq(helper.sample(ctx, code)["mode"], "invalid", "oversized saved rows are not admitted")

func test_paused_geometry_changes_invalidate_cache() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var rows: Array = []
	for n: int in BattleGroups.counts(ArmySystem.fit_count(repo, state, code), int(repo.bal("battle_group_size"))):
		rows.append({"count": n, "role": "front", "x_m": 200, "y_m": 300})
	var battle := {"place_x_m": 200, "place_y_m": 300, "att": [code], "def": [], "group_size_version": 2, "group_size_men": 100, "groups": {code: rows}, "group_facing": {code: 90}}
	state.battles = [battle]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var key := layer._roster_key()
	rows[0]["x_m"] += 30
	assert_ne(layer._roster_key(), key, "same-day physical row change must refresh without camera motion")
	key = layer._roster_key()
	battle["group_facing"][code] = 37
	assert_ne(layer._roster_key(), key, "saved facing participates independently of regiment/day hash")

func test_only_admitted_live_units_expose_rows() -> void:
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd") if ResourceLoader.exists("res://scripts/map3d/map3d_battle_groups.gd") else null
	assert_not_null(helper)
	if helper == null:
		return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var own := String(state.regiments.keys()[0])
	var foe := String(state.foes.keys()[0])
	state.foes[foe]["x_m"] = -1000000
	state.foes[foe]["y_m"] = -1000000
	var own_rows: Array = []
	for n: int in BattleGroups.counts(ArmySystem.fit_count(repo, state, own), int(repo.bal("battle_group_size"))):
		own_rows.append({"count": n, "role": "front", "x_m": 200, "y_m": 300})
	var battle := {"place_x_m": 200, "place_y_m": 300, "att": [own], "def": [foe], "groups": {own: own_rows,
		foe: [{"count": 50, "role": "front", "x_m": -1000000, "y_m": -1000000, "slot": 99, "path_m": [[1, 2]]}]},
		"group_facing": {own: 0, foe: 0}}
	state.battles = [battle]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	assert_eq(helper.sample(ctx, foe)["rows"], [])
	assert_eq(helper.sample(ctx, "ghost:" + foe)["rows"], [])
	var before: Dictionary = helper.sample(ctx, own)
	battle["groups"][foe][0]["x_m"] += 300
	battle["group_facing"][foe] = 90
	assert_eq(helper.sample(ctx, own), before, "hidden source cannot contaminate visible geometry keys")
	assert_eq(helper.sample(ctx, foe)["rows"], [])

func test_reload_and_casualty_remove_stale_nodes() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var personnel := preload("res://tests/engine/personnel_helpers.gd")
	personnel.replace(repo, state, code, 101)
	var rows: Array = [
		{"slot": 3, "count": 50, "role": "front", "x_m": 200, "y_m": 300},
		{"slot": 7, "count": 50, "role": "front", "x_m": 230, "y_m": 340},
		{"slot": 9, "count": 1, "role": "reserve", "x_m": 260, "y_m": 380}]
	var battle := {"place_x_m": 200, "place_y_m": 300, "att": [code], "def": [], "groups": {code: rows}, "group_facing": {code: 0}}
	state.battles = [battle]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	layer._battle.apply_snapshot({"map_units": {code: {"action": "MARCH"}}})
	var piece := layer._piece_of(code)
	assert_eq(piece.get("layout", ""), "physical_groups")
	if piece.get("layout", "") != "physical_groups":
		return
	var survivor: Node3D = piece["groups"][0]["piece"]["node"]
	var animator: AnimationPlayer = piece["groups"][0]["piece"]["anims"][0]
	var phase := animator.current_animation_position
	assert_almost_eq(phase, Map3DMarchLag.phase(code + ":3", 0) * animator.current_animation_length, 0.0001)
	var removed: Node3D = piece["groups"][2]["piece"]["node"]
	personnel.move(repo, state, code, "fit", "wounded", 1)
	rows.pop_back()
	piece = layer._piece_of(code)
	assert_eq(piece["figures"], 2)
	assert_eq(piece["groups"][0]["piece"]["node"], survivor, "optional slots retain live model identity")
	assert_true(removed.is_queued_for_deletion())
	assert_almost_eq(animator.current_animation_position, phase, 0.0001, "another slot removal cannot reseed surviving clip phase")
	state.battles = []
	piece = layer._piece_of(code)
	assert_ne(piece.get("layout", ""), "physical_groups", "leaving battle restores ordinary layout")
	assert_false(layer._days.has(code), "no stale march forecast across mode changes")
	layer._drop(code)
	assert_false(layer.has_piece(code))

func test_group_mode_preserves_unit_seams() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var personnel := preload("res://tests/engine/personnel_helpers.gd")
	personnel.replace(repo, state, code, 51)
	state.battles = [{"place_x_m": 200, "place_y_m": 300, "att": [code], "def": [], "groups": {code: [
		{"count": 50, "role": "front", "x_m": 0, "y_m": 0},
		{"count": 1, "role": "reserve", "x_m": 1000, "y_m": 0}]}, "group_facing": {code: 90}}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	ctx.view_size = Vector2(1920, 1080)
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var piece := layer._piece_of(code)
	assert_eq(piece.get("layout", ""), "physical_groups")
	if piece.get("layout", "") != "physical_groups":
		return
	layer._shown_xz[code] = Vector2.ZERO
	layer._place(code, piece)
	assert_true(layer.has_piece(code))
	assert_eq(layer.drawn_count(), 1, "two group models remain one selectable unit")
	assert_eq(layer.shown_positions()[code], Vector2.ZERO, "WAR ROOM receives the unit anchor")
	assert_eq(piece["model"], MapObjects.army_piece(repo, ArmySystem.regiment(repo, code, state)), "sound still looks up the arm")
	assert_eq((piece["node"] as Node3D).basis.get_scale(), Vector3.ONE)
	assert_true(piece.has("camp_scale"), "camp scale must retain the ordinary model reference scale")
	assert_true(layer.has_method("group_geometry"))
	if layer.has_method("group_geometry"):
		assert_eq(layer.group_geometry()[code].size(), 2)
	assert_eq(layer.screen_rects().keys(), [code])
	var child: Node3D = piece["groups"][0]["piece"]["node"]
	var source_xz := Vector2(child.global_position.x, child.global_position.z)
	var source_scale := child.scale.x
	var camp_before: float = piece.camp_scale
	assert_not_null(layer.get("figure_footprint_gap"))
	if layer.get("figure_footprint_gap") == null: return
	layer.set("figure_footprint_gap", 0.8)
	layer._place(code, piece)
	assert_almost_eq(child.scale.x, source_scale, 0.0001, "legacy footprint setting cannot resize battle figures")
	assert_eq(Vector2(child.global_position.x, child.global_position.z), source_xz)
	assert_eq(float(piece.camp_scale), camp_before)
	var state_hash := SaveLoad.state_hash(state)
	layer._live = [code]
	layer._roster_was = layer._roster_key()
	layer.shown = true
	layer.step(0.0)
	ctx.camera_moved.emit()
	assert_eq(SaveLoad.state_hash(state), state_hash, "refresh/paused step/camera operations remain read-only")
	for group: Dictionary in piece["groups"]:
		var node: Node3D = group["piece"]["node"]
		var screen := ctx.camera.unproject_position(node.global_position) / ctx.viewport_px_scale()
		assert_true((layer.screen_rects()[code] as Rect2).grow(0.01).has_point(screen), "rear group is in its unit hit box")

func test_group_signal_uses_built_dimensions_and_camp_keeps_ordinary_scale() -> void:
	var repo := SuiteData.repo()
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var sampled := {"mode": "groups", "rows": [
		{"slot": 0, "count": 1, "role": "front", "x_m": 200, "y_m": 300}], "facing_deg": 90}
	var piece := Map3DBattleGroups.build(repo, reg, sampled)
	add_child_autofree(piece["node"])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.view_size = Vector2(1920, 1080)
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 1.6, false)
	var ordinary := Map3DFormation.of_regiment(repo, reg, {"figures": 1, "slots": [Vector2.ZERO]}, 1.6)
	autofree(ordinary["node"])
	var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var expected := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference,
		ordinary["height_m"], ordinary["size"])
	assert_almost_eq(float(piece["camp_scale"]), expected, 0.0001)
	var empty := Map3DBattleGroups.build(repo, reg, {"rows": [], "facing_deg": 0})
	add_child_autofree(empty["node"])
	Map3DBattleGroups.place(ctx, empty, Vector2.ZERO, 1.6, false)
	assert_almost_eq(float(empty.get("camp_scale", -1)), expected, 0.0001, "zero fit retains the ordinary camp scale too")
	var child: Dictionary = piece["groups"][0]["piece"]
	assert_almost_eq(float(piece["height_m"]), float(child["height_m"]) * (child["node"] as Node3D).scale.x, 0.0001)
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	mesh.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var signals := Map3DBattleSignals.new()
	signals.apply_snapshot({"battle_signals": [{"key": "flag", "kind": "refusal", "unit_code": "own"}]})
	signals.sync({"own": piece}, {"refusal": scene}, 1.0, 1.5, repo, func(_xz: Vector2) -> float: return 20.0)
	assert_eq(signals.count(), 1)
	var flag: Node3D = (piece["node"] as Node3D).get_child(1)
	assert_almost_eq(flag.scale.y, float(piece["height_m"]), 0.0001, "identity aggregate supplies built-world height")

func test_physical_footprint_measures_nested_model_transforms() -> void:
	var helper: GDScript = load("res://scripts/map3d/map3d_battle_groups.gd")
	assert_true(helper.has_method("model_bounds"))
	if not helper.has_method("model_bounds"):
		return
	var root := Node3D.new()
	autofree(root)
	var figure := Node3D.new()
	figure.position.x = 2.0
	figure.scale = Vector3.ONE * 2.0
	root.add_child(figure)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 2, 3)
	mesh.mesh = box
	figure.add_child(mesh)
	var measured: AABB = helper.model_bounds(root)
	assert_eq(measured.position, Vector3(1, -2, -3))
	assert_eq(measured.size, Vector3(2, 4, 6))

## Opt-in authoring of synthetic saves; these prove the consumer, never N0 behavior.
func test_export_frozen_consumer_inputs() -> void:
	var directory := OS.get_environment("G1_EXPORT_DIR")
	if directory == "":
		pass_test("scratch save export is opt-in")
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var manifest: Dictionary = {"synthetic_consumer_only": true, "cases": {}}
	for n: int in [800, 1000, 10000, 51]:
		var repo := SuiteData.repo()
		var state := SuiteData.campaign(repo, 7)
		var own_codes: Array = []
		for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
			if MapObjects.army_piece(repo, reg) == "infantry":
				own_codes.append(String(reg["regiment_code"]))
		assert_gte(own_codes.size(), 2)
		if own_codes.size() < 2:
			return
		var code := String(own_codes[0])
		var origin := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state))
		var focus := origin
		var best := INF
		for cell: Dictionary in repo.cells.values():
			if MapTerrain.is_water(cell):
				continue
			var candidate := MapTerrain.cell_center(repo, cell)
			var distance := candidate.distance_to(origin)
			if distance < best and ArmySystem.town_at(repo, candidate) == "":
				focus = candidate
				best = distance
		var anchor := ArmySystem.pack_to_metres(repo, focus)
		var personnel := preload("res://tests/engine/personnel_helpers.gd")
		personnel.replace(repo, state, code, n)
		state.regiments[code]["x_m"] = anchor.x
		state.regiments[code]["y_m"] = anchor.y
		var foes := state.foes.keys()
		foes.sort()
		assert_gte(foes.size(), 3)
		if foes.size() < 3:
			return
		var foe := String(foes[0])
		personnel.replace(repo, state, foe, 51)
		state.foes[foe]["x_m"] = anchor.x + 500
		state.foes[foe]["y_m"] = anchor.y
		var events: Array = []
		BattleSystem._start(repo, state, code, foe, "", events)
		var battle := BattleSystem.battle_of(state, code)
		if n == 51:
			var second := String(own_codes[1])
			personnel.replace(repo, state, second, 51)
			state.regiments[second]["x_m"] = anchor.x
			state.regiments[second]["y_m"] = anchor.y + 300
			assert_true(BattleSystem.join(repo, state, int(battle["id"]), second, BattleRules.side_of(battle, code)))
			assert_eq(WarRoom.pieces(repo, state).filter(func(row: Dictionary) -> bool: return String(row["code"]) in [code, second]).size(), 2, "two 51-person actual units retain two WAR ROOM pieces")
		var ghost := String(foes[1])
		var hidden := String(foes[2])
		for enemy: String in [ghost, hidden]:
			state.foes[enemy]["x_m"] = anchor.x + 1000000
			state.foes[enemy]["y_m"] = anchor.y + 1000000
		Sighting.record(state, ghost, {"kind": Sighting.KIND_UNIT, "code": ghost,
			"x_m": anchor.x - 5000, "y_m": anchor.y, "day": state.absolute_day(), "source": Sighting.SEEN, "men": 1000})
		# Hidden groups exist in a separate synthetic battle; they must never enter capture evidence.
		state.battles.append({"id": int(battle["id"]) + 1, "att": [hidden, ghost], "def": [],
			"groups": {hidden: [{"count": 1, "role": "front", "x_m": anchor.x, "y_m": anchor.y}],
				ghost: [{"count": 1, "role": "front", "x_m": anchor.x, "y_m": anchor.y}]},
			"group_facing": {hidden: 0, ghost: 0}})
		BattleGroups.refresh(repo, state, battle)
		if n == 10000:  # Synthetic folded ranks test the consumer, never N0 deployment.
			var spacing := int(repo.bal("battle_group_spacing_m"))
			var depth := int(repo.bal("battle_group_depth_m"))
			for i in (battle["groups"][code] as Array).size():
				var row: Dictionary = battle["groups"][code][i]
				var rank := floori(float(i) / 20.0)
				row["x_m"] = anchor.x - rank * depth
				row["y_m"] = anchor.y + (i % 20 - 10) * spacing
				row["role"] = "front" if rank == 0 else "reserve"
			battle["group_facing"][code] = 0
		var path := directory.path_join("consumer-%d.json" % n)
		assert_true(SaveLoad.save_game(state, path))
		var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
		ctx.state_fn = func() -> GameState: return state
		assert_eq(Map3DBattleGroups.sample(ctx, code)["rows"].size(), ceili(float(n) / 50.0))
		assert_eq(Map3DBattleGroups.sample(ctx, hidden)["rows"], [])
		assert_eq(Map3DBattleGroups.sample(ctx, ghost)["rows"], [])
		assert_true(Sighting.seen_foes(repo, state).has(foe), "visible enemy fixture is actually admitted")
		assert_true(ctx.ghosts().any(func(row: Dictionary) -> bool: return row["key"] == ghost))
		manifest["cases"][str(n)] = {"save": path, "sha256": FileAccess.get_sha256(path),
			"focus_pack": [focus.x, focus.y], "unit": code, "visible_enemy": foe, "ghost": ghost, "hidden": hidden,
			"near": repo.bal("map3d_zoom_min_m"), "far": repo.bal("map3d_zoom_min_m") * 5.0}
		if n == 800:
			for row: Dictionary in battle["groups"][code]:
				row["slot"] = (battle["groups"][code] as Array).find(row) + 10
				row["path_m"] = [[row["x_m"], row["y_m"]]]
			assert_true(SaveLoad.save_game(state, directory.path_join("consumer-additive.json")))
			state.battles[1]["groups"][hidden][0]["x_m"] += 30000
			state.battles[1]["groups"][ghost][0]["count"] = 49
			state.foes[hidden]["x_m"] += 30000
			assert_true(SaveLoad.save_game(state, directory.path_join("consumer-hidden-mutated.json")))
	var file := FileAccess.open(directory.path_join("inputs.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()

func test_evidence_bounds_enclose_actual_rotated_model() -> void:
	var repo := SuiteData.repo()
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var piece := Map3DBattleGroups.build(repo, reg, {"rows": [
		{"slot": 0, "count": 1, "role": "front", "x_m": 200, "y_m": 300}], "facing_deg": 37})
	add_child_autofree(piece["node"])
	var ctx := Map3DContext.new(repo, {"pack_origin": [-100, 50], "m_per_px": 2.0})
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 1.6, false)
	var child: Dictionary = piece["groups"][0]["piece"]
	var node: Node3D = child["node"]
	var bounds := Map3DBattleGroups.model_bounds(node)
	var values: Array = Map3DBattleGroups.evidence(piece)[0]["bounds_world"]
	var drawn := Rect2(values[0], values[1], values[2], values[3]).grow(0.0001)
	for i in 8:
		var world := node.global_transform * bounds.get_endpoint(i)
		assert_true(drawn.has_point(Vector2(world.x, world.z)), "bounds must include rotated rectangle corners")

func test_stale_nodes_cannot_export_hidden_live_groups() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var foe := String(state.foes.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, foe, 1)
	state.foes[foe]["x_m"] = -1000000
	state.foes[foe]["y_m"] = -1000000
	state.battles = [{"att": [foe], "def": [], "groups": {foe: [
		{"count": 1, "role": "front", "x_m": 200, "y_m": 300}]}, "group_facing": {foe: 90}}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.dev = true
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var piece := layer._piece_of(foe)
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 1.6, false)
	assert_true(layer.group_geometry().has(foe))
	ctx.dev = false
	assert_eq(layer.group_geometry(), {}, "lost admission is enforced even before next roster refresh")

func test_signal_resizes_when_physical_model_scale_changes() -> void:
	var repo := SuiteData.repo()
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var piece := Map3DBattleGroups.build(repo, reg, {"rows": [
		{"slot": 0, "count": 1, "role": "front", "x_m": 200, "y_m": 300}], "facing_deg": 90})
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.add_child(piece["node"])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.view_size = Vector2(1920, 1080)
	layer.bind(ctx)
	layer._pieces["own"] = piece
	var model := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	mesh.owner = model
	var scene := PackedScene.new()
	scene.pack(model)
	model.free()
	layer.battle_refusal_flag = scene
	layer._battle.apply_snapshot({"battle_signals": [{"key": "flag", "kind": "refusal", "unit_code": "own"}]})
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 1.6, false)
	layer._sync_battle_signals()
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 3.2, false)
	layer._sync_battle_signals()
	var flag: Node3D = layer._battle._nodes["flag"]
	assert_almost_eq(flag.scale.y, float(piece["height_m"]), 0.0001)

func test_ghost_nodes_keep_last_known_geometry_after_hidden_mutation() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var foe := String(state.foes.keys()[0])
	state.foes[foe]["x_m"] = -1000000
	state.foes[foe]["y_m"] = -1000000
	Sighting.record(state, foe, {"kind": Sighting.KIND_UNIT, "code": foe, "x_m": 200, "y_m": 300,
		"day": state.absolute_day(), "source": Sighting.SEEN, "men": 1000})
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(1920, 1080)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	layer._roster()
	var key := Sighting.GHOST_CODE + foe
	assert_true(layer.has_piece(key))
	var piece := layer.built_piece(key)
	layer._place(key, piece)
	var node: Node3D = piece["node"]
	var before := node.global_transform
	var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var old_scale := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference, piece["height_m"], piece["size"])
	assert_almost_eq(node.scale.x, old_scale, 0.001, "ghost retains the original readable miniature size")
	assert_almost_eq(float(piece.get("camp_scale", -1)), old_scale, 0.001)
	ctx.distance *= 2.0
	ctx.target += Vector2(20, 30)
	layer._place(key, piece)
	assert_eq(node.global_transform, before, "view-only camera changes do not resize or move a ghost")
	var figures: int = piece["figures"]
	state.battles = [{"att": [foe], "def": [], "groups": {foe: [
		{"slot": 99, "count": 1, "role": "front", "x_m": 9999, "y_m": 9999, "path_m": [[1, 2]]}]}, "group_facing": {foe: 180}}]
	state.foes[foe]["x_m"] -= 30000
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, foe, 1)
	layer._roster()
	layer._place(key, layer.built_piece(key))
	assert_eq(layer.built_piece(key)["node"], node)
	assert_eq(node.global_transform, before, "hidden live movement/facing/losses cannot move a ghost")
	assert_eq(layer.built_piece(key)["figures"], figures, "ghost keeps its existing last-known presentation")
	assert_ne(layer.built_piece(key)["layout"], "physical_groups")
	assert_eq(layer.group_geometry(), {})

func test_physical_groups_keep_informed_attack_chains_and_slot_keys() -> void:
	var repo := SuiteData.repo()
	repo.balance["map3d_unit_chain_rest_min_s"] = 0.0
	repo.balance["map3d_unit_chain_rest_max_s"] = 0.0
	var reg: Dictionary = {}
	for row: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if MapObjects.army_piece(repo, row) == "infantry":
			reg = row
			break
	assert_false(reg.is_empty())
	if reg.is_empty():
		return
	var piece := Map3DBattleGroups.build(repo, reg, {"rows": [
		{"slot": 7, "count": 50, "role": "front", "x_m": 200, "y_m": 300},
		{"slot": 9, "count": 1, "role": "reserve", "x_m": 230, "y_m": 340}], "facing_deg": 90})
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.add_child(piece["node"])
	layer.bind(Map3DContext.new(repo, {}))
	layer._pieces["unit"] = piece
	layer.play("unit", "ATTACK")
	for group: Dictionary in piece["groups"]:
		var anim: AnimationPlayer = group["piece"]["anims"][0]
		assert_true(anim.has_meta("chain"), "informed battle attack retains the arm's authored clip chain")
		if anim.has_meta("chain"):
			assert_eq(anim.get_meta("chain")["code"], "unit:" + str(group["slot"]))
	layer.play("unit", "GARRISON")
	# Drain cancelled fixture guards before freeing their animation players.
	await wait_process_frames(2)

func test_nonbattle_fit_count_and_same_day_recovery_rebuild() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)[0]
	var code := String(reg.regiment_code)
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.ctx = ctx
	var personnel := preload("res://tests/engine/personnel_helpers.gd")
	var want := [0, 1, 1, 2, 9, 10]
	var ns := [0, 1, 100, 101, 900, 1000]
	for i: int in ns.size():
		personnel.replace(repo, state, code, ns[i])
		var piece: Dictionary = layer._piece_of(code)
		assert_eq(int(piece.get("figures", 0)), int(want[i]), "fit=%d" % ns[i])
	personnel.replace(repo, state, code, 1000)
	personnel.move(repo, state, code, "fit", "wounded", 100)
	var key: Array = layer._roster_key().duplicate(true)
	personnel.move(repo, state, code, "wounded", "fit", 100)
	assert_ne(layer._roster_key(), key, "same-day fit changes invalidate ordinary formations")
	assert_eq(int(layer._piece_of(code).figures), 10)

func test_zero_fit_has_no_model_hit_box_and_fleet_keeps_counter_path() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 0)
	state.battles = [{"att": [code], "def": [], "groups": {code: []}, "group_facing": {code: 0}}]
	var piece := layer._piece_of(code)
	layer._shown_xz[code] = Vector2.ZERO
	layer._place(code, piece)
	assert_false(layer.screen_rects().has(code), "empty physical roots contribute no phantom pick box")
	for reg: Dictionary in ctx.regiments():
		if String(reg.get("is_naval", "0")) != "1": continue
		var fleet := String(reg.regiment_code)
		state.battles = [{"att": [fleet], "def": []}]
		BattleGroups.refresh(repo, state, state.battles[0])
		assert_eq(layer._piece_of(fleet), {}, "naval groups never create an empty soldier piece that suppresses its counter")
		return
	fail_test("fixture needs a fleet")

func test_pending_legacy_rows_and_version_are_read_without_truncation() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 1000)
	var rows: Array = []
	for i: int in 20:
		rows.append({"slot": i, "count": 50, "role": "front", "x_m": i * 50, "y_m": 0})
	var battle := {"att": [code], "def": [], "groups": {code: rows}, "group_facing": {code: 0}, "pending_round": {"roll": 7}}
	state.battles = [battle]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var before := SaveLoad.state_hash(state)
	var sample := Map3DBattleGroups.sample(ctx, code)
	assert_eq(sample.mode, "groups")
	assert_eq(sample.rows.size(), 20, "legitimate frozen legacy rows are not cut to ten")
	assert_eq(SaveLoad.state_hash(state), before)
	battle.erase("pending_round")
	assert_eq(MilitaryReorganization.reconcile(repo, state).status, "complete")
	var migrated := Map3DBattleGroups.sample(ctx, code)
	assert_eq(migrated.mode, "groups")
	assert_eq(migrated.rows.size(), 10)
	assert_ne(migrated.key, sample.key)

func test_completed_version_rejects_uncollapsed_partial_rows() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 100)
	state.battles = [{"att": [code], "def": [], "groups": {code: [
		{"slot": 0, "count": 50, "role": "front", "x_m": 0, "y_m": 0},
		{"slot": 1, "count": 50, "role": "front", "x_m": 50, "y_m": 0}]},
		"group_facing": {code: 0}, "group_size_version": 2, "group_size_men": 100}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	assert_eq(Map3DBattleGroups.sample(ctx, code).mode, "invalid")

func test_every_ordinary_arm_retains_original_readable_scale() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(1280, 720)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 100, 100)
	ctx.camera.look_at(Vector3.ZERO)
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var checked := {}
	for reg: Dictionary in ctx.regiments():
		var arm := MapObjects.army_piece(repo, reg)
		if checked.has(arm) or String(reg.get("is_naval", "0")) == "1": continue
		var code := String(reg.regiment_code)
		var piece := layer._piece_of(code)
		if piece.is_empty(): continue
		layer._shown_xz[code] = Vector2.ZERO
		layer._place(code, piece)
		var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
		var expected := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference, piece["height_m"], piece["size"])
		assert_almost_eq((piece["node"] as Node3D).scale.x, expected, 0.0001, arm + " original scale")
		checked[arm] = true
	assert_true(checked.has("infantry"))
	assert_true(checked.has("archers"))
	assert_true(checked.has("cavalry"))
	var ordinary: Dictionary = layer._pieces.values()[0]
	var ordinary_code := String(layer._pieces.keys()[0])
	var node: Node3D = ordinary.node
	var scale_before := node.scale.x
	var camp_before: float = ordinary.camp_scale
	assert_not_null(layer.get("figure_footprint_gap"), "legacy scene property remains compatible")
	if layer.get("figure_footprint_gap") == null: return
	layer.set("figure_footprint_gap", 0.8)
	layer._place(ordinary_code, ordinary)
	assert_almost_eq(node.scale.x, scale_before, 0.0001, "physical battle spacing cannot resize ordinary figures")
	assert_eq(float(ordinary.camp_scale), camp_before)
	var capped_scale := node.scale.x
	layer.formation_gap = 3.2
	layer._place(ordinary_code, ordinary)
	assert_eq(node.scale.x, capped_scale, "layout spacing cannot shrink the per-figure ceiling")

func test_saved_size_cannot_override_the_current_people_per_figure() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 1000)
	state.battles = [{"att": [code], "def": [], "groups": {code: [{"count": 1000, "slot": 0,
		"role": "front", "x_m": 0, "y_m": 0}]}, "group_facing": {code: 0},
		"group_size_version": 2, "group_size_men": 1000}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	assert_eq(Map3DBattleGroups.sample(ctx, code).mode, "invalid")
	ctx.state_fn = Callable()

func _seat_cache_fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var rows := [{"slot": 3, "count": 100, "role": "front", "x_m": 200, "y_m": 300},
		{"slot": 7, "count": 1, "role": "reserve", "x_m": 800, "y_m": 300}]
	var piece := Map3DBattleGroups.build(repo, reg, {"rows": rows, "facing_deg": 37})
	add_child_autofree(piece["node"])
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.view_size = Vector2(1920, 1080)
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(0, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	var calls := [0]
	ctx.height_fn = func(at: Vector2) -> float:
		calls[0] += 1
		return 4.0 + at.x * 0.1 + at.y * 0.05
	return {"repo": repo, "reg": reg, "rows": rows, "piece": piece, "ctx": ctx, "calls": calls}

func test_camera_pan_reuses_physical_seats_but_updates_pick_boxes() -> void:
	var f := _seat_cache_fixture()
	Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
	assert_gt(int(f.calls[0]), 0)
	var child: Node3D = f.piece.groups[0].piece.node
	var pose := child.global_transform
	var bounds: Array = f.piece.groups[0].bounds_world.duplicate()
	var screen: Array = f.piece.groups[0].screen_bounds.duplicate()
	f.calls[0] = 0
	f.ctx.camera.position.x += 50
	f.ctx.camera.look_at(Vector3.ZERO)
	Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
	assert_eq(int(f.calls[0]), 0, "a camera pan must not repeat stationary terrain seating")
	assert_eq(child.global_transform, pose)
	assert_eq(f.piece.groups[0].bounds_world, bounds)
	assert_ne(f.piece.groups[0].screen_bounds, screen, "picking still follows the actual camera")

func test_physical_seat_cache_invalidates_for_points_facing_size_and_ground() -> void:
	var f := _seat_cache_fixture()
	Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
	for change: String in ["point", "facing", "size", "ground", "context"]:
		f.calls[0] = 0
		var child: Dictionary = f.piece.groups[0].piece
		var before: Transform3D = child.node.global_transform
		match change:
			"point": f.piece.groups[0].x_m += 1000
			"facing": f.piece.facing_deg += 90
			"size": child["size"] *= 1.1
			"ground":
				var calls: Array = f.calls
				f.ctx.height_fn = func(_at: Vector2) -> float:
					calls[0] += 1
					return 200.0
			"context":
				var ctx := Map3DContext.new(f.repo, f.ctx.meta.duplicate())
				ctx.camera = f.ctx.camera
				ctx.view_size = f.ctx.view_size
				ctx.height_fn = f.ctx.height_fn
				f.ctx = ctx
		Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
		assert_gt(int(f.calls[0]), 0, change + " must resample the actual ground")
		if change != "context": assert_ne(child.node.global_transform, before, change)

func test_row_reconciliation_reuses_seat_and_retains_measured_bounds() -> void:
	var f := _seat_cache_fixture()
	Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
	var before := Map3DBattleGroups.evidence(f.piece)
	var survivor: Node3D = f.piece.groups[0].piece.node
	f.rows[0].count = 99
	Map3DBattleGroups.sync(f.repo, f.reg, f.piece, {"rows": f.rows, "facing_deg": 37})
	f.calls[0] = 0
	Map3DBattleGroups.place(f.ctx, f.piece, Vector2.ZERO, 1.6, false)
	assert_eq(int(f.calls[0]), 0, "count reconciliation cannot invalidate unchanged physical seats")
	assert_eq(f.piece.groups[0].piece.node, survivor)
	var after := Map3DBattleGroups.evidence(f.piece)
	assert_eq(after[0].count, 99)
	assert_eq(after[0].bounds_world, before[0].bounds_world)
	assert_eq(after[0].screen_bounds, before[0].screen_bounds)

func test_calibrated_physical_ground_contains_each_unchanged_arm_model() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var ctx := Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	var factor := 50.0 / ArmySystem.metres_per_pack_px(repo)
	var checked := {}
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var model := MapObjects.army_piece(repo, reg)
		if checked.has(model) or String(reg.get("is_naval", "0")) == "1": continue
		var radius := BattleGroups.figure_radius(repo, reg) * factor
		var piece := Map3DBattleGroups.build(repo, reg, {"rows": [
			{"slot": 0, "count": 100, "role": "front", "x_m": 10000, "y_m": 10000}], "facing_deg": 0})
		add_child_autofree(piece["node"])
		Map3DBattleGroups.place(ctx, piece, ctx.to_world(ArmySystem.metres_to_pack(repo, Vector2i(10000, 10000))), 1.6, false)
		var child: Dictionary = piece.groups[0].piece
		var centre: Vector3 = (child.node as Node3D).global_position
		for corner: Vector3 in child.world_corners:
			assert_lte(Vector2(corner.x - centre.x, corner.z - centre.z).length(), radius,
				model + " visible model must fit the engine's calibrated terrain footprint")
		checked[model] = true
	assert_true(checked.has("infantry"))
	assert_true(checked.has("archers"))
	assert_true(checked.has("cavalry"))
