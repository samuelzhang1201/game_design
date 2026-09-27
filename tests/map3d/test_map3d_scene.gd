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
	"Viewport/Houses", "Viewport/Couriers",
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


const OLD_BUILD := "user://test_map3d_old_build.tscn"


func _old_build() -> void:
	var root := Node3D.new()
	root.name = "OldBuild"
	root.set_meta("map3d_world", WORLD)
	for n: Node in [DirectionalLight3D.new(), WorldEnvironment.new(), MeshInstance3D.new(),
			Camera3D.new()]:
		n.name = {"DirectionalLight3D": "Sun", "WorldEnvironment": "Environment",
			"MeshInstance3D": "Sea", "Camera3D": "Camera3D"}[n.get_class()]
		root.add_child(n)
		n.owner = root
	(root.get_node("Sea") as MeshInstance3D).mesh = PlaneMesh.new()
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OLD_BUILD)
	root.free()


func test_an_old_builds_sun_sky_sea_and_cameras_step_aside() -> void:
	_old_build()
	var v := Map3DView.create(Game.data, OLD_BUILD)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var vp := v.viewport()
	assert_eq(vp.find_children("*", "DirectionalLight3D", true, false).size(), 1, "one sun")
	assert_eq(vp.find_children("*", "WorldEnvironment", true, false).size(), 1, "one sky")
	assert_eq(vp.find_children("*", "Camera3D", true, false).size(), 1, "the rig's camera only")
	var world := vp.get_node("WorldSlot").get_child(0)
	for n: String in Map3DWorldLoader.OLD_BUILD_NODES:
		assert_null(world.get_node_or_null(n), n + " of the old build is gone")
	assert_true("Sea" in v.layer_names())
	assert_true("Shadows" in v.layer_names())


func test_the_sky_and_sun_are_data() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var env := (v.get_node("Viewport/Environment") as WorldEnvironment).environment
	assert_almost_eq(env.ambient_light_energy, Game.data.bal("map3d_ambient_energy"), 0.0001)
	# depth haze (Phase 0, 2026-09-24): the fog follows the camera's distance
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_almost_eq(env.fog_density, Game.data.bal("map3d_fog_depth_density"), 1e-9)
	assert_eq(int(env.tonemap_mode), int(Game.data.bal("map3d_env_tonemap")))
	assert_eq(env.ssao_enabled, Game.data.bal("map3d_env_ssao") > 0.0)
	var sun := v.get_node("Viewport/Sun") as DirectionalLight3D
	assert_almost_eq(sun.light_energy, Game.data.bal("map3d_sun_energy"), 0.0001)
	assert_almost_eq(sun.rotation_degrees.x, Game.data.bal("map3d_sun_pitch_deg"), 0.01)
	var sea := v.get_node("Viewport/Sea") as MeshInstance3D
	assert_not_null(sea.mesh, "the sea plane is the scene's own")
	assert_almost_eq(sea.global_position.y, 5.0, 0.001)


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
