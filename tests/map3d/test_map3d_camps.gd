extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")


func test_phase_selects_its_asset_key() -> void:
	for phase: String in ["building", "camped", "packing"]:
		assert_eq(Map3DUnitCamps.asset_key({"phase": phase}), phase)
	assert_eq(Map3DUnitCamps.asset_key({"phase": "none"}), "")
	assert_eq(Map3DUnitCamps.asset_key({}), "")


func test_packing_uses_the_complete_saved_day_and_never_restores_under_attack() -> void:
	var camp := {"phase": "packing", "build_progress": 1000,
		"pack_start_day": 11, "move_not_before_day": 12}
	assert_eq(Map3DUnitCamps.progress(camp, 10, 0.9, 2), 1.0, "a late order waits until tomorrow")
	assert_eq(Map3DUnitCamps.progress(camp, 11, 0.25, 2), 0.75)
	camp["under_attack"] = true
	assert_eq(Map3DUnitCamps.progress(camp, 11, 0.75, 2), 0.25)
	assert_eq(Map3DUnitCamps.progress(camp, 12, 0.0, 2), 0.0)
	assert_eq(Map3DUnitCamps.progress(camp, 13, 0.0, 2), 0.0)


func test_building_pitches_progressively_and_partial_camps_pack_from_their_actual_stage() -> void:
	var camp := {"phase": "building", "build_progress": 250}
	assert_eq(Map3DUnitCamps.progress(camp, 10, 0.5, 2), 0.5)
	camp["phase"] = "packing"
	camp["pack_start_day"] = 10
	camp["move_not_before_day"] = 11
	assert_eq(Map3DUnitCamps.progress(camp, 10, 0.5, 2), 0.125)
	assert_eq(Map3DUnitCamps.facility_share(0.25, 0, 6), 1.0)
	assert_eq(Map3DUnitCamps.facility_share(0.25, 1, 6), 0.5)
	assert_eq(Map3DUnitCamps.facility_share(0.25, 2, 6), 0.0)


func test_snapshot_is_copied_and_forwarded_by_units() -> void:
	var snapshot := {"absolute_day": 10, "camps": {"u": {"phase": "camped",
		"site": {"x_m": 1000, "y_m": 2000}}}}
	var layer := Map3DLayerUnits.new()
	layer.apply_snapshot(snapshot)
	snapshot["camps"]["u"]["phase"] = "none"
	assert_eq(layer._camps._snapshot["camps"]["u"]["phase"], "camped")
	layer.free()


func test_candidate_search_is_bounded_and_never_uses_a_blocked_fallback() -> void:
	var visited: Array = []
	var at: Variant = Map3DUnitCamps.clear_site(Vector2(10, 20), 5.0,
		func(p: Vector2) -> bool:
			visited.append(p)
			return false)
	assert_null(at)
	assert_eq(visited.size(), 9)
	assert_eq(visited[0], Vector2(10, 20))
	var good := Vector2(15, 20)
	assert_eq(Map3DUnitCamps.clear_site(Vector2(10, 20), 5.0,
		func(p: Vector2) -> bool: return p == good), good)


