extends GutTest
## Map3DGeometry: the 3D map's pure maths — pack px <-> world metres, the
## camera rig's pose, zoom, tilt and pan. Hand-computed expectations.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929]}


func test_pack_to_world_scales_and_offsets() -> void:
	# (100, 200) px * 50 m = (5000, 10000) m, plus the origin.
	var xz := Map3DGeometry.pack_to_world(WORLD, Vector2(100, 200))
	assert_almost_eq(xz.x, -59000.0, 0.001)
	assert_almost_eq(xz.y, -13220.0, 0.001)


func test_world_to_pack_inverts_pack_to_world() -> void:
	var px := Vector2(1234.5, 678.25)
	var back := Map3DGeometry.world_to_pack(WORLD, Map3DGeometry.pack_to_world(WORLD, px))
	assert_almost_eq(back.x, px.x, 0.001)
	assert_almost_eq(back.y, px.y, 0.001)


## The WAR ROOM reads the map's drawn pieces through this (owner 2026-10-02):
## (-59000, -13220) m is (100, 200) px, keyed as given.
func test_world_to_pack_all_keeps_the_keys() -> void:
	var out := Map3DGeometry.world_to_pack_all(WORLD, {"a": Vector2(-59000.0, -13220.0), "b": Vector2(-64000.0, -23220.0)})
	assert_almost_eq((out["a"] as Vector2).distance_to(Vector2(100, 200)), 0.0, 0.001)
	assert_almost_eq((out["b"] as Vector2).distance_to(Vector2.ZERO), 0.0, 0.001)
	assert_eq(Map3DGeometry.world_to_pack_all(WORLD, {}), {})


func test_bounds_span_the_whole_pack() -> void:
	var r := Map3DGeometry.world_bounds(WORLD)
	assert_almost_eq(r.position.x, -64000.0, 0.001)
	assert_almost_eq(r.position.y, -23220.0, 0.001)
	assert_almost_eq(r.size.x, 128000.0, 0.001)   # 2560 * 50
	assert_almost_eq(r.size.y, 46450.0, 0.001)    # 929 * 50


func test_clamp_target_keeps_the_focus_on_the_map() -> void:
	var r := Rect2(0, 0, 100, 50)
	assert_eq(Map3DGeometry.clamp_target(Vector2(-10, 20), r), Vector2(0, 20))
	assert_eq(Map3DGeometry.clamp_target(Vector2(130, 70), r), Vector2(100, 50))
	assert_eq(Map3DGeometry.clamp_target(Vector2(40, 10), r), Vector2(40, 10))


func test_zoom_multiplies_the_distance_and_clamps() -> void:
	# One step in: 10000 / 1.25 = 8000; two steps out: 10000 * 1.5625.
	assert_almost_eq(Map3DGeometry.zoomed(10000.0, -1, 1.25, 1000.0, 50000.0), 8000.0, 0.01)
	assert_almost_eq(Map3DGeometry.zoomed(10000.0, 2, 1.25, 1000.0, 50000.0), 15625.0, 0.01)
	assert_eq(Map3DGeometry.zoomed(1100.0, -3, 1.25, 1000.0, 50000.0), 1000.0)
	assert_eq(Map3DGeometry.zoomed(48000.0, 3, 1.25, 1000.0, 50000.0), 50000.0)


func test_pitch_runs_from_near_to_far_on_a_log_scale() -> void:
	# min 1000, max 100000: 10000 is halfway in log10 (3 -> 5), so the pitch
	# is halfway between -30 and -70.
	assert_almost_eq(Map3DGeometry.pitch_for(1000.0, 1000.0, 100000.0, -30.0, -70.0), -30.0, 0.001)
	assert_almost_eq(Map3DGeometry.pitch_for(100000.0, 1000.0, 100000.0, -30.0, -70.0), -70.0, 0.001)
	assert_almost_eq(Map3DGeometry.pitch_for(10000.0, 1000.0, 100000.0, -30.0, -70.0), -50.0, 0.001)


func test_pose_looks_at_the_target_from_behind_and_above() -> void:
	# yaw 0, pitch -45, distance 1000: the camera sits south (+Z) and above,
	# 1000 * cos45 back and 1000 * sin45 up, looking at the target.
	var t := Map3DGeometry.pose(Vector3(10, 0, 20), 1000.0, 0.0, -45.0)
	var h := 1000.0 * sqrt(0.5)
	assert_almost_eq(t.origin.x, 10.0, 0.01)
	assert_almost_eq(t.origin.y, h, 0.01)
	assert_almost_eq(t.origin.z, 20.0 + h, 0.01)
	var forward := -t.basis.z
	var to_target := (Vector3(10, 0, 20) - t.origin).normalized()
	assert_almost_eq(forward.dot(to_target), 1.0, 0.0001)


# A ridge 600 m high everywhere more than 500 m south (+Z) of the target, flat
# ground (0 m) elsewhere: the camera of yaw 0 sits south, so at the oblique
# -22 deg and 1000 m it stands 1000 sin22 = 375 m up — inside the ridge.
func _ridge(xz: Vector2) -> float:
	return 600.0 if xz.y > 500.0 else 0.0


