extends GutTest
## The RTS-style world map embedded in the court screen's middle zone
## (user ruling 2026-09-03: the map IS the middle view; MAP tab returned
## to "close overlays" — that behavior is pinned by test_ui_rework).

func _view() -> WorldMapView:
	var v := WorldMapView.new()
	v.size = Vector2(320, 180)
	add_child_autofree(v)
	return v

func test_court_screen_embeds_the_world_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_not_null(screen.world_map(), "court builds a WorldMapView")
	assert_true(screen.world_map().visible, "map assets exist, so it shows")

func test_selecting_a_kingdom_opens_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	var row: Dictionary = Game.data.kingdoms["hetalia"]
	v.select_state(int(row["state_id"]))
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, String(row["label"]))

func test_water_click_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_state(int(Game.data.kingdoms["hetalia"]["state_id"]))
	v.select_state(-1)
	assert_false(v.card().visible, "water/no-state closes the card")

func test_opens_showing_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	# New behavior: map fits to screen, showing the entire world
	var zoom_min := v._zoom_min()
	assert_almost_eq(v._zoom, zoom_min, 0.001,
		"starts at fit-to-screen zoom showing the entire map")
	# Map should be centered in the viewport
	var tex := v._map_texture.get_size()
	var expected_x := (v.size.x - tex.x * v._zoom) / 2.0
	var expected_y := (v.size.y - tex.y * v._zoom) / 2.0
	assert_almost_eq(v._offset.x, expected_x, 1.0, "map centered x")
	assert_almost_eq(v._offset.y, expected_y, 1.0, "map centered y")