func test_saved_site_stays_put_and_facilities_stand_plumb_on_their_own_slope() -> void:
	var repo := SuiteData.repo()
	repo.cells = {0: {"water": "", "vertex_ids": PackedInt32Array([0, 1, 2, 3])}}
	repo.vertices = {0: Vector2.ZERO, 1: Vector2(500, 0), 2: Vector2(500, 500), 3: Vector2(0, 500)}
	var ctx := Map3DContext.new(repo, {"m_per_px": 1.0, "pack_origin": [0, 0], "pack_px": [500, 500]})
	ctx.height_fn = func(p: Vector2) -> float: return 5.0 + p.x * 0.1 + p.y * 0.05
	var share := [0.0]
	ctx.day_fn = func() -> float: return share[0]
	var presenter := Map3DUnitCamps.new()
	# Keep this fixture independent of the built world's art and geometry.
	presenter._geometry_ctx = ctx
	presenter._at_sea = func(_p: Vector2) -> bool: return false
	var layer := Node3D.new()
	add_child_autofree(layer)
	var root := Node3D.new()
	layer.add_child(root)
	for label: String in ["CommandTent", "TentA"]:
		var facility := Node3D.new()
		facility.name = label
		facility.position.x = -4.0 if label == "CommandTent" else 4.0
		root.add_child(facility)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		(mesh.mesh as BoxMesh).size = Vector3(2, 2, 2)
		mesh.position.y = 1.0
		facility.add_child(mesh)
	presenter.camps["u"] = root
	var site := ArmySystem.pack_to_metres(repo, Vector2(100, 100))
	var camp := {"phase": "camped", "build_progress": 1000, "site": {"x_m": site.x, "y_m": site.y}}
	presenter.apply_snapshot({"absolute_day": 10, "camps": {"u": camp}})
	presenter.sync(layer, ctx, "u", {"extent": Vector2.ZERO}, Vector2.ZERO, 0.0, 1.0, 0.0)
	var a := root.get_node("CommandTent") as Node3D
	var b := root.get_node("TentA") as Node3D
	assert_eq(a.global_basis.y, Vector3.UP)
	assert_almost_eq(a.global_position.y, 5.0 + 97.0 * 0.1 + 101.0 * 0.05 + repo.bal("map3d_house_seat_clear_m"), 0.001)
	assert_gt(b.global_position.y, a.global_position.y, "each facility samples its own footprint")
	var anchored := root.global_position
	camp["phase"] = "packing"
	camp["pack_start_day"] = 10
	camp["move_not_before_day"] = 11
	presenter.apply_snapshot({"absolute_day": 10, "camps": {"u": camp}})
	share[0] = 0.75
	presenter.sync(layer, ctx, "u", {"extent": Vector2.ZERO}, Vector2(300, 300), PI, 1.0, 0.0)
	assert_eq(root.global_position, anchored, "the regiment's movement and turn cannot drag its saved camp")
	assert_almost_eq(a.scale.y, 0.5, 0.001)
	assert_false(b.visible)
	camp["under_attack"] = true
	presenter.apply_snapshot({"absolute_day": 10, "camps": {"u": camp}})
	share[0] = 0.875
	presenter.sync(layer, ctx, "u", {"extent": Vector2.ZERO}, Vector2.ZERO, 0.0, 1.0, 0.0)
	assert_almost_eq(a.scale.y, 0.25, 0.001, "attack cannot rebuild dismantled facilities")
	# A suspended day's save can be loaded with a fresh UI clock fraction.
	presenter.apply_snapshot({"absolute_day": 10, "day_committed": true, "camps": {"u": camp}})
	share[0] = 0.0
	presenter.sync(layer, ctx, "u", {}, Vector2.ZERO, 0.0, 1.0, 0.0)
	assert_false(a.visible, "the resolved packing day cannot rebuild on a blocked encounter")


func test_rigid_facilities_are_removed_without_squashing_people_or_carts() -> void:
	var repo := SuiteData.repo()
	var ctx := Map3DContext.new(repo, {"m_per_px": 1.0, "pack_origin": [0, 0], "pack_px": [500, 500]})
	var layer := Node3D.new()
	add_child_autofree(layer)
	var root := Node3D.new()
	layer.add_child(root)
	var facilities: Array = []
	for label: String in ["CommandTent", "SupplyCart", "Watch", "Stores"]:
		var facility := Node3D.new()
		facility.name = label
		root.add_child(facility)
		facilities.append({"node": facility, "placed": true, "scale": Vector3.ONE})
	root.set_meta("facilities", facilities)
	root.set_meta("layout_key", [Vector2(100, 100), 1.0])
	var presenter := Map3DUnitCamps.new()
	presenter.camps["u"] = root
	var site := ArmySystem.pack_to_metres(repo, Vector2(100, 100))
	for built: int in [375, 625, 875]:
		presenter.apply_snapshot({"absolute_day": 10, "camps": {"u": {"phase": "building", "build_progress": built,
			"site": {"x_m": site.x, "y_m": site.y}}}})
		presenter.sync(layer, ctx, "u", {"extent": Vector2.ZERO}, Vector2.ZERO, 0.0, 1.0, 0.0)
		for label: String in ["SupplyCart", "Watch", "Stores"]:
			assert_eq((root.get_node(NodePath(label)) as Node3D).scale, Vector3.ONE, label + " retains physical proportions")


func test_steep_facility_footprints_are_refused_instead_of_perched_at_the_high_corner() -> void:
	var repo := SuiteData.repo()
	repo.cells = {0: {"water": "", "vertex_ids": PackedInt32Array([0, 1, 2, 3])}}
	repo.vertices = {0: Vector2.ZERO, 1: Vector2(500, 0), 2: Vector2(500, 500), 3: Vector2(0, 500)}
	var ctx := Map3DContext.new(repo, {"m_per_px": 1.0, "pack_origin": [0, 0], "pack_px": [500, 500]})
	var presenter := Map3DUnitCamps.new()
	presenter._at_sea = func(_p: Vector2) -> bool: return false
	var h := {"at": Vector2(100, 100), "scale": 1.0, "yaw_deg": 0.0}
	var box := AABB(Vector3(-5, 0, -5), Vector3(10, 2, 10))
	var cap := float(repo.map3d_bake["house_max_drop_m"])
	ctx.height_fn = func(p: Vector2) -> float: return p.x * cap / 20.0
	assert_true(presenter._clear(ctx, h, box, []), "drop is half the existing house cap")
	ctx.height_fn = func(p: Vector2) -> float: return p.x * cap / 5.0
	assert_false(presenter._clear(ctx, h, box, []), "twice the permitted ground drop must be refused")
	assert_null(Map3DUnitCamps.clear_site(Vector2(100, 100), 10.0,
		func(p: Vector2) -> bool:
			h["at"] = p
			return presenter._clear(ctx, h, box, [])), "no bounded candidate can hide a uniformly steep plot")


