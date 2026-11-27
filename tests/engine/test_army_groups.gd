extends GutTest
## Armies as selection groups (spec 2026-11-27-army-groups-design): forming,
## names from data, one group per regiment, dissolving, the day's reconcile
## and the save round-trip.
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var land: Array = []


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	land = []
	var codes := state.regiments.keys()
	codes.sort()
	for c: String in codes:
		if ArmyGroups.eligible(repo, state, c):
			land.append(c)
	assert_gt(land.size(), 4, "the campaign has enough land regiments")


func test_form_names_and_summary() -> void:
	var out := ArmyGroups.form(repo, state, [land[0], land[1]], "test")
	assert_true(out["ok"])
	var g: Dictionary = state.army_groups[String(out["id"])]
	assert_eq(g["name"], repo.army_group_names[0])
	assert_eq(g["name"], "1st Army")
	assert_eq(g["members"], [land[0], land[1]])
	var second := ArmyGroups.form(repo, state, [land[2], land[3]], "test")
	assert_eq(state.army_groups[String(second["id"])]["name"], "2nd Army")
	var s := ArmyGroups.summary(repo, state, String(out["id"]))
	assert_eq(s["men"], ArmySystem.living_count(repo, state, land[0]) + ArmySystem.living_count(repo, state, land[1]))
	assert_eq(s["slowest_km"], minf(ArmySystem.speed_km_per_day(repo, state, land[0]),
		ArmySystem.speed_km_per_day(repo, state, land[1])))
	assert_eq(String(state.army_group_log[0]["reason"]), "test")


func test_too_few_and_ineligible_refused() -> void:
	assert_false(ArmyGroups.form(repo, state, [land[0]], "test")["ok"])
	assert_false(ArmyGroups.form(repo, state, [land[0], "no_such_unit", land[0]], "test")["ok"])
	assert_true(state.army_groups.is_empty())


func test_joining_leaves_old_group_which_dissolves() -> void:
	var first := String(ArmyGroups.form(repo, state, [land[0], land[1]], "test")["id"])
	var second := String(ArmyGroups.form(repo, state, [land[1], land[2]], "test")["id"])
	assert_false(state.army_groups.has(first), "1st Army fell below two and dissolved")
	assert_eq(ArmyGroups.group_of(state, land[1]), second)
	assert_eq(ArmyGroups.group_of(state, land[0]), "")
	# the freed name is used again
	var third := String(ArmyGroups.form(repo, state, [land[3], land[4]], "test")["id"])
	assert_eq(state.army_groups[third]["name"], "1st Army")


func test_disband() -> void:
	var id := String(ArmyGroups.form(repo, state, [land[0], land[1], land[2]], "test")["id"])
	assert_true(ArmyGroups.disband(repo, state, id, "test"))
	assert_true(state.army_groups.is_empty())
	assert_false(ArmyGroups.disband(repo, state, id, "test"))


func test_destroyed_member_drops_out_on_reconcile() -> void:
	var id := String(ArmyGroups.form(repo, state, [land[0], land[1], land[2]], "test")["id"])
	state.regiments.erase(land[2])
	MilitaryReorganization.reconcile(repo, state)
	assert_eq(state.army_groups[id]["members"], [land[0], land[1]])
	state.regiments.erase(land[1])
	MilitaryReorganization.reconcile(repo, state)
	assert_true(state.army_groups.is_empty(), "a group left with one dissolves")


func test_split_leaves() -> void:
	var id := String(ArmyGroups.form(repo, state, [land[0], land[1], land[2]], "test")["id"])
	ArmyGroups.leave(repo, state, land[0], "split")
	assert_eq(state.army_groups[id]["members"], [land[1], land[2]])


func test_save_round_trip() -> void:
	var id := String(ArmyGroups.form(repo, state, [land[0], land[1]], "test")["id"])
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.army_groups, state.army_groups)
	assert_eq(back.army_group_next_id, 1)
	assert_eq(typeof(back.army_groups[id]["formed_tick"]), TYPE_INT)
	assert_eq(back.army_group_log, state.army_group_log)
	assert_eq(ArmyGroups.group_of(back, land[1]), id)
