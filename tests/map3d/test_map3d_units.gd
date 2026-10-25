extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## MILITARY's 3D pieces (owner 2026-09-22): how big one is drawn, which way
## it faces, and the box a click hits. Map3DUnits is pure, so all of it is
## checked without a camera or a world.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()
	# Force clear skies so every hand-sum match still holds (task 7, owner 2026-09-27)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


## The size rule (owner 2026-09-30: 比例缩放需要和游戏视角缩放一致), by hand at
## fov 45 and a 1080 px view: metres per px = 2 d tan(22.5) / 1080 =
## d x 7.67063e-4; the reference (the opening view) 25 km away, 20 px there.
func _rule() -> void:
	repo.balance["map3d_unit_ref_px"] = 20.0


func test_a_piece_is_its_ref_px_at_the_opening_distance() -> void:
	_rule()
	# 20 px x 25000 x 7.67063e-4 = 383.53 m
	assert_almost_eq(Map3DUnits.height_m(repo, 45.0, 1080.0, 25000.0), 383.53, 0.05)


func test_a_piece_is_one_world_height_at_every_zoom() -> void:
	# No distance goes in: close in or far out the same miniature, so its size
	# on screen follows the zoom exactly — 100 px at 5 km, 625 px at 800 m.
	_rule()
	var h := Map3DUnits.height_m(repo, 45.0, 1080.0, 25000.0)
	assert_almost_eq(h / Map3DGeometry.metres_per_pixel(5000.0, 45.0, 1080.0), 100.0, 0.01)
	assert_almost_eq(h / Map3DGeometry.metres_per_pixel(800.0, 45.0, 1080.0), 625.0, 0.01)


func test_the_window_height_does_not_change_a_pieces_world_size() -> void:
	# ref_m grows with the view (distance_for_bar), so px x metres-per-px cancels.
	_rule()
	assert_almost_eq(Map3DUnits.height_m(repo, 45.0, 2160.0, 50000.0),
		Map3DUnits.height_m(repo, 45.0, 1080.0, 25000.0), 0.01)


## A COURIER's mark by a rider's own px (a regiment piece has no mark, owner
## 2026-10-10): 1 km per pack px, 50 m per pack px, a 220 px bar, fov 45, a
## 600 px view, the opening bar 25 km — the reference 25 / 220 / 0.02 x 600 /
## 0.828427 = 4115.1 m. At 12 px there and a 14 px mark, the riders go at
## 4115.1 x 12 / 14 = 3527.2 m.
func test_far_out_a_courier_becomes_his_mark() -> void:
	repo.balance["map3d_unit_ref_px"] = 12.0
	repo.balance["map3d_unit_mark_px"] = 14.0
	repo.balance["map3d_zoom_start_scale"] = 25.0
	repo.balance["map_scale_bar_max_px"] = 220.0
	repo.balance["map3d_fov_deg"] = 45.0
	var meta := {"m_per_px": 50.0}
	var info := repo.map_info.duplicate()
	repo.map_info["distance_scale"] = "1"
	assert_false(Map3DUnits.as_counters(repo, meta, 3526.0, 600.0))
	assert_true(Map3DUnits.as_counters(repo, meta, 3529.0, 600.0))
	repo.map_info = info


## A piece walks while it has somewhere to go and its start has come — not
## "it moved this frame" (owner 2026-09-30: 走路速度怎么时快时慢).
## Perf 2026-10-02: a figure's animation runs only while its piece is shown
## (behind the camera it is hidden).
func test_a_hidden_piece_stops_animating() -> void:
	var node := Node3D.new()
	var anim := AnimationPlayer.new()
	node.add_child(anim)
	var piece := {"node": node, "anims": [anim]}
	Map3DUnits.show_piece(piece, false)
	assert_false(node.visible)
	assert_false(anim.active, "a hidden piece's figures stand still")
	Map3DUnits.show_piece(piece, true)
	assert_true(node.visible)
	assert_true(anim.active, "shown again, they move again")
	node.free()


func test_a_piece_walks_from_its_start_to_its_end() -> void:
	var day := {"from": Vector2.ZERO, "to": Vector2(100.0, 0.0), "s0": 0.4}
	assert_false(Map3DUnits.walking(day, 0.3), "its courier has not reached it yet")
	assert_true(Map3DUnits.walking(day, 0.4))
	assert_true(Map3DUnits.walking(day, 0.99))
	day["to"] = Vector2(0.2, 0.0)
	assert_false(Map3DUnits.walking(day, 0.5), "a frame short of its end is no march")


