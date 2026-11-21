extends GutTest
## Every blow lands (Map3DDuelDriver + Map3DImpact + Map3DImpactBursts; spec
## 2026-11-21-infantry-melee-scrum-design.md): at a turn's contact instant the
## pair freezes, the struck figure is knocked back, one impact is told, and a
## pooled burst shows. Times are binary-exact (1/16 s frames) so the contact
## lands on a frame: strike ATTACK 1.0 s meets at 0.5 s, the reply 0.5 s at its
## middle (0.25 s in) -> reply_at 0.25, contact_at 0.5, end 1.0.

const ART := {"duel": "STRIKE:ATTACK|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH", "contact": "ATTACK:0.5;BLOCK:0.5;HIT:0.5"}
const TUNE := {"steal": 0.0, "double": 0.0, "hit": 1.0, "rest_min": 0.25, "rest_max": 0.25,
	"reach_h": 30.0, "close_h": 0.6, "step_max_h": 1.0, "chain_lo": 0.1, "chain_hi": 0.2, "open_max": 0.0,
	"hitstop": 0.125, "knock_h": 0.15, "knock_out": 0.125, "knock_back": 0.25, "block_knock": 0.4, "near_m": 1000.0, "at_h": 0.6}
const DT := 0.0625
const KEY := "A:0|B:0"


