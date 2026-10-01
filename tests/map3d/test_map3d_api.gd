extends GutTest
## The 3D map refactor's safety net (spec 2026-09-20 §5 step 0): every name,
## argument count and signal of Map3DView that the screens, GameRoot, tools
## and tests use — pinned BEFORE the view is split, and run after every task
## of the refactor. A name may move into a layer, but the view must keep a
## forwarder with the same shape. (2026-10-02: the statics, constants and
## properties pins went — every one has a typed caller in tests or scripts,
## which fails to compile on the same break; the node paths are
## test_map3d_scene.gd's. The method shapes stay: Map3DInput and the HUD
## call the view's helpers untyped, which no compiler checks.)

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_api").path_join("test_map3d_api_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

## name -> argument count (defaults included). Underscored names are the
## private handlers and helpers the tests call directly.
const METHODS := {
	"scene_path_for": 1, "has_scene": 1, "create": 2, "attach": 6,
	"load_field_map": 1, "kingdom_of_pick": 3, "pick_reach_px": 3,
	"activate": 0, "deactivate": 0, "water_normals": 0, "sea_material": 0,
	"river_material": 0, "refresh_borders": 0, "set_manor_theme": 1, "manor_theme": 0,
	"heat_on": 0, "cell_lut": 0, "lut_color": 1, "bridge_rules": 0, "bridges": 0,
	"metres_per_pixel": 0, "label_entries": 0, "manor_badges": 0, "set_military": 1,
	"military": 0, "army_badge_height": 0, "army_markers": 0, "landmark_marks": 0,
	"heat_legend_rect": 0, "heat_legend_ticks": 0, "heat_legend_yields": 0,
	"drawn_army_count": 0, "selected_army": 0, "drawn_badge_count": 0, "drawn_labels": 0,
	"ruler_reading": 0, "map_units_per_metre": 0, "map_unit": 0, "ruler": 0,
	"ground_at": 1, "pick_at": 1, "hover_pick": 2, "clear_hover": 0, "hovered_kingdom": 0,
	"hover_tooltip": 0, "tooltip_rect": 0, "select_at": 1, "clear_selection": 0,
	"is_loaded": 0, "notice": 0, "viewport": 0, "camera": 0, "cloud_count": 0,
	"target": 0, "distance": 0, "yaw": 0, "selected_province": 0, "selected_burg": 0,
	"selected_manor": 0, "selected_ring_visible": 0, "look_at_pack": 2, "look_at_home": 1,
	"layer_names": 0, "set_layer_visible": 2, "line_mesh": 1, "marker_counts": 0,
	"_gui_input": 1, "_process": 1, "_render_scale": 0, "_burg_xz": 1, "_height_at": 1,
	"_pan_by": 1, "_zoom_at": 2, "_ruler_click": 1,
}
const SIGNALS := {"object_selected": 1, "province_selected": 1, "country_hovered": 1}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func _script_methods() -> Dictionary:
	var out: Dictionary = {}
	var script: Script = load("res://scripts/map3d/map3d_view.gd")
	for m: Dictionary in script.get_script_method_list():
		out[String(m["name"])] = m
	return out


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	v.refresh_borders()
	return v


func test_every_method_keeps_its_name_and_shape() -> void:
	var have := _script_methods()
	for key: String in METHODS:
		assert_true(have.has(key), "Map3DView.%s is kept" % key)
		if have.has(key):
			assert_eq((have[key]["args"] as Array).size(), int(METHODS[key]),
				"Map3DView.%s keeps %d argument(s)" % [key, METHODS[key]])


func test_the_signals_are_kept() -> void:
	var v := Map3DView.create(Game.data, _fixture)
	add_child_autofree(v)
	for key: String in SIGNALS:
		assert_true(v.has_signal(key), key)
		for s: Dictionary in v.get_signal_list():
			if String(s["name"]) == key:
				assert_eq((s["args"] as Array).size(), int(SIGNALS[key]), key + " arguments")


func test_an_empty_line_has_no_mesh() -> void:
	var v := _view()
	assert_null(v.line_mesh("Selection"), "nothing selected: no mesh, not an empty one")
	assert_null(v.line_mesh("Hover"), "nothing hovered: no mesh")
	assert_null(v.line_mesh("NoSuchLine"))
	assert_not_null(v.line_mesh("Kingdoms"))


func test_create_takes_a_fixture_path() -> void:
	var v := _view()
	assert_true(v.is_loaded(), "a bare Node3D with map3d_world meta is a world")
	assert_eq(Map3DView.scene_path_for("no_such_pack"), "res://assets/3D/terrain/no_such_pack/world.tscn")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
