extends GutTest
## The arrow rain's pure math (spec 2026-11-28-archer-arrow-rain-design.md):
## the release crossing, the landing point and the arc.


func test_release_crossing() -> void:
	assert_true(Map3DVolley.released(0.6, 0.7, 0.68))
	assert_false(Map3DVolley.released(0.69, 0.7, 0.68), "already past")
	assert_false(Map3DVolley.released(0.95, 0.05, 0.68), "a wrap that never reached it")
	assert_true(Map3DVolley.released(0.95, 0.05, 0.02), "a wrap past it")
	assert_true(Map3DVolley.released(0.95, 0.05, 0.97), "a wrap, the share before the end")
	assert_false(Map3DVolley.released(0.5, 0.5, 0.5), "a clip standing still")


func test_flight_time_from_distance() -> void:
	var tune := {"speed_m": 50.0, "min_s": 1.0, "max_s": 3.0}
	assert_almost_eq(Map3DVolley.flight_s(100.0, tune), 2.0, 1e-6)
	assert_almost_eq(Map3DVolley.flight_s(10.0, tune), 1.0, 1e-6)
	assert_almost_eq(Map3DVolley.flight_s(1000.0, tune), 3.0, 1e-6)


func test_arc() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(100, 20, 0)
	assert_eq(Map3DVolley.at(a, b, 0.0, 10.0), a)
	assert_eq(Map3DVolley.at(a, b, 1.0, 10.0), b)
	assert_almost_eq(Map3DVolley.at(a, b, 0.5, 10.0), Vector3(50, 20, 0), Vector3.ONE * 1e-4, "midpoint + 4·apex·¼")
	var flat := Map3DVolley.heading(Vector3.ZERO, Vector3(100, 0, 0), 0.5, 10.0)
	assert_almost_eq(flat.y, 0.0, 1e-6, "level at the apex")
	assert_almost_eq(flat.length(), 1.0, 1e-6)
	assert_gt(Map3DVolley.heading(Vector3.ZERO, Vector3(100, 0, 0), 0.0, 10.0).y, 0.0, "climbing at release")
	assert_lt(Map3DVolley.heading(Vector3.ZERO, Vector3(100, 0, 0), 1.0, 10.0).y, 0.0, "falling at landing")


func test_landing_is_hashed_and_near_a_target() -> void:
	var targets: Array = [Vector2(0, 0), Vector2(100, 0), Vector2(0, 100)]
	var p := Map3DVolley.landing("arc1:3", 0, targets, 5.0)
	assert_eq(p, Map3DVolley.landing("arc1:3", 0, targets, 5.0), "a replay lands the same")
	assert_true(targets.any(func(t: Vector2) -> bool: return t.distance_to(p) <= 5.0 + 1e-4))
	var moved := false
	for n: int in range(1, 6):
		moved = moved or Map3DVolley.landing("arc1:3", n, targets, 5.0) != p
	assert_true(moved, "the next arrow lands elsewhere")
