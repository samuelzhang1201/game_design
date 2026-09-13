extends GutTest
## The RTS-style world map embedded in the court screen's middle zone
## (user ruling 2026-09-03: the map IS the middle view; MAP tab returned
## to "close overlays" — that behavior is pinned by test_ui_rework).


## The zoom-out floor stops at map_max_scale_bar_km (owner request
## 2026-09-12), so a test that needs the whole world framed lifts the cap
## first and says why. Restored by GutTest's per-test repo reload.
func _whole_world(v: WorldMapView) -> void:
	Game.data.balance["map_max_scale_bar_km"] = 0.0
	v._zoom_at(v.size / 2.0, 0.00001)

func _view() -> WorldMapView:
	var v := WorldMapView.create()
	v.size = Vector2(320, 180)
	add_child_autofree(v)
	return v

## The pack is generated from an Azgaar export, so nothing below names a
## kingdom or a town literally — a re-export that renames the world must not
## break these. Everything hangs off the realm the pack binds player_realm
## to, and off that kingdom's own capital.
func _realm() -> Dictionary:
	return Game.data.kingdoms[Game.data.resolve_realm("player_realm")]

func _capital_code() -> String:
	return String(_realm()["capital_burg"])

func _capital() -> Dictionary:
	return Game.data.burgs[_capital_code()]

func _capital_name() -> String:
	return String(_capital()["label"])

## The map is drawn from the pack's own cells (spec 2026-09-11), so native
## coordinates go to the screen through the pan and zoom alone.
func test_screen_and_map_coordinates_round_trip() -> void:
	var v := _view()
	await wait_frames(2)
	for native in [Vector2(0, 0), Vector2(1216.79, 601.05), Vector2(2559, 928)]:
		var back := v.screen_to_map(v.map_to_screen(native))
		assert_almost_eq(back.x, native.x, 0.01, "x round-trips at %s" % native)
		assert_almost_eq(back.y, native.y, 0.01, "y round-trips at %s" % native)
	var native := Vector2(1000, 400)
	var want := v.map_to_screen(Vector2.ZERO) + native * v.view_scale()
	assert_almost_eq(v.map_to_screen(native).x, want.x, 0.01, "x is offset + native * zoom")
	assert_almost_eq(v.map_to_screen(native).y, want.y, 0.01, "y is offset + native * zoom")

func test_the_terrain_is_a_mesh_built_from_the_pack() -> void:
	var v := _view()
	await wait_frames(2)
	assert_not_null(v.terrain_mesh(), "the terrain mesh is built from cells.csv")
	assert_eq(v.map_size(), Vector2(float(Game.data.map_info["width"]),
		float(Game.data.map_info["height"])), "the map's size is the pack's canvas")
	assert_true(v.visible)

## Hit-testing samples the index bitmaps, which are in native coordinates:
## the capital's own pixel must resolve to the capital's own kingdom.
func test_the_index_bitmap_agrees_with_the_mapping() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = _capital()
	var native := Vector2(float(k["x"]), float(k["y"]))
	var back := v.screen_to_map(v.map_to_screen(native))
	assert_almost_eq(back.x, native.x, 0.01, "capital survives the round trip")
	assert_almost_eq(back.y, native.y, 0.01, "capital survives the round trip")

## Rivers are drawn by the game now that no render prints them: every river
## is in view with the whole world; none is when the view is zoomed into the
## open sea at the map's corner.
func test_rivers_draw_where_the_view_is() -> void:
	var v := _view()
	await wait_frames(2)
	_whole_world(v)
	assert_eq(v.visible_river_count(), Game.data.rivers.size(), "the whole world shows every river")
	v._zoom_at(Vector2.ZERO, 1000.0)
	assert_eq(v.visible_river_count(), 0, "open sea in the corner shows none")

## macOS trackpad (user request 2026-09-09): pinch zooms, two-finger drag
## pans. Both arrive as their own event types, beside the wheel.
## Rivers (owner 2026-09-13, reversing the morning's ruling): a point at the
## source, swelling as t^gamma to full width at the mouth. n = 5, half_max
## 4, gamma 1.5:  t = 0, .25, .5, .75, 1  ->  t^1.5 = 0, .125, .35355, .6495, 1
func test_a_river_rises_as_a_point_and_is_widest_at_its_mouth() -> void:
	var half := WorldMapView.river_taper(5, 4.0, 1.5)
	assert_eq(half.size(), 5)
	assert_almost_eq(half[0], 0.0, 0.001, "a point at the source")
	assert_almost_eq(half[1], 0.5, 0.001)
	assert_almost_eq(half[2], 1.414, 0.001)
	assert_almost_eq(half[3], 2.598, 0.001)
	assert_almost_eq(half[4], 4.0, 0.001, "full width at the mouth")

## The pack's point order is the flow (source first, mouth last) and is
## kept; every drawn river begins and ends on land, and a river the pack
## runs out to sea is cut at the shoreline: its mouth is on land, and the
## next step along the crossing segment is water (owner 2026-09-13).
func test_every_river_runs_from_land_to_the_shoreline() -> void:
	var v := _view()
	await wait_frames(2)
	var steps := int(Game.data.bal("map_river_smoothing_steps"))
	var to_sea := 0
	for code: String in Game.data.rivers:
		var raw: PackedVector2Array = Game.data.rivers[code]["polyline"]
		var curve := v.river_curve(code, raw)
		if curve.size() < 2:
			continue
		assert_false(v._is_water(curve[0]), "%s rises on land" % code)
		var mouth := curve[curve.size() - 1]
		assert_false(v._is_water(mouth), "%s ends on land" % code)
		var smooth := MapGeometry.smooth_open(raw, steps)
		if not v._is_water(raw[0]):
			assert_eq(curve[0], smooth[0], "%s keeps the pack's source" % code)
		if not v._is_water(smooth[smooth.size() - 1]):
			continue
		to_sea += 1
		# The last land sample of the smoothed course and the first water one
		# after it bracket the drawn mouth, which sits on their segment.
		var last := smooth.size() - 1
		while last > 0 and v._is_water(smooth[last]):
			last -= 1
		var a := smooth[last]
		var b := smooth[last + 1]
		assert_almost_eq(a.distance_to(mouth) + mouth.distance_to(b), a.distance_to(b), 0.01,
			"%s's mouth lies on the crossing segment" % code)
		# The land is pixels: the water begins within a px or so along the
		# course, not at an exact real-valued edge.
		var dir := (b - mouth).normalized()
		var wet := false
		for px: float in [0.5, 1.0, 1.5]:
			wet = wet or v._is_water(mouth + dir * px)
		assert_true(wet, "%s's mouth is at the water's edge" % code)
	assert_gt(to_sea, 100, "most of the pack's rivers reach the sea")

## The sea (owner 2026-09-13, after the reference chart) is a SeaLayer
## behind the view: one quad over the pack's distance field, first child,
## drawn behind the parent, following the view's offset and zoom.
func test_the_sea_is_a_field_of_bands_behind_the_land() -> void:
	var v := _view()
	await wait_frames(2)
	var sea := v.sea_layer()
	assert_not_null(sea)
	assert_true(sea.show_behind_parent, "drawn under the land mesh")
	assert_eq(sea.get_index(), 0, "under every other child too")
	assert_true(sea.has_field(), "the pack's world_sea_distance.png loaded")
	assert_eq(sea.field_size(), v.map_size(), "the field is the map's canvas")
	assert_not_null(sea.material, "the band shader")
	v._zoom_at(v.size / 2.0, 1.5)
	v._offset += Vector2(-30.0, -20.0)
	v._clamp_offset()
	v.queue_redraw()
	await wait_frames(2)
	assert_eq(sea.position, v._offset, "pans with the view")
	assert_eq(sea.scale, Vector2(v._zoom, v._zoom), "zooms with it")