func _flat(_xz: Vector2) -> float:
	return 0.0


# The clearance rule, restated from the doc comment rather than called: every
# point of the sight line at share s from the target to the camera stands at
# least clear_m * s over the ground.
func _clears(pitch: float, height: Callable, clear_m: float) -> bool:
	var cam := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 0.0, pitch).origin
	for i in range(1, 65):
		var s := i / 64.0
		var q := cam * s
		if q.y < float(height.call(Vector2(q.x, q.z))) + clear_m * s:
			return false
	return true


func test_clear_pitch_keeps_the_pitch_over_open_ground() -> void:
	assert_eq(Map3DGeometry.clear_pitch(Vector3.ZERO, 1000.0, 0.0, -22.0, _flat, 60.0, 1.0, 64), -22.0)


func test_clear_pitch_lifts_the_camera_out_of_a_ridge_behind_the_target() -> void:
	# at -22 the camera is 375 m up, under the 600 m ridge: the pitch steepens
	# to the first 1-degree step whose whole sight line clears the ridge by
	# the ramped 60 m, and the step before it does not.
	assert_false(_clears(-22.0, _ridge, 60.0), "the oblique pose is inside the ridge")
	var p := Map3DGeometry.clear_pitch(Vector3.ZERO, 1000.0, 0.0, -22.0, _ridge, 60.0, 1.0, 64)
	assert_lt(p, -22.0)
	assert_true(_clears(p, _ridge, 60.0), "the camera and its sight line stand over the ridge")
	assert_false(_clears(p + 1.0, _ridge, 60.0), "no steeper than it has to be")
	var cam := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 0.0, p).origin
	assert_gt(cam.y, 660.0)


func test_clear_pitch_stops_at_its_limit_when_nothing_clears() -> void:
	var wall := func(_xz: Vector2) -> float: return 5000.0
	assert_eq(Map3DGeometry.clear_pitch(Vector3.ZERO, 1000.0, 0.0, -22.0, wall, 60.0, 5.0, 16, -85.0), -85.0)


func test_pose_turns_with_the_yaw() -> void:
	# yaw 90 degrees: the camera swings from the south to the east (+X).
	var t := Map3DGeometry.pose(Vector3.ZERO, 1000.0, 90.0, -45.0)
	var h := 1000.0 * sqrt(0.5)
	assert_almost_eq(t.origin.x, h, 0.01)
	assert_almost_eq(t.origin.z, 0.0, 0.01)


func test_metres_per_pixel_follow_the_view_frustum() -> void:
	# fov 90: the view is 2 * d * tan(45) = 2000 m tall at d = 1000 over 500 px.
	assert_almost_eq(Map3DGeometry.metres_per_pixel(1000.0, 90.0, 500.0), 4.0, 0.0001)


func test_pan_moves_the_ground_with_the_mouse() -> void:
	# Dragging right drags the ground right: the target moves left (-X);
	# dragging down moves the target north (-Z). 4 m per px at yaw 0.
	var d := Map3DGeometry.pan_delta(Vector2(10, 5), 4.0, 0.0)
	assert_almost_eq(d.x, -40.0, 0.001)
	assert_almost_eq(d.y, -20.0, 0.001)


func test_pan_turns_with_the_yaw() -> void:
	# At yaw 90 the screen's right points north (-Z): a drag right moves the
	# target south (+Z).
	var d := Map3DGeometry.pan_delta(Vector2(10, 0), 1.0, 90.0)
	assert_almost_eq(d.x, 0.0, 0.001)
	assert_almost_eq(d.y, 10.0, 0.001)


func test_a_ray_hits_flat_ground_where_the_plane_says() -> void:
	# From (0, 100, 0) down a 45-degree ray toward -Z: flat ground at y = 20
	# is met 80 m ahead.
	var dir := Vector3(0, -1, -1).normalized()
	var hit: Variant = Map3DGeometry.ground_hit(Vector3(0, 100, 0), dir,
		func(_xz: Vector2) -> float: return 20.0)
	assert_not_null(hit)
	assert_almost_eq((hit as Vector3).z, -80.0, 0.01)
	assert_almost_eq((hit as Vector3).y, 20.0, 0.01)


func test_a_ray_settles_on_sloping_ground() -> void:
	# Ground rising northward: h = -0.25 z. A ray down at 45 degrees from
	# (0, 100, 0) meets it where 100 + z = -0.25 z, z = -80: y = 20.
	var dir := Vector3(0, -1, -1).normalized()
	var hit: Variant = Map3DGeometry.ground_hit(Vector3(0, 100, 0), dir,
		func(xz: Vector2) -> float: return -0.25 * xz.y)
	assert_not_null(hit)
	assert_almost_eq((hit as Vector3).z, -80.0, 0.5)
	assert_almost_eq((hit as Vector3).y, 20.0, 0.5)


