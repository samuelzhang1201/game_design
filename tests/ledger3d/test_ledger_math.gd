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

func test_a_crowded_layer_stays_on_its_disc() -> void:
	# the court's 21, repelling one another, once spread to twice the disc
	var nodes := []
	for i in 21:
		nodes.append({"id": "character:%02d" % i, "layer": "people"})
	var pos := LedgerLayout.positions(data, {"focus_id": "", "nodes": nodes, "links": []})
	var limit := data.bal("ledger_disc_radius_m") - data.bal("ledger_layout_margin_m")
	for id: String in pos:
		var p: Vector3 = pos[id]
		assert_lte(Vector2(p.x, p.z).length(), limit + 1e-4, "%s stands on the disc" % id)

func _disc(r: float, y: float) -> Array:
	var pts := []
	for i in 32:
		var a := TAU * float(i) / 32.0
		pts.append(Vector3(cos(a) * r, y, sin(a) * r))
	return pts

func test_framing_puts_every_point_inside_the_safe_rect_and_fills_it() -> void:
	var pts := _disc(11.5, 0.0) + _disc(11.5, 6.0)
	var safe := Rect2(0.05, 0.12, 0.9, 0.84)
	var f := LedgerOrbit.frame(pts, 0.0, -24.0, 40.0, 16.0 / 9.0, safe)
	var lo := Vector2(safe.position.x * 2.0 - 1.0, 1.0 - safe.end.y * 2.0)
	var hi := Vector2(safe.end.x * 2.0 - 1.0, 1.0 - safe.position.y * 2.0)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p: Vector3 in pts:
		var s := LedgerOrbit.ndc_of(p, f["target"], f["distance"], 0.0, -24.0, 40.0, 16.0 / 9.0)
		mn = mn.min(s)
		mx = mx.max(s)
	assert_true(mn.x >= lo.x - 1e-4 and mn.y >= lo.y - 1e-4 and mx.x <= hi.x + 1e-4 and mx.y <= hi.y + 1e-4,
		"inside the safe rect: %s..%s in %s..%s" % [mn, mx, lo, hi])
	# tight: the content touches the safe rect along one axis, and is centred in it
	var touch := maxf((mx.x - mn.x) / (hi.x - lo.x), (mx.y - mn.y) / (hi.y - lo.y))
	assert_gt(touch, 0.98, "as large as it fits")
	assert_almost_eq((mn.y + mx.y) * 0.5, (lo.y + hi.y) * 0.5, 0.02, "centred in the safe rect")
	assert_almost_eq((mn.x + mx.x) * 0.5, (lo.x + hi.x) * 0.5, 0.02, "centred in the safe rect")

func test_framing_is_a_pure_function_of_the_points() -> void:
	var pts := _disc(5.0, 6.0) + [Vector3(3, 6.5, 1)]
	var safe := Rect2(0, 0, 1, 1)
	var a := LedgerOrbit.frame(pts, 0.0, -24.0, 40.0, 1.6, safe)
	assert_eq(a, LedgerOrbit.frame(pts, 0.0, -24.0, 40.0, 1.6, safe), "the same points frame the same")
	var moved := pts.map(func(p: Vector3) -> Vector3: return p + Vector3(4, -2, 7))
	var b := LedgerOrbit.frame(moved, 0.0, -24.0, 40.0, 1.6, safe)
	assert_almost_eq(float(b["distance"]), float(a["distance"]), 1e-3, "moving the content keeps the distance")
	assert_almost_eq(((b["target"] as Vector3) - (a["target"] as Vector3)).distance_to(Vector3(4, -2, 7)), 0.0, 1e-3,
		"and moves the target with it")
	var small := LedgerOrbit.frame(_disc(2.5, 6.0), 0.0, -24.0, 40.0, 1.6, safe)
	var big := LedgerOrbit.frame(_disc(10.0, 6.0), 0.0, -24.0, 40.0, 1.6, safe)
	assert_almost_eq(float(big["distance"]) / float(small["distance"]), 4.0, 1e-2, "a disc four times as wide, four times as far")
	assert_eq(LedgerOrbit.frame([], 0.0, -24.0, 40.0, 1.6, safe), {}, "nothing to frame")

func test_only_layers_holding_a_sphere_have_a_disc() -> void:
	var snap := {"nodes": [{"id": "character:a", "layer": "people"}, {"id": "report:1", "layer": "know"}], "links": []}
	assert_eq(LedgerLayout.layers_present(snap), ["people", "know"] as Array[String])
	assert_eq(LedgerLayout.layers_present({"nodes": [], "links": []}), [] as Array[String])
	var pos := LedgerLayout.positions(data, {"focus_id": "", "links": [],
		"nodes": [{"id": "type:a", "layer": "people", "x": 2.0, "z": -3.0}]})
	var pts := LedgerLayout.frame_points(data, {"nodes": [{"id": "type:a", "layer": "people", "x": 2.0, "z": -3.0}]}, pos)
	var ys := {}
	for p: Vector3 in pts:
		ys[snappedf(p.y, 0.001)] = true
	assert_false(ys.has(snappedf(LedgerLayout.disc_y(data, "things"), 0.001)), "no rim of an empty layer's disc")
	assert_true(ys.has(snappedf(LedgerLayout.disc_y(data, "people"), 0.001)), "the people disc's rim is framed")

func test_a_disc_reaches_just_past_its_own_spheres() -> void:
	var snap := {"focus_id": "regiment:r", "links": [], "nodes": [
		{"id": "regiment:r", "layer": "things", "instance": true},
		{"id": "province:p", "layer": "things", "instance": true, "x": 4.0, "z": 0.0},
		{"id": "type:far", "layer": "know", "x": 30.0, "z": 0.0}]}
	var pos := {"regiment:r": Vector3.ZERO, "province:p": Vector3(4, 0, 0), "type:far": Vector3(30, 12, 0)}
	var r_inst := data.bal("ledger_sphere_radius_instance")
	assert_almost_eq(LedgerLayout.disc_radius(data, snap, pos, "things"), 4.0 + r_inst + data.bal("ledger_disc_pad_m"), 1e-5,
		"the province's far edge plus the pad")
	assert_eq(LedgerLayout.disc_radius(data, snap, pos, "know"), data.bal("ledger_disc_radius_m"), "never over the full disc")
	assert_eq(LedgerLayout.disc_radius(data, snap, pos, "people"), data.bal("ledger_disc_min_m"), "never under the least")
