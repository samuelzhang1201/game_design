extends GutTest
## The officer's view over the table (spec 2026-10-01-war-room-design §1).

func _cam() -> WarCamera:
	var c := WarCamera.new()
	c.distance = 1.6
	c.pitch_deg = 52.0
	c.min_distance = 0.12
	c.max_distance = 2.4
	c.yaw_max = 30.0
	c.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	return c


func test_the_camera_looks_down_at_its_target_from_the_south() -> void:
	var c := _cam()
	var t := c.transform()
	assert_almost_eq(t.origin.y, 1.6 * sin(deg_to_rad(52.0)), 0.0001)
	assert_almost_eq(t.origin.z, 1.6 * cos(deg_to_rad(52.0)), 0.0001)
	assert_almost_eq((-t.basis.z).normalized().dot((c.target - t.origin).normalized()), 1.0, 0.0001)


func test_zoom_about_a_ground_point_keeps_it_under_the_pointer_direction() -> void:
	var c := _cam()
	var ground := Vector3(0.4, 0.0, 0.2)
	c.zoom_about(ground, 0.5)
	assert_almost_eq(c.distance, 0.8, 0.0001)
	assert_almost_eq(c.target.x, 0.2, 0.0001, "the target walks half way to the point")
	c.zoom_about(ground, 0.01)
	assert_almost_eq(c.distance, 0.12, 0.0001, "held at the closest lean")


func test_pan_stays_on_the_table_and_turn_is_held() -> void:
	var c := _cam()
	c.pan(Vector2(5.0, 5.0))
	assert_almost_eq(c.target.x, 0.7, 0.0001)
	assert_almost_eq(c.target.z, 0.5, 0.0001)
	c.turn(80.0)
	assert_almost_eq(c.yaw_deg, 30.0, 0.0001)
