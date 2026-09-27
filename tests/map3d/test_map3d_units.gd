extends GutTest
## MILITARY's 3D pieces (owner 2026-09-22): how big one is drawn, which way
## it faces, and the box a click hits. Map3DUnits is pure, so all of it is
## checked without a camera or a world.

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	# Force clear skies so every hand-sum match still holds (task 7, owner 2026-09-27)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


## The size rule (owner 2026-09-27), by hand at fov 45 and a 1080 px view:
## metres per px = 2 d tan(22.5) / 1080 = d x 7.67063e-4; the reference
## (the opening view) 25 km away, 20 px there, 32 px at most.
func _rule() -> void:
	repo.balance["map3d_unit_ref_px"] = 20.0
	repo.balance["map3d_unit_max_px"] = 32.0


func test_a_piece_is_its_ref_px_at_the_opening_distance() -> void:
	_rule()
	# 20 px x 25000 x 7.67063e-4 = 383.53 m
	assert_almost_eq(Map3DUnits.height_m(repo, 25000.0, 45.0, 1080.0, 25000.0), 383.53, 0.05)


func test_below_the_cap_a_piece_is_one_world_height() -> void:
	_rule()
	# 50 km: 10 px x 38.353 m = 383.53 m — the same miniature, half the px
	assert_almost_eq(Map3DUnits.height_m(repo, 50000.0, 45.0, 1080.0, 25000.0), 383.53, 0.05)
	# 18 km: 27.78 px x 13.807 m = 383.53 m
	assert_almost_eq(Map3DUnits.height_m(repo, 18000.0, 45.0, 1080.0, 25000.0), 383.53, 0.05)


func test_close_in_it_holds_at_the_cap() -> void:
	_rule()
	# 5 km: 20 x 25000 / 5000 = 100 px, held at 32 px x 3.83532 m = 122.73 m
	assert_almost_eq(Map3DUnits.height_m(repo, 5000.0, 45.0, 1080.0, 25000.0), 122.73, 0.05)
	# 800 m: 32 px x 0.613650 m = 19.64 m
	assert_almost_eq(Map3DUnits.height_m(repo, 800.0, 45.0, 1080.0, 25000.0), 19.64, 0.01)


## By the scale bar: 1 km per pack px, 50 m per pack px (0.02 km a metre), a
## 220 px bar, fov 45, a 600 px view — the bar spans 50 km at
## 50 / 220 / 0.02 x 600 / 0.828427 = 8230.2 m.
func test_far_out_the_pieces_become_counters() -> void:
	repo.balance["map3d_unit_counter_scale"] = 50.0
	repo.balance["map_scale_bar_max_px"] = 220.0
	repo.balance["map3d_fov_deg"] = 45.0
	var meta := {"m_per_px": 50.0}
	var info := repo.map_info.duplicate()
	repo.map_info["distance_scale"] = "1"
	assert_false(Map3DUnits.as_counters(repo, meta, 8229.0, 600.0))
	assert_true(Map3DUnits.as_counters(repo, meta, 8231.0, 600.0))
	repo.map_info = info


func test_the_scale_is_that_height_over_the_models_own() -> void:
	var fov := repo.bal("map3d_fov_deg")
	var want := Map3DUnits.height_m(repo, 5000.0, fov, 1080.0, 25000.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 25000.0, 2.0), want / 2.0, 0.0001)
	assert_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 25000.0, 0.0), 1.0,
		"a model with no height is left alone rather than scaled by infinity")


func test_an_arm_can_stand_bigger_than_the_rest() -> void:
	# army_art's size multiplies the drawn height; 1 leaves a piece as it was.
	var fov := repo.bal("map3d_fov_deg")
	var one := Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 25000.0, 2.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 25000.0, 2.0, 1.5), one * 1.5, 0.0001)
	assert_almost_eq(Map3DUnits.scale_for(repo, 5000.0, fov, 1080.0, 25000.0, 2.0, 1.0), one, 0.0001)


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
		if ArmySystem.day_march_m(repo, s, String(r["regiment_code"])) > 0:
			return String(r["regiment_code"])
	return ""


func test_a_piece_walks_a_days_march_in_a_days_real_seconds() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _walker(s)
	var meta := {"m_per_px": 50.0}
	# By hand: day_march_m pack metres x (50 world m / metres_per_pack_px) over
	# time_day_seconds / 2 at the 2x clock.
	var day_world := float(ArmySystem.day_march_m(repo, s, code)) * 50.0 \
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


## The MARCH clip keeps pace with the ground (owner 2026-09-27), by hand: a
## piece at scale 40 crossing 20 world m/s covers 0.5 model m/s; a 2 s clip
## that walks 1.0 model m a loop plays at 0.5 x 2 / 1.0 = 1.0.
func test_the_march_plays_at_the_grounds_pace() -> void:
	repo.balance["map3d_unit_anim_min"] = 0.5
	repo.balance["map3d_unit_anim_max"] = 3.0
	assert_almost_eq(Map3DUnits.march_rate(repo, 20.0, 40.0, 2.0, 1.0), 1.0, 0.0001)
	# twice as fast on the ground: 2.0
	assert_almost_eq(Map3DUnits.march_rate(repo, 40.0, 40.0, 2.0, 1.0), 2.0, 0.0001)
	# 200 m/s would be 10x: held at the ceiling; a crawl held at the floor
	assert_eq(Map3DUnits.march_rate(repo, 200.0, 40.0, 2.0, 1.0), 3.0)
	assert_eq(Map3DUnits.march_rate(repo, 1.0, 40.0, 2.0, 1.0), 0.5)
	assert_eq(Map3DUnits.march_rate(repo, 20.0, 40.0, 2.0, 0.0), 1.0, "no stride: as authored")
