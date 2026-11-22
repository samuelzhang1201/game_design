extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A marching piece's loop (Map3DUnitSound; owner 2026-10-13): loudness by the
## camera's distance, the nearest few only, every arm with a model has a loop.


func _repo() -> DataRepository:
	var repo := SuiteData.repo()
	repo.balance["map3d_unit_sound_near_m"] = 1000.0
	repo.balance["map3d_unit_sound_far_m"] = 11000.0
	repo.balance["map3d_unit_sound_db"] = -4.0
	repo.balance["map3d_unit_sound_floor_db"] = -24.0
	repo.balance["map3d_unit_sound_voices"] = 2.0
	repo.balance["map3d_unit_sound_fade_db_s"] = 1000.0
	return repo


func test_loudness_falls_from_near_to_far_then_silence() -> void:
	var repo := _repo()
	assert_almost_eq(Map3DUnitSound.gain_db(repo, 400.0), -4.0, 0.001, "inside near: full")
	assert_almost_eq(Map3DUnitSound.gain_db(repo, 1000.0), -4.0, 0.001)
	# (6000 - 1000) / 10000 = 0.5 of the way from -4 to -24
	assert_almost_eq(Map3DUnitSound.gain_db(repo, 6000.0), -14.0, 0.001)
	assert_almost_eq(Map3DUnitSound.gain_db(repo, 11000.0), -24.0, 0.001)
	assert_eq(Map3DUnitSound.gain_db(repo, 11001.0), Map3DUnitSound.SILENT_DB, "past far: silent")


func test_only_the_nearest_within_far_sound_ties_by_code() -> void:
	var dists := {"c": 300.0, "a": 900.0, "b": 300.0, "far": 20000.0}
	assert_eq(Map3DUnitSound.voiced(dists, 2, 11000.0), ["b", "c"])
	assert_eq(Map3DUnitSound.voiced(dists, 9, 11000.0), ["b", "c", "a"], "the far one never")
	assert_eq(Map3DUnitSound.voiced(dists, 0, 11000.0), [])


func test_every_arm_with_a_model_marches_to_a_looping_sound() -> void:
	var repo := SuiteData.repo()
	for piece: String in repo.army_art:
		if GameArt.path(GameArt.ARMY_MODELS, piece) == "":
			continue  # a fleet: no piece, no march
		var stream := Map3DUnitSound.sound_of({"model": piece}) as AudioStreamWAV
		assert_not_null(stream, piece)
		if stream != null:
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, piece)


func test_marching_pieces_sound_and_fall_silent_when_they_halt() -> void:
	var repo := _repo()
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	var pieces: Dictionary = {}
	for i in 3:  # three marching infantry, 500 / 2000 / 4000 m out; two voices
		var node := Node3D.new()
		root.add_child(node)
		node.position = Vector3(0, 0, -[500.0, 2000.0, 4000.0][i])
		pieces["r%d" % i] = {"node": node, "model": "infantry", "action": Map3DLayerUnits.MARCH}
	var sound := Map3DUnitSound.new()
	sound.sync(repo, cam, pieces, 1.0)
	assert_eq(sound.playing_count(), 2, "the two nearest")
	var p0: AudioStreamPlayer3D = (pieces["r0"]["node"] as Node3D).get_node("MarchSound")
	assert_almost_eq(p0.volume_db, -4.0, 0.001, "inside near: full")
	# 2000 m: (2000 - 1000) / 10000 = 0.1 → -4 - 2 = -6
	var p1: AudioStreamPlayer3D = (pieces["r1"]["node"] as Node3D).get_node("MarchSound")
	assert_almost_eq(p1.volume_db, -6.0, 0.001)
	assert_false((pieces["r2"]["node"] as Node3D).has_node("MarchSound"), "the third waits")
	pieces["r0"]["action"] = Map3DLayerUnits.STANDBY  # it halts: the third takes its voice
	sound.sync(repo, cam, pieces, 1.0)
	await wait_process_frames(1)
	assert_false((pieces["r0"]["node"] as Node3D).has_node("MarchSound"), "faded out and freed")
	assert_true((pieces["r2"]["node"] as Node3D).has_node("MarchSound"))
	sound.silence()
	await wait_process_frames(1)
	assert_eq(sound.playing_count(), 0)


