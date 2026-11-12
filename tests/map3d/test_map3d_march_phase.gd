extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The MARCH distance-to-phase map (Map3DMarchPhase, LOCO-CAV-PHASE). The hand
## fixture is the cavalry contract's synthetic f with knots (0,0), (.5,1), (1,3)
## (cavalry-march-contact-prerequisite.md, "Concrete distance-map construction"),
## never a production gait.

const FIXTURE := "0:0;0.5:1;1:3"

var repo: DataRepository
var knots: PackedFloat64Array


func before_all() -> void:
	repo = SuiteData.repo()
	knots = Map3DMarchPhase.of_art({"phase_map": FIXTURE})


## By hand: from z0 .25 (F = .5), 1.5 m reaches F 2 = phase .75; 3 m reaches F 3.5,
## one loop (3) and .5 on = 1.25; from .75 (F 2), 1 m is F 3 = exactly the loop, z 1.
func test_the_contract_fixture_inverts_by_hand() -> void:
	assert_eq(knots.size(), 6)
	assert_almost_eq(Map3DMarchPhase.loop_m(knots), 3.0, 1e-12)
	assert_almost_eq(Map3DMarchPhase.distance_at(knots, 0.25), 0.5, 1e-12)
	assert_almost_eq(Map3DMarchPhase.distance_at(knots, 1.75), 5.0, 1e-12)
	assert_almost_eq(Map3DMarchPhase.phase_after(knots, 0.25, 1.5), 0.75, 1e-12)
	assert_almost_eq(Map3DMarchPhase.phase_after(knots, 0.25, 3.0), 1.25, 1e-12)
	assert_almost_eq(Map3DMarchPhase.phase_after(knots, 0.75, 1.0), 1.0, 1e-12)
	assert_almost_eq(Map3DMarchPhase.phase_after(knots, 0.75, 0.0), 0.75, 1e-12)


## With no step the rate is the loop's mean: a 1 m/s model speed on a 2 s clip over a
## 3 m loop plays 2 / 3, wherever the figure stands (a near-flat segment's slope
## would fling the clip).
func test_the_rate_with_no_step_is_the_loop_mean() -> void:
	assert_almost_eq(Map3DMarchPhase.rate(knots, 0.5, 1.0, 0.0, 2.0), 2.0 / 3.0, 1e-12)
	assert_almost_eq(Map3DMarchPhase.rate(knots, 0.4, 1.0, 0.0, 2.0), 2.0 / 3.0, 1e-12)
	assert_eq(Map3DMarchPhase.rate(knots, 0.4, 0.0, 0.1, 2.0), 0.0, "no speed, no phase")


## Over a step the rate is the map's exact secant: from .4 (F .8), 0.4 m reaches F 1.2,
## phase .5 + .2 / 4 = .55, i.e. .15 of the 2 s clip in .1 s = 3.
func test_the_rate_over_a_step_crosses_a_knot_exactly() -> void:
	assert_almost_eq(Map3DMarchPhase.rate(knots, 0.4, 4.0, 0.1, 2.0), 3.0, 1e-9)


func test_a_malformed_map_is_no_map() -> void:
	for text: String in ["", "0:0", "0:0;1:0", "0.1:0;1:3", "0:0;0.5:1;0.9:3", "0:0;0.5:2;1:1", "0:0;x:1;1:3"]:
		assert_true(Map3DMarchPhase.of_art({"phase_map": text}).is_empty(), text)


## A phase-mapped piece plays each figure at its own secant, unclamped and without
## jitter. By hand: k 10, a day of 100 x time_day_seconds world m walks 100 world
## m/s = 10 model m/s, a .05 s step = .5 m. A figure
## at phase .25 (F .5) reaches F 1 = .5: .25 of the 2 s clip in .05 s = 10. One at .5
## (F 1) reaches F 1.5 = .5 + .5 / 4 = .625: .125 x 2 / .05 = 5.
func test_keep_pace_drives_each_figure_by_the_map() -> void:
	var node := Node3D.new()
	node.scale = Vector3.ONE * 10.0
	add_child_autofree(node)
	var anims: Array = []
	for start: float in [0.5, 1.0]:
		var a := AnimationPlayer.new()
		var lib := AnimationLibrary.new()
		var clip := Animation.new()
		clip.length = 2.0
		clip.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("MARCH", clip)
		a.add_animation_library("", lib)
		node.add_child(a)
		a.play("MARCH")
		a.seek(start, true)
		anims.append(a)
	var piece := {"node": node, "anims": anims, "clip_s": 2.0, "stride_m": 4.0, "exact_pace": false,
		"phase_map": knots}
	var day := {"from": Vector2.ZERO, "to": Vector2(100.0 * repo.bal("time_day_seconds"), 0.0), "s0": 0.0}
	Map3DUnitRig.keep_pace(repo, piece, day, 0.1, 1, "R1", 0.05)
	assert_almost_eq((anims[0] as AnimationPlayer).speed_scale, 10.0, 1e-6)
	assert_almost_eq((anims[1] as AnimationPlayer).speed_scale, 5.0, 1e-6)
	Map3DUnitRig.keep_pace(repo, piece, {"from": Vector2.ZERO, "to": Vector2.ZERO, "s0": 0.0}, 0.1, 1, "R1", 0.05)
	assert_eq((anims[0] as AnimationPlayer).speed_scale, 1.0, "at rest it plays as authored")


## No installed arm needs a map: the re-authored cavalry MARCH (LOCO-CAV-MARCH, owner ruling
## 2026-11-13) holds each planted hoof at the canter's own constant 2.4 model m a loop, so it is
## paced by stride_m like every other arm.
func test_no_installed_arm_carries_a_phase_map() -> void:
	for piece: String in repo.army_art:
		assert_true(Map3DMarchPhase.of_art(repo.army_art[piece]).is_empty(), piece)
	assert_almost_eq(float(repo.army_art["cavalry"]["stride_m"]), 2.4, 1e-9)


## The candidate consumer's per-figure rate (Map3DUnitRig.mapped_rate): before MARCH is the
## current clip it starts from the phase play() will seek (here .25 -> 10, as above); on
## MARCH at .5 s of a 2 s clip (phase .25) the same; at 1 s (phase .5), 5.
func test_mapped_rate_reads_the_figure_phase_or_its_start() -> void:
	var a := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 2.0
	clip.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("MARCH", clip)
	lib.add_animation("GARRISON", clip.duplicate())
	a.add_animation_library("", lib)
	add_child_autofree(a)
	a.play("GARRISON")
	assert_almost_eq(Map3DUnitRig.mapped_rate(a, knots, 2.0, 10.0, 0.05, 0.25), 10.0, 1e-6)
	a.play("MARCH")
	a.seek(1.0, true)
	assert_almost_eq(Map3DUnitRig.mapped_rate(a, knots, 2.0, 10.0, 0.05, 0.25), 5.0, 1e-6)