## The compass rose (owner request 2026-09-13) is the sheet's furniture: a
## box in the top-right corner, fixed in screen px, and gone at alpha 0.
func test_the_compass_sits_in_the_top_right_corner() -> void:
	var v := _view()
	await wait_frames(2)
	var rect := v.compass_rect()
	var margin := Game.data.bal("map_compass_margin_px")
	assert_almost_eq(rect.end.x, v.size.x - margin, 0.001, "inset from the right edge")
	assert_almost_eq(rect.position.y, margin, 0.001, "inset from the top")
	assert_eq(rect.size.x, Game.data.bal("map_compass_size_px"))
	assert_true(Rect2(Vector2.ZERO, v.size).encloses(rect), "inside the view")
	v._zoom_at(v.size / 2.0, 2.0)
	v._offset += Vector2(-30.0, -20.0)
	assert_eq(v.compass_rect(), rect, "neither zooms nor pans")
	var alpha: float = Game.data.balance["map_compass_alpha"]
	Game.data.balance["map_compass_alpha"] = 0.0
	assert_eq(v.compass_rect(), Rect2(), "hidden at alpha 0")
	Game.data.balance["map_compass_alpha"] = alpha

func test_pinch_gesture_zooms() -> void:
	var v := _view()
	await wait_frames(2)
	var before := v.view_scale()
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = v.size / 2.0
	pinch.factor = 1.5
	v._gui_input(pinch)
	assert_gt(v.view_scale(), before, "fingers apart zooms in")
	var apart := v.view_scale()
	pinch.factor = 0.5
	v._gui_input(pinch)
	assert_lt(v.view_scale(), apart, "fingers together zooms out")

func test_two_finger_pan_moves_the_view_without_zooming() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 4.0)  # zoom in so there is room to pan
	var scale_before := v.view_scale()
	var offset_before := v._offset
	var pan := InputEventPanGesture.new()
	pan.position = v.size / 2.0
	pan.delta = Vector2(6, 0)
	v._gui_input(pan)
	assert_almost_eq(v.view_scale(), scale_before, 0.0001, "panning does not zoom")
	assert_ne(v._offset, offset_before, "but it does move the view")

## Kingdom names are drawn into the terrain, so they hide when the zoom makes
## them illegible rather than piling up as unreadable specks.
func test_kingdom_labels_hide_when_too_small_to_read() -> void:
	var v := _view()
	await wait_frames(2)
	var min_px := Game.data.bal("map_label_min_px")
	var scale_px := Game.data.bal("map_label_scale_px")
	assert_gt(scale_px, 0.0, "the label size is data-driven")
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_gt(scale_px * v.view_scale(), min_px, "zoomed in, labels show")
	_whole_world(v)
	assert_lt(scale_px * v.view_scale(), min_px, "zoomed out, they drop away")

## Hovering land tells the screens which country it is, so the left column
## can swap to that country's card.
func test_hovering_a_country_announces_it() -> void:
	var v := _view()
	await wait_frames(2)
	var seen: Array[String] = []
	v.country_hovered.connect(func(code: String) -> void: seen.append(code))
	var k: Dictionary = _capital()
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	assert_false(seen.is_empty(), "hovering land announced a country")
	assert_eq(seen[seen.size() - 1], Game.data.resolve_realm("player_realm"),
		"and it is the one that holds the capital")
	v.hover_at(v.map_to_screen(Vector2(5.0, 5.0)))  # open sea
	assert_eq(seen[seen.size() - 1], "", "open sea announces no country")

## The dev demo drives the whole dynamic-territory path.
func test_dev_flip_moves_the_hovered_province_and_the_border() -> void:
	var v := _view()
	await wait_frames(2)
	var mine := Game.data.resolve_realm("player_realm")
	var before := MapOwnership.outline_of(Game.data, Game.state, mine).duplicate(true)
	var k: Dictionary = _capital()
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	# Hovering the capital picks its pin, not the land under it; nudge off it.
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]) + 40.0, float(k["y"]) + 40.0)))
	var moved := v.dev_flip_hovered_province()
	if moved.is_empty():
		pass_test("no province under that point on this pack — nothing to flip")
		return
	assert_ne(String(moved["from"]), String(moved["to"]), "it changed hands")
	assert_eq(MapOwnership.owner_of(Game.data, Game.state, String(moved["province"])),
		String(moved["to"]), "and the engine agrees")
	assert_ne(MapOwnership.outline_of(Game.data, Game.state, mine), before,
		"the player's border was redrawn")

func test_court_screen_embeds_the_world_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_not_null(screen.world_map(), "court builds a WorldMapView")
	assert_true(screen.world_map().visible, "map assets exist, so it shows")

func test_selecting_a_kingdom_opens_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	var row: Dictionary = _realm()
	v.select_state(int(row["state_id"]))
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, String(row["label"]))

func test_water_click_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_state(int(_realm()["state_id"]))
	v.select_state(-1)
	assert_false(v.card().visible, "water/no-state closes the card")

## The opening framing fills the frame — a contain fit would letterbox
## roughly half the column height on this 2.76:1 map and leave the dead
## band the middle column is meant to stop showing.
func test_opens_filling_the_frame() -> void:
	var v := _view()
	await wait_frames(2)
	var drawn := Rect2(v._offset, v.map_size() * v._zoom)
	assert_true(drawn.position.x <= 1.0, "no gutter on the left")
	assert_true(drawn.position.y <= 1.0, "no gutter on the top")
	assert_true(drawn.end.x >= v.size.x - 1.0, "no gutter on the right")
	assert_true(drawn.end.y >= v.size.y - 1.0, "no gutter on the bottom")

## ...and the whole world stays one wheel-out away. Asserts the visible
## property, not the formula: a cover-fit floor would satisfy
## "_zoom == _zoom_min()" while cropping a quarter of the map off the sides.
func test_zooming_out_reaches_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	var drawn := Rect2(v._offset, v.map_size() * v._zoom)
	assert_true(drawn.position.x >= -1.0, "nothing cropped off the left")
	assert_true(drawn.position.y >= -1.0, "nothing cropped off the top")
	assert_true(drawn.end.x <= v.size.x + 1.0, "nothing cropped off the right")
	assert_true(drawn.end.y <= v.size.y + 1.0, "nothing cropped off the bottom")
	assert_almost_eq(drawn.get_center().x, v.size.x / 2.0, 1.0, "centered x")
	assert_almost_eq(drawn.get_center().y, v.size.y / 2.0, 1.0, "centered y")

func test_wheel_zoom_in_magnifies_and_out_floors_at_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	var opening := v._zoom
	v._zoom_at(v.size / 2.0, 4.0)
	assert_gt(v._zoom, opening, "wheel up magnifies")
	v._zoom_at(v.size / 2.0, 0.0001)
	assert_almost_eq(v._zoom, v._zoom_min(), 0.0001,
		"wheel down floors at the whole map, never smaller")
	assert_lt(v._zoom, opening, "the whole map sits wider out than the opening")

