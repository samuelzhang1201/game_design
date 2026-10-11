extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A group's figures do not step off in lock-step (owner 2026-10-12): the start
## delay and gait jitter are hashed from regiment id + figure index, so they are
## reproducible, differ per figure, and stay inside the balance ranges.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_same_ids_give_the_same_offset() -> void:
	for i in 6:
		assert_eq(Map3DUnitRig.march_delay_s(repo, "reg_a", i), Map3DUnitRig.march_delay_s(repo, "reg_a", i))
		assert_eq(Map3DUnitRig.pace_jitter(repo, "reg_a", i), Map3DUnitRig.pace_jitter(repo, "reg_a", i))


func test_figures_differ_within_the_range() -> void:
	var max_s := repo.bal("map3d_march_desync_max_s")
	var spread := repo.bal("map3d_march_desync_pace")
	var delays := {}
	var paces := {}
	for i in 12:
		var d := Map3DUnitRig.march_delay_s(repo, "reg_a", i)
		var p := Map3DUnitRig.pace_jitter(repo, "reg_a", i)
		assert_between(d, 0.0, max_s, "delay in range")
		assert_between(p, 1.0 - spread, 1.0 + spread, "pace in range")
		delays[d] = true
		paces[p] = true
	assert_gt(delays.size(), 6, "the figures do not share one delay")
	assert_gt(paces.size(), 6, "the figures do not share one pace")


func test_another_regiment_gets_other_offsets() -> void:
	var same := 0
	for i in 8:
		if Map3DUnitRig.march_delay_s(repo, "reg_a", i) == Map3DUnitRig.march_delay_s(repo, "reg_b", i):
			same += 1
	assert_lt(same, 8, "the offsets follow the regiment id too")