func test_the_scale_is_that_height_over_the_models_own() -> void:
	var fov := repo.bal("map3d_fov_deg")
	var want := Map3DUnits.height_m(repo, fov, 1080.0, 25000.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, fov, 1080.0, 25000.0, 2.0), want / 2.0, 0.0001)
	assert_eq(Map3DUnits.scale_for(repo, fov, 1080.0, 25000.0, 0.0), 1.0,
		"a model with no height is left alone rather than scaled by infinity")


func test_an_arm_can_stand_bigger_than_the_rest() -> void:
	# army_art's size multiplies the drawn height; 1 leaves a piece as it was.
	var fov := repo.bal("map3d_fov_deg")
	var one := Map3DUnits.scale_for(repo, fov, 1080.0, 25000.0, 2.0)
	assert_almost_eq(Map3DUnits.scale_for(repo, fov, 1080.0, 25000.0, 2.0, 1.5), one * 1.5, 0.0001)
	assert_almost_eq(Map3DUnits.scale_for(repo, fov, 1080.0, 25000.0, 2.0, 1.0), one, 0.0001)


func test_a_marching_piece_faces_its_heading() -> void:
	# The models are authored facing +Y in Blender, which is -Z here, so a
	# piece marching toward -Z stands at yaw 0.
	assert_almost_eq(Map3DUnits.yaw_for(Vector2(0.0, -1.0), Vector2.ZERO, Vector2.ZERO),
		0.0, 0.0001)
	assert_almost_eq(absf(Map3DUnits.yaw_for(Vector2(0.0, 1.0), Vector2.ZERO, Vector2.ZERO)),
		PI, 0.0001, "marching the other way, it turns right round")
	assert_almost_eq(Map3DUnits.yaw_for(Vector2(-1.0, 0.0), Vector2.ZERO, Vector2.ZERO),
		PI * 0.5, 0.0001)


## A regiment piece faces the way it last ADVANCED (owner 2026-10-10:
## 应当固定向他们之前前进的方向前方): with no heading it stands at REST — south,
## +Z, toward where the opening camera stands — a fixed world heading with no
## camera term, so a pan never turns it.
func test_a_piece_with_no_heading_stands_at_rest() -> void:
	assert_almost_eq(absf(Map3DUnits.facing_yaw(Vector2.ZERO)), PI, 0.0001, "facing +Z")
	assert_almost_eq(Map3DUnits.facing_yaw(Vector2(-1.0, 0.0)), PI * 0.5, 0.0001,
		"a heading is its own facing")


func test_a_resting_horse_turns_its_flank() -> void:
	# stand_deg turns a piece at REST off square (a horse nose-on is a sliver);
	# one that has advanced faces its road.
	assert_almost_eq(wrapf(Map3DUnits.facing_yaw(Vector2.ZERO, 55.0) - PI - deg_to_rad(55.0), -PI, PI),
		0.0, 0.0001)
	assert_almost_eq(Map3DUnits.facing_yaw(Vector2(0.0, -1.0), 55.0), 0.0, 0.0001,
		"it faces the way it went")


## track(): the heading turns only once the drawn piece stands more than
## TRACK_MIN_M (0.5 m) past where it was last taken.
func test_standing_keeps_its_last_heading() -> void:
	var t := Map3DUnits.track({}, Vector2(0.0, 0.0), Vector2(0.3, 0.0))
	assert_eq(t["heading"], Vector2.ZERO, "0.3 m is no advance")
	assert_eq(t["trail"], Vector2.ZERO, "the trail stays where it was")
	t = Map3DUnits.track(t, Vector2(0.3, 0.0), Vector2(3.0, 4.0))
	assert_almost_eq((t["heading"] as Vector2).x, 0.6, 0.0001, "(3, 4) / 5 from the trail")
	assert_almost_eq((t["heading"] as Vector2).y, 0.8, 0.0001)
	assert_eq(t["trail"], Vector2(3.0, 4.0))
	t = Map3DUnits.track(t, Vector2(3.0, 4.0), Vector2(3.0, 4.0))
	assert_almost_eq((t["heading"] as Vector2).x, 0.6, 0.0001, "halted, it keeps facing its march")
	t = Map3DUnits.track(t, Vector2(3.0, 4.0), Vector2(3.2, 3.9))
	assert_almost_eq((t["heading"] as Vector2).y, 0.8, 0.0001, "a sub-metre creep turns nothing")
	t = Map3DUnits.track(t, Vector2(3.2, 3.9), Vector2(-7.0, 4.0))
	assert_eq(t["heading"], Vector2(-1.0, 0.0), "a real step back west turns it")


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
		var path := GameArt.path(GameArt.ARMY_MODELS, piece)
		if path == "":
			continue   # a fleet keeps the flat counter
		assert_true(ResourceLoader.exists(path), "%s names a model that is not there: %s" % [piece, path])