## Regression guard: the map shares the court screen with the left column
## and the council column. The council column hides by default (user ruling
## 2026-09-09) but must stay reachable through the handle — if the map ever
## covered or lost them there would be no way to issue an order or end the
## turn.
func test_court_keeps_the_order_panels_reachable_beside_the_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_true(screen.get_node("%LogPanel").is_visible_in_tree(),
		"the left column stays visible")
	assert_true(screen.council_handle().is_visible_in_tree(),
		"the ENTER THE COUNCIL handle is there")
	screen.council_handle().pressed.emit()
	await wait_frames(1)
	assert_true(screen.get_node("%SidePanel").is_visible_in_tree(),
		"the council column opens")
	assert_true(screen.end_turn_button().is_visible_in_tree(),
		"End Turn is reachable inside it")

## Hover: the kingdom under the mouse gets its border outlined (user request
## 2026-09-08). Loops come from the pack's borders.csv; -1 (water/no state)
## clears the outline.
func test_hovering_a_kingdom_outlines_its_border() -> void:
	var v := _view()
	await wait_frames(1)
	var sid := int(_realm()["state_id"])
	v.hover_state(sid)
	assert_eq(v.hovered_state(), sid)
	assert_gt(v.hover_loops().size(), 0, "hovered kingdom has border loops to draw")
	v.hover_state(-1)
	assert_eq(v.hovered_state(), -1, "water/no-state clears the hover")
	assert_eq(v.hover_loops().size(), 0)

func test_mouse_motion_over_a_kingdom_sets_the_hover() -> void:
	var v := _view()
	await wait_frames(2)
	var row: Dictionary = _realm()
	var mm := InputEventMouseMotion.new()
	mm.position = v.map_to_screen(Vector2(float(row["center_x"]), float(row["center_y"])))
	v._gui_input(mm)
	assert_eq(v.hovered_state(), int(row["state_id"]))

## Pins: capitals always; towns and villages appear as the player zooms in
## (thresholds in balance.csv, rule in MapObjects).
func test_town_pins_appear_as_the_view_zooms_in() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	var far := v.visible_burg_count()
	assert_eq(far, Game.data.kingdoms.size(),
		"zoomed all the way out: one pin per capital")
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_gt(v.view_scale(), Game.data.bal("map_lod_village_scale"))
	assert_eq(v.visible_burg_count(), Game.data.burgs.size(), "zoomed in: every burg")

func test_hovering_a_capital_names_it() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = _capital()
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	assert_eq(v.hovered_object().get("kind", ""), "burg")
	assert_eq(v.hovered_object().get("code", ""), _capital_code())
	assert_eq(v.hover_tooltip(), _capital_name())
	assert_eq(v.hovered_state(), int(_realm()["state_id"]),
		"the kingdom outline stays on under a pin")

func test_hovering_open_sea_clears_the_tooltip() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = _capital()
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	v.hover_at(v.map_to_screen(Vector2(5.0, 5.0)))  # top-left ocean corner
	assert_eq(v.hovered_object().get("kind", ""), "water")
	assert_eq(v.hover_tooltip(), "")

## Cards per object kind (MapInfoCard renders what MapObjects.describe says).
func test_selecting_a_town_opens_its_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": _capital_code()})
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, _capital_name())
	assert_true(v.card().body_label().text.begins_with("Capital of %s, %s" % [
		String(Game.data.provinces[String(_capital()["province_code"])]["label"]),
		String(_realm()["label"])]), v.card().body_label().text)

func test_selecting_land_leads_with_province_and_terrain() -> void:
	var v := _view()
	await wait_frames(1)
	var k: Dictionary = _capital()
	var prov: Dictionary = Game.data.provinces[String(k["province_code"])]
	var biome_id := 6  # temperate deciduous forest, present in every pack
	v.select_object({"kind": "land", "state_id": int(_realm()["state_id"]),
		"province_id": int(prov["province_id"]), "biome_id": biome_id,
		"x": float(k["x"]), "y": float(k["y"])})
	assert_eq(v.card_title().text, String(prov["label"]))
	var body := v.card().body_label().text
	assert_true(body.begins_with("%s\nTerrain: %s" % [String(_realm()["label"]),
		String(Game.data.biomes[biome_id]["label"])]), body)
	assert_true(body.contains("Capital: %s" % _capital_name()),
		"kingdom overview follows")

func test_selecting_water_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": _capital_code()})
	v.select_object({"kind": "water"})
	assert_false(v.card().visible)

func test_ask_button_is_off_until_a_screen_enables_it() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": _capital_code()})
	assert_false(v.card().ask_button().visible, "no input box wired: no Ask")
	v.set_ask_enabled(true)
	v.select_object({"kind": "burg", "code": _capital_code()})
	assert_true(v.card().ask_button().visible)

var _asked := ""

func test_ask_emits_the_question_for_the_selected_place() -> void:
	var v := _view()
	await wait_frames(1)
	v.set_ask_enabled(true)
	v.place_asked.connect(func(text: String) -> void: _asked = text)
	v.select_object({"kind": "burg", "code": _capital_code()})
	v.card().ask_button().pressed.emit()
	assert_eq(_asked, "What do we know of %s?" % _capital_name())

## The tooltip must stay readable at the frame's edge: a pin hovered in the
## bottom-right corner gets its label pushed back inside the view.
func test_tooltip_stays_inside_the_view_at_the_edge() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 1000.0)  # deep zoom: the map overflows every side
	var k: Dictionary = _capital()
	var kp := Vector2(float(k["x"]), float(k["y"]))
	var corner := v.size - Vector2(2.0, 2.0)
	# Park the capital in the corner through the view's own mapping, so this
	# stays right whatever framing the view opens with.
	v._offset += corner - v.map_to_screen(kp)
	v.hover_at(corner)
	assert_eq(v.hover_tooltip(), _capital_name())
	var r := v.tooltip_rect()
	assert_true(Rect2(Vector2.ZERO, v.size).encloses(r),
		"tooltip %s stays inside the view %s" % [r, v.size])

## The map is a scene like every other view (character portraits, locations,
## user request 2026-09-08), not a bare .new() — so it can be opened and
## decorated in the editor, and every screen gets the same one.
func test_create_instantiates_from_the_scene_file() -> void:
	var v := WorldMapView.create()
	add_child_autofree(v)
	await wait_frames(1)
	assert_eq(v.scene_file_path, WorldMapView.SCENE_PATH, "came from the scene file")
	assert_not_null(v.card(), "and is fully wired")

func test_every_gameplay_screen_uses_the_map_scene() -> void:
	for path in ["res://scenes/court.tscn", "res://scenes/conversation.tscn",
			"res://scenes/day_run.tscn"]:
		var screen: Control = load(path).instantiate()
		add_child_autofree(screen)
		await wait_frames(1)
		var map: WorldMapView = screen.find_child("WorldMap", true, false)
		assert_not_null(map, "%s embeds the map" % path.get_file())
		assert_eq(map.scene_file_path, WorldMapView.SCENE_PATH,
			"%s builds it from the scene, not .new()" % path.get_file())

## Province view (user request 2026-09-09): every kingdom's internal seams
## as light dashed lines, above a minimum zoom. ON from the first frame
## since 2026-09-12, and since 2026-09-13 (owner) not a toggle at all: no
## key turns it off.
func test_the_province_view_is_always_on() -> void:
	var v := _view()
	await wait_frames(2)
	assert_true(v.show_provinces, "on by default")
	var seen: Array = []
	v.province_view_changed.connect(func(on: bool) -> void: seen.append(on))
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_P
	v._gui_input(key)
	assert_true(v.show_provinces, "P does nothing")
	assert_true(seen.is_empty(), "nothing to announce")

