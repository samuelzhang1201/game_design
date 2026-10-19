extends GutTest
## A chained action (army_art.csv `chains`, Map3DClipChain; owner 2026-10-19:
## 士兵的动作能够根据实际情况做出自动的选择): the infantry strikes ATTACK / SLASH /
## ATTACK_VAR1 by turns in battle, each figure its own order and pauses.

const SuiteData := preload("res://tests/suite_data.gd")


func test_chains_parse_from_the_row() -> void:
	assert_eq(Map3DClipChain.of_art({"chains": "ATTACK:ATTACK;SLASH;ATTACK_VAR1|DEFEND:GARRISON"}),
		{"ATTACK": ["ATTACK", "SLASH", "ATTACK_VAR1"], "DEFEND": ["GARRISON"]})
	assert_eq(Map3DClipChain.of_art({"chains": ""}), {})
	assert_eq(Map3DClipChain.of_art({}), {})
	assert_eq(Map3DClipChain.of_art({"chains": "ATTACK|:SLASH"}), {}, "a part without both sides is skipped")


func test_the_pick_is_stable_in_range_and_differs_between_figures() -> void:
	var firsts: Dictionary = {}
	for i in 9:
		var k := Map3DClipChain.pick("REG_1", i, 0, 3)
		assert_between(k, 0, 2)
		assert_eq(k, Map3DClipChain.pick("REG_1", i, 0, 3), "the same figure and strike pick the same clip")
		firsts[k] = true
	assert_gt(firsts.size(), 1, "nine figures do not all open with the same strike")
	var seq: Array = range(6).map(func(n: int) -> int: return Map3DClipChain.pick("REG_1", 0, n, 3))
	assert_gt(seq.filter(func(k: int) -> bool: return k != seq[0]).size(), 0, "one figure varies its strikes")
	assert_eq(Map3DClipChain.pick("REG_1", 0, 0, 1), 0, "one clip: always it")


func test_the_pause_is_within_its_bounds() -> void:
	for n in 20:
		var s := Map3DClipChain.rest_s("REG_1", 3, n, 0.4, 1.4)
		assert_between(s, 0.4, 1.4)
	assert_eq(Map3DClipChain.rest_s("REG_1", 3, 5, 0.4, 1.4), Map3DClipChain.rest_s("REG_1", 3, 5, 0.4, 1.4))


func _player() -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for spec: Array in [["GARRISON", 1.0, Animation.LOOP_LINEAR], ["ATTACK", 0.15, Animation.LOOP_NONE],
			["SLASH", 0.15, Animation.LOOP_NONE]]:
		var clip := Animation.new()
		clip.length = spec[1]
		clip.loop_mode = spec[2]
		lib.add_animation(spec[0], clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func test_a_figure_strikes_by_turns_and_leaves_the_chain_on_a_new_action() -> void:
	var anim := _player()
	var chain := {"clips": ["ATTACK", "SLASH"], "lo": 0.05, "hi": 0.1}
	Map3DUnitRig.play([anim], "ATTACK", 0.0, "REG_T", chain)
	assert_eq(anim.current_animation, "GARRISON", "it stands its guard before its first strike")
	await wait_until(func() -> bool: return int(anim.get_meta("chain")["n"]) >= 3, 5.0)
	assert_gte(int(anim.get_meta("chain")["n"]), 3, "three strikes, one after another")
	Map3DUnitRig.play([anim], "ATTACK", 0.0, "REG_T", chain)
	assert_gte(int(anim.get_meta("chain")["n"]), 3, "asked again for the same action: the chain goes on")
	Map3DUnitRig.play([anim], "GARRISON", 0.0, "REG_T")
	assert_false(anim.has_meta("chain"), "a plain action takes the figure off the chain")
	await wait_process_frames(30)
	assert_eq(anim.current_animation, "GARRISON", "and no strike follows")


## The installed infantry answers every action the map asks for, and its strikes play once.
func test_the_infantry_answers_every_action_and_strikes_once() -> void:
	var repo := SuiteData.repo()
	var root := (load("res://assets/3D/units/infantry/infantry.glb") as PackedScene).instantiate()
	var anim := Map3DUnits.find_anim(root)
	assert_eq(Map3DUnits.clip_named(anim, "MARCH"), "MARCH")
	for action: String in ["GARRISON", "STANDBY", "DEFEND"]:
		assert_eq(Map3DUnits.clip_named(anim, action), "GARRISON", action + " stands the guard")
	var chains := Map3DClipChain.of_art(repo.army_art["infantry"])
	assert_eq(chains.get("ATTACK", []), ["ATTACK", "SLASH", "ATTACK_VAR1"])
	for clip: String in chains["ATTACK"]:
		var named := Map3DUnits.clip_named(anim, clip)
		assert_eq(named, clip, clip + " is in the model")
		if named != "":
			assert_eq(anim.get_animation(named).loop_mode, Animation.LOOP_NONE, clip + " plays once")
	root.free()
