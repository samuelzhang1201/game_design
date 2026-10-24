extends GutTest
## Map3DLayerHouses: independent settlement/type batches, rebuilt only when the camera
## moves far enough (spec 2026-09-20 §3).

const RunDir := preload("res://tests/run_dir.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
var _csv := RunDir.dir("map3d_layer_houses").path_join("test_map3d_layer_houses.csv")
## Fix round 1, finding 1: a distinctive, non-zero height so a refresh() that
## hardcoded or skipped the ctx.height_at() lookup could not pass by accident
## (0.0 or the fixture's own sea_y of 5.0 would both be too easy to fake).
const HEIGHT := 777.5

var _layer: Map3DLayerHouses
var _ctx: Map3DContext


func before_each() -> void:
	Game.start_campaign(42)
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var a := String(codes[0])
	var f := FileAccess.open(_csv, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	var b: Dictionary = Game.data.burgs[a]
	var at := Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
	f.store_line("%s,0,%f,%f,0,chapel,1.0,1.0" % [a, at.x, at.y])
	# cottage_a's scale and height_scale are deliberately DIFFERENT (0.8 vs
	# 2.0) so a layer that scaled uniformly (ignoring the column, or reusing
	# `scale` for both axes) would fail test_height_scale_reaches_the_transform.
	f.store_line("%s,1,%f,%f,90,cottage_a,0.8,2.0" % [a, at.x + 20.0, at.y])
	f.close()
	_ctx = Map3DContext.new(Game.data, WORLD)
	_ctx.height_fn = func(_xz: Vector2) -> float: return HEIGHT
	_layer = Map3DLayerHouses.new()
	_layer.houses_override = Map3DHouses.load_csv(_csv)
	add_child_autofree(_layer)
	_layer.bind(_ctx)


func test_each_type_keeps_its_total_count() -> void:
	_layer.refresh(_home())
	var counts := _layer.counts()
	assert_eq(counts.get("chapel", 0), 1)
	assert_eq(counts.get("cottage_a", 0), 1)


func test_every_instance_sits_on_the_ground() -> void:
	_layer.refresh(_home())
	var clear: float = Game.data.bal("map3d_house_seat_clear_m")
	# Deviation from the brief: under the headless dummy renderer GUT runs
	# under, MultiMeshInstance3D.get_instance_transform() never reflects what
	# set_instance_transform() wrote — verified directly, even for a
	# hand-built raw `buffer` assignment, so this is the renderer's storage
	# missing, not our code. transforms_of() records the Transform3D refresh()
	# ITSELF computed and handed to set_instance_transform, so this asserts on
	# what refresh() actually did — including its ctx.height_at() lookup — not
	# on a value the test supplies (fix round 1, finding 1).
	var checked := 0
	for type: String in _layer.counts():
		for t: Transform3D in _layer.transforms_of(type):
			assert_almost_eq(t.origin.y, HEIGHT + clear, 0.001,
				"a house stands on the ground, never sunk into it")
			checked += 1
	assert_eq(checked, 2, "both chapel and cottage_a were checked")


func test_a_small_camera_move_does_not_rebuild() -> void:
	assert_true(_layer.refresh(_home()), "the first call builds")
	var step: float = Game.data.bal("map3d_house_rebuild_move_m")
	assert_false(_layer.refresh(_home() + Vector2(step * 0.4, 0.0)),
		"cut once per camera pose, never per frame")
	assert_true(_layer.refresh(_home() + Vector2(step * 1.5, 0.0)),
		"a real move rebuilds")


func test_nothing_is_built_far_from_every_settlement() -> void:
	_layer.refresh(Vector2(500000.0, 500000.0))
	for type: String in _layer.counts():
		assert_eq(int(_layer.counts()[type]), 0, type + " has no instances out at sea")


func test_instances_carry_their_yaw_and_scale() -> void:
	_layer.refresh(_home())
	# Deviation from the brief (task 6 override 4): "cottage_a".capitalize()
	# returns "Cottage A" (capitalize() turns an underscore into a space), not
	# "Cottage_a" — verified against a headless Godot run. The layer names its
	# nodes after the raw _csv type instead, so the lookup here follows suit.
	var mmi := (_drawn_batches("cottage_a", true) + _drawn_batches("cottage_a", false))[0] as MultiMeshInstance3D
	assert_not_null(mmi)
	# Second deviation, same test: read the Transform3D refresh() itself
	# computed and handed to set_instance_transform (transforms_of()) rather
	# than reading it back from the MultiMesh, which the headless dummy
	# renderer never backs with real data (see
	# test_every_instance_sits_on_the_ground). A refresh() that
	# dropped the yaw or the scale fails this directly, since transforms_of()
	# is filled from inside refresh()'s own loop.
	var xforms := _layer.transforms_of("cottage_a")
	assert_eq(xforms.size(), 1)
	if xforms.size() > 0:
		var basis: Basis = (xforms[0] as Transform3D).basis
		assert_almost_eq(basis.get_euler().y, deg_to_rad(90.0), 0.01)


## Redesign owner 2026-09-20 (高低层次不齐): height_scale is a SEPARATE
## vertical multiplier, not folded into `scale`. cottage_a's fixture row
## carries scale 0.8 and height_scale 2.0, so a correct transform stands
## 0.8 wide/deep and 1.6 tall — three distinct values that could not agree
## by accident if the layer ignored the column or scaled uniformly.
func test_height_scale_reaches_the_transform() -> void:
	_layer.refresh(_home())
	var xforms := _layer.transforms_of("cottage_a")
	assert_eq(xforms.size(), 1)
	if xforms.size() > 0:
		var s := (xforms[0] as Transform3D).basis.get_scale()
		assert_almost_eq(s.x, 0.8, 0.01, "horizontal scale is the row's own scale")
		assert_almost_eq(s.z, 0.8, 0.01, "horizontal scale is the row's own scale")
		assert_almost_eq(s.y, 0.8 * 2.0, 0.01, "vertical scale is scale * height_scale")


## Owner 2026-09-24, twice: on a slope part of a house was buried in the
## hill, and then "要垂直于地面，不可以被地面遮住部分". A house stands upright on
## the HIGHEST ground anywhere under its footprint (a grid of samples, not
## just the corners), plus map3d_house_seat_clear_m, so no part of it is ever
## under the ground; its mesh's own stone footing (owner 2026-09-25) fills
## the downhill side down past the LOWEST sample.
func test_a_house_on_a_slope_stands_on_its_highest_ground_over_its_footing() -> void:
	var at := _home()
	_ctx.height_fn = func(xz: Vector2) -> float: return HEIGHT + 0.1 * (xz.x - at.x)
	_layer.refresh(at)
	var xforms := _layer.transforms_of("chapel")
	assert_eq(xforms.size(), 1)
	var mesh_box: AABB = _layer._aabbs["chapel"]
	var h := {"at": at, "scale": 1.0, "yaw_deg": 0.0}
	var ys: Array = []
	for c in Map3DHouses.footprint_grid(h, mesh_box, Game.data.bal("map3d_house_ground_inset"),
			int(Game.data.bal("map3d_house_ground_samples"))):
		ys.append(HEIGHT + 0.1 * (c.x - at.x))
	var highest: float = ys.max()
	var lowest: float = ys.min()
	assert_gt(highest - lowest, 1.0, "the fixture slope is real")
	if xforms.size() > 0:
		assert_almost_eq((xforms[0] as Transform3D).origin.y,
			highest + Game.data.bal("map3d_house_seat_clear_m"), 0.001,
			"a house stands on the highest ground under it, never buried")
	if xforms.size() > 0:
		var t := xforms[0] as Transform3D
		var footing_bottom := t.origin.y + t.basis.get_scale().y * mesh_box.position.y
		assert_lt(footing_bottom, lowest, "the chapel's own footing reaches below its lowest ground")


## A ridge BETWEEN the corners: a house that sampled only its corners stood
## below the crest and the crest came up through its floor.
func test_a_crest_between_the_corners_lifts_the_house() -> void:
	var at := _home()
	_ctx.height_fn = func(xz: Vector2) -> float: return HEIGHT + maxf(0.0, 4.0 - absf(xz.x - at.x))
	_layer.refresh(at)
	var xforms := _layer.transforms_of("chapel")
	assert_eq(xforms.size(), 1)
	if xforms.size() > 0:
		assert_gte((xforms[0] as Transform3D).origin.y, HEIGHT + 4.0 - 0.001,
			"the crest under the middle of the house is not inside it")


## Upright, never tilted with the slope: a building is plumb.
func test_a_house_on_a_slope_stays_upright() -> void:
	var at := _home()
	_ctx.height_fn = func(xz: Vector2) -> float: return HEIGHT + 0.3 * (xz.x - at.x) + 0.2 * (xz.y - at.y)
	_layer.refresh(at)
	for t: Transform3D in _layer.transforms_of("chapel"):
		assert_almost_eq(t.basis.y.normalized().dot(Vector3.UP), 1.0, 0.0001, "the house stands plumb")


## Steep ground no longer caps the seat and buries the uphill wall: even a
## steep site is stood on its highest ground, its foundation reaching down.
## (The bake keeps houses off such sites in the first place: map3d_bake.csv
## house_max_drop_m.)
func test_a_steep_site_still_buries_nothing() -> void:
	var at := _home()
	_ctx.height_fn = func(xz: Vector2) -> float: return HEIGHT + 1.5 * (xz.x - at.x)
	_layer.refresh(at)
	var mesh_box: AABB = _layer._aabbs["chapel"]
	var h := {"at": at, "scale": 1.0, "yaw_deg": 0.0}
	var ground := Map3DHouses.ground_under(h, mesh_box, Game.data.bal("map3d_house_ground_inset"),
		int(Game.data.bal("map3d_house_ground_samples")), _ctx.height_at)
	for t: Transform3D in _layer.transforms_of("chapel"):
		assert_gte(t.origin.y, ground.y, "the uphill wall is not under the hill")


## No box is laid under a house any more (owner 2026-09-25: ugly and strange):
## the layer's only children are the per-type MultiMeshes (each type's
## shadowed and unshadowed pair, perf 2026-10-02).
func test_no_foundation_box_is_laid() -> void:
	_layer.refresh(_home())
	for c in _layer.get_children():
		assert_true(_layer._instances.values().has(c) or _layer._far.values().has(c),
			"%s is not a house type's MultiMesh" % c.name)


## Perf 2026-10-02: a settlement within map3d_house_shadow_m of the camera's
## target casts its houses' shadows; past it they stand in the type's
## unshadowed MultiMesh (a house a few px tall, its shadow a pixel, drawn into
## every cascade was half the geometry drawn).
func test_only_a_near_settlement_casts_shadows() -> void:
	var at := _home()
	_layer.refresh(at)
	var near: MultiMeshInstance3D = _drawn_batches("chapel", true)[0]
	assert_true(_drawn_batches("chapel", false).is_empty())
	assert_eq(near.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(near.multimesh.instance_count, 1, "at the camera: it casts")
	var off := Game.data.bal("map3d_house_shadow_m") + 500.0
	_layer.refresh(at + Vector2(off, 0.0))
	assert_false(near.visible)
	var far: MultiMeshInstance3D = _drawn_batches("chapel", false)[0]
	assert_eq(far.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(far.multimesh.instance_count, 1, "beyond the shadow reach: drawn, no shadow")
	assert_eq(_layer.counts().get("chapel", 0), 1, "counted as one type either way")
	assert_eq(_layer.transforms_of("chapel").size(), 1)


## ... and with the camera far out (a house a few px, its shadow one) none does.
func test_far_out_no_house_casts() -> void:
	_ctx.distance = Game.data.bal("map3d_house_shadow_view_m") + 1000.0
	_layer.refresh(_home())
	assert_true(_drawn_batches("chapel", true).is_empty())
	assert_eq((_drawn_batches("chapel", false)[0] as MultiMeshInstance3D).multimesh.instance_count, 1, "drawn, unshadowed")


## Owner 2026-09-25 (颜色可以多样化一点，主色调不变): every house wears one of
## the Houses node's wall and roof variants, kept across rebuilds, and a settlement's
## houses do not all wear the same one.
func test_houses_wear_their_own_colour_variants() -> void:
	var node: Map3DLayerHouses = (load("res://scenes/map3d/map3d_world.tscn") as PackedScene) \
		.instantiate().get_node("Houses")
	var walls := Map3DHouses.tints_of(node.wall_tints).size()
	var roofs := Map3DHouses.tints_of(node.roof_tints).size()
	node.get_parent().free()
	assert_gt(walls, 1, "the table offers wall variants")
	assert_gt(roofs, 1, "and roof variants")
	var seen := {}
	for i in 40:
		var h := {"at": Vector2(1000.0 + 37.0 * i, 2000.0 - 23.0 * i)}
		var w := Map3DHouses.variant_of(h, walls, 0)
		var r := Map3DHouses.variant_of(h, roofs, 1)
		assert_true(w >= 0 and w < walls and r >= 0 and r < roofs)
		assert_eq(w, Map3DHouses.variant_of(h, walls, 0), "a house keeps its variant")
		seen[Vector2i(w, r)] = true
	assert_gt(seen.size(), 6, "neighbours vary")


## The Houses node's tints are exactly the palettes the bake indexes
## (map3d_bake.csv house_wall_palettes x house_wall_palette_size, and the
## roofs'), none above 1 in any channel, and the shader's arrays hold them.
func test_the_tint_arrays_are_the_bakes_palettes() -> void:
	var node: Map3DLayerHouses = (load("res://scenes/map3d/map3d_world.tscn") as PackedScene) \
		.instantiate().get_node("Houses")
	var t := Game.data.map3d_bake
	var walls: PackedColorArray = node.wall_tints
	var roofs: PackedColorArray = node.roof_tints
	var trims: PackedColorArray = node.trim_tints
	node.get_parent().free()
	assert_eq(walls.size(), int(t["house_wall_palettes"]) * int(t["house_wall_palette_size"]))
	assert_eq(roofs.size(), int(t["house_roof_palettes"]) * int(t["house_roof_palette_size"]))
	assert_lte(walls.size(), 24, "the shader's wall_tints[24]")
	assert_lte(roofs.size(), 24)
	assert_lte(trims.size(), 8)
	for c: Color in walls + roofs + trims:
		assert_true(c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0, "never lighter than the mesh")


func _home() -> Vector2:
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var b: Dictionary = Game.data.burgs[String(codes[0])]
	return Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))


## Owner 2026-10-01 / 2026-10-04: a pier's deck lies map3d_pier_deck_m over
## the SEA and a moored ship's origin — its waterline — on it, whatever the
## ground under them says (the fixture's ground stands at HEIGHT).
func test_a_pier_and_a_ship_are_seated_on_the_sea_not_the_ground() -> void:
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var a := String(codes[0])
	var b: Dictionary = Game.data.burgs[a]
	var at := Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
	var f := FileAccess.open(_csv, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	f.store_line("%s,0,%f,%f,0,chapel,1.0,1.0" % [a, at.x, at.y])
	f.store_line("%s,1,%f,%f,0,pier,1.0,1.0" % [a, at.x + 200.0, at.y])
	f.store_line("%s,2,%f,%f,0,cog,1.0,1.0" % [a, at.x + 200.0, at.y + 30.0])
	f.close()
	_layer.houses_override = Map3DHouses.load_csv(_csv)
	_layer.build()
	_layer.refresh(_home())
	var sea := float(WORLD["sea_y"])
	assert_almost_eq((_layer.transforms_of("pier")[0] as Transform3D).origin.y,
		sea + Game.data.bal("map3d_pier_deck_m"), 0.001, "the pier's deck stands over the sea")
	assert_almost_eq((_layer.transforms_of("cog")[0] as Transform3D).origin.y, sea, 0.001,
		"the ship's waterline is the sea's level")


func test_separate_settlements_keep_independent_native_culling_bounds() -> void:
	var first: String = _layer.houses_override.keys()[0]
	var at := _home()
	var second := ""
	var farthest := 0.0
	var limit := Game.data.bal("map3d_house_view_m") - Game.data.bal("map3d_house_rebuild_move_m") * 2.0
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		var point := _ctx.to_world(Vector2(float(b["x"]), float(b["y"])))
		var distance := point.distance_to(at)
		if code != first and distance < limit and distance > farthest:
			second = code
			farthest = distance
	assert_ne(second, "", "the pack has another settlement inside the unchanged range")
	if second == "": return
	var other: Dictionary = _layer.houses_override[first][0].duplicate(true)
	var burg: Dictionary = Game.data.burgs[second]
	other["at"] = _ctx.to_world(Vector2(float(burg["x"]), float(burg["y"])))
	_layer.houses_override[second] = [other]
	_layer.refresh(at)
	var batches: Array = _layer.get_children().filter(func(n: Node) -> bool: return n.get_meta("house_type", "") == "chapel")
	assert_eq(batches.size(), 2, "distant clusters cannot share one giant culling box")
	assert_eq(_layer.counts()["chapel"], 2, "no house is dropped")
	for node: MultiMeshInstance3D in batches:
		assert_eq(node.multimesh.instance_count, 1)
		var enclosed := 0
		for t: Transform3D in _layer.transforms_of("chapel"):
			if node.custom_aabb.has_point(t * (_layer._aabbs["chapel"] as AABB).get_center()): enclosed += 1
		assert_eq(enclosed, 1, "each native bound contains its own house, without spanning the other settlement")
		assert_lt(node.custom_aabb.size.x, farthest)
	var identities := batches.duplicate()
	_layer.refresh(at + Vector2(Game.data.bal("map3d_house_rebuild_move_m") * 1.5, 0))
	for node: MultiMeshInstance3D in identities: assert_true(_layer.get_children().has(node), "a camera rebuild reuses immutable chunks")
	var transforms := _layer.transforms_of("chapel").duplicate()
	var variants := _layer.variants_of("chapel").duplicate()
	_ctx.target = at
	_ctx.distance = Game.data.bal("map3d_house_shadow_view_m") + 1.0
	_layer._on_camera_moved()
	assert_eq(_drawn_batches("chapel", false).size(), 1, "far zoom retains batching when the clusters share the screen")
	assert_eq((_drawn_batches("chapel", false)[0] as MultiMeshInstance3D).custom_aabb, AABB(), "ordinary far batches retain native buffer bounds")
	assert_eq(_layer.transforms_of("chapel"), transforms)
	assert_eq(_layer.variants_of("chapel"), variants)
	assert_eq(_layer.counts()["chapel"], 2)
	_ctx.distance = 0.0
	_layer._on_camera_moved()
	assert_eq((_drawn_batches("chapel", true) + _drawn_batches("chapel", false)).size(), 2, "near zoom restores independently culled chunks")


func _drawn_batches(type: String, shadowed: bool) -> Array:
	var book: Dictionary = _layer._instances if shadowed else _layer._far
	return book.values().filter(func(n: MultiMeshInstance3D) -> bool: return n.visible and n.get_meta("house_type", "") == type)


func test_ship_culling_bounds_include_authored_rotation_and_heave() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 4, 6)
	var mat := ShaderMaterial.new()
	mat.shader = Map3DHouseMaterials.HOUSE_SHADER
	mesh.material = mat
	assert_eq(_layer._animated_bounds(mesh), mesh.get_aabb(), "an ordinary house keeps its exact mesh bounds")
	mat.set_shader_parameter("bob_on", 1.0)
	mat.set_shader_parameter("bob_heave_m", 2.0)
	var bounds := _layer._animated_bounds(mesh)
	for x: float in [-1.0, 1.0]:
		for y: float in [-2.0, 2.0]:
			for z: float in [-3.0, 3.0]:
				for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
					for heave: float in [-2.0, 2.0]:
						var point := Basis.from_euler(Vector3(angle, 0, angle)) * Vector3(x, y, z) + Vector3.UP * heave
						assert_true(bounds.has_point(point), "shader motion cannot leave a batch's native bound")


func test_ship_rotation_bounds_include_asymmetric_mesh_corners() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-200, -1, 200), Vector3(0, 1, 0), Vector3.ZERO])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = Map3DHouseMaterials.HOUSE_SHADER
	mat.set_shader_parameter("bob_on", 1.0)
	mat.set_shader_parameter("bob_heave_m", 0.0)
	mesh.surface_set_material(0, mat)
	var bounds := _layer._animated_bounds(mesh)
	var corner := Vector3(-200, -1, 200)
	var rotated := Basis(Vector3.UP, PI * 0.25) * corner
	assert_true(bounds.has_point(rotated), "a mixed-sign far corner must fit after shader rotation")


