# tests/ledger3d/test_ledger_math.gd
extends GutTest
## The LEDGER view's pure maths (spec 2026-09-30 §7.3), and the rule that
## nothing under scripts/ledger3d reads the Game autoload.

var data: DataRepository

func before_all() -> void:
	data = DataRepository.load_all("res://data")

func test_a_ray_meets_a_sphere_at_its_near_side() -> void:
	assert_almost_eq(LedgerPick.ray_sphere(Vector3(0, 0, 10), Vector3(0, 0, -1), Vector3.ZERO, 1.0), 9.0, 1e-5)
	assert_eq(LedgerPick.ray_sphere(Vector3(0, 5, 10), Vector3(0, 0, -1), Vector3.ZERO, 1.0), -1.0)
	assert_eq(LedgerPick.ray_sphere(Vector3(0, 0, 10), Vector3(0, 0, 1), Vector3.ZERO, 1.0), -1.0, "behind")

func test_a_ray_passes_a_segment_at_its_closest() -> void:
	var hit := LedgerPick.ray_segment(Vector3(0, 0, 10), Vector3(0, 0, -1), Vector3(-5, 0.5, 0), Vector3(5, 0.5, 0))
	assert_almost_eq(hit.x, 0.5, 1e-5)
	assert_almost_eq(hit.y, 10.0, 1e-5)

func test_a_zero_length_thread_is_a_point() -> void:
	var hit := LedgerPick.ray_segment(Vector3(0, 0, 10), Vector3(0, 0, -1), Vector3(0, 2, 0), Vector3(0, 2, 0))
	assert_almost_eq(hit.x, 2.0, 1e-5)

func test_a_sphere_beats_the_thread_behind_it() -> void:
	var spheres := [{"id": "a", "pos": Vector3.ZERO, "radius": 1.0}]
	var threads := [{"id": "t", "a": Vector3(-5, 0, -2), "b": Vector3(5, 0, -2), "radius": 0.3}]
	assert_eq(LedgerPick.pick(Vector3(0, 0, 10), Vector3(0, 0, -1), spheres, threads), {"kind": "sphere", "id": "a"})
	assert_eq(LedgerPick.pick(Vector3(3, 0, 10), Vector3(0, 0, -1), spheres, threads), {"kind": "thread", "id": "t"})
	assert_eq(LedgerPick.pick(Vector3(3, 9, 10), Vector3(0, 0, -1), spheres, threads), {})

func test_screen_to_viewport_uses_the_window_scale() -> void:
	assert_eq(LedgerPick.screen_to_viewport(Vector2(100, 50), 2.0), Vector2(200, 100))

func test_the_orbit_looks_at_its_target() -> void:
	var o := LedgerOrbit.new()
	o.distance = 10.0
	o.pitch = 0.0
	o.yaw = 0.0
	var p := o.pose()
	assert_almost_eq(p.origin.distance_to(Vector3(0, 0, 10)), 0.0, 1e-4)
	assert_almost_eq((-p.basis.z).distance_to(Vector3(0, 0, -1)), 0.0, 1e-4)
	o.pitch = -30.0
	assert_gt(o.pose().origin.y, 0.0, "a negative pitch looks down from above")

func test_turning_clamps_the_pitch_and_zoom_clamps_the_distance() -> void:
	var o := LedgerOrbit.new()
	o.turn(0.0, -10000.0, 1.0)
	assert_eq(o.pitch, -5.0)
	o.turn(0.0, 10000.0, 1.0)
	assert_eq(o.pitch, -85.0)
	o.min_distance = 8.0
	o.max_distance = 90.0
	o.zoom(0.0001)
	assert_eq(o.distance, 8.0)
	o.zoom(10000.0)
	assert_eq(o.distance, 90.0)

func test_panning_moves_the_target_across_the_screen() -> void:
	var o := LedgerOrbit.new()
	o.yaw = 0.0
	o.pitch = 0.0
	o.pan(Vector2(10, 0), 0.5)
	assert_almost_eq(o.target.x, -5.0, 1e-4)

func test_type_spheres_stand_at_their_hand_set_places() -> void:
	var snap := {"focus_id": "", "links": [], "nodes": [
		{"id": "type:a", "layer": "people", "x": 2.0, "z": -3.0}]}
	var pos := LedgerLayout.positions(data, snap)
	assert_eq(pos["type:a"], Vector3(2.0, data.bal("ledger_layer_gap_m"), -3.0))

func test_an_ego_layout_is_deterministic_and_keeps_its_layers() -> void:
	var nodes := [{"id": "regiment:r", "layer": "things"}]
	var links := []
	for i in 8:
		nodes.append({"id": "report:%d" % i, "layer": "know"})
		links.append({"from": "report:%d" % i, "to": "regiment:r"})
	var snap := {"focus_id": "regiment:r", "nodes": nodes, "links": links}
	var a := LedgerLayout.positions(data, snap)
	assert_eq(a, LedgerLayout.positions(data, snap))
	assert_eq(a["regiment:r"], Vector3.ZERO)
	for i in 8:
		assert_eq((a["report:%d" % i] as Vector3).y, LedgerLayout.layer_y(data, "know"))
		assert_lt((a["report:%d" % i] as Vector3).x, 0.0, "upstream of the focus stands left of it")

func test_no_script_under_the_ledger_view_reads_game() -> void:
	var dir := DirAccess.open("res://scripts/ledger3d")
	var n := 0
	for f in dir.get_files():
		if f.ends_with(".gd"):
			n += 1
			assert_false(FileAccess.get_file_as_string("res://scripts/ledger3d/" + f).contains("Game."), f)
	assert_gt(n, 2)
