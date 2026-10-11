extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Map3DLayerAprons (owner 2026-10-12, R7): the dirt / brick aprons at the
## houses' feet as their own layer — draped grids merged per settlement, drawn
## in the exported materials, under the roads, hidden past the houses' LOD.

const RunDir := preload("res://tests/run_dir.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const SHADER := preload("res://scripts/map3d/house_apron.gdshader")
const DIRT_TRES := "res://scenes/map3d/materials/apron_dirt.tres"
const BRICK_TRES := "res://scenes/map3d/materials/apron_brick.tres"
## A cottage's box chosen so the dirt apron's -x corners fall at x = 20 for a
## house at x = 30: 30 - 7.5 - margin 2.5.
const BOX := AABB(Vector3(-7.5, 0, -5), Vector3(15, 4, 10))

var _repo: DataRepository
var _ctx: Map3DContext
var _aprons: Map3DLayerAprons
var _village := ""
var _town := ""


func before_all() -> void:
	_repo = SuiteData.repo()
	var codes: Array = _repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var g := String(_repo.burgs[code].get("group", ""))
		if g == "village" and _village == "":
			_village = code
		elif g == "town" and _town == "":
			_town = code


func before_each() -> void:
	_ctx = Map3DContext.new(_repo, WORLD)
	_ctx.height_fn = func(xz: Vector2) -> float: return 0.1 * xz.x
	_aprons = Map3DLayerAprons.new()
	_aprons.dirt_material = _test_material()
	_aprons.brick_material = _test_material()
	add_child_autofree(_aprons)
	_aprons.bind(_ctx)


## The tests' own stand-in look (the game's are the authored .tres, Phase E6).
func _test_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


func _cottage(x: float) -> Dictionary:
	return {"type": "cottage_a", "at": Vector2(x, 0.0), "scale": 1.0, "yaw_deg": 0.0}


func _grid() -> int:
	var n := int(_repo.map3d_aprons["dirt"]["grid_n"])
	return (n + 1) * (n + 1)


func test_drape_follows_ground() -> void:
	# ground y = 0.1 x: the corner at x = 20 stands at 2.0 (the lift is the
	# shader's, in px: lift_px scaled to the SubViewport)
	_aprons.show_burgs([_village], {_village: [_cottage(30.0)]}, {"cottage_a": BOX})
	var mi := _aprons.node_of(_village)
	assert_not_null(mi)
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), _grid())
	assert_almost_eq(verts[0].x, 20.0, 0.001)
	assert_almost_eq(verts[0].y, 2.0, 0.001)
	for v: Vector3 in verts:
		assert_almost_eq(v.y, 0.1 * v.x, 0.001)
	var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("lift_px")),
		float(_repo.map3d_aprons["dirt"]["lift_px"]) * _ctx.viewport_px_scale(), 0.0001)


func test_layer_fills_dirt_for_villages_brick_for_towns() -> void:
	assert_ne(_village, "")
	assert_ne(_town, "")
	var wall := {"type": "wall", "at": Vector2(0, 0), "scale": 1.0, "yaw_deg": 0.0}
	var houses := {_village: [_cottage(0.0), _cottage(40.0), wall], _town: [_cottage(80.0)]}
	_aprons.show_burgs([_village, _town], houses, {"cottage_a": BOX, "wall": BOX})
	var counts := _aprons.vertex_counts()
	assert_eq(int(counts.get("dirt", 0)), 2 * _grid(), "two cottages, the wall wears none")
	assert_eq(int(counts.get("brick", 0)), 1 * _grid())
	_aprons.show_burgs([_town], houses, {"cottage_a": BOX, "wall": BOX})
	assert_false(_aprons.vertex_counts().has("dirt"), "a settlement not shown is hidden")


func test_a_settlement_is_built_once() -> void:
	var houses := {_village: [_cottage(0.0)]}
	_aprons.show_burgs([_village], houses, {"cottage_a": BOX})
	var first := _aprons.node_of(_village)
	_aprons.show_burgs([_village], houses, {"cottage_a": BOX})
	assert_same(_aprons.node_of(_village), first, "kept, like the roads' chunks")
	_aprons.show_burgs([_village], {_village: [_cottage(0.0)]}, {"cottage_a": BOX})
	assert_ne(_aprons.node_of(_village), first, "another houses set rebuilds")


