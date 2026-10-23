extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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
	Roster.mobilize(repo, state, "raise", [
		_cohort("r", "u", 80, "rural_population"),
		_cohort("c", "u", 20, "urban_population"),
		_cohort("other", "v", 50, "urban_population")], "initial enlistment")

func _path(field: String) -> String:
	return "economy.provinces.%s.%s" % [province, field]

func _cohort(id: String, unit: String, count: int, field: String) -> Dictionary:
	return {"id": id, "unit_code": unit, "count": count, "source_province": province,
		"source_population_field": field, "identity": "commoner", "family_name": "", "stage": "active"}

func _move(unit: String, from: String, to: String, count: int) -> Dictionary:
	return {"unit_code": unit, "from": from, "to": to, "count": count}

func _apply(id: String, orders: Array) -> Dictionary:
	var service := Roster.new()
	assert_true(service.has_method("transfer_units"), "unit casualties must write originating cohorts")
	if not service.has_method("transfer_units"):
		return {"error": "missing unit transfer"}
	return service.call("transfer_units", repo, state, id, orders, "battle personnel changes")

func test_unit_casualties_reach_both_origins_and_leave_other_unit_unchanged() -> void:
	var result := _apply("round", [_move("u", "fit", "dead", 5), _move("u", "fit", "wounded", 5)])
	assert_false(result.has("error"))
	assert_eq(Roster.fit(state, "u"), 90)
	assert_eq(Roster.living(state, "u"), 95)
	assert_eq(int(state.military_cohorts["r"]["dead"]), 4)
	assert_eq(int(state.military_cohorts["c"]["dead"]), 1)
	assert_eq(int(state.military_cohorts["r"]["wounded"]), 4)
	assert_eq(int(state.military_cohorts["c"]["wounded"]), 1)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("rural_population"))), 996)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("urban_population"))), 499)
	assert_eq(Roster.fit(state, "v"), 50)

func test_invalid_second_unit_cannot_partially_kill_first_side() -> void:
	var before := SaveLoad.state_hash(state)
	assert_true(_apply("round", [_move("u", "fit", "dead", 10), _move("v", "fit", "wounded", 51)]).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(state.military_events.has("round"))

func test_replay_after_json_does_not_reapportion_survivors() -> void:
	var orders := [_move("u", "fit", "dead", 5), _move("u", "fit", "wounded", 5)]
	assert_false(_apply("round", orders).has("error"))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_false(_apply("round", orders).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_true(_apply("round", [_move("u", "fit", "dead", 6)]).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_recovery_and_discharge_do_not_create_population() -> void:
	assert_false(_apply("wounds", [_move("u", "fit", "wounded", 20)]).has("error"))
	assert_false(_apply("recovery", [_move("u", "wounded", "fit", 5)]).has("error"))
	assert_false(_apply("desertion", [_move("u", "fit", "released", 10)]).has("error"))
	assert_eq(Roster.fit(state, "u"), 75)
	assert_eq(Roster.living(state, "u"), 90)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("rural_population"))), 1000)
	assert_eq(int(WorldLedger.value_of(repo, state, _path("urban_population"))), 500)
	var before := SaveLoad.state_hash(state)
	assert_true(_apply("return", [_move("u", "released", "fit", 1)]).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_repeated_destinations_cannot_spend_the_same_person_twice() -> void:
	var before := SaveLoad.state_hash(state)
	assert_true(_apply("round", [_move("u", "fit", "dead", 60), _move("u", "fit", "wounded", 41)]).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_mobilize_caps_live_and_reserved_people_before_any_write() -> void:
	state.world[_path("rural_population")] = 10000
	var rows := [_cohort("large", "new", 2500, "rural_population")]
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "oversize", rows, "new enlistment").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	rows = [_cohort("reserved", "u", 900, "rural_population")]
	rows[0]["stage"] = "assembling"
	assert_false(Roster.mobilize(repo, state, "reserve", rows, "paid reservation").has("error"))
	before = SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "overflow", [_cohort("one", "u", 1, "rural_population")], "extra enlistment").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_captive_return_is_illegal_even_with_room() -> void:
	assert_false(_apply("capture", [_move("u", "fit", "captured_current", 10)]).has("error"))
	for to: String in ["fit", "wounded"]:
		var before := SaveLoad.state_hash(state)
		assert_true(_apply("return:" + to, [_move("u", "captured_current", to, 1)]).has("error"))
		assert_eq(SaveLoad.state_hash(state), before)

func test_wounded_people_fill_cap_but_recovery_and_captives_do_not_add_living() -> void:
	state.world[_path("rural_population")] = 10000
	assert_false(Roster.mobilize(repo, state, "fill", [_cohort("fill", "u", 900, "rural_population")], "fill to limit").has("error"))
	assert_false(_apply("wound100", [_move("u", "fit", "wounded", 100)]).has("error"))
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "extra", [_cohort("extra", "u", 1, "rural_population")], "over limit").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(_apply("recover100", [_move("u", "wounded", "fit", 100)]).has("error"))
	assert_eq(Roster.living(state, "u"), 1000)
	assert_false(_apply("capture77", [_move("u", "fit", "captured_current", 77)]).has("error"))
	assert_false(Roster.mobilize(repo, state, "replace77", [_cohort("replace", "u", 77, "rural_population")], "paid replacements").has("error"))
	assert_eq(Roster.living(state, "u"), 1000)

func test_activation_refuses_overcap_reservations_atomically() -> void:
	state.world[_path("rural_population")] = 10000
	var row := _cohort("pending", "u", 900, "rural_population")
	row.stage = "assembling"
	assert_false(Roster.mobilize(repo, state, "pending", [row], "paid assembly").has("error"))
	state.military_cohorts.pending.fit += 1
	state.military_cohorts.pending.initial += 1
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.activate(state, "activate", ["pending"], "finish assembly", repo).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