func _anim() -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for spec: Array in [["GARRISON", 1.0, Animation.LOOP_LINEAR], ["ATTACK", 1.0, Animation.LOOP_NONE],
			["BLOCK", 0.5, Animation.LOOP_NONE], ["HIT", 0.5, Animation.LOOP_NONE]]:
		var clip := Animation.new()
		clip.length = spec[1]
		clip.loop_mode = spec[2]
		lib.add_animation(spec[0], clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func _fig(code: String, xz: Vector2) -> Dictionary:
	return {"key": "%s:0" % code, "code": code, "slot": 0, "anim": _anim(), "child": {},
		"xz": xz, "h": 2.0, "art": ART, "piece": {}}


func _battle(a: Array, b: Array) -> Array:
	return [{"id": 1, "rounds": 1, "across": Vector2(1, 0), "a": a, "b": b}]


func _speeds(a: Array, b: Array) -> Array:
	return [(a[0]["anim"] as AnimationPlayer).speed_scale, (b[0]["anim"] as AnimationPlayer).speed_scale]


## Runs until the turn's contact (8 frames: t 0.5); returns that frame's impacts.
func _to_contact(driver: Map3DDuelDriver, a: Array, b: Array, tune := TUNE) -> Array:
	for i in 7:
		driver.run(_battle(a, b), DT, true, tune)
		assert_eq(driver.take_impacts(), [], "no impact before contact (frame %d)" % i)
	driver.run(_battle(a, b), DT, true, tune)
	return driver.take_impacts()


func test_contact_freezes_the_pair() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	_to_contact(driver, a, b)
	assert_eq(_speeds(a, b), [0.0, 0.0], "both freeze at the contact instant")
	assert_almost_eq(driver.pair_time(KEY), 0.5, 0.0001)
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(_speeds(a, b), [0.0, 0.0], "still held 1/16 s in")
	assert_almost_eq(driver.pair_time(KEY), 0.5, 0.0001, "the turn clock stands with them")
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(_speeds(a, b), [1.0, 1.0], "the hold is over at hitstop")
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq(driver.pair_time(KEY), 0.5 + DT, 0.0001, "and the turn runs on")


func test_the_struck_figure_is_knocked_back() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	_to_contact(driver, a, b)
	assert_false((a[0]["child"] as Dictionary).has("knock_offset"), "the striker stands")
	driver.run(_battle(a, b), DT, true, TUNE)
	# halfway out: ease-out 0.75 x 0.15 x 2.0 = 0.225, away from the striker (b stands at -z)
	assert_almost_eq((b[0]["child"]["knock_offset"] as Vector2).y, -0.225, 0.0001)
	var placed := driver.run(_battle(a, b), DT, true, TUNE)
	assert_almost_eq((b[0]["child"]["knock_offset"] as Vector2).y, -0.3, 0.0001, "peak knock_h x h at knock_out")
	assert_almost_eq((b[0]["child"]["knock_offset"] as Vector2).x, 0.0, 0.0001)
	assert_true("B" in placed, "its piece is placed again while it is knocked")
	for i in 3:
		driver.run(_battle(a, b), DT, true, TUNE)
	assert_true(b[0]["child"].has("knock_offset"), "still coming back")
	placed = driver.run(_battle(a, b), DT, true, TUNE)
	assert_false(b[0]["child"].has("knock_offset"), "back on its stand at knock_out + knock_back")
	assert_true("B" in placed, "placed once more onto its stand")


func test_a_block_knocks_less() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var tune := TUNE.duplicate()
	tune["hit"] = 0.0
	var driver := Map3DDuelDriver.new()
	var impacts := _to_contact(driver, a, b, tune)
	assert_eq(String(impacts[0]["kind"]), "BLOCK")
	driver.run(_battle(a, b), DT, true, tune)
	driver.run(_battle(a, b), DT, true, tune)
	assert_almost_eq((b[0]["child"]["knock_offset"] as Vector2).y, -0.3 * 0.4, 0.0001, "a shield's jolt: block_knock of a hit's")


func test_contact_emits_one_impact() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	var impacts := _to_contact(driver, a, b)
	assert_eq(impacts.size(), 1)
	assert_eq(String(impacts[0]["kind"]), "HIT", "the reply's kind")
	assert_eq(String(impacts[0]["striker"]["key"]), "A:0")
	assert_eq(String(impacts[0]["struck"]["key"]), "B:0")
	assert_almost_eq((impacts[0]["at"] as Vector3).y, 1.2, 0.0001, "chest high: 0.6 of a figure height")
	assert_almost_eq((impacts[0]["at"] as Vector3).z, 0.0, 0.5, "between the two")
	var more := 0
	for i in 12:  # the rest of the turn (end 1.0 + rest 0.25, held 0.125): no second contact
		driver.run(_battle(a, b), DT, true, TUNE)
		more += driver.take_impacts().size()
	assert_eq(more, 0, "one impact per turn")
	assert_eq(driver.take_impacts(), [], "taken impacts are drained")


func test_a_far_pair_keeps_only_the_hitstop() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var tune := TUNE.duplicate()
	tune["eye"] = Vector3(0, 0, 5000)
	tune["near_m"] = 100.0
	var driver := Map3DDuelDriver.new()
	_to_contact(driver, a, b, tune)
	assert_eq(_speeds(a, b), [0.0, 0.0], "the hit-stop is kept far out")
	driver.run(_battle(a, b), DT, true, tune)
	driver.run(_battle(a, b), DT, true, tune)
	assert_false(b[0]["child"].has("knock_offset"), "no knock-back past near_m")


func test_bursts_are_capped() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var table := ArtTable.new()
	for kind: String in ["BLOCK", "HIT"]:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.draw_pass_1 = QuadMesh.new()
		var scene := PackedScene.new()
		scene.pack(p)
		p.free()
		table.art[kind] = scene
	var bursts := Map3DImpactBursts.new(parent, table, 12)
	for i in 12:
		assert_true(bursts.burst("HIT" if i % 2 == 0 else "BLOCK", Vector3(i, 0, 0)), "burst %d" % i)
	assert_eq(bursts.live_count(), 12)
	assert_true(bursts.burst("HIT", Vector3.ZERO, 2.0) == false, "still capped")
	(parent.get_child(0) as GPUParticles3D).finished.emit()
	assert_eq(bursts.live_count(), 11, "a burst burns until its one-shot has finished, not while `emitting`")
	assert_true(bursts.burst("HIT", Vector3.ZERO), "the finished one is restarted")
	assert_eq(parent.get_child_count(), 12, "from the pool, not made anew")
	assert_false(bursts.burst("HIT", Vector3.ZERO), "the 13th is refused at max_live")
	assert_false(bursts.burst("SMOKE", Vector3.ZERO), "a kind with no scene shows nothing")


func test_a_battle_ending_mid_impact_restores_the_figures() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	_to_contact(driver, a, b)
	driver.run(_battle(a, b), DT, true, TUNE)
	assert_eq(_speeds(a, b), [0.0, 0.0], "held")
	assert_true(b[0]["child"].has("knock_offset"), "knocked")
	var placed := driver.run([], DT, true, TUNE)
	assert_eq(_speeds(a, b), [1.0, 1.0], "no figure stays frozen")
	assert_false(b[0]["child"].has("knock_offset"), "nor displaced")
	assert_false(a[0]["child"].has("knock_offset"))
	assert_true("B" in placed)


func test_a_pause_inside_the_hitstop_keeps_its_remainder() -> void:
	var a := [_fig("A", Vector2(0, 10))]
	var b := [_fig("B", Vector2(0, -10))]
	var driver := Map3DDuelDriver.new()
	_to_contact(driver, a, b)
	driver.run(_battle(a, b), DT, true, TUNE)  # 1/16 s of the 1/8 s hold gone
	for i in 20:
		driver.run(_battle(a, b), DT, false, TUNE)
	assert_eq(_speeds(a, b), [0.0, 0.0], "paused: still")
	driver.run(_battle(a, b), DT / 2.0, true, TUNE)
	assert_eq(_speeds(a, b), [0.0, 0.0], "1/32 s of the remaining 1/16 s")
	driver.run(_battle(a, b), DT / 2.0, true, TUNE)
	assert_eq(_speeds(a, b), [1.0, 1.0], "the remainder finished, not a fresh hold")
	assert_almost_eq(driver.pair_time(KEY), 0.5, 0.0001)


func test_the_authored_bursts_are_one_shots() -> void:
	var table := GameArt.table(GameArt.IMPACT_BURSTS)
	assert_not_null(table, "the burst table is authored")
	for kind: String in ["BLOCK", "HIT"]:
		var node := (table.of(kind) as PackedScene).instantiate() as GPUParticles3D
		assert_not_null(node, kind + " is a GPUParticles3D scene")
		assert_true(node.one_shot and not node.emitting, kind + " waits as a one-shot")
		assert_true(node.local_coords, kind + " scales with its node (figure heights)")
		node.free()


func test_a_burst_takes_its_size() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var bursts := Map3DImpactBursts.new(parent, GameArt.table(GameArt.IMPACT_BURSTS), 4)
	assert_true(bursts.burst("BLOCK", Vector3(1, 2, 3), 2.5))
	var node := parent.get_child(0) as GPUParticles3D
	var authored: Vector2 = ((GameArt.table(GameArt.IMPACT_BURSTS).of("BLOCK") as PackedScene).instantiate().draw_pass_1 as QuadMesh).size
	assert_eq(node.scale, Vector3.ONE * 2.5, "its spread and speed")
	assert_eq((node.draw_pass_1 as QuadMesh).size, authored * 2.5, "and its particles (a node's scale never reaches them)")
	assert_true(bursts.burst("BLOCK", Vector3.ZERO, 1.0))
	assert_eq(((parent.get_child(1) as GPUParticles3D).draw_pass_1 as QuadMesh).size, authored, "each node its own quad")
	assert_eq(node.global_position, Vector3(1, 2, 3))
	assert_null(node.owner, "a save never writes it")
