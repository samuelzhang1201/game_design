extends GutTest
const RunDir := preload("res://tests/run_dir.gd")
## The build's own heightmap and woods, read by rows (spec 2026-10-02-war-room-v2
## §2.4, plan B's refinement): the heights Terrain3D was built from.

var dir := ""


## A 16 x 8 padded bake whose pack frame starts at vertex column 2: height =
## column * 10 + row, sea_y 5, 20 m vertices, 50 m per pack px (2.5 vertices a
## px); woods.png 4 x 4, one texel per two vertices (1.25 texels a pack px),
## canopy only at texel (1, 0).
func before_each() -> void:
	dir = RunDir.dir("war_bake")
	var world := {"m_per_px": 50.0, "vertex_m": 20.0, "vertices": [10, 8], "padded": [16, 8],
		"import_corner": [-40.0, 0.0], "pack_origin": [0.0, 0.0], "sea_y": 5.0}
	var f := FileAccess.open(dir + "/world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	f.close()
	var h := FileAccess.open(dir + "/height.r32", FileAccess.WRITE)
	for row in 8:
		for col in 16:
			h.store_float(float(col * 10 + row))
	h.close()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(1, 0, Color(0.8, 1.0, 0, 1))
	img.save_png(ProjectSettings.globalize_path(dir + "/woods.png"))


func test_a_pack_point_reads_its_vertex_less_the_sea_line() -> void:
	var b := WarBake.open(dir)
	assert_not_null(b)
	var g := b.heights(Rect2(0, 0, 2, 0.8), 2, 2)   # pack px (0,0) .. (2,0.8)
	# (0,0): vertex col 2, row 0 -> 20 - 5; (2,0): col 2 + 5 = 7 -> 70 - 5
	assert_almost_eq(g[0], 15.0, 0.001)
	assert_almost_eq(g[1], 65.0, 0.001)
	# (0, 0.8): row 0.8 * 2.5 = 2 -> 22 - 5
	assert_almost_eq(g[2], 17.0, 0.001)


func test_a_rect_off_the_bake_is_held_to_its_edge() -> void:
	var g := WarBake.open(dir).heights(Rect2(-10, -10, 100, 100), 3, 3)
	for v in g:
		assert_true(v >= -5.0 - 0.001 and v <= 157.0 - 5.0 + 0.001, "read inside the file: %f" % v)


func test_woods_are_where_the_canopy_is() -> void:
	var w := WarBake.open(dir).woods(Rect2(0, 0, 3, 3), 0.8)
	assert_gt(w.size(), 0)
	for t: Dictionary in w:
		var at: Vector2 = t["at"]
		assert_eq(Vector2i(int(at.x * 1.25), int(at.y * 1.25)), Vector2i(1, 0), "only texel (1, 0) has canopy")
		assert_almost_eq(float(t["cover"]), 0.8, 0.01)
		assert_almost_eq(float(t["conifer"]), 1.0, 0.01)


func test_no_bake_no_reader() -> void:
	assert_null(WarBake.open(dir + "/nothing"))


## The build's rivers.json (world metres, beside bake/) read as pack px:
## (x - pack_origin) / m_per_px, source to mouth.
func test_the_builds_river_courses_are_read_in_pack_px() -> void:
	var root := RunDir.dir("war_bake_rivers")
	var d := root + "/bake"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	var world := {"m_per_px": 50.0, "vertex_m": 20.0, "vertices": [4, 4], "padded": [4, 4],
		"import_corner": [-100.0, -200.0], "pack_origin": [-100.0, -200.0], "sea_y": 0.0}
	var f := FileAccess.open(d + "/world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	f.close()
	var h := FileAccess.open(d + "/height.r32", FileAccess.WRITE)
	for i in 16:
		h.store_float(0.0)
	h.close()
	var b := WarBake.open(d)
	assert_true(b.river_courses().is_empty(), "no rivers.json, no courses")
	WarBake.forget()
	b = WarBake.open(d)
	f = FileAccess.open(root + "/rivers.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"rivers": [{"code": "aa", "points": [[-100.0, -200.0, 5.0, 6.0, 0.0],
		[400.0, 300.0, 5.0, 6.0, 0.0], [900.0, 300.0, 5.0, 9.0, 1.0]]}, {"code": "bb", "points": [[0.0, 0.0, 0, 0, 0]]}]}))
	f.close()
	var c := b.river_courses()
	assert_eq(c.keys(), ["aa"], "a course of one point is no river")
	assert_eq(c["aa"], PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(20, 10)]))
