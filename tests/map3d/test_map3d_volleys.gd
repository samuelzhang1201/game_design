extends GutTest
## The arrow rain's live arrows (spec 2026-11-28-archer-arrow-rain-design.md):
## one arrow per release, flight, stick, fade, cap and the paused clock.

const SuiteData := preload("res://tests/suite_data.gd")

var tune := {"near_m": 300.0, "from_h": 0.75, "speed_m": 50.0, "min_s": 1.0, "max_s": 3.0, "apex": 0.3,
	"scatter_h": 1.0, "sink_h": 0.2, "stick_s": 4.0, "fade_s": 1.0, "max": 3}
var flat := func(_xz: Vector2) -> float: return 0.0


func _shot(share: float, key := "arc:0") -> Dictionary:
	return {"key": key, "share": share, "release": 0.68, "from": Vector3(0, 3, 0), "h": 4.0, "targets": [Vector2(100, 0)]}


func test_one_arrow_per_crossing() -> void:
	var v := Map3DVolleys.new()
	v.run([_shot(0.5)], 0.1, true, tune, flat)
	assert_eq(v.live().size(), 0, "no release before the share")
	v.run([_shot(0.7)], 0.1, true, tune, flat)
	assert_eq(v.live().size(), 1)
	v.run([_shot(0.75)], 0.1, true, tune, flat)
	assert_eq(v.live().size(), 1, "past it: no second arrow")
	var a: Dictionary = v.live()[0]
	assert_almost_eq(float(a["flight_s"]), 2.0, 0.2, "about 100 m at 50 m/s")
	assert_true(Vector2(a["to"].x, a["to"].z).distance_to(Vector2(100, 0)) <= 4.0 + 1e-4, "within scatter_h heights")


func test_first_sight_never_releases() -> void:
	var v := Map3DVolleys.new()
	v.run([_shot(0.7)], 0.1, true, tune, flat)
	assert_eq(v.live().size(), 0, "a figure first seen past its share has not crossed it")


func test_paused_clock_stands() -> void:
	var v := Map3DVolleys.new()
	v.run([_shot(0.5)], 0.1, true, tune, flat)
	v.run([_shot(0.7)], 0.1, true, tune, flat)
	var t := float(v.live()[0]["t"])
	v.run([_shot(0.5)], 1.0, false, tune, flat)
	assert_eq(float(v.live()[0]["t"]), t)
	assert_eq(v.live().size(), 1)


func test_no_target_no_arrow() -> void:
	var v := Map3DVolleys.new()
	var s := _shot(0.5)
	s["targets"] = []
	v.run([s], 0.1, true, tune, flat)
	s["share"] = 0.7
	v.run([s], 0.1, true, tune, flat)
	assert_eq(v.live().size(), 0)


func test_cap() -> void:
	var v := Map3DVolleys.new()
	var keys := ["a:0", "a:1", "a:2", "a:3", "a:4"]
	v.run(keys.map(func(k: String) -> Dictionary: return _shot(0.5, k)), 0.01, true, tune, flat)
	v.run(keys.map(func(k: String) -> Dictionary: return _shot(0.7, k)), 0.01, true, tune, flat)
	assert_eq(v.live().size(), 3, "at most `max`")


func test_sticks_then_fades_then_goes() -> void:
	var v := Map3DVolleys.new()
	v.run([_shot(0.5)], 0.0, true, tune, flat)
	v.run([_shot(0.7)], 0.0, true, tune, flat)
	var a: Dictionary = v.live()[0]
	v.run([], float(a["flight_s"]) + 1.0, true, tune, flat)
	assert_eq(v.live().size(), 1, "a figure gone: its arrow flies on and lands")
	assert_almost_eq(float(a["stuck_t"]), 1.0, 1e-4)
	var pose := Map3DVolleys.pose(a, tune)
	assert_lt(pose.origin.y, 0.0, "its tip in the ground")
	assert_eq(Map3DVolleys.alpha(a, tune), 1.0)
	v.run([], 3.5, true, tune, flat)
	assert_almost_eq(Map3DVolleys.alpha(a, tune), 0.5, 1e-4, "half faded")
	v.run([], 1.0, true, tune, flat)
	assert_eq(v.live().size(), 0)


func test_pose_points_along_the_flight_and_is_figure_sized() -> void:
	var a := {"from": Vector3.ZERO, "to": Vector3(100, 0, 0), "t": 1.0, "flight_s": 2.0, "apex": 10.0, "h": 4.0, "stuck_t": -1.0}
	var p := Map3DVolleys.pose(a, tune)
	assert_almost_eq(p.origin, Vector3(50, 10, 0), Vector3.ONE * 1e-4)
	assert_almost_eq(-p.basis.z.normalized(), Vector3(1, 0, 0), Vector3.ONE * 1e-4, "the tip leads (-Z)")
	assert_almost_eq(p.basis.z.length(), 4.0, 1e-4)


func test_write_draws_one_instance_each() -> void:
	var v := Map3DVolleys.new()
	v.run([_shot(0.5)], 0.0, true, tune, flat)
	v.run([_shot(0.7)], 0.0, true, tune, flat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	v.write(mm, tune)
	assert_eq(mm.visible_instance_count, 1)
	assert_eq(mm.instance_count, 3)


func test_balance_keys_exist() -> void:
	var t := Map3DVolleys.tune_of(SuiteData.repo())
	for key: String in tune:
		assert_gt(float(t[key]), 0.0, key)
