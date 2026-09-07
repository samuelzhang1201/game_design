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

## Asserts the observable property, not the formula: a cover-fit floor
## (maxf) satisfies "_zoom == _zoom_min()" while cropping a quarter of the
## map off the sides, so that spelling of this test proved nothing.
func test_opens_showing_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	var drawn := Rect2(v._offset, v._map_texture.get_size() * v._zoom)
	assert_true(drawn.position.x >= -1.0, "nothing cropped off the left")
	assert_true(drawn.position.y >= -1.0, "nothing cropped off the top")
	assert_true(drawn.end.x <= v.size.x + 1.0, "nothing cropped off the right")
	assert_true(drawn.end.y <= v.size.y + 1.0, "nothing cropped off the bottom")
	assert_almost_eq(drawn.get_center().x, v.size.x / 2.0, 1.0, "centered x")
	assert_almost_eq(drawn.get_center().y, v.size.y / 2.0, 1.0, "centered y")

func test_wheel_zoom_runs_from_whole_map_to_close_up() -> void:
	var v := _view()
	await wait_frames(2)
	var whole := v._zoom
	v._zoom_at(v.size / 2.0, 4.0)
	assert_gt(v._zoom, whole, "wheel up zooms in past the whole-map view")
	v._zoom_at(v.size / 2.0, 0.0001)
	assert_almost_eq(v._zoom, whole, 0.0001,
		"zoom-out floors at the whole map, never smaller")

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