func test_a_ray_looking_up_misses() -> void:
	assert_null(Map3DGeometry.ground_hit(Vector3(0, 100, 0), Vector3(0, 1, -1).normalized(),
		func(_xz: Vector2) -> float: return 0.0))


func test_resample_keeps_the_ends_and_caps_the_step() -> void:
	# A 10 m segment at a 3 m step: ceil(10 / 3) = 4 pieces, 5 points.
	var out := Map3DGeometry.resample(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 3.0)
	assert_eq(out.size(), 5)
	assert_eq(out[0], Vector2(0, 0))
	assert_eq(out[4], Vector2(10, 0))
	assert_almost_eq(out[1].x, 2.5, 0.0001)


func test_resample_leaves_short_segments_alone() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	assert_eq(Map3DGeometry.resample(pts, 5.0), pts)


func test_zoomed_by_multiplies_and_clamps() -> void:
	assert_almost_eq(Map3DGeometry.zoomed_by(10000.0, 0.5, 1000.0, 50000.0), 5000.0, 0.01)
	assert_eq(Map3DGeometry.zoomed_by(1500.0, 0.5, 1000.0, 50000.0), 1000.0)
	assert_eq(Map3DGeometry.zoomed_by(40000.0, 2.0, 1000.0, 50000.0), 50000.0)


func test_zoom_about_keeps_the_anchor_fixed() -> void:
	# Halving the distance halves every offset from the anchor: the target at
	# 100 m west of the anchor ends 50 m west of it.
	var t := Map3DGeometry.zoom_about(Vector2(0, 0), Vector2(100, 0), 1000.0, 500.0)
	assert_almost_eq(t.x, 50.0, 0.001)
	assert_almost_eq(t.y, 0.0, 0.001)
	var a := Vector2(-30, 70)
	assert_eq(Map3DGeometry.zoom_about(a, a, 1000.0, 300.0), a, "an anchor on the target stays")
	var out := Map3DGeometry.zoom_about(Vector2(0, 0), Vector2(100, 0), 1000.0, 2000.0)
	assert_almost_eq(out.x, -100.0, 0.001, "zooming out pushes the target away from the anchor")


func test_ease_yaw_runs_the_short_way_home() -> void:
	assert_eq(Map3DGeometry.ease_yaw(90.0, 0.0), 90.0)
	assert_eq(Map3DGeometry.ease_yaw(90.0, 1.0), 0.0)
	assert_almost_eq(Map3DGeometry.ease_yaw(90.0, 0.5), 45.0, 0.001, "smoothstep's midpoint")
	# 350 degrees is 10 west of north: it comes home through 355, not 180.
	assert_almost_eq(Map3DGeometry.ease_yaw(350.0, 0.5), -5.0, 0.001)


## The zoom-out limit reads off the SCALE BAR (owner 2026-09-20: "设置zoom out
## 标尺最多150km"): the bar lands on the 1-2-5 ladder, so a cap of 150 prints
## as 100 and the distance is the one just under the next rung.
func test_distance_for_scale_keeps_the_bar_under_its_cap() -> void:
	# beria's measure: 1 km per pack px at 50 m per px, a 220 px bar, a 600 px view.
	var units_per_m := 1.0 / 50.0
	var d := Map3DGeometry.distance_for_scale(150.0, units_per_m, 220.0, 45.0, 600.0)
	var reading := func(dist: float) -> float:
		return MapGeometry.nice_step(220.0 * Map3DGeometry.metres_per_pixel(dist, 45.0, 600.0) * units_per_m)
	assert_eq(reading.call(d), 100.0, "the bar reads the rung under the cap")
	assert_gt(reading.call(d * 1.02), 150.0, "a little farther and it jumps over the cap")
	# A cap ON a rung keeps that rung: 200 prints 200, 201 does not become 500.
	assert_eq(reading.call(Map3DGeometry.distance_for_scale(200.0, units_per_m, 220.0, 45.0, 600.0)), 200.0)
	assert_eq(reading.call(Map3DGeometry.distance_for_scale(201.0, units_per_m, 220.0, 45.0, 600.0)), 200.0)

## By hand: 25 km over a 220 px bar at 0.02 km a metre is 5.6818 m a screen px;
## x 600 / (2 tan 22.5 = 0.828427) = 4115.1 m.
func test_distance_for_span_puts_the_run_on_the_bar() -> void:
	assert_almost_eq(Map3DGeometry.distance_for_span(25.0, 0.02, 220.0, 45.0, 600.0), 4115.1, 0.1)


func test_distance_for_scale_is_unbounded_when_there_is_nothing_to_measure() -> void:
	assert_eq(Map3DGeometry.distance_for_scale(0.0, 0.02, 220.0, 45.0, 600.0), INF)
	assert_eq(Map3DGeometry.distance_for_scale(150.0, 0.0, 220.0, 45.0, 600.0), INF, "no measure")
	assert_eq(Map3DGeometry.distance_for_scale(150.0, 0.02, 0.0, 45.0, 600.0), INF, "no bar")
