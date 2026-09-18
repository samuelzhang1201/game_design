extends GutTest
## MapRuler (owner 2026-09-18): the MEASUREMENT tab's ruler. A left click
## drops the anchor, the pointer stretches the ruler, a second click fixes
## it, a right click puts it away. Points are in the map's own measuring
## space (the 2D map's native px, the 3D map's world XZ metres).


func test_a_first_click_drops_the_anchor_and_starts_stretching() -> void:
	var r := MapRuler.new()
	assert_eq(r.phase, MapRuler.Phase.IDLE)
	r.click(Vector2(10, 20))
	assert_eq(r.phase, MapRuler.Phase.STRETCHING)
	assert_eq(r.start, Vector2(10, 20))
	assert_eq(r.end, Vector2(10, 20), "zero length until the pointer moves")


func test_the_pointer_stretches_the_ruler_only_while_stretching() -> void:
	var r := MapRuler.new()
	assert_false(r.move(Vector2(5, 5)), "an idle ruler ignores the pointer")
	r.click(Vector2.ZERO)
	assert_true(r.move(Vector2(3, 4)))
	assert_eq(r.end, Vector2(3, 4))
	assert_almost_eq(r.length(), 5.0, 1e-6)


func test_a_second_click_fixes_the_ruler_and_the_pointer_no_longer_moves_it() -> void:
	var r := MapRuler.new()
	r.click(Vector2.ZERO)
	r.move(Vector2(1, 1))
	r.click(Vector2(6, 8))
	assert_eq(r.phase, MapRuler.Phase.FIXED)
	assert_eq(r.end, Vector2(6, 8), "the click, not the last move, is the end")
	assert_false(r.move(Vector2(100, 100)))
	assert_almost_eq(r.length(), 10.0, 1e-6)


func test_a_click_on_a_fixed_ruler_starts_a_new_one() -> void:
	var r := MapRuler.new()
	r.click(Vector2.ZERO)
	r.click(Vector2(6, 8))
	r.click(Vector2(50, 50))
	assert_eq(r.phase, MapRuler.Phase.STRETCHING)
	assert_eq(r.start, Vector2(50, 50))


func test_cancel_puts_the_ruler_away_and_says_whether_there_was_one() -> void:
	var r := MapRuler.new()
	assert_false(r.cancel(), "nothing to put away")
	r.click(Vector2.ZERO)
	assert_true(r.cancel())
	assert_eq(r.phase, MapRuler.Phase.IDLE)
	assert_false(r.active())


## 2D: the pack's distance_scale and distance_unit (map_info.csv).
func test_a_reading_in_the_packs_unit() -> void:
	assert_eq(MapRuler.reading(123.4, "km"), "123 km", "whole units from 10 up")
	assert_eq(MapRuler.reading(2.46, "km"), "2.5 km", "one decimal under 10")
	assert_eq(MapRuler.reading(3.0, "km"), "3 km", "no trailing .0")


## Ticks at a 1-2-5 step no closer than min_px on screen, strictly inside the ruler.
func test_ticks_fall_on_a_nice_step_inside_the_ruler() -> void:
	# 0.3 units per screen px x 40 px = 12 -> nice step 10.
	assert_almost_eq(MapRuler.tick_step(0.3, 40.0), 10.0, 1e-6)
	var t := MapRuler.ticks(35.0, 10.0)
	assert_eq(t.size(), 3)
	assert_almost_eq(t[0], 10.0, 1e-6)
	assert_almost_eq(t[2], 30.0, 1e-6)
	assert_eq(MapRuler.ticks(30.0, 10.0).size(), 2, "no tick on the end anchor")
	assert_eq(MapRuler.ticks(30.0, 0.0).size(), 0, "no step, no ticks")


func _map() -> WorldMapView:
	var v := WorldMapView.create()
	v.size = Vector2(640, 360)
	add_child_autofree(v)
	return v


func _press(v: Control, button: MouseButton, pressed: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	v._gui_input(e)


func _click(v: Control, at: Vector2) -> void:
	_press(v, MOUSE_BUTTON_LEFT, true, at)
	_press(v, MOUSE_BUTTON_LEFT, false, at)


## The 2D map: clicks drop and fix the ruler in NATIVE px (so the reading
## survives a zoom), a drag still pans, a right click puts it away.
func test_the_2d_map_routes_clicks_to_the_ruler_while_it_is_on() -> void:
	Game.start_campaign(42)
	var v := _map()
	await wait_frames(2)
	v.show_ruler = true
	_click(v, Vector2(100, 100))
	assert_eq(v.ruler().phase, MapRuler.Phase.STRETCHING)
	assert_eq(v.ruler().start, v.screen_to_map(Vector2(100, 100)))
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(300, 100)
	v._gui_input(hover)
	assert_eq(v.ruler().end, v.screen_to_map(Vector2(300, 100)))
	_click(v, Vector2(300, 200))
	assert_eq(v.ruler().phase, MapRuler.Phase.FIXED)
	assert_almost_eq(v.ruler().length(),
		v.screen_to_map(Vector2(100, 100)).distance_to(v.screen_to_map(Vector2(300, 200))), 1e-3)
	_press(v, MOUSE_BUTTON_RIGHT, true, Vector2(5, 5))
	_press(v, MOUSE_BUTTON_RIGHT, false, Vector2(5, 5))
	assert_false(v.ruler().active(), "a right click puts it away")


func test_turning_the_2d_ruler_off_puts_it_away() -> void:
	Game.start_campaign(42)
	var v := _map()
	await wait_frames(2)
	v.show_ruler = true
	_click(v, Vector2(100, 100))
	v.show_ruler = false
	assert_false(v.ruler().active())
	_click(v, Vector2(100, 100))
	assert_false(v.ruler().active(), "with the tab off a click selects, not measures")


## GameRoot: the MEASUREMENT tab is a toggle that lays the ruler over the
## map of every screen, and follows the player across a screen swap.
func test_the_measurement_tab_turns_the_ruler_on_across_screens() -> void:
	assert_true("MEASUREMENT" in BottomBar.TOGGLES)
	Game.start_campaign(42)
	Game.next_tick()
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	assert_false(r.ruler_view(), "off by default")
	r.bottom_bar().button("MEASUREMENT").pressed.emit()
	await wait_frames(1)
	assert_true(r.ruler_view())
	assert_true(r.bottom_bar().button("MEASUREMENT").button_pressed, "the tab stays lit")
	assert_true(r.current_screen.world_map().show_ruler)
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_frames(2)
	assert_true(r.current_screen.world_map().show_ruler, "the next screen's map too")
	r.bottom_bar().button("MEASUREMENT").pressed.emit()
	await wait_frames(1)
	assert_false(r.current_screen.world_map().show_ruler)
