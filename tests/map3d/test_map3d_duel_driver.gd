extends GutTest
## Front-rank duels on the map (Map3DDuelDriver; spec 2026-11-16-infantry-duel-animation-design.md):
## pairs take their figures off their chain, strike and reply meet, a pause
## freezes them, and a figure left alone goes back to its saved spot.

const ART := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
	"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.25;HIT:0.1"}
const TUNE := {"steal": 0.0, "double": 0.0, "hit": 0.0, "rest_min": 0.2, "rest_max": 0.2,
	"reach_h": 30.0, "close_h": 0.6, "step_max_h": 1.0, "chain_lo": 0.1, "chain_hi": 0.2, "open_max": 0.0,
	"hitstop": 0.0, "knock_h": 0.15, "knock_out": 0.12, "knock_back": 0.35, "block_knock": 0.4, "near_m": 1000.0}
const DT := 0.05


func _anim() -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for spec: Array in [["GARRISON", 1.0, Animation.LOOP_LINEAR], ["ATTACK", 1.0, Animation.LOOP_NONE],
			["SLASH", 1.0, Animation.LOOP_NONE], ["BLOCK", 0.8, Animation.LOOP_NONE], ["HIT", 0.8, Animation.LOOP_NONE]]:
		var clip := Animation.new()
		clip.length = spec[1]
		clip.loop_mode = spec[2]
		lib.add_animation(spec[0], clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func _fig(code: String, slot: int, xz: Vector2) -> Dictionary:
	return {"key": "%s:%d" % [code, slot], "code": code, "slot": slot, "anim": _anim(), "child": {},
		"xz": xz, "h": 1.0, "art": ART, "piece": {}}


func _battle(a: Array, b: Array, rounds := 1) -> Array:
	return [{"id": 1, "rounds": rounds, "across": Vector2(1, 0), "a": a, "b": b}]


func test_two_fronts_pair_after_the_first_round() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b, 0), DT, true, TUNE)
	assert_false(driver.is_duelling(a[0]["anim"]), "no duel before the battle's first round")
	var placed := driver.run(_battle(a, b, 1), DT, true, TUNE)
	assert_true(driver.is_duelling(a[0]["anim"]) and driver.is_duelling(b[0]["anim"]))
	assert_eq(placed, ["A", "B"], "both pieces are placed again to step in")
	assert_eq(a[0]["child"]["duel_offset"], Vector2(0, -1), "a steps its most, one height, toward b")
	assert_eq(b[0]["child"]["duel_offset"], Vector2(0, 1))
	assert_almost_eq(float(a[0]["child"]["duel_yaw"]), Map3DUnits.facing_yaw(Vector2(0, -20)), 0.0001, "they face each other")


func test_the_strike_and_reply_meet() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	var turn := Map3DDuel.turn("A:0|B:0", 0, 2, 1, 0.0, 0.0, 0.0)
	var strike: String = ["ATTACK", "SLASH"][int(turn["strike"])]
	var share := 0.4 if strike == "ATTACK" else 0.35
	var timing := Map3DDuel.timing(1.0, share, 0.8, 0.25)
	var t := 0.0
	var reply_seen := -1.0
	var strike_seen := -1.0
	while t < 1.0:
		driver.run(_battle(a, b), DT, true, TUNE)
		t += DT
		var sa: AnimationPlayer = a[0]["anim"]
		var sb: AnimationPlayer = b[0]["anim"]
		if strike_seen < 0.0 and sa.current_animation == strike:
			strike_seen = t
			assert_almost_eq(sa.current_animation_position, t - float(timing["strike_at"]), 0.001, "the strike starts on time")
		if reply_seen < 0.0 and sb.current_animation == "BLOCK":
			reply_seen = t
			assert_almost_eq(sb.current_animation_position, t - float(timing["reply_at"]), 0.001, "the block starts on time")
	assert_gt(strike_seen, 0.0, "a strikes first")
	assert_gt(reply_seen, 0.0, "b blocks")
	assert_almost_eq(reply_seen - strike_seen, float(timing["reply_at"]) - float(timing["strike_at"]), DT + 0.0001)