func test_a_piece_rebuilt_under_its_code_gets_a_fresh_loop() -> void:
	# The piece's node is freed (its model swapped, the layer rebuilt) while the
	# march goes on: the old player went with it, the next sync must not trip on it.
	var repo := _repo()
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	var old := Node3D.new()
	root.add_child(old)
	old.position = Vector3(0, 0, -500.0)
	var gone := Node3D.new()  # a second piece, disbanded the same frame
	root.add_child(gone)
	var pieces := {"r0": {"node": old, "model": "infantry", "action": Map3DLayerUnits.MARCH},
		"r1": {"node": gone, "model": "infantry", "action": Map3DLayerUnits.MARCH}}
	var sound := Map3DUnitSound.new()
	sound.sync(repo, cam, pieces, 1.0)
	assert_eq(sound.playing_count(), 2)
	old.free()
	gone.free()
	var fresh := Node3D.new()
	root.add_child(fresh)
	fresh.position = Vector3(0, 0, -500.0)
	pieces = {"r0": {"node": fresh, "model": "infantry", "action": Map3DLayerUnits.MARCH}}
	sound.sync(repo, cam, pieces, 1.0)
	assert_true(fresh.has_node("MarchSound"), "a new loop on the new node")
	assert_eq(sound.playing_count(), 1)
	sound.silence()


## A duel's blow (spec 2026-11-21-infantry-melee-scrum-design.md, step 4): one
## contact told by Map3DDuelDriver.take_impacts, `count` of them, struck figures `dist` m out.
func _blows(root: Node3D, kind: String, count: int, dist: float) -> Array:
	var out: Array = []
	for i in count:
		var node := Node3D.new()
		root.add_child(node)
		node.position = Vector3(0, 0, -dist)
		out.append({"kind": kind, "at": node.position, "striker": {}, "struck": {"child": {"node": node}}})
	return out


func _impact_repo() -> DataRepository:
	var repo := _repo()
	repo.balance["map3d_impact_db"] = -3.0
	repo.balance["map3d_impact_voices"] = 6.0
	return repo


func test_an_impact_plays_its_kind() -> void:
	var repo := _impact_repo()
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	var blows := _blows(root, "HIT", 1, 2000.0) + _blows(root, "BLOCK", 1, 500.0)
	var sound := Map3DUnitSound.new()
	sound.play_impacts(repo, cam, blows)
	var hit: AudioStreamPlayer3D = (blows[0]["struck"]["child"]["node"] as Node3D).get_node("ImpactSound")
	assert_not_null(Map3DUnitSound.impact_sound_of("HIT"), "the table has a HIT")
	assert_eq(hit.stream, Map3DUnitSound.impact_sound_of("HIT"), "on the struck figure's node")
	# 2000 m: gain -6 (as the march), + map3d_impact_db -3
	assert_almost_eq(hit.volume_db, -9.0, 0.001)
	var block: AudioStreamPlayer3D = (blows[1]["struck"]["child"]["node"] as Node3D).get_node("ImpactSound")
	assert_eq(block.stream, Map3DUnitSound.impact_sound_of("BLOCK"))
	assert_ne(block.stream, hit.stream, "a clash is not a thud")


func test_impacts_are_capped() -> void:
	var repo := _impact_repo()
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	var stream := AudioStreamWAV.new()
	var node := Node3D.new()
	root.add_child(node)
	assert_not_null(Map3DUnitSound.impact(repo, cam, node, stream, 5), "the 6th voice plays")
	assert_null(Map3DUnitSound.impact(repo, cam, node, stream, 6), "the 7th live is refused")
	var sound := Map3DUnitSound.new()
	sound.play_impacts(repo, cam, _blows(root, "HIT", 4, 500.0))
	sound.play_impacts(repo, cam, _blows(root, "BLOCK", 4, 500.0))  # the first four still sound
	assert_eq(root.find_children("ImpactSound", "AudioStreamPlayer3D", true, false).size(), 6 + 1)


func test_far_impacts_are_silent() -> void:
	var repo := _impact_repo()
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	var sound := Map3DUnitSound.new()
	sound.play_impacts(repo, cam, _blows(root, "HIT", 1, 11001.0))  # past map3d_unit_sound_far_m
	assert_eq(root.find_children("ImpactSound", "AudioStreamPlayer3D", true, false).size(), 0)
