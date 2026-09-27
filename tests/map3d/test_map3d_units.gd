extends GutTest
## MILITARY's 3D pieces (owner 2026-09-22): how big one is drawn, which way
## it faces, and the box a click hits. Map3DUnits is pure, so all of it is
## checked without a camera or a world.

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")


func test_a_piece_keeps_a_CONSTANT_height_in_screen_px() -> void:
	# The whole rule: a piece is a miniature on a table map, not a person. Two
	# camera distances an order of magnitude apart must give the same number
	# of SCREEN px, which means ten times the world height.
	var fov := repo.bal("map3d_fov_deg")
	var near := Map3DUnits.height_m(repo, 1000.0, fov, 1080.0)
	var far := Map3DUnits.height_m(repo, 10000.0, fov, 1080.0)
	assert_almost_eq(far / near, 10.0, 0.001,
		"ten times as far away is ten times as tall in the world")
	# ...and that number of px is the one the table asks for.
	var mpp := Map3DGeometry.metres_per_pixel(1000.0, fov, 1080.0)
	assert_almost_eq(near / mpp, repo.bal("map3d_unit_px"), 0.001)


func test_the_clamps_stop_the_rule_running_away() -> void:
	var fov := repo.bal("map3d_fov_deg")
	assert_eq(Map3DUnits.height_m(repo, 1.0, fov, 1080.0), repo.bal("map3d_unit_min_h_m"),
		"nose to the ground, it still stands as tall as the floor allows")
	assert_eq(Map3DUnits.height_m(repo, 1.0e9, fov, 1080.0), repo.bal("map3d_unit_max_h_m"),
		"and never grows past the ceiling")


func test_the_scale_is_that_height_over_the_models_own() -> void:
	var fov := repo.bal("map3d_fov_deg")
	var want := Map3DUnits.height_m(repo, 5000.0, fov, 1080.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 2.0), want / 2.0, 0.0001)
	assert_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 0.0), 1.0,
		"a model with no height is left alone rather than scaled by infinity")


func test_an_arm_can_stand_bigger_than_the_rest() -> void:
	# army_art's size multiplies the drawn height (owner 2026-09-27: the
	# cavalry alone, 单独调大, 更显眼一点); 1 leaves a piece as it was.
	var fov := repo.bal("map3d_fov_deg")
	var one := Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 2.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 2.0, 1.5), one * 1.5, 0.0001)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 2.0, 1.0), one, 0.0001)


func test_a_marching_piece_faces_its_heading() -> void:
	# The models are authored facing +Y in Blender, which is -Z here, so a
	# piece marching toward -Z stands at yaw 0.
	assert_almost_eq(Map3DUnits.yaw_for(Vector2(0.0, -1.0), Vector2.ZERO, Vector2.ZERO),
		0.0, 0.0001)
	assert_almost_eq(absf(Map3DUnits.yaw_for(Vector2(0.0, 1.0), Vector2.ZERO, Vector2.ZERO)),
		PI, 0.0001, "marching the other way, it turns right round")
	assert_almost_eq(Map3DUnits.yaw_for(Vector2(-1.0, 0.0), Vector2.ZERO, Vector2.ZERO),
		PI * 0.5, 0.0001)


func test_a_standing_piece_turns_square_to_the_camera() -> void:
	# No heading: it faces the camera, so a counter is never read edge-on.
	var at := Vector2(100.0, 100.0)
	var cam := Vector2(100.0, 40.0)          # due -Z of it
	assert_almost_eq(Map3DUnits.yaw_for(Vector2.ZERO, cam, at), 0.0, 0.0001)
	assert_almost_eq(absf(Map3DUnits.yaw_for(Vector2.ZERO, Vector2(100.0, 160.0), at)),
		PI, 0.0001)


func test_a_standing_horse_turns_its_flank_to_the_camera() -> void:
	# A horse square to the camera is nose-on — the narrowest thing it can
	# show; army_art's stand_deg turns it that far off square, but only while
	# it stands: a marching piece still faces its road.
	var at := Vector2(100.0, 100.0)
	var cam := Vector2(100.0, 40.0)
	assert_almost_eq(Map3DUnits.yaw_for(Vector2.ZERO, cam, at, 55.0), deg_to_rad(55.0), 0.0001)
	assert_almost_eq(Map3DUnits.yaw_for(Vector2(0.0, -1.0), cam, at, 55.0), 0.0, 0.0001,
		"marching, it faces the way it goes")


func test_a_model_is_measured_not_declared() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 6.0, 2.0)
	mi.mesh = box
	root.add_child(mi)
	autofree(root)
	var span := Map3DUnits.model_size(root)
	assert_almost_eq(span.y, 6.0, 0.001, "its height is its own")
	assert_almost_eq(span.x, 1.0, 0.001, "and its half width")


func test_a_model_with_no_mesh_falls_back_rather_than_dividing_by_zero() -> void:
	var root := Node3D.new()
	autofree(root)
	assert_eq(Map3DUnits.model_size(root), Vector2(0.5, 1.0))


func test_the_action_is_matched_on_the_tail_of_the_clip_name() -> void:
	# The glTF importer may prefix a library name onto every clip.
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	lib.add_animation("GARRISON", Animation.new())
	lib.add_animation("MARCH", Animation.new())
	anim.add_animation_library("piece", lib)
	autofree(anim)
	assert_eq(Map3DUnits.clip_named(anim, "MARCH"), "piece/MARCH")
	assert_eq(Map3DUnits.clip_named(anim, "ATTACK"), "", "a clip it has not got is no clip")


