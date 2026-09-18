extends GutTest
## Map3DCloudField: the 3D clouds' drift, spawn, retire and pause fade —
## pure, so no frames are needed.

const VIEW := Rect2(0, 0, 100000, 50000)
const P := {"max": 24, "size_min": 3000.0, "size_max": 8000.0, "speed_m_s": 100.0,
	"wind_deg": 0.0, "fade_s": 1.0, "interval_s": 2.0}


func test_play_fills_the_sky_at_once() -> void:
	var f := Map3DCloudField.new(11)
	f.step(0.1, true, 1, VIEW, P)
	assert_eq(f.clouds.size(), 24)
	for c: Dictionary in f.clouds:
		assert_true(VIEW.has_point(c["pos"]), "the first sky is over the view")


func test_clouds_drift_downwind_times_the_clock() -> void:
	var f := Map3DCloudField.new(11)
	f.step(0.1, true, 1, VIEW, P)
	var x0 := (f.clouds[0]["pos"] as Vector2).x
	f.step(1.0, true, 4, VIEW, P)
	assert_almost_eq((f.clouds[0]["pos"] as Vector2).x - x0, 400.0, 0.01, "east at 100 m/s x4")


func test_a_pause_fades_them_out_and_clears_them() -> void:
	var f := Map3DCloudField.new(11)
	f.step(0.1, true, 1, VIEW, P)
	f.step(1.0, true, 1, VIEW, P)
	assert_eq(f.fade, 1.0, "faded in")
	f.step(0.5, false, 0, VIEW, P)
	assert_almost_eq(f.fade, 0.5, 0.2)
	f.step(1.0, false, 0, VIEW, P)
	assert_eq(f.fade, 0.0)
	assert_eq(f.clouds.size(), 0)


func test_clouds_far_past_the_view_are_retired_and_replaced_upwind() -> void:
	var f := Map3DCloudField.new(11)
	f.step(0.1, true, 1, VIEW, P)
	f.clouds[0]["pos"] = Vector2(900000, 0)
	f.step(0.1, true, 1, VIEW, P)
	for c: Dictionary in f.clouds:
		assert_lt((c["pos"] as Vector2).x, 300000.0)
	assert_eq(f.clouds.size(), 24, "a new one came in upwind at once (the spawn timer was due)")


func test_the_same_seed_is_the_same_sky() -> void:
	var a := Map3DCloudField.new(5)
	var b := Map3DCloudField.new(5)
	a.step(0.1, true, 1, VIEW, P)
	b.step(0.1, true, 1, VIEW, P)
	assert_eq(a.clouds[3]["pos"], b.clouds[3]["pos"])