func test_hidden_chunks_do_not_reappear_on_a_camera_signal_and_source_change_releases_them() -> void:
	_layer.refresh(_home())
	var old := _layer.get_children().duplicate()
	_ctx.target = Vector2(500000, 500000)
	_layer.refresh(_ctx.target)
	_layer._on_camera_moved()
	for node: MultiMeshInstance3D in old: assert_false(node.visible)
	_layer.houses_override = _layer.houses_override.duplicate(true)
	_layer.refresh(_home())
	for node: MultiMeshInstance3D in old: assert_true(node.is_queued_for_deletion(), "a new source cannot retain stale buffers")
	var rebuilt := _layer.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var references: Array = rebuilt.map(func(n: Node) -> WeakRef: return weakref(n))
	_layer.build()
	for reference: WeakRef in references:
		var node := reference.get_ref() as Node
		assert_true(node == null or node.is_queued_for_deletion(), "preview rebuild clears generated batches")


func test_lod_transitions_restore_only_the_selected_cached_batches() -> void:
	_ctx.target = _home()
	_layer.refresh(_ctx.target)
	_ctx.distance = Game.data.bal("map3d_lod_houses_m") + 1.0
	_layer._on_camera_moved()
	for node: MultiMeshInstance3D in _layer.get_children(): assert_false(node.visible)
	_ctx.distance = Game.data.bal("map3d_lod_houses_m") - Game.data.bal("map3d_lod_margin_m") - 1.0
	_layer._on_camera_moved()
	assert_eq(_layer.counts()["chapel"], 1)
	for i: int in 3:
		_layer._on_camera_moved()
		assert_eq((_drawn_batches("chapel", true) + _drawn_batches("chapel", false)).size(), 1)


func test_replacing_house_source_refreshes_even_without_camera_movement() -> void:
	var at := _home()
	_layer.refresh(at)
	var old := _layer.get_children().duplicate()
	var source := _layer.houses_override.duplicate(true)
	for code: String in source:
		source[code] = (source[code] as Array).filter(func(h: Dictionary) -> bool: return h["type"] != "cottage_a")
	_layer.houses_override = source
	assert_true(_layer.refresh(at), "source identity invalidates the movement-only guard")
	assert_eq(_layer.counts()["cottage_a"], 0)
	assert_eq(_layer.counts()["chapel"], 1)
	for node: MultiMeshInstance3D in old: assert_true(node.is_queued_for_deletion())
