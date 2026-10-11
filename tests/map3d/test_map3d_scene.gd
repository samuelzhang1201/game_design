extends GutTest
## The 3D map is an AUTHORED scene (spec 2026-09-20 §2, owner: "clicking a
## node in the editor shows the real picture"): the tree, flags and anchors
## live in scenes/map3d/world_map_3d.tscn; nothing generated at runtime is
## ever saved into it.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_scene").path_join("test_map3d_scene_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const TREE := ["Viewport", "Viewport/World/WorldSlot", "Viewport/World/CameraRig",
	"Viewport/World/CameraRig/RigCamera", "Viewport/World/Sea", "Viewport/World/Rivers", "Viewport/World/Bridges",
	"Viewport/World/Lines", "Viewport/World/Clouds", "Viewport/World/Clouds/Shadows", "Viewport/World/Markers",
	"Viewport/World/Houses", "Viewport/World/Couriers",
	"Display", "Notice", "Hud", "Hud/Labels", "Hud/Landmarks", "Hud/HeatLegend", "Hud/ManorBars",
	"Hud/Badges", "Hud/Armies", "Hud/Couriers", "Hud/Backdrop", "Hud/ScaleBar", "Hud/Ruler",
	"Hud/Compass", "Hud/Needle", "Tooltip"]
