extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A halt into GARRISON lands on a footfall (Map3DUnitSettle; owner 2026-10-14:
## 转驻防的时候加入Equip.wav的音效，注意节奏要和步伐相符), the cavalry gallops
## (owner 2026-10-14: 所有骑兵前进的音效换成Horse Gallop Loop.wav), and the
## infantry's GARRISON loops without a jump (owner 2026-10-14: 驻防动画会有跳帧卡顿).

const STEPS := [0.14, 0.43, 0.64, 0.90]


func test_the_wait_is_to_the_first_footfall_far_enough_for_the_clank() -> void:
	# at share 0.5 of a 2 s clip: 0.64 is (0.64 - 0.5) x 2 = 0.28 s off, past a 0.25 s lead
	assert_almost_eq(Map3DUnitSettle.wait_s(0.5, 2.0, 1.0, STEPS, 0.25), 0.28, 0.0001)
	# a 0.3 s lead skips it: 0.90 is (0.9 - 0.5) x 2 = 0.8 s off
	assert_almost_eq(Map3DUnitSettle.wait_s(0.5, 2.0, 1.0, STEPS, 0.3), 0.8, 0.0001)
	# at twice the speed 0.64 is 0.14 s off and 0.90 0.4 s: 0.4 is the first past 0.25
	assert_almost_eq(Map3DUnitSettle.wait_s(0.5, 2.0, 2.0, STEPS, 0.25), 0.4, 0.0001)
	# past the last step it wraps to the next lap: (1.14 - 0.95) x 2 = 0.38
	assert_almost_eq(Map3DUnitSettle.wait_s(0.95, 2.0, 1.0, STEPS, 0.25), 0.38, 0.0001)
	assert_eq(Map3DUnitSettle.wait_s(0.5, 2.0, 1.0, [], 0.25), INF, "no steps: no wait")


func test_steps_parse_sorted_from_the_row() -> void:
	assert_eq(Map3DUnitSettle.steps_of({"steps": "0.43;0.14"}), [0.14, 0.43])
	assert_eq(Map3DUnitSettle.steps_of({"steps": ""}), [])
	assert_eq(Map3DUnitSettle.steps_of({}), [])


func test_the_infantry_settles_on_its_steps_with_a_sound_that_does_not_loop() -> void:
	var repo := SuiteData.repo()
	assert_eq(Map3DUnitSettle.steps_of(repo.army_art["infantry"]).size(), 2, "one left and one right footfall a loop")
	var stream := Map3DUnitSound.settle_sound_of({"model": "infantry"}) as AudioStreamWAV
	assert_not_null(stream)
	if stream != null:
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
		assert_gt(stream.get_length(), repo.bal("map3d_unit_settle_hit_s"), "the clank is inside the file")


func test_the_horsed_arms_march_to_the_gallop() -> void:
	for piece: String in ["cavalry", "royal"]:
		var stream := Map3DUnitSound.sound_of({"model": piece})
		assert_true(stream != null and stream.resource_path.ends_with("march_gallop.wav"), piece)


func _marching_piece(at_s: float) -> Dictionary:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 2.0
	clip.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("MARCH", clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	anim.play("MARCH")
	anim.seek(at_s, true)
	return {"anims": [anim], "steps": STEPS, "action": Map3DLayerUnits.MARCH}


func test_a_halt_into_garrison_is_held_once_and_dropped_on_a_new_march() -> void:
	var repo := SuiteData.repo()
	repo.balance["map3d_unit_settle_hit_s"] = 0.25
	var settle := Map3DUnitSettle.new()
	var piece := _marching_piece(1.0)
	assert_true(settle.holds(repo, "r", piece, Map3DLayerUnits.GARRISON), "held for the footfall")
	assert_true(piece.get("settling", false), "its figures keep their pace")
	assert_true(settle.holds(repo, "r", piece, Map3DLayerUnits.GARRISON), "still held, not restarted")
	assert_eq(settle.pending_count(), 1)
	settle.cancel("r", piece)
	assert_eq(settle.pending_count(), 0)
	assert_false(piece.has("settling"))
	assert_false(settle.holds(repo, "r", piece, Map3DLayerUnits.STANDBY), "only GARRISON is held")
	piece["steps"] = []
	assert_false(settle.holds(repo, "r", piece, Map3DLayerUnits.GARRISON), "no steps: at once")


func test_a_settling_piece_keeps_its_pace() -> void:
	var repo := SuiteData.repo()
	var piece := _marching_piece(0.0)
	var anim: AnimationPlayer = piece["anims"][0]
	anim.speed_scale = 3.0
	piece["settling"] = true
	var day := {"from": Vector2.ZERO, "to": Vector2.ZERO, "s0": 0.0}
	Map3DUnitRig.keep_pace(repo, piece, day, 0.5, 1, "r")
	assert_eq(anim.speed_scale, 3.0, "held at the march's pace, not reset to 1")


func test_the_infantry_garrison_and_standby_loop_without_a_seam() -> void:
	var root := (load("res://assets/3D/units/infantry/infantry.glb") as PackedScene).instantiate()
	var anim := Map3DUnits.find_anim(root)
	for action: String in ["GARRISON", "STANDBY"]:
		var clip := anim.get_animation(Map3DUnits.clip_named(anim, action))
		assert_eq(clip.loop_mode, Animation.LOOP_LINEAR, action)
		var worst := 0.0
		for t in clip.get_track_count():
			var n := clip.track_get_key_count(t)
			if clip.track_get_type(t) == Animation.TYPE_ROTATION_3D and n > 1:
				var a: Quaternion = clip.track_get_key_value(t, 0)
				var b: Quaternion = clip.track_get_key_value(t, n - 1)
				worst = maxf(worst, rad_to_deg(a.angle_to(b)))
		assert_lt(worst, 0.5, "%s: first and last frames meet (tools/units3d/loop_seam.py)" % action)
	root.free()
