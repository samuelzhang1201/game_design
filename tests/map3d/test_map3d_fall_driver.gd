extends GutTest
## Falls on the map (spec 2026-11-16-infantry-duel-animation-design.md; owner: 前排倒，后排补位):
## a lost group's fall is shown on a duellist, the removed figure walks up into
## its place, the body falls, holds and fades; a regroup frees as before.

const ART := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
	"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.25;HIT:0.1"}
const TUNE := {"steal": 0.0, "double": 0.0, "hit": 0.0, "rest_min": 0.2, "rest_max": 0.2, "open_max": 0.0,
	"reach_h": 30.0, "close_h": 0.6, "step_max_h": 1.0, "chain_lo": 0.1, "chain_hi": 0.2,
	"fall_hold": 2.0, "fall_fade": 1.5,
	"hitstop": 0.0, "knock_h": 0.15, "knock_out": 0.12, "knock_back": 0.35, "block_knock": 0.4, "near_m": 1000.0}


func _anim(clips: Array) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name: String in clips:
		var clip := Animation.new()
		clip.length = 1.0
		lib.add_animation(name, clip)
	anim.add_animation_library("", lib)
	return anim


## A group child as Map3DBattleGroups keeps it: a node holding its AnimationPlayer.
func _child(clips: Array) -> Dictionary:
	var node := Node3D.new()
	var anim := _anim(clips)
	node.add_child(anim)
	add_child_autofree(node)
	return {"node": node, "anims": [anim]}


func test_a_loss_drops_a_duellist_and_the_tail_steps_up() -> void:
	var c := {0: {"n": 0}, 1: {"n": 1}, 2: {"n": 2}, 5: {"n": 5}}
	var bodies := Map3DBattleGroups.fall_swap(c, [{"removed": 5, "faller": 1}])
	assert_eq(bodies, [{"n": 1}], "the duellist's figure is the body")
	assert_eq(c, {0: {"n": 0}, 1: {"n": 5, "step_up": true}, 2: {"n": 2}}, "the tail's figure now stands for the duellist's row")


func test_a_figure_with_no_duellist_falls_where_it_stands() -> void:
	var c := {0: {"n": 0}, 5: {"n": 5}}
	assert_eq(Map3DBattleGroups.fall_swap(c, [{"removed": 5, "faller": 5}]), [{"n": 5}])
	assert_eq(c, {0: {"n": 0}})


func test_only_a_loss_falls() -> void:
	var piece := {"sample_key": ["groups", [], 0, "", 2, 100], "groups": [{"count": 100}, {"count": 100}, {"count": 50}]}
	assert_true(Map3DBattleGroups.is_loss(piece, {"key": ["groups", [], 0, "", 2, 100], "rows": [{"count": 100}, {"count": 100}]}))
	assert_false(Map3DBattleGroups.is_loss(piece, {"key": ["groups", [], 0, "", 3, 100], "rows": [{"count": 100}]}),
		"a regroup to a new version is no loss")
	assert_false(Map3DBattleGroups.is_loss(piece, {"key": ["groups", [], 0, "", 2, 100], "rows": [{"count": 100}, {"count": 100}, {"count": 90}]}),
		"reinforced: no loss")
	assert_false(Map3DBattleGroups.is_loss({"groups": []}, {"key": ["groups", [], 0, "", 2, 100], "rows": []}), "a first sample")


