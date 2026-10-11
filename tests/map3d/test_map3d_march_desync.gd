extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A group's figures do not march in lock-step (owner 2026-10-12, R5): each
## starts its clip at a hashed phase, jitters its pace (clamped after), and trails
## its slot by a lag spring. No timers: everything is hashed from regiment id +
## figure index, reproducible, and inside the balance ranges.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _anim() -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name in ["MARCH", "STANDBY"]:
		var a := Animation.new()
		a.length = 2.0
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(name, a)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func test_phase_hashed_in_range_and_stable() -> void:
	var seen := {}
	for i in 9:
		var p := Map3DMarchLag.phase("reg_a", i)
		assert_eq(p, Map3DMarchLag.phase("reg_a", i), "stable")
		assert_true(p >= 0.0 and p < 1.0, "in [0,1)")
		seen[p] = true
	assert_gte(seen.size(), 6, "the figures do not share one phase")


func test_play_march_starts_now_at_its_phase() -> void:
	var anims: Array = [_anim(), _anim(), _anim()]
	Map3DUnitRig.play(anims, "MARCH", 0.0, "reg_a")
	for i in 3:
		var anim: AnimationPlayer = anims[i]
		assert_eq(anim.current_animation, "MARCH", "no waiting on a timer")
		assert_almost_eq(anim.current_animation_position, Map3DMarchLag.phase("reg_a", i) * 2.0, 0.001)


func test_jitter_never_exceeds_anim_max() -> void:
	var lo := repo.bal("map3d_unit_anim_min")
	var hi := repo.bal("map3d_unit_anim_max")
	var spread := repo.bal("map3d_march_desync_pace")
	for i in 12:
		assert_lte(Map3DMarchLag.pace("reg_a", i, hi, spread, lo, hi), hi, "clamped after the jitter")
		assert_gte(Map3DMarchLag.pace("reg_a", i, lo, spread, lo, hi), lo)
	var paces := {}
	for i in 12:
		paces[Map3DMarchLag.pace("reg_a", i, 1.0, spread, lo, hi)] = true
	assert_gte(paces.size(), 6, "the figures do not share one pace")


func test_tau_in_the_balance_range() -> void:
	var a := repo.bal("map3d_march_lag_min_s")
	var b := repo.bal("map3d_march_lag_max_s")
	for i in 9:
		assert_between(Map3DMarchLag.tau("reg_a", i, a, b), a, b)


func test_lag_spring_by_hand() -> void:
	# tau 0.5, v (2,0,0), dt 0.5: e^-1 = 0.367879, so each step is
	# o*0.367879 - 1.0*0.632121 -> -0.632121, -0.864665, -0.950213
	var v := Vector3(2, 0, 0)
	var o := Map3DMarchLag.step(Vector3.ZERO, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.632121, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.864665, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.950213, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 0.9)
	assert_almost_eq(o.length(), 0.9, 0.00001, "held to the cap")
	assert_lt(o.x, 0.0, "behind its slot")
	# standing: the offset relaxes by e^-1 a step
	assert_almost_eq(Map3DMarchLag.step(Vector3(-1, 0, 0), Vector3.ZERO, 0.5, 0.5, 5.0).x, -0.367879, 0.00001)