func test_every_arm_that_should_have_a_model_names_one_that_exists() -> void:
	for piece: String in repo.army_art:
		var path := String((repo.army_art[piece] as Dictionary).get("model", ""))
		if path == "":
			continue   # a fleet keeps the flat counter
		assert_true(ResourceLoader.exists(path), "%s names a model that is not there: %s" % [piece, path])


func test_the_menu_rows_are_data_and_every_one_is_a_real_order() -> void:
	assert_gt(repo.army_orders.size(), 0, "data/army_orders.csv is the menu")
	for row: Dictionary in repo.army_orders:
		var code := String(row["action_code"])
		assert_true(repo.actions.has(code), code + " is offered but is not an action")
		assert_ne(String(row["label"]), "", code + " needs something to call it")


# --- the walk between two days (owner 2026-09-24: 应该可以看到动画移动过去) ---

func _walker(s: GameState) -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.day_step_m(repo, s, String(r["regiment_code"])) > 0:
			return String(r["regiment_code"])
	return ""


func test_a_piece_walks_a_days_march_in_a_days_real_seconds() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _walker(s)
	var meta := {"m_per_px": 50.0}
	# By hand: day_step_m pack metres x (50 world m / metres_per_pack_px) over
	# time_day_seconds / 2 at the 2x clock.
	var day_world := float(ArmySystem.day_step_m(repo, s, code)) * 50.0 \
		/ float(ArmySystem.metres_per_pack_px(repo))
	assert_almost_eq(Map3DUnits.day_world_m(repo, s, code, meta), day_world, 0.001)
	assert_almost_eq(Map3DUnits.walk_speed(repo, s, code, meta, 2),
		day_world / (repo.bal("time_day_seconds") / 2.0), 0.001)
	assert_eq(Map3DUnits.walk_speed(repo, s, code, meta, 0), 0.0, "the clock stopped, the piece stands")
	assert_almost_eq(Map3DUnits.snap_m(repo, s, code, meta),
		day_world * repo.bal("map3d_unit_snap_days"), 0.001)


func test_walk_steps_toward_the_target_lands_on_it_and_jumps_when_far_behind() -> void:
	var a := Vector2.ZERO
	var b := Vector2(30.0, 40.0)   # 50 away
	assert_eq(Map3DUnits.walk(a, b, 10.0, 100.0), Vector2(6.0, 8.0), "ten metres along the way")
	assert_eq(Map3DUnits.walk(a, b, 60.0, 100.0), b, "closer than a step: lands exactly")
	assert_eq(Map3DUnits.walk(a, b, 10.0, 40.0), b, "farther than the snap: jumps")
	assert_eq(Map3DUnits.walk(a, b, 0.0, 100.0), a, "no speed: stands")


# --- seating on a slope (owner 2026-09-24: 斜面上兵人的一部分会被地图盖住) ---

func _ring() -> PackedVector2Array:
	return Map3DUnits.footprint(Vector2(10.0, 10.0), 0.0, 1.0, 8)


func test_on_flat_ground_a_piece_sits_level_on_it() -> void:
	var o := _ring()
	var h := PackedFloat32Array()
	for p in o:
		h.append(50.0)
	var s := Map3DUnits.seat(o, h, 12.0)
	assert_almost_eq(float(s["y"]), 50.0, 0.0001)
	assert_almost_eq((s["normal"] as Vector3).dot(Vector3.UP), 1.0, 0.0001)


func test_on_a_gentle_slope_it_tilts_with_it_and_sinks_nowhere() -> void:
	# h = 0.1 x + 100: a 5.7 degree grade, inside the cap. By hand the plane
	# is the slope itself, the centre sits at 100, the normal is (-0.1, 1, 0).
	var o := _ring()
	var h := PackedFloat32Array()
	for p in o:
		h.append(0.1 * p.x + 100.0)
	var s := Map3DUnits.seat(o, h, 12.0)
	assert_almost_eq(float(s["y"]), 100.0, 0.001)
	var n: Vector3 = s["normal"]
	assert_almost_eq(n.x / n.y, -0.1, 0.0001)
	for i in o.size():
		assert_true(float(s["y"]) + 0.1 * o[i].x >= h[i] - 0.001, "no sample above the base")


func test_on_a_cliff_the_tilt_is_capped_and_it_is_lifted_clear() -> void:
	# h = 1.0 x: 45 degrees. Held to 12 degrees (grade tan 12 = 0.2126); the
	# uphill edge at x = 10 is 10 high, the base there is y + 2.126, so the
	# centre must stand at 10 - 2.126 = 7.874 for nothing to poke through.
	var o := _ring()
	var h := PackedFloat32Array()
	for p in o:
		h.append(p.x)
	var s := Map3DUnits.seat(o, h, 12.0)
	var n: Vector3 = s["normal"]
	assert_almost_eq(rad_to_deg(n.angle_to(Vector3.UP)), 12.0, 0.01)
	assert_almost_eq(float(s["y"]), 10.0 - 10.0 * tan(deg_to_rad(12.0)), 0.001)


func test_a_footprint_turns_and_scales_with_the_piece() -> void:
	# A long base (half 1 x 3) turned a quarter: its long axis now lies on x.
	var o := Map3DUnits.footprint(Vector2(1.0, 3.0), PI / 2.0, 2.0, 4)
	assert_eq(o.size(), 9, "the centre and two rings of four")
	var widest := 0.0
	for p in o:
		widest = maxf(widest, absf(p.x))
	assert_almost_eq(widest, 6.0, 0.001, "3 m half length x 2 scale, along x")
