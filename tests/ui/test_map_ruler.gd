extends GutTest
## MapRuler: the ruler's static look and arithmetic, which the MARCH aim's
## ruler and the routes' dashes draw with (the MEASUREMENT tab's free ruler
## went 2026-10-02, owner).


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
