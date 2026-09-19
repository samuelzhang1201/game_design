extends GutTest
## Kingdom names on the 3D map (owner 2026-09-18, the migration list's
## second item): the 2D map's lettering — blackletter in the name's own case,
## the coast ink, faint — standing upright on the HUD over each kingdom's
## LIVE label anchor, sized as a map_label_scale_px-pack-px-tall word on the
## ground seen from the camera, and hidden below map_label_min_px. The built
## scene is git-ignored, so the view loads a flat fixture world.

const FIXTURE := "user://test_map3d_labels_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _entry(v: Map3DView, code: String) -> Dictionary:
	for e: Dictionary in v.label_entries():
		if String(e["code"]) == code:
			return e
	return {}


# --- the size rule ---------------------------------------------------------------

func test_a_label_is_its_ground_height_over_the_metres_per_pixel() -> void:
	assert_almost_eq(Map3DGeometry.label_px(2250.0, 75.0, 16.0, 60.0), 30.0, 0.001)


func test_a_near_label_stops_at_the_largest_size() -> void:
	assert_almost_eq(Map3DGeometry.label_px(2250.0, 10.0, 16.0, 60.0), 60.0, 0.001)


func test_a_far_label_is_hidden_below_the_smallest_size() -> void:
	assert_eq(Map3DGeometry.label_px(2250.0, 200.0, 16.0, 60.0), 0.0)


# --- the view's labels ------------------------------------------------------------

func test_the_players_realm_is_lettered_over_its_live_anchor() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	var anchor := MapOwnership.label_anchor(Game.data, Game.state, mine)
	v.look_at_pack(anchor, 30000.0)
	var e := _entry(v, mine)
	assert_false(e.is_empty(), "the realm under the camera is lettered")
	assert_eq(String(e["text"]), String(Game.data.kingdoms[mine]["label"]))
	assert_almost_eq((e["pos"] as Vector2).x, v.size.x * 0.5, 2.0, "over the anchor")
	assert_almost_eq((e["pos"] as Vector2).y, v.size.y * 0.5, 2.0)
	var mpp := Map3DGeometry.metres_per_pixel(30000.0, Game.data.bal("map3d_fov_deg"), v.size.y)
	assert_almost_eq(float(e["px"]), Map3DGeometry.label_px(
		Game.data.bal("map_label_scale_px") * 50.0, mpp,
		Game.data.bal("map_label_min_px"), Game.data.bal("map_label_max_px")), 0.5,
		"a word map_label_scale_px pack px tall, seen from the camera")


func test_zooming_out_far_enough_hides_the_names() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	v.look_at_pack(MapOwnership.label_anchor(Game.data, Game.state, mine),
		Game.data.bal("map3d_zoom_min_m"))
	var near := float(_entry(v, mine).get("px", 0.0))
	assert_eq(near, Game.data.bal("map_label_max_px"), "capped up close")
	v.look_at_pack(MapOwnership.label_anchor(Game.data, Game.state, mine),
		Game.data.bal("map3d_zoom_max_m") * 4.0)
	assert_true(_entry(v, mine).is_empty() or float(_entry(v, mine)["px"]) \
		< Game.data.bal("map_label_max_px"), "smaller, or gone, far away")


func test_a_conquest_moves_the_label() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	v.look_at_pack(MapOwnership.label_anchor(Game.data, Game.state, mine), 60000.0)
	var before := _entry(v, mine)
	var raider := Game.data.resolve_realm("raider_realm")
	for province: String in MapOwnership.provinces_of(Game.data, Game.state, raider):
		MapOwnership.set_owner(Game.data, Game.state, province, mine, "test: conquest")
	var after := _entry(v, mine)
	assert_false(before.is_empty() or after.is_empty())
	assert_ne(after["pos"], before["pos"], "the anchor follows the land held")


func test_the_hud_letters_the_names() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	v.look_at_pack(MapOwnership.label_anchor(Game.data, Game.state, mine), 30000.0)
	await wait_process_frames(2)
	assert_has(v.drawn_labels(), mine, "the HUD's draw letters the realm")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
