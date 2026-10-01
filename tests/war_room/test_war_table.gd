extends GutTest
## The table's maths (spec 2026-10-01-war-room-design §2).

var repo: DataRepository
const R := Rect2(630, 0, 670, 485)


func before_all() -> void:
	repo = DataRepository.load_all("res://data")


func test_the_sheet_maps_onto_the_table_centred() -> void:
	assert_almost_eq(WarTable.depth_m(R, 1.4), 1.4 * 485.0 / 670.0, 0.0001)
	var mid := WarTable.to_table(R, 1.4, R.get_center())
	assert_almost_eq(mid.x, 0.0, 0.0001)
	assert_almost_eq(mid.y, 0.0, 0.0001)
	var nw := WarTable.to_table(R, 1.4, R.position)
	assert_almost_eq(nw.x, -0.7, 0.0001)
	assert_almost_eq(nw.y, -WarTable.depth_m(R, 1.4) / 2.0, 0.0001)
	var p := Vector2(700.0, 300.0)
	var back := WarTable.from_table(R, 1.4, WarTable.to_table(R, 1.4, p))
	assert_almost_eq(back.x, p.x, 0.001)
	assert_almost_eq(back.y, p.y, 0.001)


func test_relief_values_are_metres_above_the_waterline() -> void:
	# sea level 20 units, 30 m a unit: 255 -> 100 units -> 2400 m; 51 -> 20 -> 0
	assert_almost_eq(WarTable.metres_of_relief(repo, 255.0), 2400.0, 0.01)
	assert_almost_eq(WarTable.metres_of_relief(repo, 51.0), 0.0, 0.01)
	assert_almost_eq(WarTable.metres_of_relief(repo, 10.0), 0.0, 0.01, "the sea is flat")


func test_heights_sample_the_relief_image() -> void:
	var img := Image.create(2560, 929, false, Image.FORMAT_L8)
	img.fill(Color8(51, 51, 51))
	img.set_pixel(965, 242, Color8(255, 255, 255))  # the sheet's centre, scale 1
	var h := WarTable.heights(repo, img, R, 3, 3)
	assert_eq(h.size(), 9)
	assert_almost_eq(h[4], 2400.0, 0.01)
	assert_almost_eq(h[0], 0.0, 0.01)


func test_true_scale_and_exaggeration() -> void:
	# 1 px = 1000 m; table 1.4 m / 670 px; x12: 2400 m -> 2.4 px -> 0.005015 m -> 0.06018 m
	assert_almost_eq(WarTable.table_y(repo, R, 1.4, 2400.0), 2.4 * 1.4 / 670.0 * 12.0, 0.00001)


func test_a_ray_finds_the_relief_not_the_flat_table() -> void:
	var y_at := func(_xz: Vector2) -> float: return 0.05
	var hit := WarTable.ray_hit(Vector3(0, 1, 0), Vector3(0, -1, 0), y_at)
	assert_almost_eq(hit.y, 0.05, 0.0001)
	assert_eq(WarTable.ray_hit(Vector3(0, 1, 0), Vector3(0, 1, 0), y_at), Vector3.INF)


func test_bilinear_height() -> void:
	var h := PackedFloat32Array([0.0, 100.0, 0.0, 100.0])  # 2x2: west 0, east 100
	assert_almost_eq(WarTable.height_at(h, 2, 2, 1.0, 1.0, Vector2(0.0, 0.0)), 50.0, 0.001)
	assert_almost_eq(WarTable.height_at(h, 2, 2, 1.0, 1.0, Vector2(0.5, 0.0)), 100.0, 0.001)


func test_the_mesh_carries_metres_in_uv2() -> void:
	var h := PackedFloat32Array([0.0, 100.0, 200.0, 300.0])
	var mesh := WarTable.build_mesh(h, 2, 2, 1.0, 1.0, 0.001)
	var arrays := mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_almost_eq(uv2[3].x, 300.0, 0.001)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_almost_eq(verts[3].y, 0.3, 0.0001)
