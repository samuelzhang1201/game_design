extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Population := preload("res://scripts/engine/military_population.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var province: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	# This fixture exercises a fresh explicit enlistment, not the opening host.
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	repo.balance["recruitment_eligible_permille"] = 1000
	province = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0]
	state.world[_path("rural_population")] = 1000
	state.world[_path("urban_population")] = 500

func _path(field: String) -> String:
	return "economy.provinces.%s.%s" % [province, field]

func _recruit(id: String, count: int, field := "rural_population", stage := "active") -> Dictionary:
	return {"id": id, "unit_code": "unit", "source_province": province,
		"source_population_field": field, "identity": "commoner", "family_name": "",
		"stage": stage, "count": count}

func _change(id: String, from_status: String, to_status: String, count: int) -> Dictionary:
	return {"cohort_id": id, "from": from_status, "to": to_status, "count": count}

func test_death_capture_release_conserve_original_population() -> void:
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("c", 600)], "levy raised").has("error"))
	assert_eq(Population.occupied(state, province, "rural_population"), 600)
	assert_eq(Population.available(repo, state, province, "rural_population"), 400)
	assert_false(Roster.transition(repo, state, "death", [_change("c", "fit", "dead", 40)], "battle loss").has("error"))
	assert_eq(int(WorldLedger.value_of(repo, state, _path("rural_population"))), 960)
	assert_eq(Population.occupied(state, province, "rural_population"), 560)
	assert_eq(Population.available(repo, state, province, "rural_population"), 400)
	Roster.transition(repo, state, "capture", [_change("c", "fit", "captured_current", 60)], "surrender accepted")
	assert_eq(Population.occupied(state, province, "rural_population"), 560)
	Roster.transition(repo, state, "release", [_change("c", "captured_current", "released", 60)], "prisoners released")
	assert_eq(Population.occupied(state, province, "rural_population"), 500)
	assert_eq(Population.available(repo, state, province, "rural_population"), 460)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("rural_population"))), 960)
	assert_eq(Roster.fit(state, "unit"), 500)
	assert_eq(Roster.living(state, "unit"), 500)

func test_two_origins_and_failed_batch_are_atomic() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("r", 80), _recruit("u", 20, "urban_population")], "levy raised")
	var before := SaveLoad.state_hash(state)
	var invalid := [_change("r", "fit", "dead", 8), _change("u", "fit", "dead", 21)]
	assert_true(Roster.transition(repo, state, "loss", invalid, "battle loss").has("error"))
	assert_eq(SaveLoad.state_hash(state), before, "no partial rural death or consumed token")
	assert_false(Roster.transition(repo, state, "loss", [_change("r", "fit", "dead", 8), _change("u", "fit", "dead", 2)], "battle loss").has("error"))
	assert_eq(int(WorldLedger.value_of(repo, state, _path("rural_population"))), 992)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("urban_population"))), 498)
	assert_eq(Roster.living(state, "unit"), 90)

func test_wounded_captives_and_recovery_use_mutually_exclusive_counts() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("c", 100)], "levy raised")
	Roster.transition(repo, state, "wound", [_change("c", "fit", "wounded", 20)], "wounds")
	Roster.transition(repo, state, "heal", [_change("c", "wounded", "fit", 5)], "recovery")
	assert_eq(Roster.fit(state, "unit"), 85)
	assert_eq(Roster.living(state, "unit"), 100)
	Roster.transition(repo, state, "capture", [_change("c", "fit", "captured_current", 50), _change("c", "wounded", "captured_current", 10)], "surrender accepted")
	assert_eq(Roster.fit(state, "unit"), 35)
	assert_eq(Roster.living(state, "unit"), 40)
	assert_eq(Population.occupied(state, province, "rural_population"), 100)
	assert_eq(int(state.military_cohorts.get("c", {}).get("captured_current", -1)), 60)
	assert_eq(int(state.military_cohorts.get("c", {}).get("wounded", -1)), 5)

