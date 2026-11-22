extends GutTest
## Front-rank duels, the pure part (Map3DDuel; spec 2026-11-16-infantry-duel-animation-design.md):
## who pairs with whom along the front, and each pair's hashed turns.

const SuiteData := preload("res://tests/suite_data.gd")
const ART := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
	"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.3;HIT:0.1"}


func _side(prefix: String, xs: Array) -> Array:
	var out: Array = []
	for i in xs.size():
		out.append({"key": "%s%d" % [prefix, i], "xz": Vector2(float(xs[i]), 10.0 if prefix == "a" else -10.0)})
	return out


func _keys(pairs: Array) -> Array:
	return pairs.map(func(p: Dictionary) -> String: return "%s-%s" % [p["a"], p["b"]])


func test_pairs_in_order_along_the_front() -> void:
	var pairs := Map3DDuel.pairs(_side("a", [10, -10, 0]), _side("b", [0, 10, -10]), Vector2(1, 0), 100.0)
	assert_eq(_keys(pairs), ["a1-b2", "a2-b0", "a0-b1"], "sorted along the front, paired in order")


func test_pairs_centre_the_shorter_side() -> void:
	# a at -20..20, b at -5, 5: the sums by offset are 30, 10, 10, 30; the tie takes the smallest offset.
	var pairs := Map3DDuel.pairs(_side("a", [-20, -10, 0, 10, 20]), _side("b", [-5, 5]), Vector2(1, 0), 100.0)
	assert_eq(_keys(pairs), ["a1-b0", "a2-b1"])
	var flipped := Map3DDuel.pairs(_side("a", [-5, 5]), _side("b", [-20, -10, 0, 10, 20]), Vector2(1, 0), 100.0)
	assert_eq(_keys(flipped), ["a0-b1", "a1-b2"], "either side may be the shorter")


func test_no_front_no_pairs() -> void:
	assert_eq(Map3DDuel.pairs([], _side("b", [0, 10]), Vector2(1, 0), 100.0), [])
	assert_eq(Map3DDuel.pairs(_side("a", [0]), [], Vector2(1, 0), 100.0), [])


func test_beyond_reach_is_not_a_pair() -> void:
	# a0 (0, 10) to b0 (0, -10) is 20 apart; a1 (50, 10) to b1 (80, -10) is 36.06 apart.
	var pairs := Map3DDuel.pairs(_side("a", [0, 50]), _side("b", [0, 80]), Vector2(1, 0), 30.0)
	assert_eq(_keys(pairs), ["a0-b0"])


func _anim(clips: Array) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name: String in clips:
		var clip := Animation.new()
		clip.length = 1.0
		lib.add_animation(name, clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func test_an_arm_without_its_duel_clips_does_not_duel() -> void:
	assert_true(Map3DDuel.duels(ART, _anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT", "DEATH"])))
	assert_false(Map3DDuel.duels(ART, _anim(["GARRISON", "ATTACK", "SLASH", "HIT"])), "no BLOCK clip")
	assert_false(Map3DDuel.duels({"duel": ART["duel"], "contact": "ATTACK:0.4;BLOCK:0.3;HIT:0.1"},
		_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])), "a strike without its contact share")
	assert_false(Map3DDuel.duels({}, _anim(["ATTACK", "BLOCK", "HIT"])), "no duel column")
	assert_true(Map3DDuel.duels(ART, _anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])), "DEATH is not needed to duel")


func test_the_installed_infantry_duels_and_falls() -> void:
	var repo := SuiteData.repo()
	var root := (load("res://assets/3D/units/infantry/infantry.glb") as PackedScene).instantiate()
	add_child_autofree(root)
	var anim := Map3DUnits.find_anim(root)
	assert_true(Map3DDuel.duels(repo.army_art["infantry"], anim), "every STRIKE / BLOCK / HIT clip installed with its contact")
	for clip: String in Map3DClipChain.of_column(repo.army_art["infantry"], "duel")["DEATH"]:
		assert_ne(Map3DUnits.clip_named(anim, clip), "", "%s is installed: a lost duellist falls" % clip)
	for clip: String in Map3DDuel.contact_of(repo.army_art["infantry"]):
		var share := float(Map3DDuel.contact_of(repo.army_art["infantry"])[clip])
		assert_true(share > 0.0 and share < 1.0, "%s meets inside its clip" % clip)
	# its steps in, out and up walk the installed MARCH at its measured stride, backing away backwards
	var march := Map3DUnits.clip_named(anim, "MARCH")
	assert_ne(march, "", "the combat walk is installed")
	assert_gt(float(repo.army_art["infantry"]["stride_m"]), 0.0, "with its stride, so a step is paced")
	anim.play(march)
	anim.seek(0.2, true)
	anim.speed_scale = -1.0
	anim.advance(0.3)
	assert_almost_eq(anim.current_animation_position, anim.get_animation(march).length - 0.1, 0.001,
		"played backwards the loop wraps, so a figure backs away step by step")


