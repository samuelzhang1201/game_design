extends GutTest
## Map3DHud: the 3D map's scale bar and compass. Hand-computed values.

func test_the_bar_takes_the_largest_round_distance_that_fits() -> void:
	# 1.5 km per px, 220 px at most: 330 km fits, the 1-2-5 step under it is 200 km.
	var bar := Map3DHud.scale_bar_for(1.5, 220.0, "km")
	assert_eq(bar["distance"], 200.0)
	assert_eq(bar["text"], "200 km")
	assert_almost_eq(float(bar["width_px"]), 200.0 / 1.5, 0.001)


func test_the_bar_reads_in_the_packs_own_unit() -> void:
	# 0.03 units per px * 220 = 6.6 -> 5, in whatever unit the pack names.
	assert_eq(Map3DHud.scale_bar_for(0.03, 220.0, "mi")["text"], "5 mi")
	assert_eq(Map3DHud.scale_bar_for(0.0, 220.0, "km"), {}, "nothing sensible fits")


func test_the_needle_turns_with_the_view() -> void:
	# yaw 90: the camera's right is north (Map3DGeometry.pose), so north
	# lies a quarter turn clockwise from screen-up.
	var basis := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 90.0, -45.0).basis
	assert_gt(basis.x.dot(Vector3(0, 0, -1)), 0.99)
	assert_almost_eq(Map3DHud.needle_angle(90.0), PI * 0.5, 0.0001)
	assert_eq(Map3DHud.needle_angle(0.0), 0.0)
