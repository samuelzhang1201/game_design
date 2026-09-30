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
	var at := Map3DCourierRide.walk_along(Vector2.ZERO, queue, 5.0)
	assert_eq(at, Vector2(5, 0), "half the first stretch")
	assert_eq(queue.size(), 2)
	at = Map3DCourierRide.walk_along(at, queue, 8.0)
	assert_eq(at, Vector2(10, 3), "round the corner, the step carried over")
	assert_eq(queue.size(), 1, "the corner is passed")
	at = Map3DCourierRide.walk_along(at, queue, 100.0)
	assert_eq(at, Vector2(10, 10), "never past the last point")
	assert_true(queue.is_empty())


func test_the_length_of_what_is_left() -> void:
	assert_almost_eq(Map3DCourierRide.length_along(Vector2.ZERO, [Vector2(3, 4), Vector2(3, 10)]), 11.0, 0.001)
	assert_eq(Map3DCourierRide.length_along(Vector2.ZERO, []), 0.0)


func _player(names: Array) -> AnimationPlayer:
	var p := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for n: String in names:
		var a := Animation.new()
		a.length = 1.0
		lib.add_animation(n, a)
	p.add_animation_library("", lib)
	autofree(p)
	return p


func test_a_moving_rider_gallops_and_a_paused_one_idles() -> void:
	assert_eq(Map3DLayerCouriers.action_for(true, true), "GALLOP")
	assert_eq(Map3DLayerCouriers.action_for(true, false), "IDLE", "a paused clock holds him still")
	assert_eq(Map3DLayerCouriers.action_for(false, true), "IDLE", "not yet set out")


func test_a_stand_in_without_the_couriers_clips_falls_back() -> void:
	var cav := _player(["cavalry|GARRISON", "cavalry|MARCH", "cavalry|ATTACK"])
	assert_eq(Map3DLayerCouriers.clip_or_fallback(cav, "GALLOP"), "cavalry|MARCH")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(cav, "IDLE"), "cavalry|GARRISON")
	var own := _player(["courier|GALLOP", "courier|IDLE"])
	assert_eq(Map3DLayerCouriers.clip_or_fallback(own, "GALLOP"), "courier|GALLOP")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(_player([]), "GALLOP"), "", "nothing to play: nothing played")
	assert_eq(Map3DLayerCouriers.clip_or_fallback(null, "IDLE"), "", "no AnimationPlayer at all")


func test_the_courier_art_rows_carry_a_stride() -> void:
	var repo := DataRepository.load_all("res://data")
	for kind: String in repo.courier_art:
		assert_true((repo.courier_art[kind] as Dictionary).has("stride_m"), kind)
	assert_false(repo.balance.has("map3d_courier_anim_rate"), "the old fixed rate is gone")
	assert_gt(repo.bal("map3d_courier_anim_max"), repo.bal("map3d_courier_anim_min"))


## Owner 2026-09-30 (信使送到信息后要立即淡化消失): he fades the moment his
## delivering ride is done, over map3d_courier_fade_s of real time.
func test_a_courier_fades_out_the_moment_he_delivers() -> void:
	var delivering := {"ends": true, "share": 0.4}
	assert_false(Map3DCourierRide.delivered(delivering, 0.39), "still riding up to the column")
	assert_true(Map3DCourierRide.delivered(delivering, 0.4), "there: delivered")
	assert_false(Map3DCourierRide.delivered({"ends": false, "share": 1.0}, 1.0), "a whole day's ride that does not deliver")
	assert_eq(Map3DCourierRide.alpha(-1.0, 0.6), 1.0, "not delivered: whole")
	assert_almost_eq(Map3DCourierRide.alpha(0.3, 0.6), 0.5, 0.0001, "half way through the fade")
	assert_eq(Map3DCourierRide.alpha(0.6, 0.6), 0.0, "gone")
	assert_eq(Map3DCourierRide.alpha(0.0, 0.0), 0.0, "no fade time: gone at once")
