extends GutTest
## The archers in the duel (owner 2026-11-28: 把弓手的被击中和死亡接进战斗): their
## `duel` row names HIT and DEATH only, so a foe that strikes pairs with an archer
## and every blow lands as a HIT, an archer never strikes, archers against
## archers never pair, and a lost archer falls with DEATH (Map3DDuel.duels).

const SuiteData := preload("res://tests/suite_data.gd")
const FOOT := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
	"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.25;HIT:0.1"}
const TUNE := {"steal": 0.0, "double": 0.0, "hit": 0.0, "rest_min": 0.2, "rest_max": 0.2,
	"reach_h": 30.0, "close_h": 0.6, "step_max_h": 1.0, "chain_lo": 0.1, "chain_hi": 0.2, "open_max": 0.0,
	"fall_hold": 2.0, "fall_fade": 1.5,
	"hitstop": 0.0, "knock_h": 0.15, "knock_out": 0.12, "knock_back": 0.35, "block_knock": 0.4, "near_m": 1000.0}
const DT := 0.05


func _anim(clips: Array) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name: String in clips:
		var clip := Animation.new()
		clip.length = 0.8
		lib.add_animation(name, clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func _fig(code: String, slot: int, xz: Vector2, art: Dictionary) -> Dictionary:
	var clips := ["GARRISON", "MARCH", "ATTACK", "SLASH", "BLOCK", "HIT", "HIT_2", "HIT_3", "DEATH"]
	return {"key": "%s:%d" % [code, slot], "code": code, "slot": slot, "anim": _anim(clips), "child": {},
		"xz": xz, "h": 1.0, "art": art, "piece": {"action": "ATTACK"}}


func _battle(a: Array, b: Array) -> Array:
	return [{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": a, "b": b}]


func test_the_installed_archer_takes_blows_and_falls() -> void:
	var art: Dictionary = SuiteData.repo().army_art["archers"]
	var root := (load("res://assets/3D/units/archers/archers.glb") as PackedScene).instantiate()
	add_child_autofree(root)
	var anim := Map3DUnits.find_anim(root)
	assert_true(Map3DDuel.duels(art, anim), "every HIT clip installed with its contact share")
	assert_false(Map3DDuel.strikes(art), "an archer has no melee blow")
	assert_false(Map3DClipChain.of_column(art, "duel").has("BLOCK"), "no parry: DODGE is not a BLOCK")
	assert_ne(Map3DUnits.clip_named(anim, "DEATH"), "", "a lost archer falls")
	for clip: String in Map3DDuel.contact_of(art):
		var share := float(Map3DDuel.contact_of(art)[clip])
		assert_true(share > 0.0 and share < 1.0, "%s lands inside its clip" % clip)


func test_a_striking_foe_hits_the_archer_every_turn() -> void:
	var archers: Dictionary = SuiteData.repo().army_art["archers"]
	var a := [_fig("B", 0, Vector2(0, 10), archers)]  # the archers attack: turn 0 is theirs, yet they never strike
	var b := [_fig("F", 0, Vector2(0, -10), FOOT)]
	var driver := Map3DDuelDriver.new()
	var archer_clips: Dictionary = {}
	var foot_clips: Dictionary = {}
	for i in 120:  # 6 s: several turns, the strikers alternating
		driver.run(_battle(a, b), DT, true, TUNE)
		archer_clips[(a[0]["anim"] as AnimationPlayer).current_animation] = true
		foot_clips[(b[0]["anim"] as AnimationPlayer).current_animation] = true
	assert_true(driver.is_duelling(a[0]["anim"]), "the archer is paired with the foe that strikes")
	assert_true(archer_clips.has("HIT") or archer_clips.has("HIT_2") or archer_clips.has("HIT_3"), "the archer takes the blow")
	for clip: String in ["ATTACK", "SLASH", "BLOCK"]:
		assert_false(archer_clips.has(clip), "the archer never plays %s in the duel" % clip)
	assert_true(foot_clips.has("ATTACK") or foot_clips.has("SLASH"), "the foe strikes")
	assert_false(foot_clips.has("HIT") or foot_clips.has("BLOCK"), "and is never struck back")


func test_archers_against_archers_keep_their_blocks() -> void:
	var archers: Dictionary = SuiteData.repo().army_art["archers"]
	var a := [_fig("B", 0, Vector2(0, 10), archers)]
	var b := [_fig("C", 0, Vector2(0, -10), archers)]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_false(driver.is_duelling(a[0]["anim"]) or driver.is_duelling(b[0]["anim"]), "no one strikes: no pair, no guard")


func test_an_unpaired_archer_keeps_its_action() -> void:
	var archers: Dictionary = SuiteData.repo().army_art["archers"]
	var a := [_fig("F", 0, Vector2(0, 10), FOOT)]
	var b := [_fig("B", 0, Vector2(-10, -10), archers), _fig("B", 1, Vector2(0, -10), archers), _fig("B", 2, Vector2(10, -10), archers)]
	var driver := Map3DDuelDriver.new()
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(driver.paired_slots("B"), [1] as Array[int], "the one opposite pairs")
	assert_false(driver.is_duelling(b[0]["anim"]) or driver.is_duelling(b[2]["anim"]),
		"the archers left over are not claimed to guard: they keep shooting")


func test_a_lost_archer_falls_with_death() -> void:
	var archers: Dictionary = SuiteData.repo().army_art["archers"]
	var node := Node3D.new()
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name: String in ["GARRISON", "DEATH"]:
		var clip := Animation.new()
		clip.length = 1.0
		lib.add_animation(name, clip)
	anim.add_animation_library("", lib)
	node.add_child(anim)
	add_child_autofree(node)
	var driver := Map3DDuelDriver.new()
	driver.fall({"node": node, "anims": [anim]}, archers, TUNE)
	assert_eq(anim.current_animation, "DEATH")
	assert_false(node.is_queued_for_deletion(), "it lies, then fades, rather than vanishing")