func test_turn_is_stable_and_in_range() -> void:
	for n in 40:
		var t := Map3DDuel.turn("P", n, 3, 2, 0.15, 0.15, 0.3)
		assert_eq(t, Map3DDuel.turn("P", n, 3, 2, 0.15, 0.15, 0.3), "the same pair and turn, the same choice")
		assert_between(int(t["strike"]), 0, 2)
		assert_between(int(t["reply_variant"]), 0, 1)
		assert_between(float(t["rest_u"]), 0.0, 1.0)
		assert_true(String(t["striker"]) in ["a", "b"])
		assert_true(String(t["reply"]) in ["BLOCK", "HIT"])


func test_turn_zero_is_the_attackers() -> void:
	for key: String in ["P", "Q", "R", "S"]:
		assert_eq(Map3DDuel.turn(key, 0, 3, 2, 0.0, 1.0, 0.3)["striker"], "a")


func test_turns_alternate_without_double_or_steal() -> void:
	var seq: Array = range(8).map(func(n: int) -> String: return Map3DDuel.turn("P", n, 3, 2, 0.0, 0.0, 0.3)["striker"])
	assert_eq(seq, ["a", "b", "a", "b", "a", "b", "a", "b"])
	var stolen: Array = range(8).map(func(n: int) -> String: return Map3DDuel.turn("P", n, 3, 2, 1.0, 0.0, 0.3)["striker"])
	assert_eq(stolen, ["a", "a", "a", "a", "a", "a", "a", "a"], "steal 1: the attacker takes every turn")


func test_the_hit_share() -> void:
	for n in 50:
		assert_eq(Map3DDuel.turn("P", n, 3, 2, 0.15, 0.15, 0.0)["reply"], "BLOCK")
		assert_eq(Map3DDuel.turn("P", n, 3, 2, 0.15, 0.15, 1.0)["reply"], "HIT")


func test_pairs_do_not_turn_in_step() -> void:
	var firsts: Dictionary = {}
	for key: String in ["A", "B", "C", "D", "E", "F", "G", "H"]:
		firsts["%s|%s" % [Map3DDuel.turn(key, 0, 3, 2, 0.15, 0.15, 0.3)["strike"],
			snappedf(Map3DDuel.turn(key, 0, 3, 2, 0.15, 0.15, 0.3)["rest_u"], 0.01)]] = true
	assert_gt(firsts.size(), 4, "eight pairs open with different strikes and pauses")


func test_timing_meets_at_contact() -> void:
	# strike 1.0 s meeting at 0.4 (0.4 s in), reply 0.8 s at 0.25 (0.2 s in): the reply starts 0.2 s later.
	assert_eq(Map3DDuel.timing(1.0, 0.4, 0.8, 0.25), {"strike_at": 0.0, "reply_at": 0.2, "contact_at": 0.4, "end": 1.0})
	# strike 0.5 s at 0.2 (0.1 s in), reply 1.0 s at 0.5 (0.5 s in): the strike waits 0.4 s.
	var late := Map3DDuel.timing(0.5, 0.2, 1.0, 0.5)
	assert_almost_eq(float(late["strike_at"]), 0.4, 0.0001)
	assert_eq(float(late["reply_at"]), 0.0)
	assert_almost_eq(float(late["end"]), 1.0, 0.0001)


func test_timing_names_the_contact() -> void:
	# strike 1.2 s meeting at 0.5 (0.6 s in), reply 0.8 s at 0.25 (0.2 s in): the reply starts at 0.4, both meet at 0.6.
	var t := Map3DDuel.timing(1.2, 0.5, 0.8, 0.25)
	assert_almost_eq(float(t["strike_at"]), 0.0, 0.0001)
	assert_almost_eq(float(t["reply_at"]), 0.4, 0.0001)
	assert_almost_eq(float(t["contact_at"]), 0.6, 0.0001)
	assert_almost_eq(float(t["end"]), 1.2, 0.0001)
	# strike 0.6 s at 0.25 (0.15 s in), reply 1.0 s at 0.75 (0.75 s in): the strike waits 0.6, they meet at 0.75.
	var late := Map3DDuel.timing(0.6, 0.25, 1.0, 0.75)
	assert_almost_eq(float(late["strike_at"]), 0.6, 0.0001)
	assert_almost_eq(float(late["reply_at"]), 0.0, 0.0001)
	assert_almost_eq(float(late["contact_at"]), 0.75, 0.0001)
	assert_almost_eq(float(late["end"]), 1.2, 0.0001)