func test_the_menu_rows_are_data_and_every_one_is_a_real_order() -> void:
	assert_gt(repo.army_orders.size(), 0, "data/army/army_orders.csv is the menu")
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


func test_a_days_march_in_world_metres_and_the_snap() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _walker(s)
	var meta := {"m_per_px": 50.0}
	# By hand: day_march_m pack metres x (50 world m / metres_per_pack_px).
	var day_world := float(ArmySystem.day_march_m(repo, s, code)) * 50.0 \
		/ float(ArmySystem.metres_per_pack_px(repo))
	assert_almost_eq(Map3DUnits.day_world_m(repo, s, code, meta), day_world, 0.001)
	assert_almost_eq(Map3DUnits.snap_m(repo, s, code, meta),
		day_world * repo.bal("map3d_unit_snap_days"), 0.001)


## Owner 2026-09-28: the piece walks the engine's NEXT day as the day runs,
## from where it stood when the day (or its order) turned.
func test_along_day_walks_by_the_days_share() -> void:
	var day := {"from": Vector2.ZERO, "to": Vector2(30.0, 40.0), "s0": 0.0}
	assert_eq(Map3DUnits.along_day(day, 0.0), Vector2.ZERO, "the day not begun: where it stood")
	assert_eq(Map3DUnits.along_day(day, 0.5), Vector2(15.0, 20.0), "half the day, half the way")
	assert_eq(Map3DUnits.along_day(day, 1.0), Vector2(30.0, 40.0), "the day's end: where the engine leaves it")
	day["s0"] = 0.5  # ordered mid-day: the rest of the day carries the whole step
	assert_eq(Map3DUnits.along_day(day, 0.5), Vector2.ZERO)
	assert_eq(Map3DUnits.along_day(day, 0.75), Vector2(15.0, 20.0))


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
	assert_almost_eq(Map3DUnitRig.march_rate(repo, 20.0, 40.0, 2.0, 1.0), 1.0, 0.0001)
	# twice as fast on the ground: 2.0
	assert_almost_eq(Map3DUnitRig.march_rate(repo, 40.0, 40.0, 2.0, 1.0), 2.0, 0.0001)
	# 200 m/s would be 10x: held at the ceiling; a crawl held at the floor
	assert_eq(Map3DUnitRig.march_rate(repo, 200.0, 40.0, 2.0, 1.0), 3.0)
	assert_eq(Map3DUnitRig.march_rate(repo, 1.0, 40.0, 2.0, 1.0), 0.5)
	assert_eq(Map3DUnitRig.march_rate(repo, 20.0, 40.0, 2.0, 0.0), 1.0, "no stride: as authored")


func test_the_gait_rate_follows_the_ground_within_its_bounds() -> void:
	# 12 world m/s at scale 4 = 3 model m/s; a 1.2 s loop covering 2.4 model m wants 1.5x
	assert_almost_eq(Map3DUnitRig.gait_rate(12.0, 4.0, 1.2, 2.4, 0.5, 3.0), 1.5, 0.0001)
	assert_eq(Map3DUnitRig.gait_rate(120.0, 4.0, 1.2, 2.4, 0.5, 3.0), 3.0, "held at the top bound")
	assert_eq(Map3DUnitRig.gait_rate(0.1, 4.0, 1.2, 2.4, 0.5, 3.0), 0.5, "held at the bottom bound")
	assert_eq(Map3DUnitRig.gait_rate(12.0, 4.0, 1.2, 0.0, 0.5, 3.0), 1.0, "no stride known: normal speed")


## The gait is timed from the day's PLAN (owner 2026-09-30: 走路速度怎么时快时
## 慢), by hand: 800 world m over a whole 8 s day at 1x is 100 m/s; at 4x 400;
## a day whose march starts at share 0.5 has 4 s left, so 200 m/s at 1x.
func test_the_walk_speed_is_the_days_plan() -> void:
	var day := {"from": Vector2.ZERO, "to": Vector2(800.0, 0.0), "s0": 0.0}
	assert_almost_eq(Map3DUnitRig.walk_speed(day, 8.0, 1), 100.0, 0.001)
	assert_almost_eq(Map3DUnitRig.walk_speed(day, 8.0, 4), 400.0, 0.001)
	day["s0"] = 0.5
	assert_almost_eq(Map3DUnitRig.walk_speed(day, 8.0, 1), 200.0, 0.001)
	assert_eq(Map3DUnitRig.walk_speed(day, 8.0, 0), 0.0, "a stopped clock walks nowhere")