## What the layers build under the view at load (+ refresh_borders).
const BUILT := ["Viewport/World/Markers/Selected", "Viewport/World/Markers/Capital", "Viewport/World/Markers/Village",
	"Viewport/World/Lines/Kingdoms", "Viewport/World/Lines/KingdomHalo", "Viewport/World/Lines/KingdomBand",
	"Viewport/World/Lines/Seams", "Viewport/World/Lines/Roads"]


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func test_create_instances_the_authored_scene() -> void:
	var v := Map3DView.create(Game.data, _fixture)
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
	assert_eq((v.get_node("Viewport/World/Clouds/Shadows") as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(v.get_child(v.get_child_count() - 1).name, &"Tooltip", "the name over everything")
	# what the layers build at load (+ refresh_borders), at the paths tests and
	# tools reach them by (once test_map3d_api.gd's)
	v.size = Vector2(800, 450)
	v.activate()
	v.refresh_borders()
	for path: String in BUILT:
		assert_not_null(v.get_node_or_null(path), path)
	assert_true(v.get_node("Viewport/World/Markers/Capital") is MultiMeshInstance3D)
	assert_true(v.get_node("Viewport/World/Clouds") is MultiMeshInstance3D)
	assert_true(v.get_node("Hud") is Map3DHud)
	assert_eq(String(v.camera().name), "RigCamera")
	assert_true(v.viewport().is_ancestor_of(v.camera()))


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


var _old_build_path := RunDir.dir("map3d_scene").path_join("test_map3d_old_build.tscn")


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
	ResourceSaver.save(packed, _old_build_path)
	root.free()


func test_an_old_builds_sun_sky_sea_and_cameras_step_aside() -> void:
	_old_build()
	var v := Map3DView.create(Game.data, _old_build_path)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var vp := v.viewport()
	var lights := vp.find_children("*", "DirectionalLight3D", true, false)
	assert_eq(lights.map(func(n: Node) -> String: return String(n.name)), ["Sun", "FillLight"],
		"the scene's sun and its shadowless fill light only")
	assert_false((v.world().get_node("FillLight") as DirectionalLight3D).shadow_enabled)
	assert_eq(vp.find_children("*", "WorldEnvironment", true, false).size(), 1, "one sky")
	assert_eq(vp.find_children("*", "Camera3D", true, false).size(), 1, "the rig's camera only")
	var world := v.world().get_node("WorldSlot").get_child(0)
	for n: String in Map3DWorldLoader.OLD_BUILD_NODES:
		assert_null(world.get_node_or_null(n), n + " of the old build is gone")
	assert_true("Sea" in v.layer_names())
	assert_true("Shadows" in v.layer_names())


## The sky and sun are the world SCENE's (owner 2026-10-02: edited in the
## editor): what the game draws is what the scene and its environment .tres
## say, the view taking only its own copy and following the camera.
func test_the_sky_and_sun_are_the_scenes() -> void:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var authored := load(Map3DEnvironment.ENVIRONMENT) as Environment
	var sky := v.get_node("Viewport/World/Environment") as Map3DSky
	var env := sky.environment
	assert_ne(env, authored, "the view's own copy")
	assert_almost_eq(env.ambient_light_energy, authored.ambient_light_energy, 0.0001)
	assert_eq(int(env.tonemap_mode), int(authored.tonemap_mode))
	# depth haze (Phase 0, 2026-09-24): the fog follows the camera's distance
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_almost_eq(env.fog_density, sky.fog_depth_density, 1e-6)
	# SSAO is spent up close (owner 2026-10-02): on at a zoom inside
	# map3d_close_effects_m, else as the tier's far_ssao says (blank: as near)
	var row: Dictionary = v.context().quality
	var far := v.distance() > Game.data.bal("map3d_close_effects_m")
	assert_eq(env.ssao_enabled, authored.ssao_enabled and Map3DQuality.num(row, "ssao", 1.0) > 0.0
		and (not far or Map3DQuality.num(row, "far_ssao", 1.0) > 0.0))
	var sun := v.get_node("Viewport/World/Sun") as Map3DSun
	assert_not_null(sun, "the sun is a Map3DSun")
	assert_eq(sun.fill, v.get_node("Viewport/World/FillLight"), "its fill is the scene's")
	var sea := v.get_node("Viewport/World/Sea") as MeshInstance3D
	assert_not_null(sea.mesh, "the sea plane is the scene's own")
	assert_almost_eq(sea.global_position.y, 5.0, 0.001)


## Owner 2026-10-10 (no stall as the game opens): the title opens its map a
## step a frame (Map3DView.load_step) — the world, the houses, the woods, the
## lines, the rest — and stepped it is the same map activate() loads at once,
## its SubViewport's processing off until it is shown.
func test_the_load_steps_one_heavy_piece_a_call() -> void:
	Map3DWorldCache.clear()
	var v := Map3DView.create(Game.data, _fixture)
	add_child_autofree(v)
	v.size = Vector2(800, 450)
	var steps := 1
	while v.load_step():
		steps += 1
		assert_eq((v.get_node("Viewport") as SubViewport).process_mode, Node.PROCESS_MODE_DISABLED,
			"nothing in the map runs while it is stepped in")
	assert_eq(steps, 5, "world, houses, woods, lines, the rest")
	assert_false(v.load_step(), "a finished load takes no more steps")
	v.activate()
	assert_not_null(v.context(), "the stepped world is the view's")
	assert_eq((v.get_node("Viewport") as SubViewport).render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_eq((v.get_node("Viewport") as SubViewport).process_mode, Node.PROCESS_MODE_INHERIT)
	v.refresh_borders()
	for path: String in BUILT:
		assert_not_null(v.get_node_or_null(path), path)


## The boot reads the world on worker threads (Map3DWorldLoader.request, for
## BootLoads): is_ready says when it is in, and status / instance take that
## load, kept, without reading the file again; Map3DWorldCache.clear lets it go.
func test_a_requested_world_loads_on_a_thread_and_is_kept() -> void:
	Map3DWorldCache.clear()
	assert_false(Map3DWorldLoader.request("res://no/such/world.tscn"), "nothing to read")
	assert_true(Map3DWorldLoader.request(_fixture))
	assert_true(Map3DWorldLoader.request(_fixture), "asking twice is one load")
	await wait_until(func() -> bool: return Map3DWorldLoader.is_ready(_fixture), 10.0)
	assert_true(Map3DWorldLoader.is_ready(_fixture))
	var ps := Map3DWorldLoader.packed(_fixture)
	assert_not_null(ps, "the thread's PackedScene")
	assert_same(Map3DWorldLoader.packed(_fixture), ps, "kept: the same one again")
	assert_eq(Map3DWorldLoader.status(_fixture)["state"], "legacy")
	var w := Map3DWorldLoader.instance(_fixture)
	assert_not_null(w)
	assert_eq(w.get_meta("map3d_world"), Map3DWorldLoader.scene_meta(_fixture))
	w.free()
	Map3DWorldCache.clear()
	assert_ne(Map3DWorldLoader.packed(_fixture), null, "read again, plainly, after it was let go")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
