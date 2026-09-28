extends GutTest
## The drawn rider follows his ROAD (found through the real game, 2026-09-28:
## he cut straight across the fields to where the engine had put him, and his
## dashed road began ahead of him with nothing between) — today's, as the day
## runs (CourierSystem.ride_ahead). The helpers are pure.


func test_the_points_he_passed_are_the_waypoints_dropped_then_where_he_is() -> void:
	var old_path: Array = [[10, 0, "road"], [10, 10, "road"], [20, 10, "trail"], [30, 10, "trail"]]
	var now := Vector2i(25, 10)
	var passed := CourierSystem.passed_points(old_path, 1, now)
	assert_eq(passed, [Vector2i(10, 0), Vector2i(10, 10), Vector2i(20, 10), Vector2i(25, 10)])


func test_a_day_within_one_stretch_passes_no_waypoint() -> void:
	var passed := CourierSystem.passed_points([[10, 0, "road"]], 1, Vector2i(4, 0))
	assert_eq(passed, [Vector2i(4, 0)])


func test_he_walks_along_the_corners_not_across_them() -> void:
	var queue: Array = [Vector2(10, 0), Vector2(10, 10)]
	var at := Map3DLayerCouriers.walk_along(Vector2.ZERO, queue, 5.0)
	assert_eq(at, Vector2(5, 0), "half the first stretch")
	assert_eq(queue.size(), 2)
	at = Map3DLayerCouriers.walk_along(at, queue, 8.0)
	assert_eq(at, Vector2(10, 3), "round the corner, the step carried over")
	assert_eq(queue.size(), 1, "the corner is passed")
	at = Map3DLayerCouriers.walk_along(at, queue, 100.0)
	assert_eq(at, Vector2(10, 10), "never past the last point")
	assert_true(queue.is_empty())


func test_the_length_of_what_is_left() -> void:
	assert_almost_eq(Map3DLayerCouriers.length_along(Vector2.ZERO, [Vector2(3, 4), Vector2(3, 10)]), 11.0, 0.001)
	assert_eq(Map3DLayerCouriers.length_along(Vector2.ZERO, []), 0.0)
