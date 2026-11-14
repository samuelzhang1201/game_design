extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The contact scan runs once per tactical substep of every day, over every
## crown unit against every foe: it must not pay the town check per pair.


func test_a_quiet_scan_costs_far_less_than_a_town_check_per_pair() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 11)
	assert_gt(state.foes.size(), 0, "the campaign raises the hosts")
	BattleSystem.detect_contacts(repo, state)   # warm the grids and the roster
	assert_eq(state.battles.size(), 0, "nobody is in contact as the reign opens")
	var mine: Array = state.regiments.keys()
	var theirs: Array = state.foes.keys()
	var t0 := Time.get_ticks_usec()
	for f: String in theirs:
		for p: String in mine:
			BattleSystem.town_contact(repo, state, ArmyGround.garrison_town(repo, state, p), f)
	var per_pair := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	BattleSystem.detect_contacts(repo, state)
	var scan := Time.get_ticks_usec() - t0
	assert_lt(scan * 3, per_pair, "scan %d us, a town check per pair %d us" % [scan, per_pair])
