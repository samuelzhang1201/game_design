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

func test_opens_zoomed_on_the_players_kingdom() -> void:
	var v := _view()
	await wait_frames(2)
	assert_almost_eq(v._zoom * v._render_scale, 1.0, 0.001,
		"one view px per native map unit: only a window of the map shows")
	var home: Dictionary = Game.data.kingdoms["hetalia"]
	var center := Vector2(float(home["center_x"]), float(home["center_y"]))
	var on_screen := center * v._render_scale * v._zoom + v._offset
	assert_almost_eq(on_screen.x, v.size.x / 2.0, 1.0, "home centered x")
	assert_almost_eq(on_screen.y, v.size.y / 2.0, 1.0, "home centered y")
