extends GutTest
## The easel's panel (spec 2026-10-02-war-room-v2 §1.3): a ray's hit as a UV,
## the pose square in front of it, the flight there and back.

var panel := Transform3D(Basis.IDENTITY, Vector3(-2.0, 1.0, 0.0))   # facing +Z
var size := Vector2(1.2, 0.8)


func test_a_ray_through_the_centre_hits_uv_half() -> void:
	var uv := WarBoard.uv_of(panel, size, Vector3(-2.0, 1.0, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(uv.x, 0.5, 0.0001)
	assert_almost_eq(uv.y, 0.5, 0.0001)


func test_the_top_left_corner_is_uv_zero_and_v_runs_down() -> void:
	var uv := WarBoard.uv_of(panel, size, Vector3(-2.6, 1.4, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(uv.x, 0.0, 0.0001)
	assert_almost_eq(uv.y, 0.0, 0.0001)
	var low := WarBoard.uv_of(panel, size, Vector3(-2.0, 0.8, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(low.y, 0.75, 0.0001, "0.2 m below the centre of a 0.8 m panel")


func test_a_miss_and_a_ray_from_behind() -> void:
	assert_eq(WarBoard.uv_of(panel, size, Vector3(0.0, 1.0, 2.0), Vector3(0, 0, -1)), Vector2(-1, -1), "beside it")
	assert_eq(WarBoard.uv_of(panel, size, Vector3(-2.0, 1.0, 2.0), Vector3(0, 0, 1)), Vector2(-1, -1), "looking away")
	assert_eq(WarBoard.uv_of(panel, size, Vector3(-2.0, 1.0, -2.0), Vector3(0, 0, 1)), Vector2(-1, -1), "from behind the panel")


func test_the_pose_stands_square_in_front() -> void:
	var t := WarBoard.pose(panel, 1.1, Vector2.ZERO)
	assert_almost_eq(t.origin.distance_to(Vector3(-2.0, 1.0, 1.1)), 0.0, 0.0001)
	assert_almost_eq((-t.basis.z).dot(Vector3(0, 0, -1)), 1.0, 0.0001, "looking straight at it")
	var shifted := WarBoard.pose(panel, 1.1, Vector2(0.2, 0.1))
	assert_almost_eq(shifted.origin.x, -1.8, 0.0001)
	assert_almost_eq(shifted.origin.y, 1.1, 0.0001)


func test_the_flight_eases_from_one_pose_to_the_other() -> void:
	var a := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var b := WarBoard.pose(panel, 1.1, Vector2.ZERO)
	assert_eq(WarBoard.fly(a, b, 0.0).origin, a.origin)
	assert_almost_eq(WarBoard.fly(a, b, 1.0).origin.distance_to(b.origin), 0.0, 0.0001)
	var mid := WarBoard.fly(a, b, 0.5).origin
	assert_almost_eq(mid.distance_to(a.origin.lerp(b.origin, 0.5)), 0.0, 0.0001, "smoothstep(0.5) = 0.5")


func test_the_offset_is_held_on_the_panel() -> void:
	assert_eq(WarBoard.clamp_offset(Vector2(5.0, -5.0), size), Vector2(0.6, -0.4))
