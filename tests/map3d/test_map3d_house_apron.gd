extends GutTest
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


func test_sizing_hand_computed() -> void:
	# box 10 x 6 (x, z) centred on (1, 0); scale 2, stretch 1.5, yaw 0, margin 2:
	# width 10*2*1.5 + 4 = 34, depth 6*2 + 4 = 16, centre x 100 + 1*3 = 103
	var box := AABB(Vector3(-4, 0, -3), Vector3(10, 5, 6))
	var h := {"at": Vector2(100, 50), "scale": 2.0, "stretch": 1.5, "yaw_deg": 0.0}
	var t := Map3DHouseApron.transform_of(h, box, 20.0, 2.0, 0.1)
	assert_almost_eq(t.basis.x.length(), 34.0, 0.001)
	assert_almost_eq(t.basis.z.length(), 16.0, 0.001)
	assert_almost_eq(t.origin.x, 103.0, 0.001)
	assert_almost_eq(t.origin.z, 50.0, 0.001)
	assert_almost_eq(t.origin.y, 20.1, 0.001)


func test_a_quarter_turn_swings_the_centre_offset() -> void:
	# yaw 90 about Y takes the local +x offset 3 to world -z
	var box := AABB(Vector3(-4, 0, -3), Vector3(10, 5, 6))
	var h := {"at": Vector2(0, 0), "scale": 1.0, "yaw_deg": 90.0}
	var t := Map3DHouseApron.transform_of(h, box, 0.0, 0.0, 0.0)
	assert_almost_eq(t.origin.x, 0.0, 0.001)
	assert_almost_eq(t.origin.z, -1.0, 0.001)


func test_pack_skips_types_without_an_apron() -> void:
	var boxes := {"cottage_a": AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2)), "wall": AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))}
	var rows := [
		{"type": "cottage_a", "at": Vector2(1, 1), "scale": 1.0, "yaw_deg": 0.0},
		{"type": "wall", "at": Vector2(5, 5), "scale": 1.0, "yaw_deg": 0.0},
	]
	var seat := func(_h: Dictionary, _t: String) -> Vector2: return Vector2(0.0, 7.0)
	var p := Map3DHouseApron.pack(rows, boxes, seat, 1.0, 0.1, _repo)
	assert_eq((p["xf"] as Array).size(), 1)
	assert_eq((p["buf"] as PackedFloat32Array).size(), Map3DHouseApron.BUFFER_STRIDE)
	assert_almost_eq((p["xf"] as Array)[0].origin.y, 7.1, 0.001)


func test_material_takes_its_colours_from_the_row() -> void:
	var m := Map3DHouseApron.material_of(_repo.map3d_aprons["brick"])
	assert_eq(int(m.get_shader_parameter("style")), 1)
	assert_eq((m.get_shader_parameter("color_a") as Color).to_html(false), "9a6b55")
