extends GutTest
## The officer's view over the table (spec 2026-10-02-war-room-v2 §1.1): it
## turns all the way round, its pitch follows the distance, it stays inside
## the room, and the compass eases it back to the sheet's foot.

func _cam() -> WarCamera:
	var c := WarCamera.new()
	c.distance = 1.6
	c.min_distance = 0.12
	c.mid_distance = 1.6
	c.max_distance = 3.0
	c.pitch_near_deg = 30.0
	c.pitch_mid_deg = 52.0
	c.pitch_far_deg = 28.0
	c.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	return c


func test_pitch_rises_to_the_officers_look_then_flattens_to_show_the_room() -> void:
	var c := _cam()
	c.distance = 0.12
	assert_almost_eq(c.pitch_deg(), 30.0, 0.0001, "leaning in: oblique over the pieces")
	c.distance = 1.6
	assert_almost_eq(c.pitch_deg(), 52.0, 0.0001, "the opening officer's look")
	c.distance = 3.0
	assert_almost_eq(c.pitch_deg(), 28.0, 0.0001, "stepped back: the room comes into view")
	c.distance = 0.4
	# t = ln(0.4/0.12) / ln(1.6/0.12) = 1.2040 / 2.5903 = 0.46480
	assert_almost_eq(c.pitch_deg(), 40.226, 0.01)
	c.distance = 2.2
	# t = ln(2.2/1.6) / ln(3.0/1.6) = 0.31845 / 0.62861 = 0.50660
	assert_almost_eq(c.pitch_deg(), 39.842, 0.01)


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
	c.distance = 3.0   # horizontal reach 3.0 * cos 28 = 2.65 > 1
	var d := c.clear_distance()
	assert_lt(d, 3.0, "shortened")
	var o := c.transform().origin
	assert_almost_eq(o.z, 1.0, 0.001, "stands at the wall")
	c.room = Rect2()
	assert_almost_eq(c.clear_distance(), 3.0, 0.0001, "no room, no walls")


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


func test_near_a_wall_the_distance_is_the_one_drawn_and_no_notch_is_dead() -> void:
	var c := _cam()
	c.room = Rect2(-1.0, -1.0, 2.0, 2.0)
	c.distance = 1.0
	for i in 6:
		c.zoom_about(c.target, 1.12)   # step back into the wall
	assert_almost_eq(c.distance, c.clear_distance(), 0.0001, "the rig never holds a distance it cannot stand at")
	assert_almost_eq(c.transform().origin.distance_to(c.target), c.distance, 0.001)
	var held := c.distance
	c.zoom_about(c.target, 1.0 / 1.12)
	assert_lt(c.distance, held, "the first notch back in moves the camera")
