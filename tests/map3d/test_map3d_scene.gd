extends GutTest
## The 3D map is an AUTHORED scene (spec 2026-09-20 §2, owner: "clicking a
## node in the editor shows the real picture"): the tree, flags and anchors
## live in scenes/map3d/world_map_3d.tscn; nothing generated at runtime is
## ever saved into it.

const FIXTURE := "user://test_map3d_scene_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const TREE := ["Viewport", "Viewport/WorldSlot", "Viewport/CameraRig",
	"Viewport/CameraRig/RigCamera", "Viewport/Sea", "Viewport/Rivers", "Viewport/Bridges",
	"Viewport/Lines", "Viewport/Clouds", "Viewport/Clouds/Shadows", "Viewport/Markers",
	"Display", "Notice", "Hud", "Hud/Labels", "Hud/Landmarks", "Hud/HeatLegend", "Hud/Badges",
	"Hud/Armies", "Hud/Backdrop", "Hud/ScaleBar", "Hud/Ruler", "Hud/Compass", "Hud/Needle",
	"Tooltip"]


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func test_create_instances_the_authored_scene() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	add_child_autofree(v)
	assert_eq(v.scene_file_path, Map3DView.VIEW_SCENE)
	for path: String in TREE:
		assert_not_null(v.get_node_or_null(path), path)
	var vp := v.get_node("Viewport") as SubViewport
	assert_true(vp.own_world_3d)
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	var display := v.get_node("Display") as TextureRect
	assert_eq(display.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(display.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_eq((v.get_node("Viewport/Clouds/Shadows") as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(v.get_child(v.get_child_count() - 1).name, &"Tooltip", "the name over everything")


func test_the_hud_waits_for_a_world() -> void:
	var v := Map3DView.create(Game.data, "res://no/such/world.tscn")
	add_child_autofree(v)
	v.activate()
	assert_false((v.get_node("Hud") as Control).visible, "an unbuilt map shows only its notice")
	assert_true(v.notice().visible)


func test_nothing_generated_is_saved_in_the_scene() -> void:
	var text := FileAccess.get_file_as_string(Map3DView.VIEW_SCENE)
	for word: String in ["ArrayMesh", "type=\"MultiMesh\"", "ImageTexture", "preview = true"]:
		assert_false(text.contains(word), "the scene holds no generated " + word)


func test_the_tooltip_chip_is_the_themes_own() -> void:
	var saved := load("res://scenes/map3d/tooltip_chip.tres") as StyleBoxFlat
	var live := UiPalette.chip_style()
	assert_eq(saved.bg_color, live.bg_color)
	assert_eq(saved.border_color, live.border_color)
	assert_eq(saved.corner_radius_top_left, live.corner_radius_top_left)
	assert_eq(saved.content_margin_left, live.content_margin_left)
	assert_eq(saved.content_margin_top, live.content_margin_top)
