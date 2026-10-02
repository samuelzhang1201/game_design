extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The table's maths (spec 2026-10-01-war-room-design §2).

var repo: DataRepository
const R := Rect2(630, 0, 670, 485)


func before_all() -> void:
	repo = SuiteData.repo()


func test_the_sheet_maps_onto_the_table_centred() -> void:
	assert_almost_eq(WarRoomTable.depth_m(R, 1.4), 1.4 * 485.0 / 670.0, 0.0001)
	var mid := WarRoomTable.to_table(R, 1.4, R.get_center())
	assert_almost_eq(mid.x, 0.0, 0.0001)
	assert_almost_eq(mid.y, 0.0, 0.0001)
	var nw := WarRoomTable.to_table(R, 1.4, R.position)
	assert_almost_eq(nw.x, -0.7, 0.0001)
	assert_almost_eq(nw.y, -WarRoomTable.depth_m(R, 1.4) / 2.0, 0.0001)
	var p := Vector2(700.0, 300.0)
	var back := WarRoomTable.from_table(R, 1.4, WarRoomTable.to_table(R, 1.4, p))
	assert_almost_eq(back.x, p.x, 0.001)
	assert_almost_eq(back.y, p.y, 0.001)


func test_relief_values_are_metres_above_the_waterline() -> void:
	# sea level 20 units, 30 m a unit: 255 -> 100 units -> 2400 m; 51 -> 20 -> 0
	assert_almost_eq(WarRoomTable.metres_of_relief(repo, 255.0), 2400.0, 0.01)
	assert_almost_eq(WarRoomTable.metres_of_relief(repo, 51.0), 0.0, 0.01)
	assert_almost_eq(WarRoomTable.metres_of_relief(repo, 10.0), 0.0, 0.01, "the sea is flat")


func test_heights_sample_the_relief_image() -> void:
	var img := Image.create(2560, 929, false, Image.FORMAT_L8)
	img.fill(Color8(51, 51, 51))
	img.set_pixel(965, 242, Color8(255, 255, 255))  # the sheet's centre, scale 1
	var h := WarRoomTable.heights(repo, img, R, 3, 3)
	assert_eq(h.size(), 9)
	assert_almost_eq(h[4], 2400.0, 0.01)
	assert_almost_eq(h[0], 0.0, 0.01)


func test_true_scale_and_exaggeration() -> void:
	# 1 px = 1000 m; table 1.4 m / 670 px; 2400 m -> 2.4 px -> 0.005015 m, times the exaggeration
	assert_almost_eq(WarRoomTable.table_y(repo, R, 1.4, 2400.0),
		2.4 * 1.4 / 670.0 * repo.bal("war_relief_exaggeration"), 0.00001)


func test_a_ray_finds_the_relief_not_the_flat_table() -> void:
	var y_at := func(_xz: Vector2) -> float: return 0.05
	var hit := WarRoomTable.ray_hit(Vector3(0, 1, 0), Vector3(0, -1, 0), y_at)
	assert_almost_eq(hit.y, 0.05, 0.0001)
	assert_eq(WarRoomTable.ray_hit(Vector3(0, 1, 0), Vector3(0, 1, 0), y_at), Vector3.INF)


func test_bilinear_height() -> void:
	var h := PackedFloat32Array([0.0, 100.0, 0.0, 100.0])  # 2x2: west 0, east 100
	assert_almost_eq(WarRoomTable.height_at(h, 2, 2, 1.0, 1.0, Vector2(0.0, 0.0)), 50.0, 0.001)
	assert_almost_eq(WarRoomTable.height_at(h, 2, 2, 1.0, 1.0, Vector2(0.5, 0.0)), 100.0, 0.001)


func test_the_mesh_carries_metres_in_uv2() -> void:
	var h := PackedFloat32Array([0.0, 100.0, 200.0, 300.0])
	var mesh := WarRoomTable.build_mesh(h, 2, 2, 1.0, 1.0, 0.001)
	var arrays := mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_almost_eq(uv2[3].x, 300.0, 0.001)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_almost_eq(verts[3].y, 0.3, 0.0001)


func test_raw_heights_keep_the_sea_negative_while_heights_stay_flat() -> void:
	var img := Image.create(2560, 929, false, Image.FORMAT_L8)
	img.fill(Color8(10, 10, 10))
	var clamped := WarRoomTable.heights(repo, img, R, 3, 3)
	var raw := WarRoomTable.raw_heights(repo, img, R, 3, 3)
	assert_almost_eq(clamped[0], 0.0, 0.001)
	# 10/255 of 100 = 3.92 units; (3.92 - 20) * 30 m a unit = -482.4 m
	assert_almost_eq(raw[0], (10.0 * 100.0 / 255.0 - repo.bal("elevation_sea_level")) * repo.bal("elevation_m_per_unit"), 0.01)
	assert_lt(raw[0], 0.0)


func test_the_mesh_carries_the_unclamped_metres_in_uv2_y() -> void:
	var h := PackedFloat32Array([0.0, 0.0, 0.0, 300.0])
	var raw := PackedFloat32Array([-120.0, -40.0, 0.0, 300.0])
	var uv2: PackedVector2Array = WarRoomTable.build_mesh(h, 2, 2, 1.0, 1.0, 0.001, raw).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_almost_eq(uv2[0].y, -120.0, 0.001)
	assert_almost_eq(uv2[0].x, 0.0, 0.001, "x stays clamped")
	var plain: PackedVector2Array = WarRoomTable.build_mesh(h, 2, 2, 1.0, 1.0, 0.001).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_almost_eq(plain[3].y, 300.0, 0.001, "without raw, y repeats the clamped metres")


func test_shore_distance_counts_table_metres_off_the_nearest_land() -> void:
	# 5 x 1 row, land at the west end only; vertices 0.25 m apart
	var raw := PackedFloat32Array([10.0, -5.0, -5.0, -5.0, -5.0])
	var d := WarRoomTable.shore_distance(raw, 5, 1, 0.25, 1.0, 9.0)
	assert_almost_eq(d[0], 0.0, 0.0001)
	assert_almost_eq(d[1], 0.25, 0.0001)
	assert_almost_eq(d[4], 1.0, 0.0001)
	var all_sea := WarRoomTable.shore_distance(PackedFloat32Array([-1.0, -1.0]), 2, 1, 0.25, 1.0, 9.0)
	assert_almost_eq(all_sea[0], 9.0, 0.0001, "no land anywhere reads as far")


func test_the_mesh_carries_the_shore_fade_in_color_r() -> void:
	var h := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var cols: PackedColorArray = WarRoomTable.build_mesh(h, 2, 2, 1.0, 1.0, 0.001, h, PackedFloat32Array([0.0, 0.5, 1.0, 1.0])).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_almost_eq(cols[1].r, 0.5, 0.01)
	assert_almost_eq(cols[2].r, 1.0, 0.01)
