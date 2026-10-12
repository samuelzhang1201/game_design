extends GutTest
## Kingdom names on the 3D map (owner 2026-09-18, the migration list's
## second item): the 2D map's lettering — blackletter in the name's own case,
## the coast ink, faint — standing upright on the HUD over each kingdom's
## LIVE label anchor, pinned to it, sized as a map_label_scale_px-pack-px-tall
## word on the ground seen from the camera, and shown only at the far zoom: it
## fades out from map_label_fade_from_px to map_label_hide_px (owner
## 2026-10-10: 国家名字无论我视角如何调整都会显示，很碍事). The built scene is
## git-ignored, so the view loads a flat fixture world.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_labels").path_join("test_map3d_labels_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
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
	assert_almost_eq(Map3DHudLabels.label_px(2250.0, 75.0, 16.0), 30.0, 0.001)


func test_a_near_label_grows_with_the_ground() -> void:
	assert_almost_eq(Map3DHudLabels.label_px(2250.0, 10.0, 16.0), 225.0, 0.001, "never held to one size")


func test_a_far_label_is_hidden_below_the_smallest_size() -> void:
	assert_eq(Map3DHudLabels.label_px(2250.0, 200.0, 16.0), 0.0)


## Whole to 80 px, gone at 110: at 95 px half, at 102.5 a quarter.
func test_a_name_fades_out_as_the_camera_comes_in() -> void:
	assert_eq(Map3DHudLabels.label_fade(40.0, 80.0, 110.0), 1.0)
	assert_eq(Map3DHudLabels.label_fade(80.0, 80.0, 110.0), 1.0)
	assert_almost_eq(Map3DHudLabels.label_fade(95.0, 80.0, 110.0), 0.5, 0.0001)
	assert_almost_eq(Map3DHudLabels.label_fade(102.5, 80.0, 110.0), 0.25, 0.0001)
	assert_eq(Map3DHudLabels.label_fade(110.0, 80.0, 110.0), 0.0)
	assert_eq(Map3DHudLabels.label_fade(400.0, 80.0, 110.0), 0.0)


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
	assert_almost_eq(float(e["px"]), Map3DHudLabels.label_px(
		Game.data.bal("map_label_scale_px") * 50.0, mpp,
		Game.data.bal("map_label_min_px")), 0.5,
		"a word map_label_scale_px pack px tall, seen from the camera")
	assert_almost_eq(float(e["fade"]), Map3DHudLabels.label_fade(float(e["px"]),
		Game.data.bal("map_label_fade_from_px"), Game.data.bal("map_label_hide_px")), 0.0001,
		"shown far out, faded by its size")
	assert_gt(float(e["fade"]), 0.0)


func test_close_in_the_names_are_gone() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	for at_m: float in [Game.data.bal("map3d_zoom_min_m"), 5000.0]:
		v.look_at_pack(MapOwnership.label_anchor(Game.data, Game.state, mine), at_m)
		assert_true(_entry(v, mine).is_empty(), "no name at %d m" % int(at_m))
		await wait_process_frames(2)
		assert_false(v.drawn_labels().has(mine), "and none lettered at %d m" % int(at_m))


## Pinned to its ground: once the view leaves the anchor the name goes with
## it, never sliding back inside the frame.
func test_a_name_is_pinned_to_its_anchor() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	var anchor := MapOwnership.label_anchor(Game.data, Game.state, mine)
	v.look_at_pack(anchor, 30000.0)
	var at := _entry(v, mine)["pos"] as Vector2
	v.look_at_pack(anchor + Vector2(60.0, 0.0), 30000.0)
	var moved := _entry(v, mine)
	assert_false(moved.is_empty(), "premise: still on screen")
	assert_lt((moved["pos"] as Vector2).x, at.x - 1.0, "it went with its ground")
	v.look_at_pack(anchor + Vector2(1500.0, 0.0), 30000.0)
	assert_true(_entry(v, mine).is_empty(), "its anchor off screen, no name")


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


# --- the capital's name (owner 2026-10-12: 远景时让国都名字更突出) -----------------

## Whole from 3 m per px out, gone at 2: at 2.5 half, at 2.25 a quarter.
func test_the_capitals_name_fades_as_the_camera_comes_in() -> void:
	assert_eq(Map3DHudLabels.capital_fade(40.0, 3.0, 2.0), 1.0)
	assert_eq(Map3DHudLabels.capital_fade(3.0, 3.0, 2.0), 1.0)
	assert_almost_eq(Map3DHudLabels.capital_fade(2.5, 3.0, 2.0), 0.5, 0.0001)
	assert_almost_eq(Map3DHudLabels.capital_fade(2.25, 3.0, 2.0), 0.25, 0.0001)
	assert_eq(Map3DHudLabels.capital_fade(2.0, 3.0, 2.0), 0.0)
	assert_eq(Map3DHudLabels.capital_fade(1.0, 3.0, 2.0), 0.0)


func test_the_players_capital_is_named_far_out_at_one_size() -> void:
	var v := _view()
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var burg: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), 30000.0)
	var e := v.capital_label()
	assert_false(e.is_empty(), "far out the capital is named")
	assert_eq(String(e["text"]), String(burg["label"]))
	assert_eq(float(e["px"]), Game.data.bal("map_capital_label_px"), "one size, not the ground's")
	assert_almost_eq((e["pos"] as Vector2).x, v.size.x * 0.5, 2.0, "over its mark")
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), Game.data.bal("map3d_zoom_min_m"))
	assert_true(v.capital_label().is_empty(), "close in the town itself is the mark")


func test_a_lost_capital_is_not_named() -> void:
	var v := _view()
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var burg: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
	var province := String(burg["province_code"])
	MapOwnership.set_owner(Game.data, Game.state, province, Game.data.resolve_realm("raider_realm"),
		"test: the capital falls")
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), 30000.0)
	assert_true(v.capital_label().is_empty(), "the realm no longer holds it")