## The piece walks the day's ROUTE (along_day by its corners), so the plan's
## speed is the route's length, not the chord: 0 -> (300,0) -> (300,400) is
## 700 m (the chord 500) over an 8 s day at 1x, 87.5 m/s.
func test_the_walk_speed_follows_the_route_corners() -> void:
	var day := {"from": Vector2.ZERO, "to": Vector2(300.0, 400.0), "s0": 0.0,
		"via": PackedVector2Array([Vector2(300.0, 0.0)])}
	assert_almost_eq(Map3DUnitRig.walk_speed(day, 8.0, 1), 87.5, 0.001)


## An exact-pace arm (army_art.csv exact_pace, owner 2026-10-14: 步伐和移动能够
## 完全匹配): its feet keep the ground at ANY speed — no anim bounds, no
## per-figure jitter. By hand: 100 m/s world at k 10 is 10 model m/s; a 2 s
## loop over 4 m is 2 m/s natural, so x5 — past anim_max 2.0, every figure alike.
func test_an_exact_pace_piece_plays_the_true_rate_on_every_figure() -> void:
	var node := Node3D.new()
	node.scale = Vector3.ONE * 10.0
	var anims: Array = []
	for i in 3:
		var a := AnimationPlayer.new()
		node.add_child(a)
		anims.append(a)
	var piece := {"node": node, "anims": anims, "clip_s": 2.0, "stride_m": 4.0, "exact_pace": true}
	var day := {"from": Vector2.ZERO, "to": Vector2(800.0, 0.0), "s0": 0.0}
	Map3DUnitRig.keep_pace(repo, piece, day, 0.1, 1, "R1")
	for a: AnimationPlayer in anims:
		assert_almost_eq(a.speed_scale, 5.0, 0.0001)
	piece["exact_pace"] = false
	piece.erase("pace_key")
	Map3DUnitRig.keep_pace(repo, piece, day, 0.1, 1, "R1")
	assert_lte((anims[0] as AnimationPlayer).speed_scale, repo.bal("map3d_unit_anim_max"),
		"an arm without it is still held to the bound")
	node.free()


## The infantry is an exact-pace arm (owner 2026-10-14), and the piece carries it.
func test_the_infantry_keeps_exact_pace() -> void:
	assert_eq(String(repo.army_art["infantry"].get("exact_pace", "")), "1")


## The chip hangs over the HEAD (owner 2026-09-30: 兵人的icon和模型间隔太远了),
## never above the figure's box: with a spear the box's top is its tip, with the
## sword-and-shield knight (2026-10-19) it is the helmet itself.
func test_the_chip_hangs_at_the_head() -> void:
	var node := (load("res://assets/3D/units/infantry/infantry.glb") as PackedScene).instantiate() as Node3D
	var box := Map3DUnits.model_size(node).y
	var head := Map3DUnitRig.head_m(repo, node, box)
	assert_between(head, 1.5, 2.0, "a man's head with its helmet, not a spear tip")
	assert_lte(head, box)
	var bare := Node3D.new()
	assert_eq(Map3DUnitRig.head_m(repo, bare, 3.0), 3.0, "no head bone: the box's top")
	bare.free()
	node.free()


## The clip a held piece plays (spec 2026-10-11-war-room-front-line-design
## §2, the architect's T2.3 / T2.4): DEFEND standing in hold, GARRISON when
## the model has no DEFEND, and the held facing's yaw.
func test_the_action_for_a_held_piece_is_its_standing_clip() -> void:
	var hold := {"stand_clip": "DEFEND"}
	var steady := {"stand_clip": ""}
	assert_eq(Map3DUnitRig.action_for(true, ArmySystem.ORDER_MARCH, hold), "MARCH")
	assert_eq(Map3DUnitRig.action_for(false, ArmySystem.ORDER_GARRISON, hold), "DEFEND")
	assert_eq(Map3DUnitRig.action_for(false, ArmySystem.ORDER_MARCH, hold), "GARRISON" if false else "STANDBY", "a stopped column under a march order, not walking")
	assert_eq(Map3DUnitRig.action_for(false, ArmySystem.ORDER_GARRISON, steady), "GARRISON")
	assert_eq(Map3DUnitRig.action_for(false, ArmySystem.ORDER_STANDBY, steady), "STANDBY")
	assert_eq(Map3DUnitRig.action_for(false, ArmySystem.ORDER_STANDBY, {}), "STANDBY")
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	lib.add_animation("GARRISON", Animation.new())
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	assert_eq(Map3DUnits.clip_named(anim, "DEFEND"), "GARRISON", "no DEFEND: it holds in GARRISON")
	assert_eq(Map3DUnits.clip_named(anim, "ATTACK"), "", "other missing clips stay missing")