## Kingdom outlines are drawn as the B-spline Azgaar drew the render with:
## one smooth ring per outline loop, steps points per vertex, following
## ownership.
func test_border_rings_are_smoothed_outlines_that_follow_conquest() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	var mine := Game.data.resolve_realm("player_realm")
	var loops := MapOwnership.outline_of(Game.data, Game.state, mine)
	var rings := v.border_rings(mine)
	assert_eq(rings.size(), loops.size(), "one ring per loop")
	var steps := int(Game.data.bal("map_border_smoothing_steps"))
	for i in loops.size():
		assert_eq((rings[i] as PackedVector2Array).size(), (loops[i] as PackedVector2Array).size() * steps)
	var before: int = (rings[0] as PackedVector2Array).size()
	var lost: String = MapOwnership.provinces_of(Game.data, Game.state, mine)[0]
	MapOwnership.set_owner(Game.data, Game.state, lost, Game.data.resolve_realm("raider_realm"), "raid")
	var after := v.border_rings(mine)
	var total_before := 0
	for l in loops:
		total_before += (l as PackedVector2Array).size() * steps
	var total_after := 0
	for r in after:
		total_after += (r as PackedVector2Array).size()
	assert_ne(total_after, total_before, "the rings were rebuilt for the new border")

## In the province view a click names the province under it for the left
## column, and bare land opens no floating card; water clears the selection.
func test_clicking_land_in_the_province_view_selects_the_province() -> void:
	var v := _view()
	await wait_frames(2)
	var picked: Array = []
	v.province_selected.connect(func(code: String) -> void: picked.append(code))
	var code := String(Game.data.burgs[_capital_code()]["province_code"])
	var row: Dictionary = Game.data.provinces[code]
	var centre := Vector2(float(row["center_x"]), float(row["center_y"]))
	v.show_provinces = false
	v._select_at(v.map_to_screen(centre))
	assert_eq(v.selected_province(), "", "no selection while the view is off")
	assert_true(picked.is_empty())
	v.show_provinces = true
	v._select_at(v.map_to_screen(centre))
	assert_eq(v.selected_province(), code, "the province under the click")
	assert_eq(picked, [code])
	v._select_at(v.map_to_screen(Vector2(2.0, 2.0)))
	assert_eq(v.selected_province(), "", "water clears it")
	assert_eq(picked, [code, ""])
	v._select_at(v.map_to_screen(centre))
	v.show_provinces = false
	assert_eq(v.selected_province(), "", "turning the view off clears it too")

func test_province_seams_draw_only_when_zoomed_in_enough() -> void:
	var v := _view()
	await wait_frames(2)
	v.show_provinces = true
	_whole_world(v)
	assert_eq(v.visible_seam_count(), 0, "zoomed out, no seams")
	# Zoom to the ceiling and centre the frame on one of the realm's own
	# seams — the frame is a few native px wide at that zoom, so it has to
	# be looking at a seam to show one.
	var seams := MapOwnership.seams_of(Game.data, Game.state, String(_realm()["kingdom_code"]))
	assert_gt(seams.size(), 0, "the realm has seams to draw")
	var mid: Vector2 = (seams[0][0] + seams[0][1]) / 2.0
	v._zoom_at(v.size / 2.0, 1000.0)
	v._offset += v.size / 2.0 - v.map_to_screen(mid)
	v._clamp_offset()
	assert_gt(v.visible_seam_count(), 0, "zoomed in on a seam, it is on screen")
	v.show_provinces = false
	assert_eq(v.visible_seam_count(), 0, "off means none")

## The render is terrain only (user ruling 2026-09-09): the view paints every
## province in its live owner's palette colour and draws every kingdom's
## border itself, so conquest repaints without new art.
func test_every_province_on_screen_is_washed_in_its_owners_colour() -> void:
	var v := _view()
	await wait_frames(2)
	_whole_world(v)
	var fills := v.political_fills()
	assert_eq(fills.size(), Game.data.province_borders.size(), "every province is painted")
	var mine := Game.data.resolve_realm("player_realm")
	var want := MapPalette.color_of(Game.data, mine)
	var checked := 0
	for f in fills:
		if MapOwnership.owner_of(Game.data, Game.state, String(f["code"])) == mine:
			var c: Color = f["color"]
			assert_eq(Color(c.r, c.g, c.b), Color(want.r, want.g, want.b),
				"%s wears the crown's colour" % String(f["code"]))
			assert_almost_eq(c.a, Game.data.bal("map_political_alpha"), 0.001)
			checked += 1
	assert_gt(checked, 0)