func test_pause_freezes_and_resumes_in_step() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	driver.run(_battle(a, b), DT, true, TUNE)
	var before := driver.pair_time("A:0|B:0")
	for i in 40:
		driver.run(_battle(a, b), DT, false, TUNE)
	assert_almost_eq(driver.pair_time("A:0|B:0"), before, 0.0001, "a paused duel's clock does not move")
	assert_eq((a[0]["anim"] as AnimationPlayer).speed_scale, 0.0, "nor do its figures")
	assert_eq((b[0]["anim"] as AnimationPlayer).speed_scale, 0.0)
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time("A:0|B:0"), before + DT, 0.0001)
	assert_eq((a[0]["anim"] as AnimationPlayer).speed_scale, 1.0, "resumed")
	assert_eq((b[0]["anim"] as AnimationPlayer).speed_scale, 1.0)


func test_the_duel_keeps_real_time_whatever_the_clock() -> void:
	var driver := Map3DDuelDriver.new()
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time("A:0|B:0"), DT, 0.0001, "run takes real seconds; the clock's speed never reaches it")


func test_an_unpaired_front_figure_guards_facing_a_foe() -> void:
	# no one fights air (spec 2026-11-21-infantry-melee-scrum-design.md): 3 v 1, the two left over
	# leave their chain for the guard and face the foe, without stepping in
	var a := [_fig("A", 0, Vector2(-10, 10)), _fig("A", 1, Vector2(0, 10)), _fig("A", 2, Vector2(10, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	var placed := driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(driver.paired_slots("A"), [1], "the one opposite pairs")
	for i: int in [0, 2]:
		var f: Dictionary = a[i]
		assert_true(driver.is_duelling(f["anim"]), "A:%d is claimed off its chain" % i)
		assert_eq((f["anim"] as AnimationPlayer).current_animation, "GARRISON", "and guards")
		assert_false((f["child"] as Dictionary).has("duel_offset"), "without stepping in")
		var want := Map3DUnits.facing_yaw(Vector2(0, -10) - (f["xz"] as Vector2))
		assert_almost_eq(angle_difference(float(f["child"]["duel_yaw"]), want), 0.0, deg_to_rad(1.0), "facing the foe")
	assert_true("A" in placed, "its piece turns them")
	driver.run(_battle(a, []), DT, true, TUNE)
	assert_false(driver.is_duelling(a[0]["anim"]), "the battle gone, a waiting figure is released like a duellist")
	assert_false((a[0]["child"] as Dictionary).has("duel_yaw"))


func test_a_waiting_figure_takes_a_fallen_partners_place() -> void:
	var a := [_fig("A", 0, Vector2(0, 10)), _fig("A", 1, Vector2(5, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(driver.paired_slots("A"), [0])
	assert_true(driver.is_duelling(a[1]["anim"]), "A:1 waits its moment")
	var waiting: Dictionary = a[1]
	a.remove_at(0)  # its duellist fell
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(driver.paired_slots("A"), [1], "the waiting figure pairs with the foe")
	assert_true((waiting["child"] as Dictionary).has("duel_offset"), "and steps in")
	assert_true(driver.is_duelling(b[0]["anim"]))


func test_a_rebuilt_figure_is_claimed_again() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	var rebuilt := [_fig("A", 0, Vector2(0, 10))]  # the same slot, a new node (its piece was built again)
	driver.run(_battle(rebuilt, b), DT, true, TUNE)
	assert_true(driver.is_duelling(rebuilt[0]["anim"]), "the new figure takes over the pair")
	for i in 30:
		driver.run(_battle(rebuilt, b), DT, true, TUNE)
	assert_ne((rebuilt[0]["anim"] as AnimationPlayer).current_animation, "", "and plays its turns")


func test_unpairing_returns_to_the_saved_spot() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	var placed := driver.run(_battle(a, []), DT, true, TUNE)
	assert_false(driver.is_duelling(a[0]["anim"]))
	assert_false((a[0]["child"] as Dictionary).has("duel_offset"), "back to its saved point")
	assert_false((a[0]["child"] as Dictionary).has("duel_yaw"), "and its saved facing")
	assert_true("A" in placed, "its piece is placed again to walk back")
	assert_eq((a[0]["anim"] as AnimationPlayer).current_animation, "GARRISON", "a piece with no action stands its guard")


func test_a_front_does_not_open_in_unison() -> void:
	var a: Array = []
	var b: Array = []
	for i in 8:
		a.append(_fig("A", i, Vector2(i * 5.0, 10)))
		b.append(_fig("B", i, Vector2(i * 5.0, -10)))
	var driver := Map3DDuelDriver.new()
	var first: Dictionary = {}
	var tune := TUNE.duplicate()
	tune["open_max"] = 1.2
	for frame in 60:
		driver.run(_battle(a, b), DT, true, tune)
		for f: Dictionary in a + b:
			var anim: AnimationPlayer = f["anim"]
			if not first.has(f["key"]) and anim.current_animation in ["ATTACK", "SLASH"]:
				first[f["key"]] = frame
	var frames: Dictionary = {}
	for k: String in first:
		frames[first[k]] = true
	assert_gt(frames.size(), 3, "eight pairs open on different frames, not one")


func test_losing_one_figure_keeps_the_other_pairs_running() -> void:
	var a: Array = []
	var b: Array = []
	for i in 5:
		a.append(_fig("A", i, Vector2(i * 5.0, 10)))
		b.append(_fig("B", i, Vector2(i * 5.0, -10)))
	var driver := Map3DDuelDriver.new()
	for frame in 10:
		driver.run(_battle(a, b), DT, true, TUNE)
	var before := driver.pair_time("A:4|B:4")
	a.remove_at(1)
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time("A:4|B:4"), before + DT, 0.0001, "an untouched pair keeps its exchange")
	assert_true(driver.is_duelling(a[0]["anim"]), "A:0 still duels B:0")
	assert_false(1 in driver.paired_slots("B"), "B:1 lost its partner")
	assert_true(driver.is_duelling(b[1]["anim"]), "and waits its moment, guarding toward a foe")


func test_a_pair_does_not_strike_while_it_steps_in() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	a[0]["child"]["walking"] = true
	var t := driver.pair_time("A:0|B:0")
	for i in 20:
		driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time("A:0|B:0"), t, 0.0001, "the turn waits for the step to end")
	a[0]["child"]["walking"] = false
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time("A:0|B:0"), t + DT, 0.0001)


func test_a_step_in_or_out_never_turns_its_back() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_true(a[0]["child"].get("step_facing", false), "stepping in keeps its facing")
	driver.run(_battle(a, []), DT, true, TUNE)
	assert_true(a[0]["child"].get("step_facing", false), "stepping back too")


func test_whether_a_figure_duels_is_worked_out_once() -> void:
	var f := _fig("A", 0, Vector2.ZERO)
	assert_true(Map3DDuelDriver.can_duel(f["child"], ART, f["anim"]))
	(f["anim"] as AnimationPlayer).get_animation_library("").remove_animation("BLOCK")
	assert_true(Map3DDuelDriver.can_duel(f["child"], ART, f["anim"]), "cached on the figure, not parsed every frame")
	var other := _fig("A", 1, Vector2.ZERO)
	(other["anim"] as AnimationPlayer).get_animation_library("").remove_animation("BLOCK")
	assert_false(Map3DDuelDriver.can_duel(other["child"], ART, other["anim"]))


func test_a_freed_figure_releases_its_partner() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	(a[0]["anim"] as AnimationPlayer).free()
	driver.run(_battle([], b), DT, true, TUNE)
	assert_false(driver.is_duelling(b[0]["anim"]), "the survivor is handed back")
	assert_eq((b[0]["anim"] as AnimationPlayer).current_animation, "GARRISON")


func test_a_zero_length_turn_still_ends_the_frame() -> void:
	var a := [_fig("A", 0, Vector2(0, 10))]
	var b := [_fig("B", 0, Vector2(0, -10))]
	for f: Dictionary in a + b:
		for clip: String in ["ATTACK", "SLASH", "BLOCK", "HIT"]:
			(f["anim"] as AnimationPlayer).get_animation(clip).length = 0.0
	var tune := TUNE.duplicate()
	tune["rest_min"] = 0.0
	tune["rest_max"] = 0.0
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), 1.0, true, tune)
	assert_true(driver.is_duelling(a[0]["anim"]), "it returned")