func test_the_faller_is_a_duellist() -> void:
	var driver := Map3DDuelDriver.new()
	var a := [{"key": "A:1", "code": "A", "slot": 1, "anim": add_child_autofree(_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])),
		"child": {}, "xz": Vector2(0, 10), "h": 1.0, "art": ART, "piece": {}}]
	var b := [{"key": "B:0", "code": "B", "slot": 0, "anim": add_child_autofree(_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])),
		"child": {}, "xz": Vector2(0, -10), "h": 1.0, "art": ART, "piece": {}}]
	driver.run([{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": a, "b": b}], 0.05, true, TUNE)
	assert_eq(driver.plan_falls("A", [5], [0, 1, 2]), [{"removed": 5, "faller": 1}])
	assert_eq(driver.plan_falls("B", [3], [1, 2]), [{"removed": 3, "faller": 3}], "B:0 is not kept: no duellist to fall")


func test_the_body_falls_then_fades_and_is_freed() -> void:
	var driver := Map3DDuelDriver.new()
	var body := _child(["GARRISON", "DEATH"])
	driver.fall(body, ART, TUNE)
	assert_eq((body["anims"][0] as AnimationPlayer).current_animation, "DEATH")
	for i in 60:  # 3.0 s: the 1 s fall, then the 2 s hold from where it ends
		driver.run([], 0.05, true, TUNE)
	assert_almost_eq(float(body.get("alpha", 1.0)), 1.0, 0.0001, "it falls, then lies whole through its hold")
	for i in 15:  # 0.75 s into the fade
		driver.run([], 0.05, true, TUNE)
	assert_almost_eq(float(body["alpha"]), 0.5, 0.01, "half faded")
	for i in 30:
		driver.run([], 0.05, false, TUNE)
	assert_almost_eq(float(body["alpha"]), 0.5, 0.01, "a paused fall stands still")
	for i in 20:
		driver.run([], 0.05, true, TUNE)
	assert_true((body["node"] as Node3D).is_queued_for_deletion(), "gone once faded")


func test_the_tail_man_waits_while_the_body_falls_in_his_place() -> void:
	var driver := Map3DDuelDriver.new()
	var clips := ["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT", "DEATH"]
	var faller := _child(clips)
	var b := [{"key": "B:0", "code": "B", "slot": 0, "anim": add_child_autofree(_anim(clips)),
		"child": {}, "xz": Vector2(0, -10), "h": 1.0, "art": ART, "piece": {}}]
	var fig := func(child: Dictionary, piece: Dictionary) -> Array:
		return [{"key": "A:1", "code": "A", "slot": 1, "anim": child["anims"][0], "child": child,
			"xz": Vector2(0, 10), "h": 1.0, "art": ART, "piece": piece}]
	driver.run([{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": fig.call(faller, {}), "b": b}], 0.05, true, TUNE)
	driver.fall(faller, ART, TUNE)  # its row's figure is now the tail man, walking up
	var walker := _child(clips)
	walker["step_up"] = true
	walker["walk"] = {"to": {"xz": Vector2(0, 10)}, "t0": 0.0}
	var piece := {"clock": 5.0}
	var battle := [{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": fig.call(walker, piece), "b": b}]
	driver.run(battle, 0.05, true, TUNE)
	assert_eq(float(walker["walk"]["t0"]), 5.0, "he holds back while the body falls")
	for i in 21:  # past the 1 s fall: the body lies
		driver.run(battle, 0.05, true, TUNE)
	piece["clock"] = 9.0
	driver.run(battle, 0.05, true, TUNE)
	assert_eq(float(walker["walk"]["t0"]), 5.0, "he steps up once it lies")


func test_no_death_clip_frees_as_today() -> void:
	var driver := Map3DDuelDriver.new()
	var body := _child(["GARRISON"])
	driver.fall(body, ART, TUNE)
	assert_true((body["node"] as Node3D).is_queued_for_deletion())


## Review 2026-11-17: a duellist that falls as itself must not be released back to its piece's action.
func test_a_fallen_duellist_stays_down() -> void:
	var driver := Map3DDuelDriver.new()
	var body := _child(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT", "DEATH"])
	var fig_a := {"key": "A:1", "code": "A", "slot": 1, "anim": add_child_autofree(_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])),
		"child": {}, "xz": Vector2(0, 10), "h": 1.0, "art": ART, "piece": {"action": "ATTACK"}}
	var fig_b := {"key": "B:0", "code": "B", "slot": 0, "anim": body["anims"][0], "child": body, "xz": Vector2(0, -10),
		"h": 1.0, "art": ART, "piece": {"action": "ATTACK"}}
	driver.run([{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": [fig_a], "b": [fig_b]}], 0.05, true, TUNE)
	driver.fall(body, ART, TUNE)
	driver.run([{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": [fig_a], "b": []}], 0.05, true, TUNE)
	assert_eq((body["anims"][0] as AnimationPlayer).current_animation, "DEATH", "the body keeps falling")
	assert_false(driver.is_duelling(fig_a["anim"]), "its opponent is released")


## Review 2026-11-17: the figure stepping up from the tail turns into its way, never slides across the block.
func test_the_step_up_walker_turns_into_its_way() -> void:
	var driver := Map3DDuelDriver.new()
	var walker := {"step_up": true}
	var a := [{"key": "A:1", "code": "A", "slot": 1, "anim": add_child_autofree(_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])),
		"child": walker, "xz": Vector2(0, 10), "h": 1.0, "art": ART, "piece": {}}]
	var b := [{"key": "B:0", "code": "B", "slot": 0, "anim": add_child_autofree(_anim(["GARRISON", "ATTACK", "SLASH", "BLOCK", "HIT"])),
		"child": {}, "xz": Vector2(0, -10), "h": 1.0, "art": ART, "piece": {}}]
	driver.run([{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": a, "b": b}], 0.05, true, TUNE)
	assert_false(walker.get("step_facing", false), "its long walk up is an ordinary walk")
	assert_true(b[0]["child"].get("step_facing", false), "its opponent's short step still faces it")


func test_the_swap_marks_the_walker() -> void:
	var c := {1: {"n": 1}, 5: {"n": 5}}
	Map3DBattleGroups.fall_swap(c, [{"removed": 5, "faller": 1}])
	assert_true(c[1].get("step_up", false))
