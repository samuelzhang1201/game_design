extends GutTest
## Map3DHud: the 3D map's scale bar and compass. Hand-computed values.

func test_the_bar_takes_the_largest_round_distance_that_fits() -> void:
	# 30 m per px, 220 px at most: 6600 m fits, the 1-2-5 step under it is 5 km.
	var bar := Map3DHud.scale_bar_for(30.0, 220.0)
	assert_eq(bar["distance_m"], 5000.0)
	assert_eq(bar["text"], "5 km")
	assert_almost_eq(float(bar["width_px"]), 5000.0 / 30.0, 0.001)


func test_short_distances_read_in_metres() -> void:
	# 1.5 m per px * 220 = 330 m -> 200 m.
	var bar := Map3DHud.scale_bar_for(1.5, 220.0)
	assert_eq(bar["text"], "200 m")


func test_the_needle_turns_with_the_view() -> void:
	# yaw 90: the camera's right is north (Map3DGeometry.pose), so north
	# lies a quarter turn clockwise from screen-up.
	var basis := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 90.0, -45.0).basis
	assert_gt(basis.x.dot(Vector3(0, 0, -1)), 0.99)
	assert_almost_eq(Map3DHud.needle_angle(90.0), PI * 0.5, 0.0001)
	assert_eq(Map3DHud.needle_angle(0.0), 0.0)
