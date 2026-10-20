extends GutTest
## Hidden enemy truth must not alter the crown's target menu.
const TaskViewTests := preload("res://tests/engine/test_battle_task_view.gd")

func _fixture() -> Dictionary:
	var helper := TaskViewTests.new()
	var f := helper._fixture()
	helper.free()
	f.state.foes[f.enemy].x_m = -100000000
	f.state.foes[f.enemy].y_m = -100000000
	return f

func _remove_fit(f: Dictionary) -> void:
	for id: String in f.state.military_rosters[f.enemy].cohort_ids:
		var cohort: Dictionary = f.state.military_cohorts[id]
		cohort.wounded = int(cohort.wounded) + int(cohort.fit)
		cohort.fit = 0

func test_hidden_position_and_personnel_do_not_change_task_view() -> void:
	var f := _fixture()
	var original := JSON.stringify(f.state.to_dict())
	var before := JSON.stringify(BattlePresentation.task_view(f.repo, f.state, f.a))
	assert_eq(JSON.stringify(f.state.to_dict()), original, "Reading the view cannot mutate simulation state")
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).targets.size(), 1)
	f.state.foes[f.enemy].x_m -= 100000
	assert_eq(JSON.stringify(BattlePresentation.task_view(f.repo, f.state, f.a)), before)
	_remove_fit(f)
	assert_eq(MilitaryRoster.fit(f.state, f.enemy), 0)
	assert_eq(JSON.stringify(BattlePresentation.task_view(f.repo, f.state, f.a)), before,
		"Unobserved wounded transfers cannot remove the target from the menu")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(JSON.stringify(BattlePresentation.task_view(f.repo, restored, f.a)), before,
		"JSON reload must preserve the same known task view")

func test_locally_observed_personnel_refresh_the_target_menu() -> void:
	var f := _fixture()
	f.state.king_state.x_m = int(f.state.foes[f.enemy].x_m)
	f.state.king_state.y_m = int(f.state.foes[f.enemy].y_m)
	assert_true(BattlePresentation.local_unit(f.repo, f.state, f.enemy))
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).targets.size(), 1)
	_remove_fit(f)
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).targets, [])

func test_hidden_capture_does_not_change_the_target_menu() -> void:
	var f := _fixture()
	var before := JSON.stringify(BattlePresentation.task_view(f.repo, f.state, f.a))
	f.state.foes[f.enemy].captured = true
	assert_eq(JSON.stringify(BattlePresentation.task_view(f.repo, f.state, f.a)), before)
	f.state.king_state.x_m = int(f.state.foes[f.enemy].x_m)
	f.state.king_state.y_m = int(f.state.foes[f.enemy].y_m)
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).targets, [],
		"Direct observation refreshes a captured target")