## A model with no guard clip (MARCH and STANDBY only) garrisons and holds
## standing by, never frozen in its march.
func test_a_model_with_no_garrison_stands_by_instead() -> void:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	lib.add_animation("MARCH", Animation.new())
	lib.add_animation("STANDBY", Animation.new())
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	assert_eq(Map3DUnits.clip_named(anim, "GARRISON"), "STANDBY")
	assert_eq(Map3DUnits.clip_named(anim, "DEFEND"), "STANDBY", "no DEFEND, no GARRISON: it holds standing by")
	assert_eq(Map3DUnits.clip_named(anim, "STANDBY"), "STANDBY")
	var bare := AnimationPlayer.new()
	bare.add_animation_library("", AnimationLibrary.new())
	add_child_autofree(bare)
	assert_eq(Map3DUnits.clip_named(bare, "STANDBY"), "", "no standing clip at all: no clip, no endless fallback")


func test_a_held_facing_turns_the_piece_about() -> void:
	var repo := SuiteData.repo()
	var s := SuiteData.campaign(repo, 7)
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var e: Dictionary = s.regiments[code]
	e["order"] = ArmySystem.ORDER_GARRISON
	e["facing_deg"] = 90
	var f := ArmySystem.facing_of(s, code)
	assert_almost_eq(f.x, 0.0, 0.0001)
	assert_almost_eq(f.y, 1.0, 0.0001)
	assert_almost_eq(absf(Map3DUnits.facing_yaw(f)), PI, 0.01, "facing south: turned about")
	e["order"] = ArmySystem.ORDER_MARCH
	assert_eq(ArmySystem.facing_of(s, code), Vector2.ZERO, "a marching column shows no held facing")


## A camp pitched behind a held line (spec 2026-10-11-war-room-front-line-
## design §3, T3.3): behind a line facing south lies north; the +Z rear.
func test_behind_a_south_facing_line_is_north() -> void:
	var at := Map3DUnitCamps.behind(Vector2(100, 200), PI, 28.0)
	assert_almost_eq(at.x, 100.0, 0.001)
	assert_almost_eq(at.y, 172.0, 0.001)
	var east := Map3DUnitCamps.behind(Vector2(0, 0), 0.0, 10.0)
	assert_almost_eq(east.y, 10.0, 0.001, "yaw 0: the rear is +Z")

func test_held_line_keeps_engine_ground_points_on_a_slope() -> void:
	var repo := preload("res://tests/suite_data.gd").repo()
	var state := preload("res://tests/suite_data.gd").campaign(repo, 7)
	var reg: Dictionary = {}
	for candidate: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if MapObjects.regiment_arm(repo, candidate) == "infantry":
			reg = candidate
			break
	var code := String(reg.regiment_code)
	state.regiments[code].merge({"x_m": 10000, "y_m": 10000, "facing_deg": 0,
		"stance": "hold", "order": ArmySystem.ORDER_GARRISON}, true)
	var ctx := Map3DContext.new(repo, {"pack_origin": [-500, -500], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.height_fn = func(at: Vector2) -> float: return at.y * 0.15
	ctx.camera = Camera3D.new()
	add_child_autofree(ctx.camera)
	ctx.camera.position = Vector3(500, 500, 500)
	ctx.camera.look_at(Vector3.ZERO)
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(ctx)
	var piece := layer._piece_of(code)
	layer._shown_xz[code] = Vector2.ZERO
	layer._place(code, piece)
	var expected := BattleGroups.layout(repo, "line", piece.figures, Vector2i(10000, 10000), 0, reg)
	for i: int in piece.figs.size():
		var fig: Node3D = piece.figs[i]
		var point := ctx.to_world(ArmySystem.metres_to_pack(repo, expected[i]))
		assert_almost_eq(fig.global_position.x, point.x, 0.01)
		assert_almost_eq(fig.global_position.z, point.y, 0.01, "grounding must not slide the line outside its engine footprint")
	assert_eq(Vector2((piece.node as Node3D).global_position.x, (piece.node as Node3D).global_position.z), Vector2.ZERO)
