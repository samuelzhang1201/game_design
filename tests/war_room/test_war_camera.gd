extends GutTest
## The officer's view over the table (spec 2026-10-02-war-room-v2 §1.1): it
## turns all the way round, its pitch follows the distance, it stays inside
## the room, and the compass eases it back to the sheet's foot.

func _cam() -> WarCamera:
	var c := WarCamera.new()
	c.distance = 1.6
	c.min_distance = 0.12
	c.max_distance = 2.4
	c.pitch_near_deg = 30.0
	c.pitch_far_deg = 55.0
	c.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	return c


func test_pitch_follows_the_distance_on_a_log_scale() -> void:
	var c := _cam()
	c.distance = 0.12
	assert_almost_eq(c.pitch_deg(), 30.0, 0.0001, "closest: oblique")
	c.distance = 2.4
	assert_almost_eq(c.pitch_deg(), 55.0, 0.0001, "farthest: overhead")
	c.distance = 1.6
	# t = ln(1.6/0.12) / ln(2.4/0.12) = 2.5903 / 2.9957 = 0.86467
	assert_almost_eq(c.pitch_deg(), 51.617, 0.01)


func test_the_camera_looks_at_its_target_from_the_south_at_yaw_zero() -> void:
	var c := _cam()
	var t := c.transform()
	var p := deg_to_rad(c.pitch_deg())
	assert_almost_eq(t.origin.y, 1.6 * sin(p), 0.0001)
	assert_almost_eq(t.origin.z, 1.6 * cos(p), 0.0001)
	assert_almost_eq(t.origin.x, 0.0, 0.0001)
	assert_almost_eq((-t.basis.z).normalized().dot((c.target - t.origin).normalized()), 1.0, 0.0001)


func test_turn_wraps_through_a_full_circle() -> void:
	var c := _cam()
	c.turn(200.0)
	assert_almost_eq(c.yaw_deg, -160.0, 0.0001)
	c.turn(-40.0)
	assert_almost_eq(c.yaw_deg, 160.0, 0.0001)
	var t := c.transform()
	assert_lt(t.origin.z, 0.0, "at 160 deg the camera stands north of the table")


func test_pan_view_follows_the_pointer_at_every_yaw() -> void:
	var c := _cam()
	c.pan_view(Vector2(0.1, 0.0))
	assert_almost_eq(c.target.x, 0.1, 0.0001, "yaw 0: screen right is +x")
	c.target = Vector3.ZERO
	c.yaw_deg = 90.0
	c.pan_view(Vector2(0.1, 0.0))
	assert_almost_eq(c.target.z, -0.1, 0.0001, "yaw 90: screen right is -z")
	assert_almost_eq(c.target.x, 0.0, 0.0001)
	c.target = Vector3.ZERO
	c.yaw_deg = 180.0
	c.pan_view(Vector2(0.1, 0.2))
	assert_almost_eq(c.target.x, -0.1, 0.0001, "yaw 180: screen right is -x")
	assert_almost_eq(c.target.z, -0.2, 0.0001, "yaw 180: screen down is -z")


func test_pan_stays_on_the_table() -> void:
	var c := _cam()
	c.pan(Vector2(5.0, 5.0))
	assert_almost_eq(c.target.x, 0.7, 0.0001)
	assert_almost_eq(c.target.z, 0.5, 0.0001)


func test_zoom_about_a_ground_point_keeps_it_under_the_pointer_direction() -> void:
	var c := _cam()
	var ground := Vector3(0.4, 0.0, 0.2)
	c.zoom_about(ground, 0.5)
	assert_almost_eq(c.distance, 0.8, 0.0001)
	assert_almost_eq(c.target.x, 0.2, 0.0001, "the target walks half way to the point")
	c.zoom_about(ground, 0.01)
	assert_almost_eq(c.distance, 0.12, 0.0001, "held at the closest lean")


func test_the_camera_is_kept_inside_the_room() -> void:
	var c := _cam()
	c.room = Rect2(-1.0, -1.0, 2.0, 2.0)
	c.distance = 2.4   # horizontal reach 2.4 * cos 55 = 1.377 > 1
	var d := c.clear_distance()
	assert_lt(d, 2.4, "shortened")
	var o := c.transform().origin
	assert_almost_eq(o.z, 1.0, 0.001, "stands at the wall")
	c.room = Rect2()
	assert_almost_eq(c.clear_distance(), 2.4, 0.0001, "no room, no walls")


func test_the_compass_eases_the_yaw_back_to_zero() -> void:
	var c := _cam()
	c.yaw_deg = 120.0
	c.start_north()
	assert_true(c.easing())
	assert_true(c.step(0.2, 0.4))
	assert_almost_eq(c.yaw_deg, 60.0, 0.0001, "half way: smoothstep(0.5) = 0.5")
	assert_true(c.step(0.2, 0.4))
	assert_almost_eq(c.yaw_deg, 0.0, 0.0001)
	assert_false(c.easing())
	assert_false(c.step(0.2, 0.4), "nothing to ease")


func test_a_turn_cancels_the_ease() -> void:
	var c := _cam()
	c.yaw_deg = 90.0
	c.start_north()
	c.turn(10.0)
	assert_false(c.easing())
