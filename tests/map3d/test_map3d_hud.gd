extends GutTest
## Map3DHud: the 3D map's scale bar and compass. Hand-computed values.

const RunDir := preload("res://tests/run_dir.gd")


func test_the_bar_takes_the_largest_round_distance_that_fits() -> void:
	# 1.5 km per px, 220 px at most: 330 km fits, the 1-2-5 step under it is 200 km.
	var bar := Map3DHud.scale_bar_for(1.5, 220.0, "km")
	assert_eq(bar["distance"], 200.0)
	assert_eq(bar["text"], "200 km")
	assert_almost_eq(float(bar["width_px"]), 200.0 / 1.5, 0.001)


func test_the_bar_reads_in_the_packs_own_unit() -> void:
	# 0.03 units per px * 220 = 6.6 -> 5, in whatever unit the pack names.
	assert_eq(Map3DHud.scale_bar_for(0.03, 220.0, "mi")["text"], "5 mi")
	assert_eq(Map3DHud.scale_bar_for(0.0, 220.0, "km"), {}, "nothing sensible fits")


func test_the_needle_turns_with_the_view() -> void:
	# yaw 90: the camera's right is north (Map3DGeometry.pose), so north
	# lies a quarter turn clockwise from screen-up.
	var basis := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 90.0, -45.0).basis
	assert_gt(basis.x.dot(Vector3(0, 0, -1)), 0.99)
	assert_almost_eq(Map3DHud.needle_angle(90.0), PI * 0.5, 0.0001)
	assert_eq(Map3DHud.needle_angle(0.0), 0.0)


var _hud_fixture := RunDir.dir("map3d_hud").path_join("test_map3d_hud_world.tscn")
const HUD_WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func _hud_view() -> Map3DView:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", HUD_WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _hud_fixture)
	root.free()
	var v := Map3DView.create(Game.data, _hud_fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_hud_is_one_child_per_job_in_paint_order() -> void:
	var v := _hud_view()
	var names: Array = []
	for c: Node in v.get_node("Hud").get_children():
		names.append(String(c.name))
	assert_eq(names, ["Labels", "Landmarks", "Weather", "HeatLegend", "Badges", "Armies",
		"Couriers", "Backdrop", "ScaleBar", "Ruler", "Compass", "Needle"])
	assert_true(v.get_node("Hud/Labels") is Map3DHudLabels)
	assert_true(v.get_node("Hud/Needle") is Map3DHudNeedle)


func test_the_views_seams_read_the_pieces() -> void:
	var v := _hud_view()
	var hud := v.get_node("Hud") as Map3DHud
	assert_eq(v.label_entries(), (hud.piece("Labels") as Map3DHudLabels).entries())
	assert_eq(v.army_markers(), (hud.piece("Armies") as Map3DHudArmies).markers())
	assert_eq(v.heat_legend_rect(), (hud.piece("HeatLegend") as Map3DHudHeatLegend).rect())


func test_no_hud_script_reads_the_game_autoload() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if f.begins_with("map3d_hud") and f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string("res://scripts/map3d/" + f)
			assert_false(text.contains("Game."), f + " takes the context, not Game")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