func test_installed_stage_assets_share_the_camp_scene_with_separated_facilities() -> void:
	var path := "res://scenes/models/buildings/field_camp.tscn"
	for phase: String in ["building", "camped", "packing"]:
		assert_eq(GameArt.path(GameArt.CAMP_MODELS, Map3DUnitCamps.asset_key({"phase": phase})), path)
	var scene := load(path) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return
	var camp := scene.instantiate() as Node3D
	autofree(camp)
	var footprints: Array = []
	for label: String in Map3DUnitCamps.FACILITIES:
		var node := camp.get_node_or_null(NodePath(label)) as Node3D
		assert_not_null(node, label + " is independently staged and grounded")
		if node == null:
			continue
		var box := node.transform * Map3DUnitCamps._box(node)
		assert_gt(box.size.length(), 0.0, label + " has real model geometry")
		var polygon := Map3DHouseApron.corners({"at": Vector2.ZERO, "scale": 1.0, "yaw_deg": 0.0}, box, 0.0)
		for other: Dictionary in footprints:
			assert_true(Geometry2D.intersect_polygons(polygon, other["polygon"]).is_empty(),
				label + " has a separated footprint from " + String(other["name"]))
		footprints.append({"name": label, "polygon": polygon})


func test_canopy_coverage_rejects_a_footprint_and_respects_pack_origin_and_image_bounds() -> void:
	var repo := SuiteData.repo()
	repo.cells = {0: {"water": "", "vertex_ids": PackedInt32Array([0, 1, 2, 3])}}
	repo.vertices = {0: Vector2.ZERO, 1: Vector2(500, 0), 2: Vector2(500, 500), 3: Vector2(0, 500)}
	var ctx := Map3DContext.new(repo, {"m_per_px": 1.0, "pack_origin": [1000, 2000], "pack_px": [500, 500]})
	ctx.height_fn = func(_p: Vector2) -> float: return 5.0
	var presenter := Map3DUnitCamps.new()
	presenter._at_sea = func(_p: Vector2) -> bool: return false
	var h := {"at": Vector2(1100, 2100), "scale": 1.0, "yaw_deg": 0.0}
	var box := AABB(Vector3(-5, 0, -5), Vector3(10, 2, 10))
	assert_true(presenter._clear(ctx, h, box, []), "an absent optional canopy map imposes no restriction")
	var woods := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	woods.fill(Color(0, 1, 1, 1))
	presenter.set("_woods", woods)
	assert_true(presenter._clear(ctx, h, box, []), "only the red canopy channel blocks the plot")
	woods.set_pixel(2, 2, Color(1.0 / 255.0, 0, 0, 1))
	assert_false(presenter._clear(ctx, h, box, []), "any canopy coverage under the footprint blocks it")
	h["at"] = Vector2(1400, 2400)
	assert_true(presenter._clear(ctx, h, box, []), "image bounds are checked before reading")

func test_recreating_the_view_cannot_move_camp_with_regiment_facing_or_formation() -> void:
	var repo := SuiteData.repo()
	var ctx := Map3DContext.new(repo, {"m_per_px": 1.0, "pack_origin": [0, 0], "pack_px": [500, 500]})
	var site := ArmySystem.pack_to_metres(repo, Vector2(100, 100))
	var snapshot := {"absolute_day": 10, "camps": {"u": {"phase": "camped", "build_progress": 1000, "site": {"x_m": site.x, "y_m": site.y}}}}
	var transforms: Array = []
	for yaw: float in [0.0, PI]:
		var presenter := Map3DUnitCamps.new()
		presenter._geometry_ctx = ctx
		presenter._at_sea = func(_point: Vector2) -> bool: return false
		var layer := Node3D.new()
		add_child_autofree(layer)
		var root := Node3D.new()
		layer.add_child(root)
		presenter.camps["u"] = root
		presenter.apply_snapshot(snapshot)
		presenter.sync(layer, ctx, "u", {"extent": Vector2.ONE if yaw == 0.0 else Vector2(9, 9)}, Vector2.ZERO, yaw, 1.0, 6.0)
		transforms.append(root.transform)
	assert_eq(transforms[0], transforms[1], "camp belongs to its saved site across screen recreation")
