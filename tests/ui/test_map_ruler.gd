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
## The dashes as one segment list (perf 2026-10-02: one draw call a path),
## running on across a joint: 10 px dashes over an L of 15 + 15 px.
func test_the_dashes_run_on_across_a_joint() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(15, 0), Vector2(15, 15)])
	assert_eq(MapRuler.dash_pieces(pts, 10.0), PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0),  # the first dash
		# a 10 px gap: the last 5 of the first leg and the first 5 of the second
		Vector2(15, 5), Vector2(15, 15),  # the second dash, on the second leg
	]))


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


## GameRoot: the MEASUREMENT tab is a toggle that lays the ruler over the
## map of every screen, and follows the player across a screen swap.
func test_the_measurement_tab_turns_the_ruler_on_across_screens() -> void:
	assert_true("MEASUREMENT" in BottomBar.TOGGLES)
	Game.start_campaign(42)
	Game.next_tick()
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	assert_false(r.ruler_view(), "off by default")
	r.bottom_bar().button("MEASUREMENT").pressed.emit()
	await wait_process_frames(1)
	assert_true(r.ruler_view())
	assert_true(r.bottom_bar().button("MEASUREMENT").button_pressed, "the tab stays lit")
	assert_true(r.current_screen.map3d_view().ruler_on)
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_process_frames(2)
	assert_true(r.current_screen.map3d_view().ruler_on, "the next screen's map too")
	r.bottom_bar().button("MEASUREMENT").pressed.emit()
	await wait_process_frames(1)
	assert_false(r.current_screen.map3d_view().ruler_on)
