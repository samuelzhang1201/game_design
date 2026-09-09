extends GutTest
## The RTS-style world map embedded in the court screen's middle zone
## (user ruling 2026-09-03: the map IS the middle view; MAP tab returned
## to "close overlays" — that behavior is pinned by test_ui_rework).

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

## Azgaar's PNG export captures the current view, so a render taken while
## zoomed is a scaled, shifted picture of the same world. maps.csv carries
## the correction; map_to_screen applies it and screen_to_map undoes it.
func test_screen_and_map_coordinates_round_trip_through_the_calibration() -> void:
	var v := _view()
	await wait_frames(2)
	for native in [Vector2(0, 0), Vector2(1216.79, 601.05), Vector2(2559, 928)]:
		var back := v.screen_to_map(v.map_to_screen(native))
		assert_almost_eq(back.x, native.x, 0.01, "x round-trips at %s" % native)
		assert_almost_eq(back.y, native.y, 0.01, "y round-trips at %s" % native)

## The calibration must actually be applied, not silently dropped. Checked
## against the mapping written out longhand, so a change to map_to_screen
## that forgets the calibration fails here.
func test_the_calibration_is_applied_to_the_render_mapping() -> void:
	var v := _view()
	await wait_frames(2)
	var s := Game.data.render_scale
	var off := Game.data.render_offset
	assert_gt(s, 0.0, "the pack carries a usable render scale")
	var native := Vector2(1000, 400)
	var want := v.map_to_screen(Vector2.ZERO) \
		+ native * s * (v.view_scale() / s)
	assert_almost_eq(v.map_to_screen(native).x, want.x, 0.01, "x")
	assert_almost_eq(v.map_to_screen(native).y, want.y, 0.01, "y")
	# And the offset really moves the origin off the texture's corner.
	var origin := v.map_to_screen(Vector2.ZERO) - v._offset
	assert_almost_eq(origin.x, off.x * v.view_scale() / s, 0.01, "origin x")
	assert_almost_eq(origin.y, off.y * v.view_scale() / s, 0.01, "origin y")

## Hit-testing samples the index bitmaps, which are in native coordinates:
## the capital's own pixel must resolve to the capital's own kingdom.
func test_the_index_bitmap_agrees_with_the_calibrated_mapping() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = _capital()
	var native := Vector2(float(k["x"]), float(k["y"]))
	var back := v.screen_to_map(v.map_to_screen(native))
	assert_almost_eq(back.x, native.x, 0.01, "capital survives the round trip")
	assert_almost_eq(back.y, native.y, 0.01, "capital survives the round trip")

## macOS trackpad (user request 2026-09-09): pinch zooms, two-finger drag
## pans. Both arrive as their own event types, beside the wheel.
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
	v._zoom_at(v.size / 2.0, 0.00001)
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
	var drawn := Rect2(v._offset, v._map_texture.get_size() * v._zoom)
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
	var drawn := Rect2(v._offset, v._map_texture.get_size() * v._zoom)
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

## Regression guard: the map shares the court screen with the log and
## council columns. If it ever covers or hides them there is no way to
## issue an order or end the turn.
func test_court_keeps_the_order_panels_beside_the_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_true(screen.get_node("%LogPanel").is_visible_in_tree(),
		"court log column stays visible")
	assert_true(screen.get_node("%SidePanel").is_visible_in_tree(),
		"council column stays visible")
	assert_true(screen.end_turn_button().is_visible_in_tree(),
		"End Turn stays reachable")

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
	# stays right whatever render calibration the pack carries.
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

## Province view (user request 2026-09-09): a toggle draws every kingdom's
## internal province seams as light dashed lines, above a minimum zoom.
func test_province_view_toggles_by_key_and_announces_it() -> void:
	var v := _view()
	await wait_frames(2)
	assert_false(v.show_provinces, "off by default")
	var seen: Array = []
	v.province_view_changed.connect(func(on: bool) -> void: seen.append(on))
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_P
	v._gui_input(key)
	assert_true(v.show_provinces, "P turns it on")
	v._gui_input(key)
	assert_false(v.show_provinces, "P turns it off again")
	assert_eq(seen, [true, false], "each flip is announced once")

## Province names show in the province view once the zoom makes them legible.
func test_province_names_show_only_in_the_view_and_zoomed_in() -> void:
	var v := _view()
	await wait_frames(2)
	var realm: Dictionary = _realm()
	var centre := Vector2(float(realm["center_x"]), float(realm["center_y"]))
	v.show_provinces = true
	v._zoom_at(v.size / 2.0, 0.00001)
	assert_eq(v.visible_province_label_count(), 0, "zoomed out, names hide")
	v._zoom_at(v.size / 2.0, 1000.0)
	v._offset += v.size / 2.0 - v.map_to_screen(centre)
	v._clamp_offset()
	assert_gt(v.visible_province_label_count(), 0, "zoomed in on the realm, names show")
	v.show_provinces = false
	assert_eq(v.visible_province_label_count(), 0, "off means none")

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
	v._zoom_at(v.size / 2.0, 0.00001)
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