func test_duplicate_after_json_does_not_repeat_and_changed_request_is_refused() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("c", 100)], "levy raised")
	var changes := [_change("c", "fit", "dead", 10)]
	Roster.transition(repo, state, "loss", changes, "battle loss")
	var original_hash := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(SaveLoad.state_hash(state), original_hash, "integer event facts survive JSON exactly")
	var before := SaveLoad.state_hash(state)
	assert_false(Roster.transition(repo, state, "loss", changes, "battle loss").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_true(Roster.transition(repo, state, "loss", [_change("c", "fit", "dead", 11)], "battle loss").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_gathering_is_reserved_once_and_released_people_need_new_enlistment() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("c", 600, "rural_population", "assembling")], "paid recruitment")
	state.recruitment_projects["project"] = {"cohort_ids": ["c"], "completion_day": 2}
	assert_eq(Population.occupied(state, province, "rural_population"), 600)
	assert_eq(Roster.fit(state, "unit"), 0)
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "overbook", [_recruit("d", 401)], "extra levy").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	Roster.transition(repo, state, "discharge", [_change("c", "fit", "released", 60)], "cancelled recruitment")
	before = SaveLoad.state_hash(state)
	assert_true(Roster.transition(repo, state, "undo", [_change("c", "released", "fit", 60)], "automatic return").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_invalid_origins_and_reason_cannot_change_state() -> void:
	var before := SaveLoad.state_hash(state)
	var invalid := _recruit("c", 100, "grain")
	assert_true(Roster.mobilize(repo, state, "raise", [invalid], "levy raised").has("error"))
	invalid = _recruit("c", 100)
	invalid["source_province"] = "unknown"
	assert_true(Roster.mobilize(repo, state, "raise", [invalid], "levy raised").has("error"))
	assert_true(Roster.mobilize(repo, state, "raise", [_recruit("c", 100)], "").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_inconsistent_origin_cannot_partially_apply_a_death() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("c", 600)], "levy raised")
	state.world[_path("rural_population")] = 500  # legacy conflict to be reported, not hidden
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.transition(repo, state, "loss", [_change("c", "fit", "dead", 10)], "battle loss").has("error"))
	assert_eq(SaveLoad.state_hash(state), before, "failed population write must not leave casualty changes")

func test_fractional_personnel_are_refused_without_mutation() -> void:
	var recruit := _recruit("c", 100)
	recruit["count"] = 100.75
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "fraction", [recruit], "levy raised").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	Roster.mobilize(repo, state, "raise", [_recruit("c", 100)], "levy raised")
	var change := _change("c", "fit", "dead", 10)
	change["count"] = 10.75
	before = SaveLoad.state_hash(state)
	assert_true(Roster.transition(repo, state, "loss", [change], "battle loss").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_integral_json_counts_have_canonical_retry_payloads() -> void:
	var recruit := _recruit("c", 100)
	recruit["count"] = 100.0
	recruit["unused_ui_progress"] = 0.75
	assert_false(Roster.mobilize(repo, state, "raise", [recruit], "levy raised").has("error"))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("c", 100)], "levy raised").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_transition_cannot_consume_people_created_earlier_in_the_batch() -> void:
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("c", 12)], "levy raised").has("error"))
	assert_false(Roster.transition(repo, state, "prior_wounds", [_change("c", "fit", "wounded", 2)], "prior wounds").has("error"))
	var before := state.to_dict()
	assert_true(Roster.transition(repo, state, "chained", [
		_change("c", "fit", "wounded", 5), _change("c", "wounded", "dead", 7)], "invalid chained loss").has("error"))
	assert_eq(state.to_dict(), before, "original ten fit and two wounded remain untouched")

func test_eligible_population_subtracts_service_and_promises_and_blocks_conflicts() -> void:
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("c", 200)], "levy raised").has("error"))
	assert_false(Roster.transition(repo, state, "release", [_change("c", "fit", "released", 20)], "civilian promise").has("error"))
	state.military_cohorts.c.civilian_promises = [{"count": 20, "until_day": 0, "reason": "Civilian service promise"}]
	repo.balance["recruitment_eligible_permille"] = 250
	assert_eq(Population.available(repo, state, province, "rural_population"), 50, "1000 * 250 / 1000 - 180 - 20")
	state.military_migration = {"recruitment_blocked": true, "conflicts": [province]}
	assert_eq(Population.available(repo, state, province, "rural_population"), 0)
