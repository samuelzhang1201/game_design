extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Map3DHouseApron: the dirt / brick skirt round a house's foot (owner
## 2026-10-12), its kind from data and its size from the mesh's footprint.

var _repo: DataRepository


func before_all() -> void:
	_repo = SuiteData.repo()


func test_kind_follows_the_settlement_group_from_data() -> void:
	assert_eq(Map3DHouseApron.kind_of("village", _repo), "dirt")
	for g in ["fort", "town", "city", "capital"]:
		assert_eq(Map3DHouseApron.kind_of(g, _repo), "brick", g)
	assert_eq(Map3DHouseApron.kind_of("nowhere", _repo), "")


func test_every_kind_a_group_names_has_a_row() -> void:
	for g: String in _repo.map3d_settlements:
		assert_true(_repo.map3d_aprons.has(Map3DHouseApron.kind_of(g, _repo)), g)


func test_only_buildings_wear_one() -> void:
	assert_true(Map3DHouseApron.wears("cottage_a", _repo))
	assert_true(Map3DHouseApron.wears("palace", _repo))
	for t in ["wall", "wall_tower", "pier", "cog"]:
		assert_false(Map3DHouseApron.wears(t, _repo), t)


func test_corners_hand_computed() -> void:
	# box 10 x 6 (x, z) from (-4, -3); scale 2, stretch 1.5, yaw 0, margin 2:
	# x from -4*3 - 2 = -14 to 6*3 + 2 = 20, z from -3*2 - 2 = -8 to 3*2 + 2 = 8,
	# about the house at (100, 50): width 34, depth 16, centre x 103
	var box := AABB(Vector3(-4, 0, -3), Vector3(10, 5, 6))
	var h := {"at": Vector2(100, 50), "scale": 2.0, "stretch": 1.5, "yaw_deg": 0.0}
	var c := Map3DHouseApron.corners(h, box, 2.0)
	assert_eq(c.size(), 4)
	assert_almost_eq(c[0].x, 86.0, 0.001)
	assert_almost_eq(c[0].y, 42.0, 0.001)
	assert_almost_eq(c[2].x, 120.0, 0.001)
	assert_almost_eq(c[2].y, 58.0, 0.001)
	assert_almost_eq(c[0].distance_to(c[1]), 34.0, 0.001)
	assert_almost_eq(c[0].distance_to(c[3]), 16.0, 0.001)


func test_a_quarter_turn_swings_the_footprint() -> void:
	# yaw 90 about Y takes local +x to world -z: the box's x 6 end lands at z -6
	var box := AABB(Vector3(-4, 0, -3), Vector3(10, 5, 6))
	var h := {"at": Vector2(0, 0), "scale": 1.0, "yaw_deg": 90.0}
	var c := Map3DHouseApron.corners(h, box, 0.0)
	var centre := (c[0] + c[1] + c[2] + c[3]) / 4.0
	assert_almost_eq(centre.x, 0.0, 0.001)
	assert_almost_eq(centre.y, -1.0, 0.001)
	assert_almost_eq(c[1].y, -6.0, 0.001)


func test_drape_lays_a_grid_on_the_ground() -> void:
	# a 4 x 4 grid over a 10 x 8 quad on the plane y = 0.5 z: 25 vertices, 32
	# triangles; every vertex on the plane, its normal the plane's (0, 2, -1)/sqrt 5
	var c := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 8), Vector2(0, 8)])
	var a := Map3DHouseApron.new_arrays()
	Map3DHouseApron.drape(a, c, 4, func(xz: Vector2) -> float: return 0.5 * xz.y)
	assert_eq((a["v"] as PackedVector3Array).size(), 25)
	assert_eq((a["i"] as PackedInt32Array).size(), 96)
	for v: Vector3 in a["v"]:
		assert_almost_eq(v.y, 0.5 * v.z, 0.0001)
	var want := Vector3(0, 2, -1).normalized()
	for n: Vector3 in a["n"]:
		assert_almost_eq(n.distance_to(want), 0.0, 0.0001)
	assert_eq((a["uv2"] as PackedVector2Array)[0], Vector2(10, 8))
	assert_eq((a["uv"] as PackedVector2Array)[24], Vector2(1, 1))


func test_a_second_drape_indexes_its_own_vertices() -> void:
	var c := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var a := Map3DHouseApron.new_arrays()
	var flat := func(_xz: Vector2) -> float: return 0.0
	Map3DHouseApron.drape(a, c, 1, flat)
	Map3DHouseApron.drape(a, c, 1, flat)
	assert_eq((a["v"] as PackedVector3Array).size(), 8)
	var idx: PackedInt32Array = a["i"]
	assert_eq(idx.size(), 12)
	for k in range(6, 12):
		assert_between(idx[k], 4, 7)