func test_aprons_hide_past_lod() -> void:
	_aprons.show_burgs([_village], {_village: [_cottage(0.0)]}, {"cottage_a": BOX})
	_ctx.distance = _repo.bal("map3d_lod_houses_m") + _repo.bal("map3d_lod_margin_m") + 1.0
	_ctx.camera_moved.emit()
	assert_false(_aprons.node_of(_village).visible)
	assert_true(_aprons.vertex_counts().is_empty())
	_ctx.distance = 1.0
	_ctx.camera_moved.emit()
	assert_true(_aprons.node_of(_village).visible)


func test_aprons_under_roads() -> void:
	assert_lt(Map3DPriority.APRONS, Map3DPriority.ROADS)
	_aprons.show_burgs([_village], {_village: [_cottage(0.0)]}, {"cottage_a": BOX})
	var mat := _aprons.node_of(_village).mesh.surface_get_material(0)
	assert_eq(mat.render_priority, Map3DPriority.APRONS)
	assert_ne(mat, _aprons.dirt_material, "a copy: the authored look is never edited")


func test_no_material_draws_nothing_and_never_crashes() -> void:
	_aprons.dirt_material = null
	_aprons.show_burgs([_village, _town], {_village: [_cottage(0.0)], _town: [_cottage(9.0)]},
		{"cottage_a": BOX})
	assert_null(_aprons.node_of(_village))
	assert_eq(int(_aprons.vertex_counts().get("brick", 0)), _grid(), "the other kind still draws")


func test_aprons_wear_the_houses_weather() -> void:
	var houses := Map3DLayerHouses.new()
	houses.weather = {"weather_on": 1.0, "weather_wet_dark": 0.4}
	_aprons.bind(_ctx, houses)
	_aprons.show_burgs([_village], {_village: [_cottage(0.0)]}, {"cottage_a": BOX})
	var mat := _aprons.node_of(_village).mesh.surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("weather_on")), 1.0, 0.0001)
	assert_true(houses.surface_mats.has(mat), "Map3DLayerWeather lays each turn on it")
	_aprons.clear()
	assert_false(houses.surface_mats.has(mat))
	houses.free()


## The Houses layer feeds the aprons every settlement it shows.
func test_houses_feed_the_aprons() -> void:
	var csv := RunDir.dir("map3d_layer_aprons").path_join("houses.csv")
	var b: Dictionary = _repo.burgs[_village]
	var at := Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
	var f := FileAccess.open(csv, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	f.store_line("%s,1,%f,%f,0,cottage_a,1.0,1.0" % [_village, at.x, at.y])
	f.close()
	var houses := Map3DLayerHouses.new()
	houses.houses_override = Map3DHouses.load_csv(csv)
	houses.aprons = _aprons
	add_child_autofree(houses)
	houses.bind(_ctx)
	houses.refresh(at)
	assert_eq(int(_aprons.vertex_counts().get("dirt", 0)), _grid())


func test_apron_materials_are_the_tres() -> void:
	if not ResourceLoader.exists(DIRT_TRES) or not ResourceLoader.exists(BRICK_TRES):
		pending("Phase E6: apron_dirt.tres / apron_brick.tres and the Aprons node are authored in the editor")
		return
	var world := (load("res://scenes/map3d/map3d_world.tscn") as PackedScene).instantiate()
	var node := world.get_node_or_null("Aprons") as Map3DLayerAprons
	assert_not_null(node, "World/Aprons")
	if node != null:
		assert_eq(node.dirt_material.resource_path, DIRT_TRES)
		assert_eq(node.brick_material.resource_path, BRICK_TRES)
		for m: ShaderMaterial in [node.dirt_material, node.brick_material]:
			assert_eq(m.shader, SHADER)
			assert_eq(m.render_priority, Map3DPriority.APRONS)
		assert_eq((world.get_node("Houses") as Map3DLayerHouses).aprons, node, "Houses.aprons")
	world.free()