## Owner ruling 2026-09-12 (second pass, after development/exmaples/
## mapSample.jpg): every realm wears its own muted wash again — the
## monochrome sheet was dropped — and the wash is what carries the colour, so
## the land underneath stays a pale neutral that does not tint it.
func test_every_realm_is_washed_in_its_own_colour() -> void:
	var v := _view()
	await wait_frames(2)
	assert_gt(Game.data.bal("map_political_alpha"), 0.0,
		"the political wash is on in balance.csv")
	assert_true(v.political_wash_visible(), "so the view paints it")
	_whole_world(v)
	var seen: Dictionary = {}
	for f in v.political_fills():
		seen[MapOwnership.owner_of(Game.data, Game.state, String(f["code"]))] = f["color"]
	assert_gt(seen.size(), 1, "more than one realm is on screen")
	var hues: Dictionary = {}
	for code: String in seen:
		var c: Color = seen[code]
		hues["%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]] = true
	assert_eq(hues.size(), seen.size(), "and no two of them share a colour")

func test_the_map_is_drawn_on_paper() -> void:
	var v := _view()
	await wait_frames(2)
	assert_true(v.paper_grain_visible(), "a trace of paper grain is on")
	# The bright modern theme (owner 2026-09-13) dropped the rolled-scroll
	# shadow; balance.csv map_paper_vignette brings it back.
	assert_false(v.paper_vignette_visible(), "but not the scroll's edge shadow")

func test_a_conquered_province_is_repainted_for_its_new_owner() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	_whole_world(v)
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var lost: String = MapOwnership.provinces_of(Game.data, Game.state, mine)[0]
	MapOwnership.set_owner(Game.data, Game.state, lost, raider, "a raid")
	var want := MapPalette.color_of(Game.data, raider)
	for f in v.political_fills():
		if String(f["code"]) == lost:
			var c: Color = f["color"]
			assert_eq(Color(c.r, c.g, c.b), Color(want.r, want.g, want.b), "the raiders' colour now")
			return
	fail_test("the lost province was not painted at all")

## The ECONOMY view (owner request 2026-09-13, after
## development/exmaples/economyView.png): the land drawn as manors — the
## pack's cells — in their holders' colours, and the working manors badged
## with the good they make most of and how many units.
func test_the_economy_view_draws_the_land_as_manors() -> void:
	var v := _view()
	await wait_frames(2)
	assert_null(v.manor_mesh(), "no manors outside the economy view")
	assert_eq(v.manor_badges().size(), 0)
	v.show_economy = true
	assert_not_null(v.manor_mesh(), "the manors are one mesh")
	assert_false(v.political_wash_visible(), "standing in for the political wash")
	assert_gt(v.manor_edges().size(), 0, "with their edges ruled in")
	# Close on the capital, where every settlement passes the LOD rule.
	var at := Vector2(float(_capital()["x"]), float(_capital()["y"]))
	v._zoom_at(v.size / 2.0, 3.0)
	v._offset += v.size / 2.0 - v.map_to_screen(at)
	v._clamp_offset()
	var badges := v.manor_badges()
	assert_gt(badges.size(), 0, "working manors around the capital carry badges")
	var manors := MapEconomy.manors(Game.data)
	for b: Dictionary in badges:
		var m: Dictionary = manors[int(b["cell"])]
		assert_eq(String(b["good"]), String(m["good"]), "a badge shows its manor's chief good")
		assert_eq(String(b["text"]), v._trim_zeros(float(m["units"])), "and how many units")
		assert_true((m["burgs"] as Array).has(String(b["burg"])), "for a settlement in that manor")
	for i in badges.size():
		for j in range(i + 1, badges.size()):
			assert_false((badges[i]["rect"] as Rect2).intersects(badges[j]["rect"]),
				"badges never overlap")
	assert_eq(v.settlement_sprites().size(), 0, "the badges stand in for the town drawings")
	var first: Dictionary = badges[0]
	var obj := v._object_under((first["badge"] as Rect2).get_center())
	assert_eq(String(obj.get("kind", "")), "burg", "clicking a badge picks its settlement")
	assert_eq(String(obj.get("code", "")), String(first["burg"]))
	v.show_economy = false
	assert_gt(v.settlement_sprites().size(), 0, "and the towns come back with the layer off")

func test_a_conquered_manor_takes_its_new_holders_colour() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	v.show_economy = true
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var ids: Array = Game.data.cells.keys()
	ids.sort()
	var cell := -1
	for id: int in ids:
		if not MapTerrain.is_water(Game.data.cells[id]) and v.cell_owner(id) == mine:
			cell = id
			break
	assert_gte(cell, 0, "the realm holds land cells")
	var before := v.manor_color(cell)
	var mesh_before := v.manor_mesh()
	MapOwnership.set_owner(Game.data, Game.state, v.cell_province(cell), raider, "a raid")
	assert_eq(v.cell_owner(cell), raider, "the manor is the raiders' now")
	assert_ne(v.manor_color(cell), before, "and wears their colour")
	assert_ne(v.manor_mesh(), mesh_before, "the manor mesh is rebuilt for the new holder")

## Settlement art (user request 2026-09-09): zoomed in, towns draw as their
## tier's picture standing on their point and are picked anywhere on it;
## zoomed out they fall back to pins.
func test_towns_draw_as_art_when_zoomed_in_and_pins_when_out() -> void:
	var v := _view()
	await wait_frames(2)
	_whole_world(v)
	assert_eq(v.sprite_height(), 0.0, "zoomed out, no art")
	assert_eq(v.settlement_sprites().size(), 0)
	var k: Dictionary = _capital()
	var at := Vector2(float(k["x"]), float(k["y"]))
	v._zoom_at(v.size / 2.0, 1000.0)
	v._offset += v.size / 2.0 - v.map_to_screen(at)
	v._clamp_offset()
	assert_gt(v.sprite_height(), 0.0, "zoomed in, art")
	assert_lte(v.sprite_height(), Game.data.bal("map_sprite_max_px"))
	var found: Dictionary = {}
	for sp in v.settlement_sprites():
		if String(sp["code"]) == _capital_code():
			found = sp
	assert_false(found.is_empty(), "the capital is drawn")
	var rect: Rect2 = found["rect"]
	var base := v.map_to_screen(at)
	# A seaside drawing is slid back onto its own land (owner 2026-09-13), so
	# it stands on its point PLUS that push and no further.
	var push := v.inland_bias(_capital_code(), at, rect.size.x * 0.5 / v.view_scale()) \
		* rect.size.x * Game.data.bal("map_sprite_inland")
	assert_almost_eq(rect.position.x + rect.size.x / 2.0, base.x + push.x, 0.5,
		"standing on its point, nudged inland")
	assert_true(rect.end.y >= base.y + push.y, "its feet reach the point")
	var obj := v._object_under(rect.get_center())
	assert_eq(String(obj.get("kind", "")), "burg")
	assert_eq(String(obj.get("code", "")), _capital_code(), "picked anywhere on the picture")

## The military layer (owner request 2026-09-13, after
## development/exmaples/MilitaryView.png): the realm's own regiments as
## counters — a glyph square joined to a box stating the headcount. Swords
## for a regiment, a crown for the one nearest the capital, waves for a fleet.
func test_the_military_layer_draws_the_realms_regiments_as_counters() -> void:
	var v := _view()
	await wait_frames(2)
	assert_eq(v.army_markers().size(), 0, "nothing is drawn while the layer is off")
	v.show_armies = true
	var mine := Game.data.resolve_realm("player_realm")
	var regiments := MapObjects.regiments_of(Game.data, mine)
	assert_gt(regiments.size(), 0, "the pack quarters regiments in the realm")
	# The map opens on the capital now, so only part of the realm is framed:
	# pull back to the whole world before counting.
	v._zoom_at(v.size / 2.0, 0.0001)
	var markers := v.army_markers()
	assert_eq(markers.size(), regiments.size(), "one counter per regiment of the realm")
	# Owner ruling 2026-09-10: the player's host only.
	var by_code: Dictionary = {}
	for m: Dictionary in markers:
		by_code[String(m["code"])] = m
	for r: Dictionary in Game.data.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != mine:
			assert_false(by_code.has(String(r["regiment_code"])),
				"a foreign regiment is not drawn")
	var royal := MapObjects.royal_regiment(Game.data, mine)
	assert_ne(royal, "", "the realm has a land regiment to fly the crown over")
	var capital := _capital()
	var seat := Vector2(float(capital["x"]), float(capital["y"]))
	var royal_row: Dictionary = Game.data.world_table("military", "regiments")[royal]
	var royal_d := seat.distance_to(Vector2(float(royal_row["x"]), float(royal_row["y"])))
	for r: Dictionary in regiments:
		var code := String(r["regiment_code"])
		var m: Dictionary = by_code[code]
		assert_eq(String(m["text"]), str(int(MapObjects.regiment_size(Game.data, r))),
			"%s states its headcount" % code)
		var naval := String(r.get("is_naval", "0")) == "1"
		assert_eq(String(m["glyph"]), "waves" if naval else ("crown" if code == royal else "swords"))
		if not naval:
			assert_gte(seat.distance_to(Vector2(float(r["x"]), float(r["y"]))), royal_d,
				"no land regiment lies nearer the capital than the royal one")
	# Zoomed out the counters crowd together; the stacked ones are pushed clear.
	for i in markers.size():
		for j in range(i + 1, markers.size()):
			assert_false((markers[i]["rect"] as Rect2).intersects(markers[j]["rect"]),
				"counters never overlap")
	v.show_armies = false
	assert_eq(v.army_markers().size(), 0, "the layer clears")

## The markers are counters on the map: fixed screen size at any zoom, and
## each stands on the point the pack quarters its regiment at.
func test_regiment_markers_stand_on_their_point_at_a_fixed_size() -> void:
	var v := _view()
	await wait_frames(2)
	v.show_armies = true
	var r: Dictionary = MapObjects.regiments_of(Game.data,
		Game.data.resolve_realm("player_realm"))[0]
	var at := Vector2(float(r["x"]), float(r["y"]))
	v._offset += v.size / 2.0 - v.map_to_screen(at)
	v._clamp_offset()
	var found: Dictionary = {}
	for m: Dictionary in v.army_markers():
		if String(m["code"]) == String(r["regiment_code"]):
			found = m
	assert_false(found.is_empty(), "the regiment is drawn")
	var rect: Rect2 = found["rect"]
	var icon: Rect2 = found["icon"]
	var count: Rect2 = found["count"]
	var h := v.army_badge_height()
	assert_almost_eq(rect.size.y, h, 0.01)
	assert_almost_eq(icon.size.x, h, 0.01, "the glyph sits in a square")
	assert_almost_eq(count.position.x, icon.end.x, 0.01, "joined to the headcount box")
	assert_almost_eq(icon.size.x + count.size.x, rect.size.x, 0.01)
	assert_almost_eq(rect.get_center().x, v.map_to_screen(at).x, 0.5, "standing on its point")
	assert_gte(rect.get_center().y, v.map_to_screen(at).y - 0.5, "never pushed ABOVE its point")
	# Owner request 2026-09-13: smaller than the towns, and never over one.
	for zoom in [1.0, 4.0]:
		v._zoom_at(v.size / 2.0, zoom)
		assert_gt(v.sprite_height(), 0.0, "the towns are drawings at this zoom")
		assert_lt(v.army_badge_height(), v.sprite_height(),
			"a counter is smaller than the largest settlement drawing")
		assert_lte(v.army_badge_height(), Game.data.bal("map_army_badge_max_px"))
		var marks := v.settlement_marks()
		for m: Dictionary in v.army_markers():
			for mark: Rect2 in marks:
				assert_false((m["rect"] as Rect2).intersects(mark),
					"%s covers no settlement" % m["code"])

## Clicking a regiment names it in the fact card, like any other map object.
func test_clicking_a_regiment_opens_its_card() -> void:
	var v := _view()
	await wait_frames(2)
	v.show_armies = true
	var r: Dictionary = MapObjects.regiments_of(Game.data,
		Game.data.resolve_realm("player_realm"))[0]
	var at := Vector2(float(r["x"]), float(r["y"]))
	v._offset += v.size / 2.0 - v.map_to_screen(at)
	v._clamp_offset()
	var obj := v._object_under(v.map_to_screen(at))
	assert_eq(String(obj.get("kind", "")), "army", "the marker is picked over the land")
	assert_eq(String(obj.get("code", "")), String(r["regiment_code"]))
	assert_eq(MapObjects.label_of(Game.data, obj), String(r["label"]), "the tooltip names it")
	var entry := MapObjects.describe(Game.data, obj, Game.state)
	assert_eq(String(entry["title"]), String(r["label"]))
	var text := "\n".join(entry["lines"])
	assert_string_contains(text, "Under arms: %d" % int(MapObjects.regiment_size(Game.data, r)))
	# With the layer off the same point is land again, not a regiment.
	v.show_armies = false
	assert_ne(String(v._object_under(v.map_to_screen(at)).get("kind", "")), "army")

## Owner ruling 2026-09-12: the pack's points of interest are off the sheet.
## The code that drew them stays, switched off by map_show_markers, so this
## turns it back on and checks it still works — and checks that with the
## switch at 0 nothing is drawn however far in the view is zoomed.
func test_points_of_interest_are_off() -> void:
	var v := _view()
	await wait_frames(2)
	assert_eq(Game.data.bal("map_show_markers"), 0.0, "switched off in balance.csv")
	assert_false(MapObjects.markers_visible(Game.data))
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_eq(v.marker_sprites().size(), 0, "nothing drawn at any zoom")

## With the switch on they draw as their icons (data/marker_art.csv) once the
## zoom passes the marker LOD: a fixed map_marker_px square on the point,
## none while zoomed out.
func test_points_of_interest_draw_as_icons_when_shown_and_zoomed_in() -> void:
	var v := _view()
	await wait_frames(2)
	Game.data.balance["map_show_markers"] = 1.0
	v._zoom_at(v.size / 2.0, 0.0001)
	assert_eq(v.marker_sprites().size(), 0, "zoomed out, no marker icons")
	var code: String = Game.data.markers.keys()[0]
	var m: Dictionary = Game.data.markers[code]
	var at := Vector2(float(m["x"]), float(m["y"]))
	v._zoom_at(v.size / 2.0, 1000.0)
	v._offset += v.size / 2.0 - v.map_to_screen(at)
	v._clamp_offset()
	var found: Dictionary = {}
	for sp in v.marker_sprites():
		if String(sp["code"]) == code:
			found = sp
	assert_false(found.is_empty(), "the marker under the view is drawn as an icon")
	var rect: Rect2 = found["rect"]
	var px := Game.data.bal("map_marker_px")
	assert_almost_eq(rect.size.x, px, 0.01, "fixed screen size")
	assert_almost_eq(rect.get_center().x, v.map_to_screen(at).x, 0.5, "centred on the point")
	assert_almost_eq(rect.get_center().y, v.map_to_screen(at).y, 0.5, "centred on the point")

## The scale bar (owner request 2026-09-12): the pack's own distance_scale
## turned into the largest round distance whose bar still fits, restated at
## every zoom so the bar always means something.
func test_the_scale_bar_fits_its_allowance_and_reads_round() -> void:
	var v := _view()
	await wait_frames(2)
	var bar := v.scale_bar()
	assert_false(bar.is_empty(), "the pack carries a distance scale")
	assert_lte(float(bar["width_px"]), Game.data.bal("map_scale_bar_max_px") + 0.001,
		"the bar never runs past its allowance")
	assert_almost_eq(float(bar["distance"]),
		MapGeometry.nice_step(float(bar["distance"])), 0.0001,
		"the distance is on the 1-2-5 ladder")
	assert_true(String(bar["text"]).ends_with(String(Game.data.map_info["distance_unit"])),
		"and is labelled in the pack's unit")

func test_zooming_in_shrinks_the_distance_the_scale_bar_states() -> void:
	var v := _view()
	await wait_frames(2)
	# _zoom_at takes a FACTOR, and the floor clamps it: start at the floor
	# (the whole world) and multiply in.
	v._zoom_at(v.size / 2.0, 0.0001)
	var far := float(v.scale_bar()["distance"])
	v._zoom_at(v.size / 2.0, 20.0)
	var near := float(v.scale_bar()["distance"])
	assert_lt(near, far, "a closer view measures a shorter distance")

## Rivers are smoothed once in native coordinates and kept (owner 2026-09-12:
## the pack's raw polylines read as hard kinks).
func test_a_river_is_smoothed_and_still_meets_both_its_ends() -> void:
	var v := _view()
	await wait_frames(2)
	var code: String = Game.data.rivers.keys()[0]
	var raw: PackedVector2Array = Game.data.rivers[code]["polyline"]
	if raw.size() < 3:
		return
	var curve := v.river_curve(code, raw)
	assert_gt(curve.size(), raw.size(), "the course carries more points than the pack stored")
	# The clamped B-spline lands on the endpoints through a sum of basis
	# weights, so compare within float error rather than bit for bit.
	assert_almost_eq(curve[0].distance_to(raw[0]), 0.0, 0.001,
		"it still starts where the river rises")
	assert_almost_eq(curve[curve.size() - 1].distance_to(raw[raw.size() - 1]), 0.0, 0.001,
		"and ends where it meets the water")
	assert_eq(v.river_curve(code, raw), curve, "and is computed once")

## The tier hierarchy is data (owner request 2026-09-12): a capital towers
## over a hamlet at the SAME zoom, and the ratio lives in the size column of
## data/settlement_art.csv — it used to be baked into each PNG's pixel
## height, where tuning it meant regenerating art.
func test_a_capital_draws_taller_than_every_smaller_tier() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	v._zoom_at(v.size / 2.0, 40.0)  # close enough that every tier draws its art
	var tallest := v.sprite_height()
	assert_gt(tallest, 0.0, "settlement art is drawn at this zoom")
	var by_tier: Dictionary = {}
	for row: Dictionary in Game.data.settlement_art:
		by_tier[String(row["tier"])] = float(row["size"])
	var order := ["capital", "city", "walled_town", "village", "hamlet"]
	for i in order.size():
		assert_true(by_tier.has(order[i]), "%s has a size" % order[i])
	assert_eq(by_tier["capital"], 1.0, "the capital sets the scale")
	for i in range(1, order.size()):
		assert_lte(float(by_tier[order[i]]), float(by_tier[order[i - 1]]),
			"%s is no bigger than %s" % [order[i], order[i - 1]])
	assert_lt(float(by_tier["hamlet"]), float(by_tier["capital"]) * 0.5,
		"and a hamlet is less than half a capital, not a hair shorter")

func test_a_settlement_sprite_is_drawn_at_its_tiers_share_of_the_tallest() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	v._zoom_at(v.size / 2.0, 40.0)
	var tallest := v.sprite_height()
	var seen := 0
	for sp in v.settlement_sprites():
		var b: Dictionary = Game.data.burgs[sp["code"]]
		var art := MapObjects.settlement_art(Game.data, b)
		var want := tallest * float(art["size"])
		assert_almost_eq((sp["rect"] as Rect2).size.y, want, 0.01,
			"%s draws at its tier's share" % String(sp["code"]))
		seen += 1
	assert_gt(seen, 0, "some settlements are on screen")

## Owner request 2026-09-12: a settlement and every terrain symbol wear the
## colour of the realm that holds their province, so they sit in the wash
## instead of on it — and because the OWNER is looked up live while the
## province is fixed geometry, a conquest recolours them with no new art.
func test_symbols_wear_their_realms_colour_and_follow_conquest() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var lost: String = MapOwnership.provinces_of(Game.data, Game.state, mine)[0]
	var strength := Game.data.bal("map_sprite_tint")
	assert_gt(strength, 0.0, "the tint is on in balance.csv")

	var before := v.realm_tint(lost, strength)
	assert_ne(before, Color.WHITE, "the symbol takes the crown's colour")
	MapOwnership.set_owner(Game.data, Game.state, lost, raider, "a raid")
	var after := v.realm_tint(lost, strength)
	assert_ne(after, before, "and the raiders' once they hold it")
	assert_eq(after, Color.WHITE.lerp(MapPalette.color_of(Game.data, raider), strength))

func test_an_unheld_point_is_left_untinted() -> void:
	var v := _view()
	await wait_frames(2)
	assert_eq(v.realm_tint("", 0.8), Color.WHITE, "no province, no tint")
	assert_eq(v.realm_tint("anything", 0.0), Color.WHITE, "tint strength 0 is off")

## The inland nudge is self-scaling (owner 2026-09-13): twelve probes on a
## ring around the point, each landward one adding its direction. In open
## country they cancel and the drawing does not move at all; on a coast they
## do not, and it slides toward the land.
func test_an_inland_town_is_not_nudged_but_a_coastal_one_is() -> void:
	var v := _view()
	await wait_frames(2)
	var far_from_sea := Vector2.ZERO
	var on_the_sea := Vector2.ZERO
	var far_code := ""
	var sea_code := ""
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if String(b.get("is_port", "0")) == "1" and sea_code == "":
			sea_code = code
			on_the_sea = at
		elif String(b.get("is_port", "0")) == "0" and far_code == "":
			far_code = code
			far_from_sea = at
	assert_ne(sea_code, "", "the pack has a port")
	assert_ne(far_code, "", "and an inland town")
	var inland := v.inland_bias(far_code, far_from_sea, 12.0)
	var coastal := v.inland_bias(sea_code, on_the_sea, 12.0)
	assert_lt(inland.length(), coastal.length(),
		"land all round cancels out; a shore does not")

## A thematic map shows one theme: the HEIGHTS view drops the political wash,
## because a height ramp cannot be read through a realm colour.
func test_the_heights_view_drops_the_political_wash() -> void:
	var v := _view()
	await wait_frames(2)
	assert_true(v.political_wash_visible(), "the wash is on by default")
	v.show_heights = true
	assert_false(v.political_wash_visible(), "and off under the height ramp")
	assert_not_null(v.heat_mesh(), "which is what is drawn instead")
	v.show_heights = false
	assert_true(v.political_wash_visible(), "and back when the view closes")

## Every chief good a manor can badge has a category colour for its ring and
## something to draw inside it: its own picture, or its category's glyph.
func test_every_manor_badge_has_a_ring_colour_and_a_picture() -> void:
	for id: int in MapEconomy.manors(Game.data):
		var good := String(MapEconomy.manors(Game.data)[id]["good"])
		var tag := MapEconomy.good_tag(Game.data, good)
		assert_true(Game.data.goods_palette.has(tag), "goods_palette.csv covers '%s'" % tag)
		assert_true(Game.data.goods_art.has(good) or Game.data.resource_icons.has("tag_" + tag),
			"'%s' has art or its category '%s' has a glyph" % [good, tag])

## A thematic view drops the realm tint from the symbols too: a blue-teal
## wood standing on an economy wash is a third colour that means nothing.
func test_thematic_views_leave_the_symbols_untinted() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	var mine := Game.data.resolve_realm("player_realm")
	var held: String = MapOwnership.provinces_of(Game.data, Game.state, mine)[0]
	assert_ne(v.realm_tint(held, 1.0), Color.WHITE, "tinted on the political map")
	for layer in ["heights", "economy"]:
		v.show_heights = layer == "heights"
		v.show_economy = layer == "economy"
		assert_eq(v.realm_tint(held, 1.0), Color.WHITE, "untinted under %s" % layer)
	v.show_heights = false
	v.show_economy = false
	assert_ne(v.realm_tint(held, 1.0), Color.WHITE, "and tinted again after")

## The decor is one mesh (owner 2026-09-13): every mark a quad over one
## atlas, rebuilt when ownership changes and otherwise kept, hidden under a
## theme.
func test_the_woods_are_one_mesh_over_one_atlas() -> void:
	var v := _view()
	await wait_frames(2)
	assert_true(v.decor_visible())
	var atlas := v.decor_atlas()
	assert_not_null(atlas.texture)
	assert_gt(atlas.uv.size(), 3, "the terrain art is on one sheet")
	var mesh := v.decor_mesh()
	assert_eq(mesh.get_surface_count(), 1, "one surface, one draw call")
	assert_eq(MarkMesh.quad_count(mesh), MapObjects.terrain_decor(Game.data).size(),
		"every mark is a quad")
	assert_true(v.decor_mesh() == mesh, "kept between frames")
	var realm := Game.data.resolve_realm("player_realm")
	var foreign := ""
	for code: String in Game.data.provinces:
		if MapOwnership.owner_of(Game.data, Game.state, code) != realm:
			foreign = code
			break
	MapOwnership.set_owner(Game.data, Game.state, foreign, realm, "test: conquest")
	assert_false(v.decor_mesh() == mesh, "conquest recolours: a new mesh")
	v.show_heights = true
	assert_false(v.decor_visible(), "hidden under a theme")

## The manors' marks are meshes by zoom tier, in the MANORS view only
## (owner 2026-09-13: not the default map): nothing at the world zoom,
## the farmsteads at the home zoom, the fields closer in.
func test_the_manor_marks_come_in_by_zoom_tier_in_the_manors_view() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom = 3.0
	assert_eq(v.manor_decor_tiers_shown(), [], "the default map carries none")
	v.show_manors = true
	var meshes := v.manor_decor_meshes()
	assert_eq(meshes.size(), 2, "two tiers in data/manor_decor.csv")
	var tiers: Array = meshes.keys()
	tiers.sort()
	for tier: float in tiers:
		assert_gt(MarkMesh.quad_count(meshes[tier]), 0, "tier %.1f has marks" % tier)
	v._zoom = float(tiers[0]) - 0.1
	assert_eq(v.manor_decor_tiers_shown(), [], "below the first tier: none")
	v._zoom = float(tiers[0])
	assert_eq(v.manor_decor_tiers_shown(), [tiers[0]])
	v._zoom = float(tiers[1]) + 0.5
	assert_eq(v.manor_decor_tiers_shown(), tiers, "close in: every tier")
	assert_true(v.manor_decor_meshes() == meshes, "kept between frames")
	# Every element wears its manor's colour there (owner 2026-09-13): the
	# marks and the town drawings alike, at map_manor_mark_alpha.
	var cell := -1
	for c: int in Game.data.manors:
		if MapManors.burg_of(Game.data, c) == "" and v.house_manor_color(c).a > 0.0:
			cell = c
			break
	assert_gt(cell, -1)
	var tint := v.manor_mark_tint(cell)
	assert_almost_eq(tint.a, Game.data.bal("map_manor_mark_alpha"), 0.001)
	var wash := v.house_manor_color(cell)
	assert_almost_eq(tint.r, wash.r, 0.001, "the manor's own colour")
	var burg: String = Game.data.burgs.keys()[0]
	var burg_cell := int(MapEconomy.burg_cells(Game.data).get(burg, -1))
	assert_gt(burg_cell, -1)
	assert_eq(v.sprite_tint(burg, String(Game.data.burgs[burg]["province_code"]), 1.0),
		v.manor_mark_tint(burg_cell), "a town drawing wears its manor's colour too")
	v.show_manors = false
	assert_ne(v.sprite_tint(burg, String(Game.data.burgs[burg]["province_code"]), 1.0),
		v.manor_mark_tint(burg_cell), "and the realm's on the default map")
	v.show_economy = true
	assert_eq(v.manor_decor_tiers_shown(), [], "none in the economy view either")

## A thematic view drops the terrain decoration: a wood is not what the view
## is about. The HEIGHTS view keeps the town drawings — a town is still a
## place — while the ECONOMY view marks its places with manor badges instead
## (economyView.png), which a town drawing would cover.
func test_thematic_views_drop_the_woods() -> void:
	var v := _view()
	await wait_frames(2)
	assert_gt(v.terrain_sprites().size(), 0, "woods on the political map")
	var towns := v.settlement_sprites().size()
	assert_gt(towns, 0)
	v.show_heights = true
	assert_eq(v.terrain_sprites().size(), 0, "no woods under the height ramp")
	assert_eq(v.settlement_sprites().size(), towns, "the towns are still there")
	v.show_heights = false
	v.show_economy = true
	assert_eq(v.terrain_sprites().size(), 0, "no woods under the manors")
	assert_eq(v.settlement_sprites().size(), 0, "the manor badges stand in for the towns")

## The dashed layers — borders, hatching, seams, lanes — are cut once per
## zoom (MapDashCache) and only transformed on a pan (bench 2026-09-13: the
## per-frame cut held the map at 6–8 fps). A pan cuts nothing; a zoom or a
## conquest cuts afresh.
func test_a_pan_cuts_no_dashes_but_a_zoom_or_conquest_does() -> void:
	Game.start_campaign(42)
	var v := _view()
	v.show_provinces = true
	await wait_frames(2)
	var cache := v.dash_cache()
	assert_gt(cache.builds, 0, "the first frame cut the borders")
	var cut := cache.builds
	v._offset += Vector2(-40.0, -25.0)
	v._clamp_offset()
	v.queue_redraw()
	await wait_frames(2)
	assert_eq(cache.builds, cut, "a pan cut nothing")
	v._zoom_at(v.size / 2.0, 1.5)
	await wait_frames(2)
	assert_gt(cache.builds, cut, "a zoom cut every line again")
	cut = cache.builds
	var mine := Game.data.resolve_realm("player_realm")
	var lost: String = MapOwnership.provinces_of(Game.data, Game.state, mine)[0]
	MapOwnership.set_owner(Game.data, Game.state, lost, Game.data.resolve_realm("raider_realm"), "raid")
	v.queue_redraw()
	await wait_frames(2)
	assert_gt(cache.builds, cut, "a conquest cut the borders again")

## In a layer that shows manors a click on bare land selects the manor
## under it (MANOR_SYSTEM.md §6); on the political map it still means the
## province's land.
func test_in_the_economy_view_a_click_on_land_selects_its_manor() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	var realm := Game.data.resolve_realm("player_realm")
	var province: String = MapOwnership.provinces_of(Game.data, Game.state, realm)[0]
	var cell: int = MapManors.manors_of_province(Game.data, province)[0]
	var centre := MapTerrain.cell_center(Game.data, Game.data.cells[cell])
	v._zoom_at(v.size / 2.0, 6.0)
	v._offset += v.size / 2.0 - v.map_to_screen(centre)
	v._clamp_offset()
	var seen: Array = []
	v.object_selected.connect(func(entry: Dictionary) -> void: seen.append(entry))
	v.show_provinces = false
	v.show_economy = true
	v._select_at(v.map_to_screen(centre))
	assert_eq(String(v._selected_obj.get("kind", "")), "manor")
	assert_eq(int(v._selected_obj.get("cell", -1)), cell)
	assert_eq(String(seen[-1]["title"]), MapManors.label_of(Game.data, cell))
	v.show_economy = false
	v._select_at(v.map_to_screen(centre))
	assert_eq(String(v._selected_obj.get("kind", "")), "land", "the political map: land")

## The MANORS view (MANOR_SYSTEM.md §6): the manor mesh is built for it,
## coloured by house — the crown's manors in the realm's colour, another
## house's in its own — a click selects the manor, and off again the mesh
## goes with it.
func test_the_manors_view_colours_manors_by_house_and_picks_them() -> void:
	Game.start_campaign(42)
	var v := _view()
	await wait_frames(2)
	assert_null(v.manor_mesh(), "no theme, no manor mesh")
	v.show_provinces = false
	v.show_manors = true
	assert_not_null(v.manor_mesh())
	var realm := Game.data.resolve_realm("player_realm")
	var crowns := -1
	var theirs := -1
	for province: String in MapOwnership.provinces_of(Game.data, Game.state, realm):
		for cell: int in MapManors.manors_of_province(Game.data, province):
			if MapManors.is_crowns(Game.data, Game.state, cell) and crowns < 0:
				crowns = cell
			elif not MapManors.is_crowns(Game.data, Game.state, cell) and theirs < 0:
				theirs = cell
	var mine := v.house_manor_color(crowns)
	var other := v.house_manor_color(theirs)
	assert_gt(mine.a, 0.0)
	assert_ne(Color(mine, 1.0), Color(other, 1.0), "two houses, two colours")
	var realm_colour := MapPalette.color_of(Game.data, realm)
	assert_lt(Color(mine, 1.0).h - realm_colour.h if Color(mine, 1.0).h > realm_colour.h else realm_colour.h - Color(mine, 1.0).h,
		0.05, "the crown wears its realm's hue")
	var centre := MapTerrain.cell_center(Game.data, Game.data.cells[theirs])
	v._zoom_at(v.size / 2.0, 6.0)
	v._offset += v.size / 2.0 - v.map_to_screen(centre)
	v._clamp_offset()
	v._select_at(v.map_to_screen(centre))
	assert_eq(String(v._selected_obj.get("kind", "")), "manor")
	assert_eq(int(v._selected_obj.get("cell", -1)), theirs)
	v.show_manors = false
	assert_null(v.manor_mesh(), "off again")
